/*
 * p1_exploratory_first_admission_measurements.sql
 *
 * Purpose : Retrieve all measurements recorded within 48 hours of each
 *           patient's first hospital admission. Used during Phase 1
 *           exploration to inspect the distribution of lab values
 *           and assess data density around the index admission.
 *
 * Input   : visit_occurrence, measurement, concept
 * Output  : result set only (no table created), limited to 50 rows
 *
 * Notes:
 *   - This is a standalone exploratory query, not part of the pipeline.
 * 		 It does not depend on any tables built by the pipeline.
 *   - The 48-hour window and LIMIT 50 are for inspection.
 */

WITH first_admission AS (
    -- Step 1: Find the very first time each patient entered the hospital
    SELECT
        person_id,
        MIN(visit_start_date) AS first_adm_date
    FROM visit_occurrence
    GROUP BY person_id
)

-- Step 2: Grab all measurements that happened within 48 hours of that admission
SELECT
    m.person_id,
    c.concept_name AS measurement_name,
    m.measurement_date,
    m.value_as_number,
    c_unit.concept_name AS unit,
    fa.first_adm_date
FROM measurement AS m
INNER JOIN first_admission AS fa
    ON m.person_id = fa.person_id
INNER JOIN concept AS c
    ON m.measurement_concept_id = c.concept_id
LEFT JOIN concept AS c_unit
    ON m.unit_concept_id = c_unit.concept_id
WHERE
    m.measurement_date >= fa.first_adm_date
    AND m.measurement_date <= fa.first_adm_date + INTERVAL '2 DAYS'
ORDER BY m.person_id, m.measurement_date
LIMIT 50;
