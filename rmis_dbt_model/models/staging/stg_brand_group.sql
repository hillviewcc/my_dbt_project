/*
==============================================================================
  Model     : stg_brand_group
  Layer     : Staging | incremental (merge)
  Purpose   : Typed brand-group staging table with a hashed surrogate key.
  Grain     : One row per brand_group_id.
  Depends on: lnd_static_brand_group
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='brand_group_id', 
    incremental_strategy='merge' 
    
  )
}}


select 
bg.brand_group                 as brand_group,
bg.brand_group_id              as brand_group_id,
abs(hash(bg.brand_group_id))   as brand_group_key,
bg.loaded_timestamp            as loaded_datetime
from {{ ref('lnd_static_brand_group') }} bg

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where bg.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}