-- Analysis Phase, run one by one in BigQuery on GCD
-- THE RECONNAISSANCE SCAN 
-- Goal: Understand the "Fact" table structure.

SELECT 
    order_id, 
    user_id, 
    product_id, 
    sale_price, 
    created_at 
FROM `bigquery-public-data.thelook_ecommerce.order_items` 
LIMIT 10;

-- phase 2: PHASE 2: AGGREGATION
-- Goal: Collapse rows to calculate Monthly Revenue
SELECT
  DATE_TRUNC(created_at, MONTH) as sales_month,
  COUNT(order_id) as total_items_sold,
  SUM(sale_price) as total_revenue

-- THIS IS THE ADDRESS (The Table)
-- If you delete this line, the query will fail.
FROM `bigquery-public-data.thelook_ecommerce.order_items`

GROUP BY 1
ORDER BY 1 DESC;

/* PHASE 3: THE JOIN
   Goal: Attach "Category" names to our sales numbers.
*/

SELECT
  p.category,  -- Grab the text name from the PRODUCTS table (p)
  COUNT(o.order_id) as total_sold,
  SUM(o.sale_price) as total_revenue

FROM `bigquery-public-data.thelook_ecommerce.order_items` as o

-- THE STITCHING COMMAND
-- "Keep all the rows from Orders (o), and find the matching info in Products (p)"
LEFT JOIN `bigquery-public-data.thelook_ecommerce.products` as p
  ON o.product_id = p.id  -- The Common Key

GROUP BY 1
ORDER BY 3 DESC; -- Order by Revenue (High to Low)

/* PHASE 3.5: CALCULATED METRICS
   Goal: Let the server do the math and clean the decimals.
*/

SELECT
  p.category,
  COUNT(o.order_id) as total_sold,
  
  -- Clean the Revenue (Round to 2 decimal places)
  ROUND(SUM(o.sale_price), 2) as total_revenue,

  -- CALCULATED COLUMN: The "Price Per Item"
  -- We do the math right here in the SELECT statement
  ROUND(SUM(o.sale_price) / COUNT(o.order_id), 2) as avg_price_per_item

FROM `bigquery-public-data.thelook_ecommerce.order_items` as o
LEFT JOIN `bigquery-public-data.thelook_ecommerce.products` as p
  ON o.product_id = p.id

GROUP BY 1
ORDER BY 3 DESC; -- Order by Total Revenue

/* PHASE 4: LOGIC & SEGMENTATION
   Goal: Create a "VIP" list based on spending habits.
*/

SELECT
  user_id,
  SUM(sale_price) as lifetime_spend,
  
  -- THE LOGIC LAYER
  -- We classify users into buckets based on the SUM we just calculated
  CASE
    WHEN SUM(sale_price) > 500 THEN 'High Value (VIP)'
    WHEN SUM(sale_price) > 100 THEN 'Mid Tier'
    ELSE 'Low Value'
  END as customer_segment

FROM `bigquery-public-data.thelook_ecommerce.order_items`

GROUP BY 1
ORDER BY 2 DESC; -- Show big spenders first

/* PHASE 5: THE PARETO TEST (80/20 Rule)
   Goal: See what % of revenue comes from the top users.
*/

-- STEP 1: Create a temporary table in memory (The CTE)
WITH user_spend AS (
  SELECT
    user_id,
    SUM(sale_price) as total_spend
  FROM `bigquery-public-data.thelook_ecommerce.order_items`
  GROUP BY 1
),

-- STEP 2: Calculate Statisitcs on that table
stats AS (
  SELECT
    user_id,
    total_spend,
    
    -- Rank users: #1 is the biggest spender
    ROW_NUMBER() OVER (ORDER BY total_spend DESC) as rank_id,
    
    -- Count total users (to calculate top %)
    COUNT(*) OVER () as total_users,

    -- Running Total of Revenue (The Cumulative Sum)
    SUM(total_spend) OVER (ORDER BY total_spend DESC) as running_revenue,

    -- Grand Total Revenue (to calculate %)
    SUM(total_spend) OVER () as grand_total_revenue

  FROM user_spend
)

-- STEP 3: Final Calculation
SELECT
  rank_id,
  user_id,
  total_spend,
  
  -- Calculate Percentages
  ROUND((rank_id / total_users) * 100, 2) as pct_of_customers,
  ROUND((running_revenue / grand_total_revenue) * 100, 2) as pct_of_revenue

FROM stats
-- Let's look at the "Top 20%" mark
WHERE (rank_id / total_users) <= 0.25 
ORDER BY rank_id DESC
LIMIT 20;