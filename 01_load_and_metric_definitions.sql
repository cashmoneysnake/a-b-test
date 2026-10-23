-- BigQuery Standard SQL
-- Setup: create dataset `ab_project`, then load data/marketing_ab_clean.csv into
-- `ab_project.marketing_ab` (Console -> Create table -> Upload -> CSV, auto-detect schema,
-- header row skip = 1). Replace `YOUR_PROJECT` below with your GCP project id.
-- Expected schema: user_id INT64, test_group STRING, converted INT64,
--                  total_ads INT64, most_ads_day STRING, most_ads_hour INT64

-- 0) Sanity checks (row count, duplicate users, nulls)
SELECT
  COUNT(*)                         AS n_rows,
  COUNT(DISTINCT user_id)          AS n_users,
  COUNTIF(user_id IS NULL OR test_group IS NULL OR converted IS NULL) AS n_nulls
FROM `YOUR_PROJECT.ab_project.marketing_ab`;

-- 1) Metric definition: one row per user, with a clean treatment flag
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_user_metrics` AS
SELECT
  user_id,
  IF(test_group = 'ad', 'treatment', 'control') AS variant,
  converted,                                  -- primary metric (0/1)
  total_ads,
  most_ads_day,
  most_ads_hour,
  CASE
    WHEN total_ads <= 5   THEN '01-5'
    WHEN total_ads <= 20  THEN '06-20'
    WHEN total_ads <= 50  THEN '21-50'
    WHEN total_ads <= 100 THEN '51-100'
    ELSE '101+'
  END AS ads_bucket
FROM `YOUR_PROJECT.ab_project.marketing_ab`;

-- 2) Primary metric by variant (feeds Looker Studio + cross-checks the notebook)
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_primary_metric` AS
SELECT
  variant,
  COUNT(*)                          AS users,
  SUM(converted)                    AS conversions,
  SAFE_DIVIDE(SUM(converted), COUNT(*)) AS conversion_rate
FROM `YOUR_PROJECT.ab_project.vw_user_metrics`
GROUP BY variant;

-- 3) Validity: allocation across day-of-week (input to chi-square independence test)
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_allocation_by_day` AS
SELECT
  most_ads_day,
  COUNTIF(variant = 'treatment') AS treatment_users,
  COUNTIF(variant = 'control')   AS control_users,
  SAFE_DIVIDE(COUNTIF(variant = 'control'), COUNT(*)) AS control_share
FROM `YOUR_PROJECT.ab_project.vw_user_metrics`
GROUP BY most_ads_day;

-- 4) Validity: allocation across hour
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_allocation_by_hour` AS
SELECT
  most_ads_hour,
  COUNTIF(variant = 'treatment') AS treatment_users,
  COUNTIF(variant = 'control')   AS control_users,
  SAFE_DIVIDE(COUNTIF(variant = 'control'), COUNT(*)) AS control_share
FROM `YOUR_PROJECT.ab_project.vw_user_metrics`
GROUP BY most_ads_hour;

-- 5) Group balance on exposure
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_balance_total_ads` AS
SELECT
  variant,
  AVG(total_ads)                              AS mean_total_ads,
  APPROX_QUANTILES(total_ads, 100)[OFFSET(50)] AS median_total_ads,
  APPROX_QUANTILES(total_ads, 100)[OFFSET(99)] AS p99_total_ads
FROM `YOUR_PROJECT.ab_project.vw_user_metrics`
GROUP BY variant;

-- 6) Exploratory segment lift (NOT used for the decision)
CREATE OR REPLACE VIEW `YOUR_PROJECT.ab_project.vw_conversion_by_segment` AS
SELECT
  ads_bucket,
  variant,
  COUNT(*)                              AS users,
  SUM(converted)                        AS conversions,
  SAFE_DIVIDE(SUM(converted), COUNT(*)) AS conversion_rate
FROM `YOUR_PROJECT.ab_project.vw_user_metrics`
GROUP BY ads_bucket, variant;
