/*
 * p1_05_cohort_characterization.sql
 *
 * Purpose : Produce a cohort summary table describing the
 *           demographic and target variable distribution of the Phase 1
 *           ML matrix. Intended to be run after p1_build_pipeline.sql
 *
 * Input   : final_ml_matrix (built by p1_build_pipeline.sql)
 * Output  : result set only (no table created)
 *
 */

WITH total_cohort AS (
    -- Total patient count used as denominator for proportions
    SELECT COUNT(*) AS total_n
    FROM final_ml_matrix
),

year_of_birth_metrics AS (
    SELECT
        'Demographics' AS variable_role,
        'Year of Birth' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG(year_of_birth), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV(year_of_birth), 2)::VARCHAR AS metric_sd_or_proportion,
        NULL::BIGINT AS hardcoded_concept_id
    FROM final_ml_matrix
),

gender_metrics AS (
    SELECT
        'Demographics' AS variable_role,
        'Gender' AS variable_name,
        'Categorical' AS data_type,
        gender AS category_value,
        COUNT(*)::VARCHAR AS metric_mean_or_count,
        ROUND(
            (COUNT(*) * 100.0) / (SELECT total_n FROM total_cohort), 1
        )::VARCHAR AS metric_sd_or_proportion,
        NULL::BIGINT AS hardcoded_concept_id
    FROM final_ml_matrix
    GROUP BY gender
),

target_metrics AS (
    SELECT
        'Target / Outcome' AS variable_role,
        'Atrial Fibrillation (Target)' AS variable_name,
        'Categorical' AS data_type,
        target_value::VARCHAR AS category_value,
        COUNT(*)::VARCHAR AS metric_mean_or_count,
        ROUND(
            (COUNT(*) * 100.0) / (SELECT total_n FROM total_cohort), 1
        )::VARCHAR AS metric_sd_or_proportion,
        4068155::BIGINT AS hardcoded_concept_id
    FROM (
        UNPIVOT final_ml_matrix
        ON target_ecg_afib
        INTO NAME target_var_name VALUE target_value
    )
    GROUP BY target_var_name, target_value
),
combined_metrics AS (
    SELECT * FROM year_of_birth_metrics
    UNION ALL
    SELECT * FROM gender_metrics
    UNION ALL
    SELECT * FROM target_metrics
),

concept_lookup AS (
    -- Pre-aggregate concept dictionary to prevent duplicate row explosions
    -- Only standard concepts (standard_concept = 'S') are matched
    SELECT
        LOWER(concept_name) AS match_name,
        MIN(concept_id) AS matched_concept_id
    FROM concept
    WHERE standard_concept = 'S'
    GROUP BY LOWER(concept_name)
)

-- Final output: cohort summary with OMOP concept IDs where available
-- Export this result to R/Python as your Phase 1 target profile
-- for propensity score matching against p2_filtered_ml_matrix
SELECT
    cm.variable_role,
    cm.variable_name,
    COALESCE(cm.hardcoded_concept_id, cl.matched_concept_id) AS omop_concept_id,
    cm.data_type,
    cm.category_value,
    cm.metric_mean_or_count,
    cm.metric_sd_or_proportion
FROM combined_metrics AS cm
LEFT JOIN concept_lookup AS cl
    ON cm.data_type = 'Categorical'
    AND cm.variable_role = 'Demographics'
    AND LOWER(cm.category_value) = cl.match_name
ORDER BY
    cm.data_type DESC,
    cm.variable_role ASC,
    cm.variable_name ASC,
    cm.category_value ASC;
