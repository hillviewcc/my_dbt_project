/*
==============================================================================
  Model     : lnd_static_product_category
  Layer     : Landing | view
  Purpose   : Product category reference list with English, French and German
              display names.
  Grain     : One row per PRODUCT_CATEGORY_ID.
  Depends on: source raw_static.raw_static_product_category
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH CATEGORY AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['product_category']::VARCHAR AS PRODUCT_CATEGORY
    , SNAPSHOT_RECORD['display_category_fr']::VARCHAR AS PRODUCT_CATEGORY_FR
    , SNAPSHOT_RECORD['display_category_de']::VARCHAR AS PRODUCT_CATEGORY_DE
    , SNAPSHOT_RECORD['category_id']::NUMBER AS PRODUCT_CATEGORY_ID
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['category_id']::NUMBER ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_product_category') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , PRODUCT_CATEGORY
  , PRODUCT_CATEGORY_FR
  , PRODUCT_CATEGORY_DE
  , PRODUCT_CATEGORY_ID
FROM CATEGORY
WHERE
  ROW_NUMBER = 1