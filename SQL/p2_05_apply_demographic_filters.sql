/*
 * p2_05_apply_demographic_filters.sql
 *
 * Purpose : Optional post-processing step that enriches p2_final_ml_matrix
 *           with patient demographics and applies inclusion/exclusion criteria.
 *
 *           Run this after p2_build_pipeline.sql if you want a
 *           filtered subset of the matrix. Re-run with different WHERE
 *           conditions without rebuilding the full pipeline.
 *
 * Input   : p2_final_ml_matrix (built by p2_build_pipeline.sql)
 * Output  : p2_filtered_ml_matrix
 */

-- Uncomment if running this script standalone, outside the same session
-- as p2_build_pipeline.sql:
-- SET variable mimic_path = 'data/mimic/hosp/';

CREATE OR REPLACE TABLE p2_filtered_ml_matrix AS
SELECT
    m.*,
    p.gender,
    p.anchor_age AS age
FROM p2_final_ml_matrix m
JOIN read_csv_auto(getvariable('mimic_path') || 'patients.csv.gz') p
    ON m.subject_id = p.subject_id
-- -------------------------------------------------------------------------
-- Inclusion / exclusion criteria — modify as needed:
-- -------------------------------------------------------------------------
WHERE p.anchor_age >= 0           -- no filter currently applied (template)
  -- AND p.gender = 'F'           -- uncomment to restrict to female patients
  -- AND p.anchor_age >= 18       -- uncomment to restrict to adults only
  -- AND p.anchor_age <= 89       -- uncomment to exclude very elderly patients
  ;

