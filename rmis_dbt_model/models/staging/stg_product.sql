/*
==============================================================================
  Model     : stg_product
  Layer     : Staging | incremental (merge)
  Purpose   : Product master staging table, including audit columns (created /
              last updated timestamp and user).
  Grain     : One row per ean_upc_key.
  Depends on: lnd_product
  Notes     : On incremental runs the model joins to itself (the existing
              table) so that created_datetime / created_by are preserved for
              existing products while last_updated_* are refreshed.
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
  lp.ean_upc                       as ean_upc,
  abs(hash(lp.ean_upc))            as ean_upc_key, 
  lp.product_name                  as product_name, 
  lp.category_id                   as product_category_id, 
  lp.sub_category_id               as product_sub_category_id,
  lp.department_id                 as product_department_id, 
  lp.gender                        as product_gender, 
  lp.colour                        as product_colour, 
  lp.size                          as product_size, 
  lp.sustainability                as sustainability, 
  lp.market                        as product_market,
  lp.jacket_type                   as jacket_type,
  lp.shell_construction            as shell_construction,
  lp.insulation_type               as insulation_type,
  lp.layer_position               as layer_position,
  lp.waterproof_technology        as waterproof_technology,
  lp.weight_class                 as weight_class,
  lp.primary_use                  as primary_use, 
  lp.brand_id                      as brand_id, 
  lp.brand_group_id                as brand_group_id, 
  lp.loaded_timestamp              as loaded_datetime,

 
  --- Auditing fields
  -- On incremental runs the model is LEFT JOINed to itself (alias 'this', see
  -- the bottom of the file) so existing products keep their original
  -- created_* values while new products get the current time / user.
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

from {{ ref('lnd_product') }} lp

{% if is_incremental() %}
  -- Join with the existing incremental table to filter new or updated records
  left join {{ this }} as this
    on lp.ean_upc = this.ean_upc
       and lp.loaded_timestamp <= this.loaded_datetime  -- check for new/updated records

  -- Filter to only include rows where there is no match or an updated timestamp
  where this.ean_upc is null  -- New records
     or lp.loaded_timestamp > this.loaded_datetime  -- Updated records
{% endif %}
