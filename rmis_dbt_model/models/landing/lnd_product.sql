/*
==============================================================================
  Model     : lnd_product
  Layer     : Landing | view
  Purpose   : Extracts the retailer product master from the raw JSON feed and
              standardises free-text attributes (gender, jacket type, layer
              position, waterproofing, weight class, primary use) into a fixed
              set of reporting-friendly labels.
  Grain     : One row per EAN_UPC (latest load wins).
  Depends on: source raw_retailer.raw_product
  Notes     : Unrecognised or blank attribute values are mapped to an explicit
              'Unknown ...' label rather than NULL so dashboards always have a
              bucket to show.
==============================================================================
*/
WITH RETAILER_PRODUCT AS (
  SELECT
       SOURCE_S3_URI_KEY
     , DELTA_RAW_DIFF_KEY
     , DELTA_RAW_KEY
     , DELTA_RAW_TIMESTAMP
     , DELTA_RECORD['ean_upc']::NUMBER AS EAN_UPC
     , COALESCE(
         DELTA_RECORD['product_name']::VARCHAR,
         DELTA_RECORD[' product_name']::VARCHAR
       ) AS PRODUCT_NAME           -- some files send the key with a leading space
       -- Gender: every retailer uses its own codes ('M', '1-men', 'Mens', ...).
       -- Exact matches are checked first, then prefix matches as a fallback.
     , CASE
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'men','male','m','m - mens','man','1-men','mens'
         ) THEN 'MEN'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'woman','2-women','lady','w','womens','female','women'
         ) THEN 'WOMEN'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'youth','junior'
         ) THEN 'YOUTH'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'k','kid','kids','children','c','3-kids'
         ) THEN 'KIDS'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'unisex','uni','u','unisex all ages'
         ) THEN 'UNISEX'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'infant'
         ) THEN 'INFANT'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) IN (
           'not applicable','equipment','','n/a',
           'o - other','ski comp','#n/a','no gender'
         ) THEN 'NOT APPLICABLE'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) LIKE 'men%' THEN 'MENS'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) LIKE 'women%' THEN 'WOMENS'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) LIKE 'kid%' THEN 'KIDS'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) LIKE 'girl%' THEN 'GIRLS'
         WHEN LOWER(DELTA_RECORD['gender']::VARCHAR) LIKE 'boy%' THEN 'BOYS'
       END AS GENDER
     , DELTA_RECORD['color']::VARCHAR AS COLOUR
     , DELTA_RECORD['size']::VARCHAR AS SIZE
     , DELTA_RECORD['sustainability']::VARCHAR AS SUSTAINABILITY
     , DELTA_RECORD['market']::VARCHAR AS MARKET
    -- ---- Technical jacket attributes (produced by the AI product-categorisation pipeline) ----
    ,NULLIF(TRIM(DELTA_RECORD['shell_construction']::VARCHAR), '') AS shell_construction
    -- Insulation type: an uninsulated hard/soft shell has no insulation, so an
    -- 'unknown' value there really means 'not applicable'.
    ,CASE
       WHEN LOWER(NULLIF(TRIM(DELTA_RECORD['shell_construction']::VARCHAR), '')) IN ('hardshell', 'softshell')
       AND (
         LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), '')) LIKE 'unknown%'
         OR LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), '')) IS NULL
       )
      THEN 'not_applicable'
      ELSE LOWER(NULLIF(TRIM(DELTA_RECORD['insulation_type']::VARCHAR), ''))
    END AS insulation_type
    -- The CASE blocks below translate snake_case codes into display labels and
    -- group detailed values into broader buckets (e.g. all Gore-Tex variants ->
    -- 'Gore-Tex', ski touring + resort -> 'Ski'). Anything unrecognised falls
    -- into an 'Unknown ...' bucket.
     ,CASE
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'casual_lifestyle' THEN 'Casual Lifestyle'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'fleece_jacket' THEN 'Fleece Jacket'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'hardshell' THEN 'Hardshell'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'hybrid' THEN 'Hybrid'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'not_applicable' THEN 'Not Applicable'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'rain_jacket' THEN 'Rain Jacket'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'ski_snowboard_jacket' THEN 'Snow Jacket'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'softshell' THEN 'Softshell'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) = 'windbreaker' THEN 'Windbreaker'
  WHEN TRIM(DELTA_RECORD['jacket_type']::VARCHAR) IN ('unknown', 'Unknown Jacket Type', '') THEN 'Unknown Jacket Type'
  WHEN DELTA_RECORD['jacket_type']::VARCHAR IS NULL THEN 'Unknown Jacket Type'
  ELSE 'Unknown Jacket Type'
END AS JACKET_TYPE

,CASE 
  WHEN TRIM(DELTA_RECORD['layer_position']::VARCHAR) = 'base' THEN 'Base Layer'
  WHEN TRIM(DELTA_RECORD['layer_position']::VARCHAR) = 'mid' THEN 'Mid Layer'
  WHEN TRIM(DELTA_RECORD['layer_position']::VARCHAR) IN ('outer_insulated', 'outer_shell') THEN 'Outer Layer'
  WHEN TRIM(DELTA_RECORD['layer_position']::VARCHAR) = 'not_applicable' THEN 'Not Applicable'
  WHEN TRIM(DELTA_RECORD['layer_position']::VARCHAR) IN ('unknown', 'Unknown Layer Position', '') THEN 'Unknown Layer Position'
  WHEN DELTA_RECORD['layer_position']::VARCHAR IS NULL THEN 'Unknown Layer Position'
  ELSE 'Unknown Layer Position'
END AS LAYER_POSITION

,CASE 
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) = 'dwr_only' THEN 'Durable Water Repellent'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) IN ('gore_tex', 'gore_tex_active', 'gore_tex_infinium', 'gore_tex_pro') THEN 'Gore-Tex'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) = 'none' THEN 'Not Waterproof'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) = 'pertex_shield' THEN 'Pertex Shield'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) = 'proprietary_brand_membrane' THEN 'Brand Membrane'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) = 'other' THEN 'Other'
  WHEN TRIM(DELTA_RECORD['waterproof_technology']::VARCHAR) IN ('unknown', 'Unknown Waterproof Technology', '') THEN 'Unknown Waterproof Technology'
  WHEN DELTA_RECORD['waterproof_technology']::VARCHAR IS NULL THEN 'Unknown Waterproof Technology'
  ELSE 'Unknown Waterproof Technology'
END AS WATERPROOF_TECHNOLOGY

,CASE 
  WHEN TRIM(DELTA_RECORD['weight_class']::VARCHAR) = 'ultralight' THEN 'Ultralight'
  WHEN TRIM(DELTA_RECORD['weight_class']::VARCHAR) = 'lightweight' THEN 'Lightweight'
  WHEN TRIM(DELTA_RECORD['weight_class']::VARCHAR) = 'midweight' THEN 'Midweight'
  WHEN TRIM(DELTA_RECORD['weight_class']::VARCHAR) = 'heavyweight' THEN 'Heavyweight'
  WHEN TRIM(DELTA_RECORD['weight_class']::VARCHAR) IN ('unknown', 'Unknown Weight Class', '') THEN 'Unknown Weight Class'
  WHEN DELTA_RECORD['weight_class']::VARCHAR IS NULL THEN 'Unknown Weight Class'
  ELSE 'Unknown Weight Class'
END AS WEIGHT_CLASS

,CASE 
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('backcountry_ski_touring', 'resort_ski_snowboard') THEN 'Ski'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) = 'camping_backpacking' THEN 'Camping'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('climbing_bouldering', 'mountaineering_alpine') THEN 'Climbing'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('hiking_day', 'hiking_trekking_multiday') THEN 'Hiking'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) = 'trail_running' THEN 'Running'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('everyday_outdoor', 'lifestyle_casual', 'multisport_allrounder', 'other', 'travel_commute') THEN 'Everyday'
  WHEN TRIM(DELTA_RECORD['primary_use']::VARCHAR) IN ('unknown', 'Unknown Primary Use', '') THEN 'Unknown Primary Use'
  WHEN DELTA_RECORD['primary_use']::VARCHAR IS NULL THEN 'Unknown Primary Use'
  ELSE 'Unknown Primary Use'
END AS PRIMARY_USE
     -- foreign keys to the reference dimensions (assigned by the categorisation pipeline)
     , DELTA_RECORD['department_id']::NUMBER AS DEPARTMENT_ID
     , DELTA_RECORD['category_id']::NUMBER AS CATEGORY_ID
     , DELTA_RECORD['sub_category_id']::NUMBER AS SUB_CATEGORY_ID
     , DELTA_RECORD['brand_id']::NUMBER AS BRAND_ID
     , DELTA_RECORD['brand_group_id']::NUMBER AS BRAND_GROUP_ID
     -- keep only the most recent version of each product
     , ROW_NUMBER() OVER (
         PARTITION BY DELTA_RECORD['ean_upc']::NUMBER
         ORDER BY DELTA_RAW_TIMESTAMP DESC
       ) AS ROW_NUMBER
  FROM {{ source('raw_retailer', 'raw_product') }}
)

SELECT
  DELTA_RAW_DIFF_KEY AS RECORD_HASHKEY
  , DELTA_RAW_KEY AS SOURCE_HASHKEY
  , DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , EAN_UPC
  , PRODUCT_NAME
  , GENDER
  , COLOUR
  , SIZE
  , SUSTAINABILITY
  , MARKET
  , shell_construction
  , insulation_type
  , JACKET_TYPE
  , LAYER_POSITION
  , WATERPROOF_TECHNOLOGY
  , WEIGHT_CLASS
  , PRIMARY_USE
  , DEPARTMENT_ID
  , CATEGORY_ID
  , SUB_CATEGORY_ID
  , BRAND_ID
  , BRAND_GROUP_ID
FROM RETAILER_PRODUCT
WHERE
  ROW_NUMBER = 1