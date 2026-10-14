/*
==============================================================================
  Model     : stg_store
  Layer     : Staging | incremental (merge)
  Purpose   : Store staging table.
  Grain     : One row per store_key.
  Depends on: lnd_store
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
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
  st.store_id::varchar             as store_id,
  st.store_key                     as store_key, 
  st.store_name                    as store_name, 
  st.store_postcode                as store_postcode, 
  st.store_postcode_area           as store_postcode_area, 
  st.store_tenure                  as store_tenure, 
  st.store_city                    as store_city, 
  st.store_county                  as store_county, 
  st.store_region                  as store_region, 
  st.store_country                 as store_country, 
  st.store_latitude                as store_latitude, 
  st.store_longitude               as store_longitude, 
  st.retailer_group_id             as retailer_group_id,
  st.retailer_id                   as retailer_id,  
  st.loaded_timestamp              as loaded_datetime 
from {{ ref('lnd_store') }} st


{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where st.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}