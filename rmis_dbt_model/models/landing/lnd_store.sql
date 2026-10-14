/*
==============================================================================
  Model     : lnd_store
  Layer     : Landing | view
  Purpose   : Retailer store master: location, tenure and geography of each
              physical or online store.
  Grain     : One row per (RETAILER_GROUP_ID, STORE_ID), latest load wins.
  Depends on: source raw_retailer.raw_store
  Notes     : STORE_KEY is a hash of store_id + retailer_id because store ids
              are only unique within a retailer.
==============================================================================
*/
 WITH RETAILER_STORE  AS(
 SELECT
    SOURCE_S3_URI_KEY
    , DELTA_RAW_DIFF_KEY
    , DELTA_RAW_KEY
    , DELTA_RAW_TIMESTAMP
    , DELTA_RECORD['retailer_group_id']::NUMBER AS RETAILER_GROUP_ID
    , DELTA_RECORD['retailer_id']::NUMBER AS RETAILER_ID
    , DELTA_RECORD['store_id']::VARCHAR AS STORE_ID
    , DELTA_RECORD['retailer_mapping']::VARCHAR AS RETAILER_MAPPING
    -- surrogate key: hash of store_id + retailer_id
    , CONCAT(abs(hash(DELTA_RECORD['store_id']::VARCHAR, '-', DELTA_RECORD['retailer_id']::VARCHAR))) as STORE_KEY
    , DELTA_RECORD['store_name']::VARCHAR AS STORE_NAME
    -- TRY_CAST: bad coordinates become NULL instead of failing the load
    , TRY_CAST(DELTA_RECORD['store_longitude']::VARCHAR AS DOUBLE) AS STORE_LONGITUDE
    , TRY_CAST(DELTA_RECORD['store_latitude']::VARCHAR AS DOUBLE) AS STORE_LATITUDE
    , DELTA_RECORD['store_tenure']::VARCHAR AS STORE_TENURE
    , DELTA_RECORD['store_postcode']::VARCHAR AS STORE_POSTCODE
    , DELTA_RECORD['store_postcode_area']::VARCHAR AS STORE_POSTCODE_AREA
    , DELTA_RECORD['store_city']::VARCHAR AS STORE_CITY
    , DELTA_RECORD['store_county']::VARCHAR AS STORE_COUNTY
    , DELTA_RECORD['store_region']::VARCHAR AS STORE_REGION
    , DELTA_RECORD['store_country']::VARCHAR AS STORE_COUNTRY
    -- store ids are only unique within a retailer group; keep the latest version of each
    , ROW_NUMBER() OVER (PARTITION BY DELTA_RECORD['retailer_group_id']::NUMBER, DELTA_RECORD['store_id']::VARCHAR ORDER BY DELTA_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{source('raw_retailer', 'raw_store')}}
 )
  SELECT
  DELTA_RAW_DIFF_KEY AS RECORD_HASHKEY
  , DELTA_RAW_KEY AS SOURCE_HASHKEY
  , DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , RETAILER_GROUP_ID
  , RETAILER_ID
  , STORE_ID
  , STORE_KEY
  , STORE_NAME
  , STORE_LONGITUDE
  , STORE_LATITUDE
  , STORE_TENURE
  , STORE_POSTCODE
  , STORE_POSTCODE_AREA
  , STORE_CITY
  , STORE_COUNTY
  , STORE_REGION
  , STORE_COUNTRY
FROM RETAILER_STORE
WHERE
  ROW_NUMBER = 1