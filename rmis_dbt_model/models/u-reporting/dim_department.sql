/*
==============================================================================
  Model     : dim_department
  Layer     : Reporting | incremental (merge)
  Purpose   : Product department dimension (EN/FR/DE labels).
  Grain     : One row per department_id.
  Depends on: stg_department
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='department_id', 
    incremental_strategy='merge' 
    
  )
}}


select
sd.product_department,
sd.product_department_fr,
sd.product_department_de,
sd.department_id,
sd.department_key,
sd.loaded_datetime                 
from {{ ref('stg_department') }} sd

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sd.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}