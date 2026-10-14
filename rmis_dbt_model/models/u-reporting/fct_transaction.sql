/*
==============================================================================
  Model     : fct_transaction
  Layer     : Reporting | incremental (merge) - central fact table
  Purpose   : Joins cleansed transactions to the product, retailer, sales-
              channel and FX dimensions, converts every sale into GBP and EUR,
              and keeps only outdoor-market products.
  Grain     : One row per transaction_concat_key.
  Depends on: stg_transaction, dim_product, stg_product_gipfelhaus,
              dim_retailer, dim_sales_channel, dim_fx_rates
  Notes     : Smart incremental logic: besides new transactions, a run also
              re-processes rows whose product, retailer or channel changed, or
              whose FX value was missing last time. A post_hook removes rows
              that no longer exist in staging (e.g. replaced ESTIMATED rows).
==============================================================================
*/
-- post_hook: after the merge, delete fact rows whose key no longer exists in
-- stg_transaction (e.g. an ESTIMATED row that was replaced by ACTUAL data),
-- so the fact table always mirrors staging exactly.
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='transaction_concat_key',
    on_schema_change='fail',
    post_hook=[
      """
      delete from {{ this }} f
      where not exists (
        select 1
        from {{ ref('stg_transaction') }} s
        where s.transaction_concat_key = f.transaction_concat_key
      )
      """
    ]
  )
}}

/* ----------------------- INCREMENTAL CONTROL CTEs -----------------------
   On an incremental run a fact row is (re)built when ANY of these is true:
     - the transaction itself is new                (max_fct_time)
     - its product was re-categorised               (changed_products)
     - its retailer reference data changed          (changed_retailers)
     - its sales-channel mapping changed            (changed_channels)
     - its FX conversion was NULL last time         (changed_fx_rates)
   On a full refresh these CTEs return an empty set / 1900-01-01.
   ------------------------------------------------------------------------- */

-- high-water mark: latest load time already in the fact table
with max_fct_time as (
    {% if is_incremental() %}
    select max(loaded_datetime) as max_time from {{ this }}
    {% else %}
    select to_timestamp('1900-01-01') as max_time
    {% endif %}
),

/* Capture only the product keys that actually changed since last load */
changed_products as (
    {% if is_incremental() %}
    select distinct ean_upc_key
    from {{ ref('dim_product') }}
    where last_updated_datetime > (select max_time from max_fct_time)
    {% else %}
    select null::number as ean_upc_key where 1 = 0
    {% endif %}
),

/* Capture only the retailer keys that actually changed since last load */
changed_retailers as (
    {% if is_incremental() %}
    select distinct retailer_id
    from {{ ref('dim_retailer') }}
    where loaded_datetime > (select max_time from max_fct_time)
    {% else %}
    select null::number as retailer_id where 1 = 0
    {% endif %}
),

/* Capture only the sales channel keys that actually changed since last load */
changed_channels as (
    {% if is_incremental() %}
    select distinct sales_mapping_key
    from {{ ref('dim_sales_channel') }}
    where loaded_datetime > (select max_time from max_fct_time)
    {% else %}
    select null::number as sales_mapping_key where 1 = 0
    {% endif %}
),

/* Capture FX dates that have changed since last load, to ensure we recalculate FX values for any transactions on those dates */
changed_fx_rates as (
    {% if is_incremental() %}
    -- Re-process any transaction dates that previously produced null FX values
    select distinct transaction_date as fx_date
    from {{ this }}
    where gbp_fx_transaction_value is null
       or eur_fx_transaction_value is null
    {% else %}
    select null::date as fx_date where 1 = 0
    {% endif %}
),

/* -------------------------- DIM CTEs  -------------------------- */
-- Products: the main product dimension UNION the separately-built Gipfelhaus
-- products, so that supplier's sales can be matched too.
cte_product as (
    select *
    from (
        select
            dp.ean_upc                                           as product_ean_upc,
            dp.ean_upc_key                                       as product_ean_upc_key,
            dp.product_category_id,
            dp.product_sub_category_id,
            dp.product_department_id,
            dp.brand_id,
            dp.brand_group_id,
            dp.product_market 
        from {{ ref('dim_product') }} dp
        union
        select
            sp.ean_upc                                           as product_ean_upc,
            ean_upc_key                                          as product_ean_upc_key,
            sp.product_category_id,
            sp.product_sub_category_id,
            sp.product_department_id,
            sp.brand_id,
            sp.brand_group_id,
            sp.product_market
            from {{ref('stg_product_gipfelhaus') }} sp
            
       
    )
    
),

-- Retailers: transactions carry a retailer NAME, not an id, so both sides are
-- matched on a hash of the lower-cased TRANSACTION_MAPPING name.
cte_retailer as (
    select *
    from (
        select
            sr.retailer_id,
            sr.retailer_transaction_country,
            sr.retailer_key,
            abs(hash(lower(sr.retailer_name::varchar)))  as retailer_name_key,
            sr.retailer_group_id,
            sr.transaction_mapping,
            abs(hash(lower(sr.transaction_mapping::varchar))) as retailer_mapping_key,
            
        from {{ ref('dim_retailer') }} sr
    )
    
),

-- Sales channels: one row per raw channel value (see stg_sales_channel), matched
-- the same way on a hash of the lower-cased value.
cte_sales_channel as (
    select *
    from (
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
            abs(hash(lower(sc.transaction_mapping::varchar))) as mapping_key,
            
        from {{ ref('dim_sales_channel') }} sc
    )
   
),

/* ------------------------ FACT-STAGING CTE ------------------------------ */
cte_transaction as (
    select
        lt.loaded_datetime,
        lt.transaction_id,
        lt.transaction_date,
        fx.fx_date,
        lt.transaction_channel,
        abs(hash(lower(lt.transaction_channel::varchar))) as transaction_channel_key,
        lt.transaction_store_id::varchar                  as transaction_store_id,
        lt.transaction_ean_upc,
        lt.transaction_ean_upc_key,
        lt.transaction_concat_key,
        lt.transaction_value,
        -- Currency conversion: rates are 'units per GBP/EUR', so divide by the
        -- day's rate. Values already in the target currency are left as-is.
        case 
            when UPPER(lt.transaction_currency) = 'EUR' then (lt.transaction_value / fx.EUR_GBP)
            when UPPER(lt.transaction_currency) = 'EURO' then (lt.transaction_value / fx.EUR_GBP)
            when UPPER(lt.transaction_currency) = 'CHF' then (lt.transaction_value / fx.CHF_GBP)
            when UPPER(lt.transaction_currency) = 'NOK' then (lt.transaction_value / fx.NOK_GBP)
            else lt.transaction_value
        end as gbp_fx_transaction_value,
        case 
            when UPPER(lt.transaction_currency) = 'GBP' then (lt.transaction_value / fx.GBP_EUR)
            when UPPER(lt.transaction_currency) = 'CHF' then (lt.transaction_value / fx.CHF_EUR)
            when UPPER(lt.transaction_currency) = 'NOK' then (lt.transaction_value / fx.NOK_EUR)
            else lt.transaction_value
        end as eur_fx_transaction_value,
        lower(lt.transaction_market) as transaction_market,
        lt.transaction_quantity,
        lt.transaction_currency,
        lt.transaction_country,
        lt.retailer_group_id,
        lt.retailer               as retailer_name,
        abs(hash(lower(lt.retailer::varchar))) as retailer_name_key
    from {{ ref('stg_transaction') }} lt
    left join {{ ref('dim_fx_rates') }} fx on lt.transaction_date = fx.fx_date   -- rate for the day of sale

),

/* ------------------------- BUILD THE FACT ------------------------------- */
cte_fact as (
    select
        a.loaded_datetime,
        a.transaction_id,
        a.transaction_date,
        a.transaction_channel,
        a.transaction_ean_upc,
        a.transaction_ean_upc_key,
        a.transaction_concat_key,
        a.transaction_value,
        a.gbp_fx_transaction_value,
        a.eur_fx_transaction_value,
        b.product_market as transaction_market, -- market comes from the product master (more reliable than the market sent on the transaction)
        a.transaction_quantity,
        a.transaction_currency,
        -- country: suppliers send country inconsistently, so it is taken from the retailer reference data instead
        c.retailer_transaction_country as transaction_country,
        a.retailer_group_id,
        a.retailer_name,    -- kept for troubleshooting data-quality issues
        -- -1 = 'unknown member' convention: no matching dimension row
        coalesce(b.product_category_id,   -1) as product_category_id,
        coalesce(b.product_sub_category_id,-1) as product_sub_category_id,
        coalesce(b.product_department_id, -1) as product_department_id,
        coalesce(b.brand_id,              -1) as brand_id,
        coalesce(b.brand_group_id,        -1) as brand_group_id,
        coalesce(b.product_ean_upc,       -1) as product_ean_upc, --  -1 means no matching  product
        coalesce(b.product_ean_upc_key,   -1) as product_ean_upc_key,
        coalesce(c.retailer_id,           -1) as retailer_id,
        abs(hash(concat(a.transaction_store_id::varchar, '-', c.retailer_id::varchar))) as transaction_store_key,
        d.sales_channel_id,
        coalesce(a.transaction_store_id::varchar, '-1') as original_store_id,
        c.retailer_key        as retailer_id_key,
        d.sales_mapping_key,
        -- safety net: if a join fans out, keep only the latest row per transaction
        row_number() over (partition by a.transaction_concat_key order by a.loaded_datetime desc) as row_no
    from cte_transaction       a
    left join cte_product      b on a.transaction_ean_upc_key  = b.product_ean_upc_key
    left join cte_retailer     c on a.retailer_name_key        = c.retailer_mapping_key
    left join cte_sales_channel d on a.transaction_channel_key = d.mapping_key
-- Scope: only categorised OUTDOOR products in the core outdoor departments.
-- (Filtering on b.* also drops unmatched products - their value is reported
-- separately in fct_uncat_transaction and combined_data.)
where b.product_market = 'OUTDOOR'
and b.product_department_id in (1,2,3,4,5,6) -- excludes non-core departments e.g. equestrian, cycling

)

/* ------------------------- FINAL SELECT -------------------------------- */
select 
    loaded_datetime,
    transaction_id,
    transaction_date,
    transaction_channel,
    transaction_ean_upc,
    transaction_ean_upc_key,
    transaction_concat_key,
    transaction_value,
    gbp_fx_transaction_value,
    eur_fx_transaction_value,
    transaction_market,
    transaction_quantity,
    transaction_currency,
    transaction_country,
    retailer_group_id,
    product_category_id,
    product_sub_category_id,
    product_department_id,
    brand_id,
    brand_group_id,
    product_ean_upc,
    product_ean_upc_key,
    retailer_id,
    transaction_store_key,
    sales_channel_id,
    original_store_id,
    retailer_id_key,
    sales_mapping_key
from cte_fact ft
where row_no = 1
{% if is_incremental() %}
  -- only (re)process rows affected since the last run - see the control CTEs at the top
  and (
        ft.loaded_datetime > (select max_time from max_fct_time)
        or ft.transaction_ean_upc_key in (select ean_upc_key from changed_products)
        or ft.retailer_id_key in (select retailer_id from changed_retailers)         
        or ft.sales_mapping_key in (select sales_mapping_key from changed_channels)
        or ft.transaction_date in (select fx_date from changed_fx_rates)
                  
      )
{% endif %}