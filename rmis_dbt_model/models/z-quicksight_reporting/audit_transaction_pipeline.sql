/*
==============================================================================
  Model     : audit_transaction_pipeline
  Layer     : Dashboard | table
  Purpose   : Automated pipeline audit. Compares record counts layer by layer
              (landing -> staging -> fact -> reporting), checks data freshness
              and reports how much of staging is ESTIMATED backfill.
  Grain     : One row per check.
  Depends on: lnd_transaction, stg_transaction, fct_transaction,
              tb_market_share_all
  Notes     : requires_attention = 1 flags FAIL / VERY_STALE results for
              alerting.
==============================================================================
*/
{{ 
  config(
    materialized = 'table'
  )
}}

-- Transaction Pipeline Audit Model
-- This model checks record counts across the entire transaction pipeline
-- and validates data integrity from landing to reporting

with 

-- Get counts from each model in the pipeline
lnd_counts as (
  select 
    'lnd_transaction' as model_name,
    count(*) as record_count,
    max(loaded_timestamp) as latest_loaded_timestamp,
    min(transaction_date) as earliest_transaction_date,
    max(transaction_date) as latest_transaction_date
  from {{ ref('lnd_transaction') }}
),

stg_counts as (
  select 
    'stg_transaction' as model_name,
    count(*) as total_records,
    sum(case when data_source_flag = 'ACTUAL' then 1 else 0 end) as actual_records,
    sum(case when data_source_flag = 'ESTIMATED' then 1 else 0 end) as estimated_records,
    max(loaded_datetime) as latest_loaded_datetime,
    min(transaction_date) as earliest_transaction_date,
    max(transaction_date) as latest_transaction_date
  from {{ ref('stg_transaction') }}
),

fct_counts as (
  select 
    'fct_transaction' as model_name,
    count(*) as record_count,
    max(loaded_datetime) as latest_loaded_datetime,
    min(transaction_date) as earliest_transaction_date,
    max(transaction_date) as latest_transaction_date
  from {{ ref('fct_transaction') }}
),

reporting_counts as (
  select 
    'tb_market_share_all' as model_name,
    count(*) as record_count,
    min(transaction_date) as earliest_transaction_date,
    max(transaction_date) as latest_transaction_date
  from {{ ref('tb_market_share_all') }}
),

-- Prepare the audit results
audit_results as (
  -- Landing layer
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name,
    record_count,
    'BASELINE' as status,
    'Landing layer - source of truth' as notes
  from lnd_counts
  
  union all
  
  -- Staging layer - total count
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name || '_TOTAL' as model_name,
    total_records as record_count,
    case 
      when total_records >= (select record_count from lnd_counts) then 'PASS'
      else 'FAIL'
    end as status,
    'Staging total (actual + estimated records)' as notes
  from stg_counts
  
  union all
  
  -- Staging layer - actual records only
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name || '_ACTUAL' as model_name,
    actual_records as record_count,
    case 
      when actual_records = (select record_count from lnd_counts) then 'PASS'
      when actual_records < (select record_count from lnd_counts) then 'FAIL'
      else 'WARNING'
    end as status,
    'Staging actual records - should match landing' as notes
  from stg_counts
  
  union all
  
  -- Staging layer - estimated records
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name || '_ESTIMATED' as model_name,
    estimated_records as record_count,
    case 
      when estimated_records = 0 then 'INFO'
      when estimated_records > 0 then 'BACKFILL_ACTIVE'
      else 'UNKNOWN'
    end as status,
    'Estimated/backfilled records from prior year' as notes
  from stg_counts
  
  union all
  
  -- Fact layer
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name,
    record_count,
    case 
      when record_count = (select total_records from stg_counts) then 'PASS'
      when record_count < (select total_records from stg_counts) then 'FAIL'
      else 'WARNING'
    end as status,
    'Fact layer - should match staging total' as notes
  from fct_counts
  
  union all
  
  -- Reporting layer
  select 
    'COUNT_CHECK' as check_type,
    current_timestamp() as last_updated,
    model_name,
    record_count,
    case 
      when record_count = (select record_count from fct_counts) then 'PASS'
      when record_count < (select record_count from fct_counts) then 'FAIL'
      else 'WARNING'
    end as status,
    'Reporting layer - should match fact layer' as notes
  from reporting_counts
  
  union all
  
  -- Data freshness checks
  select 
    'FRESHNESS_CHECK' as check_type,
    current_timestamp() as last_updated,
    'DATA_FRESHNESS' as model_name,
    datediff('hour', (select latest_loaded_timestamp from lnd_counts), current_timestamp()) as record_count,
    case 
      when datediff('hour', (select latest_loaded_timestamp from lnd_counts), current_timestamp()) <= 48 then 'FRESH'
      when datediff('hour', (select latest_loaded_timestamp from lnd_counts), current_timestamp()) <= 168 then 'STALE'
      else 'VERY_STALE'
    end as status,
    'Hours since last data load' as notes
  
  union all
  
  -- Pipeline integrity check
  select 
    'INTEGRITY_CHECK' as check_type,
    current_timestamp() as last_updated,
    'PIPELINE_INTEGRITY' as model_name,
    null as record_count,
    case 
      when (select actual_records from stg_counts) = (select record_count from lnd_counts)
        and (select record_count from fct_counts) = (select total_records from stg_counts)
        and (select record_count from reporting_counts) = (select record_count from fct_counts)
      then 'PASS'
      else 'FAIL'
    end as status,
    'Overall pipeline count integrity check' as notes
  
  union all
  
  -- Backfill summary
  select 
    'BACKFILL_SUMMARY' as check_type,
    current_timestamp() as last_updated,
    'BACKFILL_IMPACT' as model_name,
    (select estimated_records from stg_counts) as record_count,
    case 
      when (select estimated_records from stg_counts) = 0 then 'NO_BACKFILL'
      when (select estimated_records from stg_counts) > 0 then 'BACKFILL_ACTIVE'
      else 'UNKNOWN'
    end as status,
    concat('Backfill represents ', 
           round((select estimated_records from stg_counts) * 100.0 / nullif((select total_records from stg_counts),0), 2), 
           '% of staging data') as notes
)

-- Final output
select 
  check_type,
  last_updated,
  model_name,
  record_count,
  status,
  notes,
  -- Add some helpful flags
  case when status in ('FAIL', 'VERY_STALE') then 1 else 0 end as requires_attention,
  case when status in ('BACKFILL_ACTIVE', 'STALE') then 1 else 0 end as monitor_closely
from audit_results

-- Sort by check type and model order
order by 
  case check_type 
    when 'COUNT_CHECK' then 1 
    when 'FRESHNESS_CHECK' then 2
    when 'INTEGRITY_CHECK' then 3
    when 'BACKFILL_SUMMARY' then 4
    else 5 
  end,
  case when model_name like '%lnd%' then 1
       when model_name like '%stg%' then 2  
       when model_name like '%fct%' then 3
       when model_name like '%reporting%' then 4
       else 5 
  end