/*
 * p2_06_cohort_characterization.sql
 *
 * Purpose : Produce a cohort summary table describing the demographic and
 *           target variable distribution of the Phase 2 MIMIC-IV pool,
 *           before propensity score matching is applied.
 *
 *           Compare the output of this script 
 *              against p1_05_cohort_characterization.sql
 *           to understand how different the two cohorts are before matching.
 *
 * Input   : p2_filtered_ml_matrix 
 *          (built by p2_05_apply_demographic_filters.sql)
 * Output  : result set only (no table created)
 *
 */

WITH total_cohort AS (
    -- Total patient count used as denominator for proportions
    SELECT COUNT(*) AS total_n
    FROM p2_filtered_ml_matrix
),

age_metrics AS (
    -- Continuous summary: anchor_age mean and SD
    -- anchor_age is the MIMIC-IV de-identified age proxy
    SELECT
        'Demographics' AS variable_role,
        'Anchor Age' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG(age), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV(age), 2)::VARCHAR AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix
),

gender_metrics AS (
    -- Categorical summary: gender counts and proportions
    SELECT
        'Demographics' AS variable_role,
        'Gender' AS variable_name,
        'Categorical' AS data_type,
        gender AS category_value,
        COUNT(*)::VARCHAR AS metric_mean_or_count,
        ROUND(
            (COUNT(*) * 100.0) / (SELECT total_n FROM total_cohort), 1
        )::VARCHAR AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix
    GROUP BY gender
),

target_metrics AS (
    -- Categorical summary: all target_ columns unpivoted dynamically
    SELECT
        'Target / Outcome' AS variable_role,
        REPLACE(target_var_name, 'target_', '') AS variable_name,
        'Categorical' AS data_type,
        target_value::VARCHAR AS category_value,
        COUNT(*)::VARCHAR AS metric_mean_or_count,
        ROUND(
            (COUNT(*) * 100.0) / (SELECT total_n FROM total_cohort), 1
        )::VARCHAR AS metric_sd_or_proportion
	FROM (
        -- Dynamically unpivot all columns whose name starts with 'target_'
        UNPIVOT p2_filtered_ml_matrix
        ON COLUMNS('^target_')  -- Fixed: Use POSIX regex pattern directly
        INTO
        NAME target_var_name
        VALUE target_value
    )
    GROUP BY target_var_name, target_value
),

lab_metrics AS (
    -- Continuous summary: mean and SD for each of the four lab features
    -- Compare these against Phase 1 to assess pre-matching comparability
    SELECT
        'Lab Feature' AS variable_role,
        'RDW' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG(rdw), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV(rdw), 2)::VARCHAR AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix

    UNION ALL

    SELECT
        'Lab Feature' AS variable_role,
        'MCHC' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG(mchc), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV(mchc), 2)::VARCHAR AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix

    UNION ALL

    SELECT
        'Lab Feature' AS variable_role,
        'Urea Nitrogen' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG("Urea Nitrogen"), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV("Urea Nitrogen"), 2)::VARCHAR AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix

    UNION ALL

    SELECT
        'Lab Feature' AS variable_role,
        'White Blood Cells' AS variable_name,
        'Continuous' AS data_type,
        'N/A' AS category_value,
        ROUND(AVG("White Blood Cells"), 2)::VARCHAR AS metric_mean_or_count,
        ROUND(STDDEV("White Blood Cells"), 2)::VARCHAR
            AS metric_sd_or_proportion
    FROM p2_filtered_ml_matrix
),

combined_metrics AS (
    SELECT * FROM age_metrics
    UNION ALL
    SELECT * FROM gender_metrics
    UNION ALL
    SELECT * FROM target_metrics
    UNION ALL
    SELECT * FROM lab_metrics
)

-- Final output: Phase 2 MIMIC-IV cohort summary
-- Compare side by side with p1_05 output to assess pre-matching balance
SELECT
    variable_role,
    variable_name,
    data_type,
    category_value,
    metric_mean_or_count,
    metric_sd_or_proportion
FROM combined_metrics
ORDER BY
    data_type DESC,
    variable_role ASC,
    variable_name ASC,
    category_value ASC;
