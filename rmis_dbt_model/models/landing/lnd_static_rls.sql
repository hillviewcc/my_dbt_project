/*
==============================================================================
  Model     : lnd_static_rls
  Layer     : Landing | view
  Purpose   : Row-level-security rules: which retailer / store / brand /
              category each BI user is allowed to see.
  Grain     : One row per USERNAME.
  Depends on: source raw_static.raw_static_rls
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH STATIC_RLS AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['username']::VARCHAR AS USERNAME
    , SNAPSHOT_RECORD['retailer_name']::VARCHAR AS RETAILER_NAME
    , SNAPSHOT_RECORD['retailer_group']::VARCHAR AS RETAILER_GROUP
    , SNAPSHOT_RECORD['store_name']::VARCHAR AS STORE_NAME
    , SNAPSHOT_RECORD['product_brand']::VARCHAR AS PRODUCT_BRAND
    , SNAPSHOT_RECORD['product_brand_group']::VARCHAR AS PRODUCT_BRAND_GROUP
    , SNAPSHOT_RECORD['product_category']::VARCHAR AS PRODUCT_CATEGORY
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['username']::VARCHAR ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_rls') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , USERNAME
  , RETAILER_NAME
  , RETAILER_GROUP
  , STORE_NAME
  , PRODUCT_BRAND
  , PRODUCT_BRAND_GROUP
  , PRODUCT_CATEGORY
FROM STATIC_RLS
WHERE
  ROW_NUMBER = 1
