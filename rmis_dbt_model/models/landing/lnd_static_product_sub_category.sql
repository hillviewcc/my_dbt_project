/*
==============================================================================
  Model     : lnd_static_product_sub_category
  Layer     : Landing | view
  Purpose   : Product sub-category reference list with English, French and
              German display names.
  Grain     : One row per SUB_CATEGORY_ID.
  Depends on: source raw_static.raw_static_product_sub_category
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH SUB_CATEGORY AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['product_sub_category']::VARCHAR AS PRODUCT_SUB_CATEGORY
    , SNAPSHOT_RECORD['display_sub_category_fr']::VARCHAR AS PRODUCT_SUB_CATEGORY_FR
    , SNAPSHOT_RECORD['display_sub_category_de']::VARCHAR AS PRODUCT_SUB_CATEGORY_DE
    , SNAPSHOT_RECORD['sub_category_id']::NUMBER AS SUB_CATEGORY_ID
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['sub_category_id']::NUMBER ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_product_sub_category') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , PRODUCT_SUB_CATEGORY
  , PRODUCT_SUB_CATEGORY_FR
  , PRODUCT_SUB_CATEGORY_DE
  , SUB_CATEGORY_ID
FROM SUB_CATEGORY
WHERE
  ROW_NUMBER = 1