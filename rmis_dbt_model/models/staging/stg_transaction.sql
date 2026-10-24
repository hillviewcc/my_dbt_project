/*
==============================================================================
  Model     : stg_transaction
  Layer     : Staging | incremental (merge)
  Purpose   : Cleansed transaction table PLUS gap-filling. If a retailer has
              not yet delivered data for the reporting month, its sales for
              the same month last year are copied forward and flagged as
              ESTIMATED, so market-share figures are not distorted by a late
              supplier.
  Grain     : One row per transaction_concat_key (ACTUAL or ESTIMATED).
  Depends on: lnd_transaction
  Notes     : A pre_hook deletes ESTIMATED rows as soon as the real (ACTUAL)
              data for that retailer and month arrives, so estimates are
              always replaced, never doubled.
==============================================================================
*/
-- History: an earlier version of this model was a straight copy of
-- lnd_transaction. It was replaced by the version below, which adds the
-- ESTIMATED back-fill for retailers that are late delivering a month.

{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='transaction_concat_key', 
    incremental_strategy='merge',
    pre_hook = "{% if is_incremental() %}DELETE FROM {{ this }} WHERE data_source_flag = 'ESTIMATED' AND (retailer, retailer_group_id, 
    date_trunc('month', transaction_date)) IN (SELECT retailer, retailer_group_id, 
    date_trunc('month', transaction_date) FROM {{ ref('lnd_transaction') }}
    WHERE {% if is_incremental() %}loaded_timestamp > (SELECT coalesce(max(loaded_datetime), to_timestamp('1900-01-01')) FROM {{ this }} WHERE data_source_flag = 'ACTUAL'){% else %}1=1{% endif %}){% endif %}"
  )
}}

/*
  How the back-fill works (the reporting month = 2 months ago, because
  suppliers deliver a month in arrears):
    1. current_data            - new ACTUAL rows from landing
    2. data_availability       - which retailers already have ACTUAL rows for
                                 the reporting month (new rows + this table)
    3. all_retailers           - every retailer seen in the last 13 months
    4. retailers_needing_fallback = 3 minus 2
    5. fallback_data           - those retailers' rows from the same month
                                 last year, shifted forward 1 year and
                                 flagged ESTIMATED with new keys
    6. combined_data           - ACTUAL UNION ALL ESTIMATED
  The pre_hook above deletes the ESTIMATED rows for a retailer/month as soon
  as ACTUAL rows for that retailer/month land, so they are never counted twice.
*/

-- 1. Use only ACTUAL source timestamps as the ingestion watermark.
-- ESTIMATED rows have synthetic timestamps and must never advance it.
-- 1. Get current data (new records only in incremental mode)
with current_data as (
  select
    lt.loaded_timestamp,
    lt.transaction_id,
    lt.transaction_date,
    -- one supplier sends the channel wrapped in stray CSV quotes: '"Ecom"""' -> 'Ecom'
    case 
      when lt.transaction_channel = '"Ecom"""' and lt.retailer_group_id = '9' then 'Ecom'
      else lt.transaction_channel 
    end as transaction_channel,
    lt.transaction_store_id,
    lt.transaction_ean_upc,
    abs(hash(lt.transaction_ean_upc)) as transaction_ean_upc_key, 
    lt.transaction_concat_key,
    lt.transaction_value,
    lt.transaction_market,
    lt.transaction_quantity,
    lt.transaction_currency,
    lt.transaction_country,
    lt.retailer_group_id,
    lt.retailer
  from {{ ref('lnd_transaction') }} lt
  {% if is_incremental() %}
  where lt.loaded_timestamp > (select coalesce(max(loaded_datetime), to_timestamp('1900-01-01')) from {{ this }} where data_source_flag = 'ACTUAL')
  {% endif %}
),

-- 2. Check which retailers have data for the previous month (the month we're loading data for)
-- and Check both new data AND existing table to prevent duplicates
data_availability as (
  -- Check new data for previous month
  select 
    retailer,
    retailer_group_id,
    max(case when date_trunc('month', transaction_date) = date_trunc('month', dateadd('month', -2, current_date())) -- reporting month = 2 months ago
             then 1 else 0 end) as has_previous_month_data,
    count(*) as current_records_count
  from current_data
  group by retailer, retailer_group_id
  
  {% if is_incremental() %}
  union all
  
  -- In incremental mode, also check existing table for retailers with ACTUAL data
  select 
    retailer,
    retailer_group_id,
    1 as has_previous_month_data,  -- They have data if they exist as ACTUAL
    count(*) as current_records_count
  from {{ this }}
  where date_trunc('month', transaction_date) = date_trunc('month', dateadd('month', -2, current_date())) -- reporting month = 2 months ago
    and data_source_flag = 'ACTUAL'
  group by retailer, retailer_group_id
  {% endif %}
),

-- 2b. Aggregate to handle potential duplicates from the union above
final_data_availability as (
  select 
    retailer,
    retailer_group_id,
    max(has_previous_month_data) as has_previous_month_data,
    sum(current_records_count) as current_records_count
  from data_availability
  group by retailer, retailer_group_id
),

-- 3. Get all unique retailers from the system (to check for missing ones)
all_retailers as (
  select distinct 
    lt.retailer,
    lt.retailer_group_id
  from {{ ref('lnd_transaction') }} lt
  where lt.transaction_date >= dateadd('month', -13, current_date()) -- Look back 13 months to ensure we have prior year data
),

-- 4. Identify retailers that need fallback data (missing previous month data)
retailers_needing_fallback as (
  select 
    ar.retailer,
    ar.retailer_group_id
  from all_retailers ar
  left join final_data_availability da 
    on ar.retailer = da.retailer 
    and ar.retailer_group_id = da.retailer_group_id
  where coalesce(da.has_previous_month_data, 0) = 0
  and ar.retailer_group_id <> 21 -- Exclude retailer_group_id 21 (edgeworks) from fallback
),

-- 5. Generate fallback data from the same month last year, but only for the specific month we're loading
fallback_data as (
  select
    current_timestamp() as loaded_timestamp, -- Mark as newly loaded
    concat('EST_', lt.transaction_id) as transaction_id, -- Prefix to distinguish estimated records
    dateadd('year', 1, lt.transaction_date) as transaction_date, -- Shift date to target year
    case 
      when lt.transaction_channel = '"Ecom"""' and lt.retailer_group_id = '9' then 'Ecom'
      else lt.transaction_channel 
    end as transaction_channel,
    lt.transaction_store_id,
    lt.transaction_ean_upc,
    abs(hash(lt.transaction_ean_upc)) as transaction_ean_upc_key,
    abs(hash(concat('EST_', cast(lt.transaction_concat_key as varchar)))) as transaction_concat_key, -- Create new hash for unique key
    lt.transaction_value,
    lt.transaction_market,
    lt.transaction_quantity,
    lt.transaction_currency,
    lt.transaction_country,
    lt.retailer_group_id,
    lt.retailer,
    'ESTIMATED' as data_source_flag -- Flag to identify estimated records
  from {{ ref('lnd_transaction') }} lt
  inner join retailers_needing_fallback rnf 
    -- re-apply the retailer-name clean-up rules so names match all_retailers
    on case 
         when lt.retailer_group_id = 1 and lt.retailer is null then 'PEAKLINE'
         when lt.retailer_group_id = 11 and lt.retailer is null then 'Campforge'
         when lt.retailer_group_id = 20 and lower(lt.retailer) = 'granite peak' then concat(lt.retailer, '_', lt.transaction_country)
         when lt.retailer_group_id = 9 and lower(lt.retailer) = 'trailstep.com' then concat(lt.retailer, '/', 'UK')
         when lt.retailer is null then 'unknown retailer' 
         else lt.retailer 
       end = rnf.retailer
    and lt.retailer_group_id = rnf.retailer_group_id
  -- pull data from the same month last year that we're currently loading
  where date_trunc('month', lt.transaction_date) = dateadd('month', -12, date_trunc('month', dateadd('month', -2, current_date()))) -- reporting month = 2 months ago
    -- Additional check: ensure the shifted date matches the month we're loading  
    and date_trunc('month', dateadd('year', 1, lt.transaction_date)) = date_trunc('month', dateadd('month', -2, current_date())) -- reporting month = 2 months ago
),

-- 6. Combine current and fallback data
combined_data as (
  -- Current/actual data
  select 
    cd.loaded_timestamp as loaded_datetime,
    cd.transaction_id,
    cd.transaction_date,
    cd.transaction_channel,
    cd.transaction_store_id,
    cd.transaction_ean_upc,
    cd.transaction_ean_upc_key,
    cd.transaction_concat_key,
    cd.transaction_value,
    cd.transaction_market,
    cd.transaction_quantity,
    cd.transaction_currency,
    cd.transaction_country,
    cd.retailer_group_id,
    cd.retailer,
    'ACTUAL' as data_source_flag,
    current_timestamp() as last_updated_datetime,
    current_user() as last_updated_by
  from current_data cd
  
  union all
  
  -- Fallback/estimated data
  select 
    fd.loaded_timestamp as loaded_datetime,
    fd.transaction_id,
    fd.transaction_date,
    fd.transaction_channel,
    fd.transaction_store_id,
    fd.transaction_ean_upc,
    fd.transaction_ean_upc_key,
    fd.transaction_concat_key,
    fd.transaction_value,
    fd.transaction_market,
    fd.transaction_quantity,
    fd.transaction_currency,
    fd.transaction_country,
    fd.retailer_group_id,
    fd.retailer,
    fd.data_source_flag,
    current_timestamp() as last_updated_datetime,
    current_user() as last_updated_by
  from fallback_data fd
)

-- Final select (data_source_flag lets reports include or exclude estimates)
select
  loaded_datetime, 
  transaction_id,  
  transaction_date,
  transaction_channel,
  transaction_store_id,
  transaction_ean_upc,
  transaction_ean_upc_key, 
  transaction_concat_key,
  transaction_value,
  transaction_market,
  transaction_quantity,
  transaction_currency,
  transaction_country,
  retailer_group_id,
  retailer,
  data_source_flag, -- New column to track actual vs estimated data
  last_updated_datetime,
  last_updated_by
from combined_data

