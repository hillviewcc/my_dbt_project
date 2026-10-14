/*
==============================================================================
  Model     : dim_brand
  Layer     : Reporting | incremental (merge)
  Purpose   : Brand dimension.
  Grain     : One row per brand_id.
  Depends on: stg_brand
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='brand_id', 
    incremental_strategy='merge' 
  )
}}

select
sb.brand_description,
sb.brand_id ,
sb.brand_key,
sb.single_brand,
sb.loaded_datetime
from {{ ref('stg_brand') }} sb

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sb.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}