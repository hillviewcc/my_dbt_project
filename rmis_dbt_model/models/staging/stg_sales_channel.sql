/*
==============================================================================
  Model     : stg_sales_channel
  Layer     : Staging | incremental (merge)
  Purpose   : Explodes each sales channel's comma-separated
              TRANSACTION_MAPPING list into one row per raw channel value, so
              transactions can be joined on an exact match.
  Grain     : One row per (sales_channel_id, raw mapping value) =
              sales_mapping_key.
  Depends on: lnd_static_sales_channel
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='sales_mapping_key', 
    incremental_strategy='merge' 
  )
}}

-- Each sales channel lists the raw channel values that belong to it as a
-- comma-separated string (e.g. "web,online,ecom"). LATERAL SPLIT_TO_TABLE
-- turns that list into one row per value so the fact table can join on it.
WITH CTE_SPLIT_CHANNEL AS (
  SELECT
    a.sales_channel_id,
    TRIM(a.sales_channel) AS sales_channel,
    TRIM(a.sales_channel_fr) AS sales_channel_fr,
    TRIM(a.sales_channel_de) AS sales_channel_de,
    TRIM(a.sales_channel_group) AS sales_channel_group,
    TRIM(a.sales_channel_group_fr) AS sales_channel_group_fr,
    TRIM(a.sales_channel_group_de) AS sales_channel_group_de,
    TRIM(b.value::VARCHAR) AS transaction_mapping,
    a.loaded_timestamp
  FROM {{ ref('lnd_static_sales_channel') }} AS a,
       LATERAL split_to_table(a.transaction_mapping, ',') AS b
)

SELECT 
  sc.sales_channel_id::NUMBER AS sales_channel_id,

  -- unique key per (channel, raw value); NaN/NULL mappings are normalised first
  CONCAT(
    sc.sales_channel_id,
    ABS(HASH(COALESCE(NULLIF(sc.transaction_mapping, 'NaN'), 'NULL')))
  ) AS sales_mapping_key,

  coalesce(sc.sales_channel, 'Unknown Sales Channel') AS sales_channel,
  coalesce(sc.sales_channel_fr, 'Unknown Sales Channel FR') AS sales_channel_fr,
  coalesce(sc.sales_channel_de, 'Unknown Sales Channel DE') AS sales_channel_de,
  coalesce(sc.sales_channel_group, 'Unknowns Sales Channel Group') AS sales_channel_group,
  coalesce(sc.sales_channel_group_fr, 'Unknowns Sales Channel Group FR') AS sales_channel_group_fr,
  coalesce(sc.sales_channel_group_de, 'Unknowns Sales Channel Group DE') AS sales_channel_group_de,
  coalesce(sc.transaction_mapping, 'Unknown transaction_mapping') AS transaction_mapping,
  sc.loaded_timestamp AS loaded_datetime

FROM CTE_SPLIT_CHANNEL AS sc

{% if is_incremental() %}
  WHERE sc.loaded_timestamp > (
    SELECT MAX(loaded_datetime) FROM {{ this }}
  )
{% endif %}
