-- Looker Studio Phase
/* THE SEMANTIC LAYER
   Goal: Create a "Wide Table" for the Dashboard.
   It joins Transactions + Product Info + User Info.
*/

CREATE OR REPLACE VIEW `ecommerce_bi.master_sales_view` AS

-- STEP 1: Calculate Monthly Totals (The Grain)
WITH monthly_metrics AS (
  SELECT
    DATE_TRUNC(created_at, MONTH) as sales_month,
    SUM(sale_price) as monthly_revenue
  FROM `bigquery-public-data.thelook_ecommerce.order_items`
  WHERE status = 'Complete' -- Let's only count real money
  GROUP BY 1
),

-- STEP 2: The Time Machine (Window Functions)
growth_calc AS (
  SELECT
    sales_month,
    monthly_revenue,
    -- LAG(1) looks at the "Previous Row"
    LAG(monthly_revenue, 1) OVER (ORDER BY sales_month) as previous_month_revenue
  FROM monthly_metrics
)

-- STEP 3: The Final Layer (Merging it back to the details)
-- Note: In a real job, you might just connect Looker to Step 2 for the trend chart.
-- But to keep your current dashboard working, we will just JOIN this math back to the main view.

SELECT
  o.order_id,
  o.sale_price,
  o.created_at,
  p.category as product_category,
  u.country as user_country,
  
  -- BRING IN THE GROWTH METRIC
  -- We calculate the % change here
  ROUND(
    SAFE_DIVIDE(
      (g.monthly_revenue - g.previous_month_revenue), 
      g.previous_month_revenue
    ) * 100, 2
  ) as monthly_growth_pct

FROM `bigquery-public-data.thelook_ecommerce.order_items` as o
LEFT JOIN `bigquery-public-data.thelook_ecommerce.products` as p
  ON o.product_id = p.id
LEFT JOIN `bigquery-public-data.thelook_ecommerce.users` as u
  ON o.user_id = u.id
-- Join the Math we did above
LEFT JOIN growth_calc as g
  ON DATE_TRUNC(o.created_at, MONTH) = g.sales_month;


/* PHASE: MACHINE LEARNING
   Goal: Train a model to predict future revenue.
*/

-- 1. Create the Model (This takes ~1-2 minutes to run)
CREATE OR REPLACE MODEL `ecommerce_bi.revenue_forecast_model`
OPTIONS(model_type='ARIMA_PLUS',
        time_series_timestamp_col='sales_month',
        time_series_data_col='total_revenue') AS

-- 2. The Training Data
SELECT
    DATE_TRUNC(created_at, MONTH) as sales_month,
    SUM(sale_price) as total_revenue
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE status = 'Complete'
GROUP BY 1;