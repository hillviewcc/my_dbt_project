/*
==============================================================================
  Model     : lnd_static_market
  Layer     : Landing | view
  Purpose   : Market reference list (e.g. OUTDOOR) used to scope which
              products are reported on.
  Grain     : One row per MARKET.
  Depends on: source raw_static.raw_static_market
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH MARKET 
 AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['market_id']::NUMBER AS MARKET_ID
    , SNAPSHOT_RECORD['market']::VARCHAR AS MARKET
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['market']::VARCHAR ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_market') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , MARKET_ID
  , MARKET
FROM MARKET
WHERE
  ROW_NUMBER = 1
