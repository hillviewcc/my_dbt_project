/*
==============================================================================
  Model     : lnd_static_department
  Layer     : Landing | view
  Purpose   : Product department reference list with English, French and
              German display names.
  Grain     : One row per DEPARTMENT_ID.
  Depends on: source raw_static.raw_static_department
  Notes     : Static reference data arrives as JSON snapshots (SNAPSHOT_RECORD
              variant). ROW_NUMBER() keeps only the most recent version of
              each record, so re-sent files never create duplicates.
==============================================================================
*/
WITH DEPARTMENT AS (
  SELECT
    SOURCE_S3_URI_KEY
    , SNAPSHOT_RAW_DIFF_KEY
    , SNAPSHOT_RAW_KEY
    , SNAPSHOT_RAW_TIMESTAMP
    , SNAPSHOT_RECORD['display_department']::VARCHAR AS PRODUCT_DEPARTMENT -- used display_department as department for easy sorting in Quicksight 
    , SNAPSHOT_RECORD['display_department_fr']::VARCHAR AS PRODUCT_DEPARTMENT_FR 
    , SNAPSHOT_RECORD['display_department_de']::VARCHAR AS PRODUCT_DEPARTMENT_DE
    , SNAPSHOT_RECORD['department_id']::NUMBER AS DEPARTMENT_ID
    , ROW_NUMBER() OVER (PARTITION BY SNAPSHOT_RECORD['department_id']::NUMBER ORDER BY SNAPSHOT_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_static', 'raw_static_department') }}
)

SELECT
  SNAPSHOT_RAW_DIFF_KEY AS RECORD_HASHKEY
  , SNAPSHOT_RAW_KEY AS SOURCE_HASHKEY
  , SNAPSHOT_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , PRODUCT_DEPARTMENT
  , PRODUCT_DEPARTMENT_FR
  , PRODUCT_DEPARTMENT_DE
  , DEPARTMENT_ID
FROM DEPARTMENT
WHERE
  ROW_NUMBER = 1