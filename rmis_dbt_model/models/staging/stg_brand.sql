/*
==============================================================================
  Model     : stg_brand
  Layer     : Staging | incremental (merge)
  Purpose   : Typed brand dimension staging table with a hashed surrogate key.
  Grain     : One row per brand_id.
  Depends on: lnd_static_brand
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
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
  sb.brand_description        as brand_description,
  sb.brand_id                 as brand_id,
  abs(hash(sb.brand_id))      as brand_key,
  sb.single_brand             as single_brand,
  sb.loaded_timestamp         as loaded_datetime
from {{ ref('lnd_static_brand') }} sb

{% if is_incremental() %}
  -- Load only new or updated records based on loaded_timestamp
  where sb.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}
