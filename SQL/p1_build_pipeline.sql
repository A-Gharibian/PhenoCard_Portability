/* EXECUTION ORDER — run scripts in sequence,
* each step depends on the previous:
 *   01  patient_index    → defines cases (AFib) and controls
 *   02  target_labels    → binary AFib label per patient
 *   03  tall_features    → long-format feature table
 * (conditions + measurements)
 *   04  final_ml_matrix  → wide-format ML-ready output
 *(main output of Phase 1)
 * VOCABULARY TABLES (concept, concept_ancestor, etc.)
 * must be loaded before
 * running this pipeline. See 00_load_vocabulary.sql.
 * =============================================================================
 */
-- =============================================================================
-- 01  patient_index
--
-- One row per patient with an index date and binary target flag.
--
--   is_target = 1 → Case:    earliest AFib diagnosis date
--   is_target = 0 → Control: most recent visit date
--
-- Source : condition_occurrence, concept_ancestor, concept,
--          person, visit_occurrence
-- =============================================================================
CREATE OR REPLACE TABLE patient_index AS

WITH target_patients AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS index_date,
        1 AS is_target
    FROM condition_occurrence AS co
    INNER JOIN concept_ancestor AS ca
        ON
            co.condition_concept_id = ca.descendant_concept_id
            -- Atrial fibrillation (all descendants)
            AND ca.ancestor_concept_id = 4068155
    INNER JOIN concept AS c
        ON
            co.condition_concept_id = c.concept_id
            -- exclude deprecated concepts
            AND c.invalid_reason IS NULL
    GROUP BY co.person_id
),

non_target_patients AS (
    SELECT
        p.person_id,
        MAX(vo.visit_start_date) AS index_date,
        0 AS is_target
    FROM person AS p
    LEFT JOIN visit_occurrence AS vo
        ON p.person_id = vo.person_id
    WHERE p.person_id NOT IN (SELECT person_id FROM target_patients)
    GROUP BY p.person_id
)

SELECT
    person_id,
    index_date,
    is_target
FROM target_patients
UNION ALL
SELECT
    person_id,
    index_date,
    is_target
FROM non_target_patients;


-- =============================================================================
-- 02  target_labels
--
-- One row per patient with a binary AFib label for the ML pipeline.
--
--   target_ecg_afib = 1 → patient has at least one AFib diagnosis
--   target_ecg_afib = 0 → patient has no AFib diagnosis
--
-- Source : patient_index, condition_occurrence, concept_ancestor, concept
-- =============================================================================
CREATE OR REPLACE TABLE target_labels AS
SELECT
    person_id AS subject_id,
    is_target AS target_ecg_afib
FROM patient_index;


-- =============================================================================
-- 03  tall_features
--
-- Long-format feature table: one row per patient per feature.
-- Features are derived from all clinical history up to (not after) index_date
-- to prevent look-ahead leakage.
--
--   Conditions  → binary (1.0 = present at any point before index_date)
--                 AFib and all descendants excluded to prevent target leakage
--   Measurements→ single most recent value before index_date per concept
--
-- Source : condition_occurrence, concept_ancestor, concept,
--          measurement, patient_index
-- =============================================================================
CREATE OR REPLACE TABLE tall_features AS

WITH ranked_measurements AS (
    SELECT
        m.person_id AS subject_id,
        'measurement_' || c.concept_name AS feature_name,
        m.value_as_number AS feature_value,
        ROW_NUMBER() OVER (
            PARTITION BY m.person_id, c.concept_id
            ORDER BY m.measurement_date DESC  -- most recent first
        ) AS rn
    FROM measurement AS m
    INNER JOIN concept AS c
        ON
            m.measurement_concept_id = c.concept_id
            AND c.invalid_reason IS NULL
    INNER JOIN patient_index AS idx
        ON
            m.person_id = idx.person_id
            AND m.measurement_date <= idx.index_date  -- no look-ahead
    WHERE m.value_as_number IS NOT NULL
)

-- Conditions: all history up to index_date, AFib excluded
SELECT
    co.person_id AS subject_id,
    'condition_' || c.concept_name AS feature_name,
    1.0 AS feature_value
FROM condition_occurrence AS co
INNER JOIN concept AS c
    ON
        co.condition_concept_id = c.concept_id
        AND c.invalid_reason IS NULL
INNER JOIN patient_index AS idx
    ON
        co.person_id = idx.person_id
        AND co.condition_start_date <= idx.index_date  -- no look-ahead
LEFT JOIN concept_ancestor AS ca
    ON
        co.condition_concept_id = ca.descendant_concept_id
        AND ca.ancestor_concept_id = 4068155
-- exclude AFib and all descendants
WHERE ca.ancestor_concept_id IS NULL

UNION ALL

-- Measurements: single most recent value before index_date
SELECT
    subject_id,
    feature_name,
    feature_value
FROM ranked_measurements
WHERE rn = 1;

-- =============================================================================
-- 04  final_ml_matrix  ★ MAIN OUTPUT OF PHASE 1 ★
--
-- Wide-format ML-ready matrix: one row per patient, one column per feature.
-- Combines demographics, the AFib label, and all pivoted features.
--
--   Columns:
--     person_id, index_date, year_of_birth, gender  → demographics
--     target_ecg_afib               → label
--     [one column per feature_name] → pivoted from tall_features
--
-- Source : person, patient_index, concept, target_labels, tall_features
-- =============================================================================
CREATE OR REPLACE TABLE final_ml_matrix AS
SELECT
    p.person_id,
    idx.index_date,
    p.year_of_birth,
    c_gender.concept_name AS gender,
    COALESCE(tl.target_ecg_afib, 0) AS target_ecg_afib,
    pf.* EXCLUDE (subject_id)
FROM person AS p
INNER JOIN patient_index AS idx
    ON p.person_id = idx.person_id
LEFT JOIN concept AS c_gender
    ON
        p.gender_concept_id = c_gender.concept_id
        AND c_gender.invalid_reason IS NULL
LEFT JOIN target_labels AS tl
    ON p.person_id = tl.subject_id
LEFT JOIN (
    -- DuckDB dynamic PIVOT: one column per unique feature_name,
    -- aggregated as MAX(feature_value) per patient.
    PIVOT tall_features
    ON feature_name
    USING MAX(feature_value)
) AS pf ON p.person_id = pf.subject_id;


SELECT
    (SELECT COUNT(*) FROM patient_index WHERE is_target = 1) AS cases_in_index,
    (SELECT COUNT(*) FROM target_labels WHERE target_ecg_afib = 1) AS cases_in_labels,
    (SELECT COUNT(*) FROM final_ml_matrix WHERE target_ecg_afib = 1) AS cases_in_matrix;
