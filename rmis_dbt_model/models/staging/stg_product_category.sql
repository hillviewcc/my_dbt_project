/*
==============================================================================
  Model     : stg_product_category
  Layer     : Staging | incremental (merge)
  Purpose   : Product category staging table (EN/FR/DE labels) with a hashed
              surrogate key.
  Grain     : One row per product_category_id.
  Depends on: lnd_static_product_category
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
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
pc.product_category                 as product_category,
pc.product_category_fr              as product_category_fr,
pc.product_category_de              as product_category_de,
pc.product_category_id              as product_category_id,
abs(hash(pc.product_category_id))   as product_category_key,
pc.loaded_timestamp                 as loaded_datetime
from {{ ref('lnd_static_product_category') }} pc

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where pc.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}