/*
==============================================================================
  Model     : lnd_static_defaults
  Layer     : Landing | view
  Purpose   : Per-user default retailer / store used by the BI tool when a
              dashboard is opened.
  Grain     : One row per DEFAULT_USER.
  Depends on: source raw_static.raw_static_defaults
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH STATIC_DEFAULTS AS (
SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['user']::VARCHAR AS DEFAULT_USER
    , SNAPSHOT_RECORD['default_retailer']::VARCHAR AS DEFAULT_RETAILER
    , SNAPSHOT_RECORD['default_retailer_group']::VARCHAR AS DEFAULT_RETAILER_GROUP
    , SNAPSHOT_RECORD['default_store']::VARCHAR AS DEFAULT_STORE
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['user']::VARCHAR ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_defaults') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , DEFAULT_USER
  , DEFAULT_RETAILER
  , DEFAULT_RETAILER_GROUP
  , DEFAULT_STORE
FROM STATIC_DEFAULTS
WHERE
  ROW_NUMBER = 1
  
  