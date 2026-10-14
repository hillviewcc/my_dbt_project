/*
==============================================================================
  Model     : lnd_static_brand
  Layer     : Landing | view
  Purpose   : Latest version of the internally maintained brand reference
              list.
  Grain     : One row per BRAND_DESCRIPTION.
  Depends on: source raw_static.raw_static_brand
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH BRAND AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['brand_description']::VARCHAR AS BRAND_DESCRIPTION
    , SNAPSHOT_RECORD['single_brand']::VARCHAR AS single_brand
    , SNAPSHOT_RECORD['brand_id']::NUMBER AS BRAND_ID
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['brand_description']::VARCHAR ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_brand') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , BRAND_DESCRIPTION
  , SINGLE_BRAND
  , BRAND_ID
FROM BRAND
WHERE
  ROW_NUMBER = 1

