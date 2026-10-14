/*
==============================================================================
  Model     : dim_fx_rates
  Layer     : Reporting | incremental (merge)
  Purpose   : Daily FX-rate dimension used to convert sales into GBP and EUR.
  Grain     : One row per FX_DATE_KEY.
  Depends on: stg_fx_rates
  Notes     : Incremental merge: only rows updated in staging since the last
              run are merged.
==============================================================================
*/
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail',
    unique_key='FX_DATE_KEY', 
    incremental_strategy='merge' 
  )
}}

SELECT
    loaded_datetime,
    FX_DATE_KEY,
    FX_DATE,
    GBP_EUR,
    CHF_GBP,
    USD_GBP,
    EUR_GBP,
    NOK_GBP,
    CZK_GBP,
    DKK_GBP,
    PLN_GBP,
    SEK_GBP,
    CHF_EUR,
    NOK_EUR,
    USD_EUR,
    DKK_EUR,
    SEK_EUR,
    CZK_EUR,
    PLN_EUR
FROM  {{ ref('stg_fx_rates') }} fx

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where fx.loaded_datetime > (select max(loaded_datetime) from {{ this }})
{% endif %}