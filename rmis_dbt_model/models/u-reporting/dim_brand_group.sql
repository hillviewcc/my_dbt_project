/*
==============================================================================
  Model     : dim_brand_group
  Layer     : Reporting | incremental (merge)
  Purpose   : Brand-group (parent company) dimension.
  Grain     : One row per brand_group_id.
  Depends on: stg_brand_group
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
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
brand_group,
brand_group_id,
brand_group_key,
loaded_datetime
from {{ ref('stg_brand_group') }} bg

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where bg.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}