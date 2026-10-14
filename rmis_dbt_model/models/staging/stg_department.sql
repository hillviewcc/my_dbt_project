/*
==============================================================================
  Model     : stg_department
  Layer     : Staging | incremental (merge)
  Purpose   : Product department staging table (EN/FR/DE labels) with a hashed
              surrogate key.
  Grain     : One row per department_id.
  Depends on: lnd_static_department
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
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
sd.product_department               as product_department,
sd.product_department_fr            as product_department_fr,
sd.product_department_de            as product_department_de, 
sd.department_id                    as department_id,
abs(hash(sd.department_id))         as department_key,
sd.loaded_timestamp                 as loaded_datetime
from {{ ref('lnd_static_department') }} sd

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where sd.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}