/*
==============================================================================
  Model     : lnd_static_brand_group
  Layer     : Landing | view
  Purpose   : Latest version of the brand-group (parent company) reference
              list.
  Grain     : One row per BRAND_GROUP_ID.
  Depends on: source raw_static.raw_static_brand_group
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH BRAND_GROUP AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['brand_group']::VARCHAR AS BRAND_GROUP
    , SNAPSHOT_RECORD['brand_group_id']::NUMBER AS BRAND_GROUP_ID
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['brand_group_id']::NUMBER ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_brand_group') }}
  
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , BRAND_GROUP
  , BRAND_GROUP_ID
FROM BRAND_GROUP
WHERE
  ROW_NUMBER = 1
  
