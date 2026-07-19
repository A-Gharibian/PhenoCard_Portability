/*
 * PURPOSE: Phase 2 validates the AFib model developed in Phase 1 on a
 *   larger sample (10,000 patients) drawn directly from raw MIMIC-IV CSV files,
 *   without any OMOP vocabulary mapping.
 *
 *   Features are restricted to four lab values that were identified as
 *   informative in Phase 1: RDW, MCHC, Urea Nitrogen, White Blood Cells.
 *   A 6-month lookback window is applied to all feature extraction.
 *
 *   Lab tests are identified by itemid, not by d_labitems.label text.
 *   d_labitems.label is not unique in raw MIMIC-IV. itemids below were
 * 	 verified against d_labitems.csv.gz before being hardcoded.
 * 
 * EXECUTION ORDER:
 *   p2_01  p2_cohort_index    → 10,000 random patients with their index visit
 *   p2_02  p2_target_labels   → binary AFib label per patient (ICD-based)
 *   p2_03  p2_tall_features   → long-format lab feature table
 *   p2_04  p2_final_ml_matrix → wide-format ML-ready output MAIN OUTPUT
 *
 * DATA SOURCES:
 *   Update mimic_path below to match your local MIMIC-IV directory.
 */

-- -------------------------------------------------------------------------
-- STEP 0: ENVIRONMENT CONFIGURATION
-- -------------------------------------------------------------------------
SET variable mimic_path = '<mimic_path>/';

-- -------------------------------------------------------------------------
-- STAGING: admissions.csv.gz is read twice downstream (p2_01 and p2_02),
-- -------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE stage_admissions AS
    SELECT * FROM read_csv_auto(getvariable('mimic_path') || 'admissions.csv.gz');


-- =============================================================================
-- p2_01  p2_cohort_index
--
-- Randomly samples 10,000 patients from the MIMIC-IV patients file and
-- identifies their most recent hospital admission as the index visit.
--
-- One row per patient:
--   subject_id     → patient identifier (MIMIC-IV native key)
--   index_visit_id → hadm_id of the most recent admission
--   index_date     → admittime of the most recent admission
-- =============================================================================
CREATE OR REPLACE TABLE p2_cohort_index AS

WITH sampled_patients AS (
    -- Reservoir sampling directly on the CSV read: uniform random sample
    -- without staging the file first or sorting the full table.
    SELECT subject_id
    FROM read_csv_auto(getvariable('mimic_path') || 'patients.csv.gz')
    USING SAMPLE 10000 ROWS
),

ranked_visits AS (
    -- For each sampled patient, rank admissions latest-first
    SELECT
        a.subject_id,
        a.hadm_id    AS index_visit_id,
        a.admittime  AS index_date,
        ROW_NUMBER() OVER (
            PARTITION BY a.subject_id
            ORDER BY a.admittime DESC  -- most recent admission first
        )            AS rn
    FROM stage_admissions a
    JOIN sampled_patients sp
        ON a.subject_id = sp.subject_id
)

-- Keep only the single most recent admission per patient
SELECT
    subject_id,
    index_visit_id,
    index_date
FROM ranked_visits
WHERE rn = 1;


-- =============================================================================
-- p2_02  p2_target_labels
--
-- Assigns a binary AFib label to each patient in p2_cohort_index.
-- AFib is identified via ICD-9 and ICD-10 codes using the MIMIC-IV
-- diagnosis dictionary, without any OMOP vocabulary mapping.
--
--   target_ecg_afib = 1 → patient has at least one AFib diagnosis
--                         recorded on or before their index date
--   target_ecg_afib = 0 → no AFib diagnosis found
-- =============================================================================
CREATE OR REPLACE TABLE p2_target_labels AS

WITH target_dictionary AS (
    -- Build a lookup of all ICD codes whose description mentions AFib.
    -- Matches both ICD-9 and ICD-10 codes via the icd_version field.
    -- Read directly — this file is used only once in the pipeline.
    SELECT
        icd_code,
        icd_version
    FROM read_csv_auto(getvariable('mimic_path') || 'd_icd_diagnoses.csv.gz')
    WHERE LOWER(long_title) LIKE '%atrial fibrillation%'
),

patient_targets AS (
    -- Find all patients with a matching AFib diagnosis recorded during an
    -- admission on or before their index date. admittime <= index_date
    -- enforces no look-ahead leakage. GROUP BY here deduplicates in a
    -- single pass, avoiding a separate DISTINCT + GROUP BY/MAX() later.
    -- diagnoses_icd is read directly — used only once in the pipeline.
    SELECT
        d.subject_id
    FROM read_csv_auto(getvariable('mimic_path') || 'diagnoses_icd.csv.gz') d
    JOIN p2_cohort_index ci
        ON d.subject_id = ci.subject_id
    JOIN stage_admissions a
        ON  d.hadm_id = a.hadm_id
        AND a.admittime <= ci.index_date  -- no look-ahead
    JOIN target_dictionary td
        ON  d.icd_code = td.icd_code
        AND d.icd_version = td.icd_version  -- match ICD version to avoid code collisions
    GROUP BY d.subject_id
)

-- Every patient in the cohort gets a row; non-matches default to 0
SELECT
    ci.subject_id,
    CASE WHEN pt.subject_id IS NOT NULL THEN 1 ELSE 0 END AS target_ecg_afib
FROM p2_cohort_index ci
LEFT JOIN patient_targets pt
    ON ci.subject_id = pt.subject_id;


-- =============================================================================
-- p2_03  p2_tall_features
--
-- Long-format feature table: one row per patient per lab test.
-- Restricted to the four lab values identified as informative in Phase 1:
--   RDW, MCHC, Urea Nitrogen, White Blood Cells
--

-- =============================================================================
CREATE OR REPLACE TABLE p2_tall_features AS

WITH lab_dictionary AS (
    SELECT * FROM (VALUES
        (51301, 'White Blood Cells'),
        (51277, 'RDW'),
        (51249, 'MCHC'),
        (51006, 'Urea Nitrogen')
    ) AS t(itemid, feature_name)
),

ranked_patient_labs AS (
    SELECT
        le.subject_id,
        ld.feature_name,
        le.valuenum  AS feature_value,
        ROW_NUMBER() OVER (
            PARTITION BY le.subject_id, ld.feature_name
            ORDER BY le.charttime DESC  -- most recent result first
        )            AS rn
    FROM read_csv_auto(getvariable('mimic_path') || 'labevents.csv.gz') AS le
    INNER JOIN lab_dictionary AS ld
        ON le.itemid = ld.itemid
    INNER JOIN p2_cohort_index AS ci
        ON le.subject_id = ci.subject_id
    WHERE le.valuenum IS NOT NULL
      AND le.charttime <= ci.index_date                        -- no look-ahead
      AND le.charttime >= ci.index_date - INTERVAL '180 days'  -- 6-month window
)

-- Keep only the single most recent result per patient per lab test
SELECT
    subject_id,
    feature_name,
    feature_value
FROM ranked_patient_labs
WHERE rn = 1;


-- =============================================================================
-- p2_04  p2_final_ml_matrix  ★ MAIN OUTPUT OF PHASE 2 ★
--
-- Wide-format matrix: one row per patient, one column per feature.
-- Combines the AFib label with the four pivoted lab features.
--
--   Columns:
--     subject_id        → patient identifier
--     index_date        → anchor date for all feature extraction
--     target_ecg_afib   → binary AFib label
--     RDW, MCHC,
--     Urea Nitrogen,
--     White Blood Cells → most recent lab value in 6-month window
--
-- Notes:
--   - Patients with no lab results in the 6-month window will have NULL
-- =============================================================================
CREATE OR REPLACE TABLE p2_final_ml_matrix AS

SELECT
    ci.subject_id,
    ci.index_date,
    COALESCE(tl.target_ecg_afib, 0) AS target_ecg_afib,
    pf.* EXCLUDE (subject_id)
FROM p2_cohort_index ci
LEFT JOIN p2_target_labels tl
    ON ci.subject_id = tl.subject_id
LEFT JOIN (
    -- DuckDB dynamic PIVOT: one column per unique feature_name,
    -- aggregated as MAX(feature_value) per patient.
    -- Since tall_features already holds only the most recent value,
    -- MAX() here is effectively a passthrough.
    PIVOT p2_tall_features
    ON feature_name
    USING MAX(feature_value)
) pf ON ci.subject_id = pf.subject_id;
