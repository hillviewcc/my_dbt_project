/*
==============================================================================
  Model     : dim_store
  Layer     : Reporting | incremental (merge)
  Purpose   : Store dimension.
  Grain     : One row per store_key.
  Depends on: stg_store
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='store_key', 
    incremental_strategy='merge' 
    
  )
}}
select 
  st.store_id,
  store_key, 
  st.retailer_id,
  st.store_name, 
  st.store_postcode, 
  st.store_postcode_area , 
  st.store_tenure, 
  st.store_city, 
  st.store_county, 
  st.store_region, 
  st.store_country, 
  st.store_latitude, 
  st.store_longitude, 
  st.retailer_group_id,
  st.loaded_datetime              as loaded_datetime 
from {{ ref('stg_store') }} st

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where st.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}