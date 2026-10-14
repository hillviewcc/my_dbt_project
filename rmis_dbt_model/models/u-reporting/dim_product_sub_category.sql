/*
==============================================================================
  Model     : dim_product_sub_category
  Layer     : Reporting | incremental (merge)
  Purpose   : Product sub-category dimension (EN/FR/DE labels).
  Grain     : One row per sub_category_id.
  Depends on: stg_product_sub_category
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='sub_category_id', 
    incremental_strategy='merge' 
    
  )
}}

select
sc.product_sub_category,
sc.product_sub_category_fr,
sc.product_sub_category_de,
sc.sub_category_id ,
sub_category_key,
sc.loaded_datetime                  
from {{ ref('stg_product_sub_category') }} sc

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sc.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}