/*
==============================================================================
  Model     : dim_product_category
  Layer     : Reporting | incremental (merge)
  Purpose   : Product category dimension (EN/FR/DE labels).
  Grain     : One row per product_category_id.
  Depends on: stg_product_category
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='product_category_id', 
    incremental_strategy='merge' 
    
  )
}}


select
pc.product_category,
pc.product_category_fr,
pc.product_category_de,
pc.product_category_id ,
product_category_key,
pc.loaded_datetime                 
from {{ ref('stg_product_category') }} pc

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where pc.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}