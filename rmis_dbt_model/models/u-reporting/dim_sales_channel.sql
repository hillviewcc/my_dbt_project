/*
==============================================================================
  Model     : dim_sales_channel
  Layer     : Reporting | incremental (merge)
  Purpose   : Sales channel dimension (one row per raw channel mapping).
  Grain     : One row per sales_mapping_key.
  Depends on: stg_sales_channel
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='sales_mapping_key', 
    incremental_strategy='merge' 
    
  )
}}

select 
sc.sales_channel_id,
sc.sales_mapping_key,
sc.sales_channel,
sc.sales_channel_fr,
sc.sales_channel_de,
sc.sales_channel_group,
sc.sales_channel_group_fr,
sc.sales_channel_group_de,
sc.transaction_mapping,
sc.loaded_datetime  

from {{ ref('stg_sales_channel') }} sc

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sc.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}