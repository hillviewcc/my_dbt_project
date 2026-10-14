/*
==============================================================================
  Model     : stg_fx_rates
  Layer     : Staging | incremental (merge)
  Purpose   : Daily FX rates in lower-case, typed columns ready for the
              reporting layer.
  Grain     : One row per fx_date_key.
  Depends on: lnd_fx_rates
  Notes     : Incremental merge on the unique key: only rows loaded since the
              last run (loaded_timestamp > max(loaded_datetime)) are
              processed.
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
    LOADED_TIMESTAMP as loaded_datetime,
    FX_DATE_KEY      as fx_date_key,
    FX_DATE          as fx_date,
    GBP_EUR          as gbp_eur,
    CHF_GBP          as chf_gbp,
    USD_GBP          as usd_gbp,
    EUR_GBP          as eur_gbp,
    NOK_GBP          as nok_gbp,
    CZK_GBP          as czk_gbp,
    DKK_GBP          as dkk_gbp,
    PLN_GBP          as pln_gbp,
    SEK_GBP          as sek_gbp,
    CHF_EUR          as chf_eur,
    NOK_EUR          as nok_eur,
    USD_EUR          as usd_eur,
    DKK_EUR          as dkk_eur,
    SEK_EUR          as sek_eur,
    CZK_EUR          as czk_eur,
    PLN_EUR          as pln_eur,
    IS_WEEKEND       as is_weekend,
    IS_FRIDAY_RATE   as is_friday_rate
FROM  {{ ref('lnd_fx_rates') }} fx

{% if is_incremental() %}
  -- Load only new records based on loaded_timestamp
  where fx.loaded_timestamp > (select max(loaded_datetime) from {{ this }})
{% endif %}
