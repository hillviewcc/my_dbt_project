/*
==============================================================================
  Model     : combined_data
  Layer     : Dashboard | table
  Purpose   : Reconciliation dataset. Splits every raw transaction value into
              four mutually exclusive buckets - DASHBOARD (reported),
              NON_OUTDOOR, UNMATCHED (outdoor but no product match) and
              UNMATCHED_UNKNOWN_MARKET - so raw totals can be reconciled to
              what the dashboards show.
  Grain     : One row per transaction (TRANSACTION_CONCAT_KEY).
  Depends on: source raw_retailer.raw_transaction, dim_product
  Notes     : The four buckets always add up to RAW_DATA_VALUE.
==============================================================================
*/
-- Step 1: parse raw transactions (same rules as lnd_transaction).
WITH RETAILER_TRANSACTION 
 AS (
  SELECT
    DELTA_RECORD['retailer_group_id']::NUMBER AS RETAILER_GROUP_ID,
    COALESCE(NULLIF(TRIM(DELTA_RECORD['retailer']::VARCHAR), ''), TRIM(DELTA_RECORD['retailer']::VARCHAR)) AS RETAILER,
    TO_DATE(
        TRY_TO_TIMESTAMP_TZ(
            CASE
                WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z') IS NOT NULL THEN
                    TO_CHAR(TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z'), 'YYYY-MM-DD HH24:MI:SS')
                WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD HH24:MI:SS') IS NOT NULL THEN
                    DELTA_RECORD['transaction_datetime']::STRING
                WHEN TRY_TO_TIMESTAMP_TZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY/MM/DD HH24:MI:SS') IS NOT NULL THEN
                    REPLACE(DELTA_RECORD['transaction_datetime']::STRING, '/', '-')
                WHEN TRY_TO_DATE(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD') IS NOT NULL THEN
                    DELTA_RECORD['transaction_datetime']::STRING || ' 00:00:00'
                ELSE
                    NULL
            END, 'YYYY-MM-DD HH24:MI:SS'
        )
    ) AS TRANSACTION_DATE,

    DELTA_RECORD['transaction_ean_upc']::NUMBER AS TRANSACTION_EAN_UPC,
    -- returns: align the sign of value and quantity (same rule as lnd_transaction)
     CASE
    -- Both negative (return) - keep value negative
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER < 0 
       THEN  DELTA_RECORD['transaction_value']::NUMBER(38, 2)
    
    -- Negative quantity, positive value - make value negative  
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER > 0
         THEN -ABS(DELTA_RECORD['transaction_value']::NUMBER(38, 2))
    
    -- Both positive (normal sale) - keep as is
    ELSE DELTA_RECORD['transaction_value']::NUMBER(38, 2)
END AS TRANSACTION_VALUE,

    CASE 
        WHEN DELTA_RECORD['transaction_value']:: NUMBER < 0 THEN -COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
        ELSE COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
    END AS TRANSACTION_QUANTITY,
    
    DELTA_RECORD['transaction_market']::VARCHAR AS TRANSACTION_MARKET,
    COALESCE(DELTA_RECORD['transaction_currency_new']::VARCHAR, 'GBP')  AS TRANSACTION_CURRENCY,
    CASE 
    WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'trailstep.com/de'
        THEN 'Germany'
    WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'trailstep.com/fr'
        THEN 'France'
    ELSE COALESCE(NULLIF(NULLIF(TRIM(DELTA_RECORD['transaction_country']::VARCHAR), ''), ' '), 'United Kingdom')
    END AS TRANSACTION_COUNTRY,

  ABS(HASH(
    NULLIF(TRIM(DELTA_RECORD['transaction_id']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['retailer']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_ean_upc']::NUMBER), ''),
    NULLIF(TRIM(COALESCE(DELTA_RECORD['transaction_quantity']::VARCHAR, DELTA_RECORD[' transaction_quantity']::VARCHAR)), ''),
    NULLIF(TRIM(DELTA_RECORD['product_name']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_store_id']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_datetime']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_value']::NUMBER), '')
)) AS TRANSACTION_CONCAT_KEY,

    ROW_NUMBER() OVER (
        PARTITION BY
            NULLIF(TRIM(DELTA_RECORD['transaction_id']::VARCHAR), ''),
            NULLIF(TRIM(COALESCE(DELTA_RECORD['retailer']::VARCHAR, DELTA_RECORD[' retailer']::VARCHAR)), ''),
            NULLIF(TRIM(DELTA_RECORD['transaction_ean_upc']::NUMBER), ''),
            COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER),
            NULLIF(TRIM(COALESCE(DELTA_RECORD['product_name']::VARCHAR, DELTA_RECORD[' product_name']::VARCHAR)), ''),
            NULLIF(TRIM(DELTA_RECORD['transaction_datetime']::VARCHAR), ''),
            NULLIF(TRIM(DELTA_RECORD['transaction_value']::NUMBER), ''),
            NULLIF(TRIM(DELTA_RECORD['transaction_store_id']::VARCHAR), '')
        ORDER BY DELTA_RAW_TIMESTAMP DESC
    ) AS ROW_NUMBER
  FROM {{ source('raw_retailer', 'raw_transaction') }}
  
WHERE TRIM(DELTA_RECORD['transaction_ean_upc']::VARCHAR) IS NOT NULL
  AND TRIM(DELTA_RECORD['transaction_ean_upc']::VARCHAR) <> ''
  AND DELTA_RECORD['retailer_group_id']::NUMBER <> 8
),

-- Step 2: de-duplicate, normalise to line totals and standardise country names
-- (suppliers send 'DE', 'Allemagne', 'Germany', ... for the same country).
TRANSACTION_SELECTION AS (
SELECT
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_EAN_UPC,
  TRANSACTION_DATE,
  CASE
        WHEN RETAILER_GROUP_ID IN (1,4,7,9,15,17,22,24,25,27,29,38,39,40) THEN COALESCE(TRANSACTION_VALUE, 0) -- already a line total
        ELSE
        COALESCE(TRANSACTION_VALUE, 0) *  ABS(TRANSACTION_QUANTITY)--ABS to avoid -ve(item_price) * -ve(quantity) = +ve
        END AS TRANSACTION_VALUE,
  
  TRANSACTION_MARKET,
  TRANSACTION_CURRENCY,
  TRANSACTION_QUANTITY,
  CASE 
    WHEN LOWER(TRANSACTION_COUNTRY) IN ('de','germany','allemagne') THEN 'Germany'
    WHEN LOWER(TRANSACTION_COUNTRY) IN ('switzerland','ch') THEN 'Switzerland'  
    WHEN LOWER(TRANSACTION_COUNTRY) IN ('austria','autriche','at') THEN 'Austria'
    WHEN LOWER(TRANSACTION_COUNTRY) IN ('united kingdom','gb', 'gbr') THEN 'United Kingdom'
    WHEN LOWER(TRANSACTION_COUNTRY) IN ('france','fr', 'fra') THEN 'France'
    ELSE TRANSACTION_COUNTRY
    END as TRANSACTION_COUNTRY,
  TRANSACTION_CONCAT_KEY
FROM RETAILER_TRANSACTION
WHERE ROW_NUMBER = 1
AND YEAR(transaction_date) >= 2023
),

-- Step 3: match to the product master and allocate each value to exactly one bucket.
cte_select_join as (
SELECT 
  p.ean_upc,
  t.RETAILER_GROUP_ID,
  t.RETAILER,
  t.TRANSACTION_EAN_UPC,
  t.TRANSACTION_DATE,
  t.TRANSACTION_MARKET,
  t.TRANSACTION_CURRENCY,
  t.TRANSACTION_COUNTRY,
  t.TRANSACTION_CONCAT_KEY,
  t.TRANSACTION_VALUE AS RAW_DATA_VALUE,
  
  -- MUTUALLY EXCLUSIVE CATEGORIES - ALL FOUR CATEGORIES:
  -- 1. Dashboard Value: Has product match AND product market is 'outdoor' (excluding specific categories)
  CASE 
  WHEN p.ean_upc IS NOT NULL 
    AND LOWER(TRIM(p.product_market)) = 'outdoor'
    AND NOT (p.product_department_id = 3 AND p.product_category_id IN (2,26,27))  -- EXCLUDE from dashboard even though product market is outdoor
  THEN t.TRANSACTION_VALUE 
  ELSE NULL 
  END AS DASHBOARD_VALUE,
  
  -- 2. Non-Outdoor Value:
  --    - has a product match AND product market is NOT 'outdoor', or
  --    - no product match AND transaction market is NOT 'outdoor' (and not null/empty), or
  --    - the outdoor products carved out of the dashboard in bucket 1
CASE 
  WHEN (p.ean_upc IS NOT NULL AND LOWER(TRIM(p.product_market)) <> 'outdoor') OR 
       (p.ean_upc IS NULL AND TRIM(t.TRANSACTION_MARKET) IS NOT NULL AND TRIM(t.TRANSACTION_MARKET) <> '' AND LOWER(TRIM(t.TRANSACTION_MARKET)) <> 'outdoor') OR
       (p.product_department_id = 3 AND p.product_category_id IN (2,26,27) AND LOWER(TRIM(p.product_market)) = 'outdoor' AND p.ean_upc IS NOT NULL)  -- ADD the hidden group here
  THEN t.TRANSACTION_VALUE 
  ELSE NULL 
END AS NON_OUTDOOR_VALUE,
  
  -- 3. Unmatched Value: No product match AND transaction market is 'outdoor' ONLY
  CASE 
    WHEN p.ean_upc IS NULL AND TRIM(t.TRANSACTION_MARKET) IS NOT NULL AND TRIM(t.TRANSACTION_MARKET) <> '' AND LOWER(TRIM(t.TRANSACTION_MARKET)) = 'outdoor'
    THEN t.TRANSACTION_VALUE 
    ELSE NULL 
  END AS UNMATCHED_VALUE,
  
  -- 4. Unmatched Unknown Market: No product match AND transaction market is NULL/empty
  CASE 
    WHEN p.ean_upc IS NULL AND (TRIM(t.TRANSACTION_MARKET) IS NULL OR TRIM(t.TRANSACTION_MARKET) = '')
    THEN t.TRANSACTION_VALUE 
    ELSE NULL 
  END AS UNMATCHED_UNKNOWN_MARKET

FROM TRANSACTION_SELECTION t 
LEFT JOIN {{ ref('dim_product') }} p ON p.ean_upc = t.TRANSACTION_EAN_UPC
)

-- Step 4: aggregate per transaction; the four buckets sum to RAW_DATA_VALUE.
SELECT 
  ean_upc,
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_EAN_UPC,
  TRANSACTION_DATE,
  TRANSACTION_MARKET,
  TRANSACTION_CURRENCY,
  TRANSACTION_COUNTRY,
  TRANSACTION_CONCAT_KEY,
  SUM(RAW_DATA_VALUE) as RAW_DATA_VALUE,
  SUM(UNMATCHED_VALUE) as UNMATCHED_VALUE,
  SUM(NON_OUTDOOR_VALUE) as NON_OUTDOOR_VALUE,
  SUM(DASHBOARD_VALUE) as DASHBOARD_VALUE,
  SUM(UNMATCHED_UNKNOWN_MARKET) as UNMATCHED_UNKNOWN_MARKET
  
FROM cte_select_join
GROUP BY
  ean_upc,
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_EAN_UPC,
  TRANSACTION_DATE,
  TRANSACTION_MARKET,
  TRANSACTION_CURRENCY,
  TRANSACTION_COUNTRY,
  TRANSACTION_CONCAT_KEY

