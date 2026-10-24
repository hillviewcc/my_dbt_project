/* Scope-aware reconciliation: staging ACTUAL keys match landing; facts are
   an outdoor subset; dashboard data excludes France and unknown categories.
   Compare dashboard measures at its eligible fact scope, not raw row counts. */
{{ config(materialized='table') }}
with landing as (
    select transaction_concat_key from {{ ref('lnd_transaction') }}
), actual as (
    select transaction_concat_key from {{ ref('stg_transaction') }}
    where data_source_flag = 'ACTUAL'
), actual_key_differences as (
    select coalesce(l.transaction_concat_key, a.transaction_concat_key) as transaction_concat_key
    from landing l full outer join actual a
      on l.transaction_concat_key = a.transaction_concat_key
    where l.transaction_concat_key is null or a.transaction_concat_key is null
), eligible_facts as (
    select f.* from {{ ref('fct_transaction') }} f
    where exists (
      select 1 from {{ ref('dim_product_category') }} c
      where c.product_category_id = f.product_category_id and c.product_category is not null
    ) and exists (
      select 1 from {{ ref('dim_retailer') }} d
      where d.retailer_id = f.retailer_id
        and lower(d.retailer_transaction_country) <> 'france'
    )
), dashboard_by_key as (
    select transaction_concat_key, sum(market_sales) as sales,
           sum(market_quantity) as quantity,
           sum(gbp_market_sales) as gbp_sales, sum(eur_market_sales) as eur_sales
    from {{ ref('tb_market_share_all') }} group by transaction_concat_key
), dashboard_differences as (
    select coalesce(f.transaction_concat_key, d.transaction_concat_key) as transaction_concat_key
    from eligible_facts f full outer join dashboard_by_key d
      on f.transaction_concat_key = d.transaction_concat_key
    where f.transaction_concat_key is null or d.transaction_concat_key is null
      or abs(coalesce(f.transaction_value, 0) - coalesce(d.sales, 0)) > 0.01
      or abs(coalesce(f.transaction_quantity, 0) - coalesce(d.quantity, 0)) > 0.000001
      or (f.gbp_fx_transaction_value is null) <> (d.gbp_sales is null)
      or (f.eur_fx_transaction_value is null) <> (d.eur_sales is null)
      or abs(coalesce(f.gbp_fx_transaction_value, 0) - coalesce(d.gbp_sales, 0)) > 0.01
      or abs(coalesce(f.eur_fx_transaction_value, 0) - coalesce(d.eur_sales, 0)) > 0.01
), checks as (
    select 'INTEGRITY_CHECK' as check_type, 'STAGING_ACTUAL_KEYS' as model_name,
           count(*) as record_count, iff(count(*) = 0, 'PASS', 'FAIL') as status,
           'Symmetric difference between landing and staging ACTUAL keys' as notes
    from actual_key_differences
    union all
    select 'INTEGRITY_CHECK', 'FACT_SCOPE', count(*), iff(count(*) = 0, 'PASS', 'FAIL'),
           'Fact rows outside outdoor scope or absent from staging'
    from {{ ref('fct_transaction') }} f
    where f.transaction_market <> 'OUTDOOR' or f.transaction_market is null
       or f.product_department_id not in (1,2,3,4,5,6) or f.product_department_id is null
       or not exists (select 1 from {{ ref('stg_transaction') }} s
                      where s.transaction_concat_key = f.transaction_concat_key)
    union all
    select 'INTEGRITY_CHECK', 'DASHBOARD_RECONCILIATION', count(*), iff(count(*) = 0, 'PASS', 'FAIL'),
           'Per-key sales, currency values and quantity versus eligible facts; 0.01 currency tolerance'
    from dashboard_differences
    union all
    select 'FRESHNESS_CHECK', 'DATA_FRESHNESS',
           datediff('hour', max(loaded_timestamp), current_timestamp()),
           case when max(loaded_timestamp) is null then 'FAIL'
                when datediff('hour', max(loaded_timestamp), current_timestamp()) <= 48 then 'FRESH'
                when datediff('hour', max(loaded_timestamp), current_timestamp()) <= 168 then 'STALE'
                else 'VERY_STALE' end,
           'Hours since latest source load; thresholds require tuning to supplier cadence'
    from {{ ref('lnd_transaction') }}
    union all
    select 'BACKFILL_SUMMARY', 'BACKFILL_IMPACT', count(*),
           iff(count(*) = 0, 'NO_BACKFILL', 'BACKFILL_ACTIVE'), 'Estimated rows retained in staging'
    from {{ ref('stg_transaction') }} where data_source_flag = 'ESTIMATED'
)
select check_type, current_timestamp() as last_updated, model_name, record_count,
       status, notes, iff(status in ('FAIL', 'VERY_STALE'), 1, 0) as requires_attention,
       iff(status in ('STALE', 'BACKFILL_ACTIVE'), 1, 0) as monitor_closely
from checks
