/*
==============================================================================
  Model     : fct_uncat_transaction
  Layer     : Reporting | table
  Purpose   : Sales value of transactions that could not be matched to a
              categorised product, so the business can size the 'unknown'
              bucket and prioritise categorisation work.
  Grain     : One row per (transaction_date, retailer, sales_channel,
              ean_upc).
  Depends on: stg_transaction, dim_product, dim_retailer, dim_sales_channel,
              dim_fx_rates
  Notes     : product_category_id = -1 is the convention for 'no matching
              product'.
==============================================================================
*/
/* -------------------------- DIM CTEs  -------------------------- */
-- Same join pattern as fct_transaction, but WITHOUT the outdoor filter,
-- because here we want exactly the rows that fail to match a product.
with cte_product as (
        select
            dp.ean_upc                 as product_ean_upc,
            dp.ean_upc_key             as product_ean_upc_key,
            dp.product_category_id
        from {{ ref('dim_product') }} dp
       
),

cte_retailer as (

        select
            sr.retailer_id,
            sr.retailer_key,
            sr.retailer_name,
            abs(hash(lower(sr.retailer_name::varchar)))  as retailer_name_key,
            sr.retailer_group_id,
            sr.transaction_mapping,
            abs(hash(lower(sr.transaction_mapping::varchar))) as retailer_mapping_key
            
        from {{ ref('dim_retailer') }} sr
    
    
),

cte_sales_channel as (

        select 
            sc.sales_channel_id,
            sc.sales_mapping_key,
            sc.sales_channel,
            sc.sales_channel_group,
            sc.transaction_mapping,
            abs(hash(lower(sc.transaction_mapping::varchar))) as mapping_key
            
        from {{ ref('dim_sales_channel') }} sc
   
),

/* ------------------------ FACT-STAGING CTE ------------------------------ */
cte_transaction as (
    select
        lt.loaded_datetime,
        lt.transaction_date,
        lt.transaction_channel,
        lt.transaction_concat_key,
        abs(hash(lower(lt.transaction_channel::varchar))) as transaction_channel_key,
        lt.transaction_ean_upc,
        lt.transaction_ean_upc_key,
        lt.transaction_value,
        -- convert to GBP / EUR using the day's FX rate (see fct_transaction)
        case 
            when lt.transaction_currency = 'EUR' then (lt.transaction_value / fx.EUR_GBP)
            when UPPER(lt.transaction_currency) = 'EURO' then (lt.transaction_value / fx.EUR_GBP)
            when lt.transaction_currency = 'CHF' then (lt.transaction_value / fx.CHF_GBP)
            when lt.transaction_currency = 'NOK' then (lt.transaction_value / fx.NOK_GBP)
            else lt.transaction_value
        end as gbp_fx_transaction_value,
        case 
            when lt.transaction_currency = 'GBP' then (lt.transaction_value / fx.GBP_EUR)
            when lt.transaction_currency = 'CHF' then (lt.transaction_value / fx.CHF_EUR)
            when lt.transaction_currency = 'NOK' then (lt.transaction_value / fx.NOK_EUR)
            else lt.transaction_value
        end as eur_fx_transaction_value,
        lower(lt.transaction_market) as transaction_market,
        lt.transaction_quantity,
        lt.transaction_country,
        lt.retailer_group_id,
        lt.retailer               as retailer_name,
        abs(hash(lower(lt.retailer::varchar))) as retailer_name_key
    from {{ ref('stg_transaction') }} lt
    left join {{ ref('dim_fx_rates') }} fx on lt.transaction_date = fx.fx_date
),

cte_fact as (
    select
        a.loaded_datetime,
        a.transaction_date,
        a.transaction_channel,
        a.transaction_ean_upc,
        a.transaction_ean_upc_key,
        a.transaction_value,
        a.gbp_fx_transaction_value,
        a.eur_fx_transaction_value,
        a.transaction_market, 
        a.transaction_quantity,
        a.transaction_country,
        a.retailer_group_id,
        c.retailer_name,    
        coalesce(b.product_category_id,   -1) as product_category_id,--  -1 means no matching  product
        coalesce(c.retailer_id,           -1) as retailer_id,
        d.sales_channel,
        row_number() over (partition by a.transaction_concat_key order by a.loaded_datetime desc) as row_no
    from cte_transaction       a
    left join cte_product      b on a.transaction_ean_upc_key  = b.product_ean_upc_key
    left join cte_retailer     c on a.retailer_name_key        = c.retailer_mapping_key
    left join cte_sales_channel d on a.transaction_channel_key = d.mapping_key

),

-- keep one row per transaction, and only those with no product match (-1)
cte_final as (
select 
    transaction_date,
    transaction_ean_upc,
    transaction_value,
    gbp_fx_transaction_value,
    eur_fx_transaction_value,
    transaction_market,
    transaction_quantity,
    product_category_id,
    retailer_name,
    retailer_id,
    sales_channel,
from cte_fact ft
where row_no = 1
and product_category_id = -1
)

/* ------------------------- Reporting select -------------------------------- */
-- Aggregate to one row per day / retailer / channel / unmatched EAN, which is
-- the list the categorisation team works through.
SELECT
a.transaction_date,
a.retailer_name,
a.retailer_id,
a.sales_channel,
a.transaction_ean_upc,
SUM(a.transaction_value) AS transaction_value,
SUM(a.gbp_fx_transaction_value) AS gbp_transaction_value,
SUM(a.eur_fx_transaction_value) AS eur_transaction_value,
SUM(a.transaction_quantity) AS transaction_quantity
FROM cte_final a
where a.product_category_id = -1
group by
a.transaction_date,
a.retailer_name,
a.retailer_id,
a.sales_channel,
a.transaction_ean_upc
