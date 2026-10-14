/*
==============================================================================
  Model     : lnd_static_retailer
  Layer     : Landing | view
  Purpose   : Retailer reference list: name, group, segment, size, coverage,
              reporting country and the TRANSACTION_MAPPING value used to
              match raw transaction rows to a retailer.
  Grain     : One row per RETAILER_ID.
  Depends on: source raw_static.raw_static_retailer
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates. Retailer
              groups that no longer share data are excluded.
==============================================================================
*/
WITH RETAILER AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['retailer_id']::NUMBER AS RETAILER_ID
    , SNAPSHOT_RECORD['country']::VARCHAR AS RETAILER_TRANSACTION_COUNTRY
    , SNAPSHOT_RECORD['retailer_name']::VARCHAR AS RETAILER_NAME
    , SNAPSHOT_RECORD['retailer_group_id']::NUMBER AS RETAILER_GROUP_ID
    , SNAPSHOT_RECORD['retailer_group']::VARCHAR AS RETAILER_GROUP
    , SNAPSHOT_RECORD['retailer_segment']::VARCHAR AS RETAILER_SEGMENT
    , SNAPSHOT_RECORD['retailer_physical_size']::VARCHAR AS RETAILER_PHYSICAL_SIZE
    , SNAPSHOT_RECORD['retailer_coverage']::VARCHAR AS RETAILER_COVERAGE
    , SNAPSHOT_RECORD['transaction_mapping']::VARCHAR AS TRANSACTION_MAPPING
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['retailer_id']::VARCHAR ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_retailer') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , RETAILER_ID
  , RETAILER_TRANSACTION_COUNTRY
  , RETAILER_NAME
  , RETAILER_GROUP_ID
  , RETAILER_GROUP
  , RETAILER_SEGMENT
  , RETAILER_PHYSICAL_SIZE
  , RETAILER_COVERAGE
  , TRANSACTION_MAPPING
FROM RETAILER
WHERE
  ROW_NUMBER = 1
  and retailer_group_id not in (2,3,5,6,10,12,13,14,16,18,19) -- exclude retailers who are not relevant for the analysis
  
