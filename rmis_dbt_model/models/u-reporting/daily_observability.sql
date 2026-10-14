/*
==============================================================================
  Model     : daily_observability
  Layer     : Reporting | table
  Purpose   : Data-observability view of last month's deliveries: for every
              participating retailer, the value and volume received per day.
              Retailers with no rows (LEFT JOIN from dim_retailer) show up as
              gaps.
  Grain     : One row per (retailer, transaction date, market, currency,
              product, transaction key).
  Depends on: source raw_retailer.raw_transaction, dim_retailer
  Notes     : Reads the raw source directly (not lnd_transaction) so it
              reflects exactly what each supplier delivered, before any in-
              scope filtering.
==============================================================================
*/

-- Step 1: parse the raw records with the same rules as lnd_transaction
-- (dates, store ids, signs of returns) but WITHOUT the retailer allow-list,
-- so every delivery is visible.
WITH RETAILER_TRANSACTION 
 AS (
  SELECT
    DELTA_RAW_TIMESTAMP,
    DELTA_RECORD['retailer_group_id']::NUMBER AS RETAILER_GROUP_ID,
    COALESCE(NULLIF(TRIM(DELTA_RECORD['retailer']::VARCHAR), ''), TRIM(DELTA_RECORD['retailer']::VARCHAR)) AS RETAILER,
    DELTA_RECORD['transaction_id']::VARCHAR AS TRANSACTION_ID,

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

    TO_DATE(TRY_TO_TIMESTAMP_TZ(
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
    )) AS TRANSACTION_DATETIME,

    DELTA_RECORD['transaction_channel']::VARCHAR AS TRANSACTION_CHANNEL,
    CASE
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'trailstep.com'
       THEN 'Trailstep.com/UK'   -- added this to cater for the changes made to the trailstep
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 20 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = '0'  
       THEN 'GB'   -- transform all historic '0' values to 'GB' for this supplier
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 7 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'summitgear.store'  
       THEN 'summitgear.store_GB'   -- transform all historic 'summitgear.store' values to 'summitgear.store_GB'  for this supplier
       ELSE
       DELTA_RECORD['transaction_store_id']::VARCHAR
       END AS TRANSACTION_STORE_ID,
    DELTA_RECORD['transaction_ean_upc']::NUMBER AS TRANSACTION_EAN_UPC,  --- change this back to number data type
   --to make sure that the negative quantity is also negative transaction value depicting a return
    CASE
    -- Both negative (return) - keep value negative
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER < 0 
        THEN DELTA_RECORD['transaction_value']::NUMBER(38, 2)
    
    -- Negative quantity, positive value - make value negative  
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER > 0
        THEN -DELTA_RECORD['transaction_value']::NUMBER(38, 2)

    -- Both positive (normal sale) - keep as is
    ELSE DELTA_RECORD['transaction_value']::NUMBER(38, 2)
END AS TRANSACTION_VALUE,
    
    --to make sure that the negative transaction value is also negative transaction quantity depicting a return
    CASE 
    -- Both negative (return) - keep quantity negative
    WHEN DELTA_RECORD['transaction_value']::NUMBER < 0 AND 
         COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER) < 0
    THEN COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
    
    -- Negative value, positive quantity - make quantity negative
    WHEN DELTA_RECORD['transaction_value']::NUMBER < 0 AND 
         COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER) > 0
    THEN -COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
    
    -- Both positive (normal sale) - keep as is
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
    END AS TRANSACTION_COUNTRY, --- ???why cant we just ask for country
    COALESCE(DELTA_RECORD['product_name']::VARCHAR, DELTA_RECORD[' product_name']::VARCHAR) AS TRANSACTION_PRODUCT_NAME,
    DELTA_RECORD['category']::VARCHAR AS TRANSACTION_PRODUCT_CATEGORY,
    DELTA_RECORD['sub_category']::VARCHAR AS TRANSACTION_PRODUCT_SUB_CATEGORY,
    DELTA_RECORD['color']::VARCHAR AS TRANSACTION_PRODUCT_COLOUR,
    DELTA_RECORD['size']::VARCHAR AS TRANSACTION_PRODUCT_SIZE,
    DELTA_RECORD['brand']::VARCHAR AS TRANSACTION_PRODUCT_BRAND,
    DELTA_RECORD['mpn']::VARCHAR AS TRANSACTION_PRODUCT_MPN,
    DELTA_RECORD['sku']::VARCHAR AS TRANSACTION_PRODUCT_SKU,
    DELTA_RECORD['plu']::VARCHAR AS TRANSACTION_PRODUCT_PLU,

  ABS(HASH(
    NULLIF(TRIM(DELTA_RECORD['transaction_id']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['retailer']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_ean_upc']::NUMBER), ''),
    NULLIF(TRIM(COALESCE(DELTA_RECORD['transaction_quantity']::VARCHAR, DELTA_RECORD[' transaction_quantity']::VARCHAR)), ''),
    NULLIF(TRIM(DELTA_RECORD['product_name']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_store_id']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_datetime']::VARCHAR), ''),
    NULLIF(TRIM(DELTA_RECORD['transaction_value']::NUMBER), '')
)) AS TRANSACTION_CONCAT_KEY, --composite key for merge

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
  AND TRIM(DELTA_RECORD['transaction_id']::VARCHAR) NOT IN ('2264','2166','2187','2227','2120','2224','2168') -- known bad records (no retailer / store id)
  AND DELTA_RECORD['retailer_group_id']::NUMBER <> 8 --retailer no longer participating

),

-- Step 2: de-duplicate, normalise values to line totals and restrict to
-- last calendar month.
TRANSACTION_SELECTION AS (
SELECT
  DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP,
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_ID,
  TRANSACTION_DATE,
  TRANSACTION_DATETIME,
   CASE
        WHEN RETAILER_GROUP_ID IN (1,4,7,9,15,17,22,24,25,27,29,38,39,40,46,48,49,50) THEN COALESCE(TRANSACTION_VALUE, 0) -- already a line total
        ELSE
        COALESCE(TRANSACTION_VALUE, 0) *  ABS(TRANSACTION_QUANTITY)--ABS to avoid -ve(item_price) * -ve(quantity) = +ve
        END AS TRANSACTION_VALUE,
  TRANSACTION_MARKET,
  TRANSACTION_QUANTITY,
  TRANSACTION_CURRENCY,
  TRANSACTION_COUNTRY,
  TRANSACTION_PRODUCT_NAME,
  TRANSACTION_CONCAT_KEY
FROM RETAILER_TRANSACTION
WHERE ROW_NUMBER = 1
AND transaction_date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
AND transaction_date <= DATEADD('day', -1, DATE_TRUNC('month', CURRENT_DATE))  -- to restrict data volume for just last month data
)

-- Step 3: start from the retailer list so retailers with NO data last month
-- still appear (with NULL values) - that gap is what this model is for.

SELECT 
  r.RETAILER_NAME,
  r.RETAILER_ID,
  r.transaction_mapping,
  t.TRANSACTION_DATE,
  t.TRANSACTION_MARKET,
  t.TRANSACTION_CURRENCY,
  t.TRANSACTION_PRODUCT_NAME,
  t.TRANSACTION_CONCAT_KEY,
  SUM(t.TRANSACTION_QUANTITY) AS TRANSACTION_QUANTITY,
  SUM(t.TRANSACTION_VALUE) AS TRANSACTION_VALUE
FROM {{ ref('dim_retailer') }} r 
LEFT JOIN TRANSACTION_SELECTION t ON  r.transaction_mapping = t.RETAILER
where r.retailer_id not in (2,3,10,11,15,17,18,19,21,23,24,16,13,26) -- exclude old non participating retailers
GROUP BY
  r.RETAILER_NAME,
  r.RETAILER_ID,
  r.transaction_mapping,
  t.TRANSACTION_DATE,
  t.TRANSACTION_MARKET,
  t.TRANSACTION_CURRENCY,
  t.TRANSACTION_PRODUCT_NAME,
  t.TRANSACTION_CONCAT_KEY