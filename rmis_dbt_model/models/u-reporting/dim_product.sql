/*
==============================================================================
  Model     : dim_product
  Layer     : Reporting | incremental (merge)
  Purpose   : Product dimension: category, department, brand and technical
              jacket attributes for every EAN/UPC, with audit columns.
  Grain     : One row per ean_upc_key.
  Depends on: stg_product
  Notes     : last_updated_datetime is used by fct_transaction to detect
              products whose categorisation changed, so only the affected fact
              rows are re-processed.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='ean_upc_key',
    incremental_strategy='merge'
    
  )
}}

select 
  dp.ean_upc,
  dp.ean_upc_key, --as product_ean_upc_key, 
  dp.product_name, 
  dp.product_category_id, 
  dp.product_sub_category_id,
  dp.product_department_id, 
  dp.product_gender, 
  dp.product_colour, 
  dp.product_size, 
  dp.sustainability, 
  upper(dp.product_market) as product_market,
  dp.shell_construction,
  dp.insulation_type,
  dp.jacket_type,
  dp.layer_position,
  dp.waterproof_technology,
  dp.weight_class,
  dp.primary_use,
  dp.brand_id, 
  dp.brand_group_id, 
  dp.loaded_datetime,
  -- Audit columns: on incremental runs the model joins to itself (alias 'this')
  -- so existing products keep their original created_* values.
  -- Timestamp when the row is first created
  {% if is_incremental() %}
    case 
      when this.ean_upc is not null then this.created_datetime -- Preserve existing value
      else current_timestamp()  -- New value for new records
    end as created_datetime,  
  -- Snowflake user who created the row
  case 
    when this.ean_upc is not null then this.created_by  -- Preserve existing value
    else current_user()  -- New value for new records
  end as created_by, 
   {% else %}
    current_timestamp()          as created_datetime,
    current_user()               as created_by,
  {% endif %}       

  -- capture the latest update time and user
  current_timestamp()               as last_updated_datetime,  --Timestamp when the row is last updated
  current_user()                    as last_updated_by         -- Snowflake user who created the row

from {{ ref('stg_product') }} dp

{% if is_incremental() %}
  -- Join with the existing incremental table to filter new or updated records
  left join {{ this }} as this
    on dp.ean_upc = this.ean_upc
       and dp.loaded_datetime <= this.loaded_datetime  -- check for new/updated records

  -- Filter to only include rows where there is no match or an updated timestamp
  where this.ean_upc is null  -- New records
     or dp.loaded_datetime > this.loaded_datetime  -- Updated records
{% endif %}

