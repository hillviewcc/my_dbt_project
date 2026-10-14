/*
==============================================================================
  Model     : dim_retailer
  Layer     : Reporting | incremental (merge)
  Purpose   : Retailer dimension.
  Grain     : One row per retailer_id.
  Depends on: stg_retailer
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
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
sr.retailer_id,
sr.retailer_key, 
sr.retailer_name,
sr.retailer_transaction_country, 
sr.retailer_group_id, 
sr.retailer_group,  
sr.retailer_segment,  
sr.retailer_size,               
sr.retailer_coverage,                   
sr.transaction_mapping,                
sr.loaded_datetime               
from {{ ref('stg_retailer') }} sr

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sr.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}