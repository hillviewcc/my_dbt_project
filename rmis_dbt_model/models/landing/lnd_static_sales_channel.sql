/*
==============================================================================
  Model     : lnd_static_sales_channel
  Layer     : Landing | view
  Purpose   : Sales channel reference list (e.g. online / in-store) with
              translated labels. TRANSACTION_MAPPING holds a comma-separated
              list of the raw channel values that map to each channel; it is
              split into rows in stg_sales_channel.
  Grain     : One row per SALES_CHANNEL.
  Depends on: source raw_static.raw_static_sales_channel
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH SALES_CHANNEL AS (
  SELECT
    SOURCE_S3_URI_KEY,
    SNAPSHOT_RAW_DIFF_KEY,
    SNAPSHOT_RAW_KEY,
    SNAPSHOT_RAW_TIMESTAMP,
    SNAPSHOT_RECORD['sales_channel_id']::NUMBER AS SALES_CHANNEL_ID,
    TRIM(SNAPSHOT_RECORD['sales_channel']::VARCHAR) AS SALES_CHANNEL,
      TRIM(SNAPSHOT_RECORD['sales_channel_fr']::VARCHAR) AS SALES_CHANNEL_FR,
      TRIM(SNAPSHOT_RECORD['sales_channel_de']::VARCHAR) AS SALES_CHANNEL_DE,
    TRIM(SNAPSHOT_RECORD['sales_channel_group']::VARCHAR) AS SALES_CHANNEL_GROUP,
    TRIM(SNAPSHOT_RECORD['sales_channel_group_fr']::VARCHAR) AS SALES_CHANNEL_GROUP_FR,
    TRIM(SNAPSHOT_RECORD['sales_channel_group_de']::VARCHAR) AS SALES_CHANNEL_GROUP_DE,
    TRIM(SNAPSHOT_RECORD['transaction_mapping']::VARCHAR) AS TRANSACTION_MAPPING,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(SNAPSHOT_RECORD['sales_channel']::VARCHAR)
      ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC
    ) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_sales_channel') }}
)


SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , SALES_CHANNEL_ID
  , SALES_CHANNEL
  , SALES_CHANNEL_GROUP
  , SALES_CHANNEL_GROUP_FR
  , SALES_CHANNEL_GROUP_DE
  , SALES_CHANNEL_FR
  , SALES_CHANNEL_DE
  , TRANSACTION_MAPPING
FROM SALES_CHANNEL
WHERE
  ROW_NUMBER = 1
