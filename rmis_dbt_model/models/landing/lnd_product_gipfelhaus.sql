/*
==============================================================================
  Model     : lnd_product_gipfelhaus
  Layer     : Landing | view
  Purpose   : Builds a synthetic product file for the Gipfelhaus supplier, who
              sends aggregated sales only (no product master). Product
              attributes are taken from the supplier's transaction rows
              instead.
  Grain     : One row per generated EAN_UPC (latest load wins), transactions
              from 2023 onwards.
  Depends on: source raw_retailer.raw_transaction (retailer_group_id = 40)
  Notes     : EANs are generated during pre-processing and change on every
              run, so this supplier is fully reloaded each month instead of
              loaded incrementally.
==============================================================================
*/
/*
Note on Gipfelhaus supplier:
- Gipfelhaus does not supply granular transaction records at daily level.
- Missing fields: ean_UPC, transaction_id, retailer, and product name.
- No product file provided; generating product file from transaction file.
- EAN_UPC and transaction_id are generated internally.
- Since these fields are randomly generated, a full load is performed monthly, wiping previous month data to avoid duplication as EANs will differ each preprocessing run.
*/

WITH GIPFELHAUS_PRODUCT_FILE
 AS (
  SELECT
    SOURCE_S3_URI_KEY,
    DELTA_RAW_DIFF_KEY,
    DELTA_RAW_KEY,
    DELTA_RAW_TIMESTAMP,
    TO_DATE(
    TRY_TO_TIMESTAMP_TZ(
        CASE
           --     TO_CHAR(TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z'), 'YYYY-MM-DD HH24:MI:SS')
            WHEN TRY_TO_TIMESTAMP_TZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY/MM/DD HH24:MI:SS') IS NOT NULL THEN
                REPLACE(DELTA_RECORD['transaction_datetime']::STRING, '/', '-')
            ELSE
                NULL
        END, 'YYYY-MM-DD HH24:MI:SS'
    )
) AS TRANSACTION_DATE,
    DELTA_RECORD['transaction_ean_upc']::NUMBER AS EAN_UPC,
   COALESCE(DELTA_RECORD['product_name']::VARCHAR, DELTA_RECORD[' product_name']::VARCHAR) AS PRODUCT_NAME,
    DELTA_RECORD['gender']::VARCHAR AS GENDER,
    DELTA_RECORD['color']::VARCHAR AS COLOUR,
    DELTA_RECORD['size']::VARCHAR AS SIZE,
     ''  AS SUSTAINABILITY,   -- not supplied by this retailer; kept so the columns match lnd_product
    DELTA_RECORD['transaction_market']::VARCHAR AS MARKET,
    DELTA_RECORD['department_id']::NUMBER AS DEPARTMENT_ID,
    DELTA_RECORD['category_id']::NUMBER AS CATEGORY_ID,
    DELTA_RECORD['sub_category_id']::NUMBER AS SUB_CATEGORY_ID,
    DELTA_RECORD['brand_id']::NUMBER AS BRAND_ID,
    DELTA_RECORD['brand_group_id']::NUMBER AS BRAND_GROUP_ID,
    NULLIF(TRIM(DELTA_RECORD['shell_construction']::VARCHAR), '') AS shell_construction
    ,CASE
       WHEN LOWER(NULLIF(TRIM(DELTA_RECORD['shell_construction']::VARCHAR), '')) IN ('hardshell', 'softshell')
       AND (
         LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), '')) LIKE 'unknown%'
         OR LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), '')) IS NULL
       )
      THEN 'not_applicable'
      ELSE LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), ''))
    END AS insulation_type

,CASE 
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('backcountry_ski_touring', 'resort_ski_snowboard') THEN 'Ski'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) = 'camping_backpacking' THEN 'Camping'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('climbing_bouldering', 'mountaineering_alpine') THEN 'Climbing'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('hiking_day', 'hiking_trekking_multiday') THEN 'Hiking'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) = 'trail_running' THEN 'Running'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('everyday_outdoor', 'lifestyle_casual', 'multisport_allrounder', 'other', 'travel_commute') THEN 'Everyday'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('unknown', 'Unknown Primary Use', '') THEN 'Unknown Primary Use'
  WHEN DELTA_RECORD['primary_use']::VARCHAR IS NULL THEN 'Unknown Primary Use'
  ELSE 'Unknown Primary Use'
END AS PRIMARY_USE

-- keep the latest load of each generated EAN
,    ROW_NUMBER() OVER (
         PARTITION BY DELTA_RECORD['transaction_ean_upc']::NUMBER
         ORDER BY DELTA_RAW_TIMESTAMP DESC
       ) AS ROW_NUMBER
  FROM {{ source('raw_retailer', 'raw_transaction') }}
  where CAST(DELTA_RECORD['retailer_group_id'] AS INTEGER) = 40   -- Gipfelhaus only
 )
SELECT
  DELTA_RAW_DIFF_KEY AS RECORD_HASHKEY
  , DELTA_RAW_KEY AS SOURCE_HASHKEY
  , DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , EAN_UPC
  , PRODUCT_NAME
  , GENDER
  , COLOUR
  , SIZE
  , SUSTAINABILITY
  , MARKET
  , DEPARTMENT_ID
  , CATEGORY_ID
  , SUB_CATEGORY_ID
  , BRAND_ID
  , BRAND_GROUP_ID
  , SHELL_CONSTRUCTION
  , INSULATION_TYPE
  , PRIMARY_USE
FROM GIPFELHAUS_PRODUCT_FILE
WHERE
ROW_NUMBER = 1
and year(transaction_date) >= 2023   -- same history window as lnd_transaction