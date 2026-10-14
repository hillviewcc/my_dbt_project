/*
==============================================================================
  Model     : stg_retailer
  Layer     : Staging | incremental (merge)
  Purpose   : Retailer staging table with a hashed surrogate key.
  Grain     : One row per retailer_id.
  Depends on: lnd_static_retailer
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='retailer_id', 
    incremental_strategy='merge' 
    
  )
}}

select
sr.retailer_id::number                as retailer_id,
abs(hash(sr.retailer_id))             as retailer_key,
sr.retailer_transaction_country       as retailer_transaction_country, 
sr.retailer_name                      as retailer_name, 
sr.retailer_group_id                  as retailer_group_id, 
sr.retailer_group                     as retailer_group,  
sr.retailer_segment                   as retailer_segment,  
sr.retailer_physical_size             as retailer_size,  
sr.retailer_coverage                  as retailer_coverage,  
sr.transaction_mapping                as transaction_mapping, 
sr.loaded_timestamp                   as loaded_datetime 
from {{ ref('lnd_static_retailer') }} sr

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sr.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}