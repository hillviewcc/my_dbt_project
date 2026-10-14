/*
==============================================================================
  Model     : lnd_fx_rates
  Layer     : Landing | view
  Purpose   : Flattens the daily FX-rate feed into one column per currency
              pair. Rates are quoted as 'units per base currency', so
              downstream models DIVIDE by the rate to convert a value into GBP
              or EUR.
  Grain     : One row per FX_DATE (latest load wins).
  Depends on: source raw_retailer.raw_fx_rates
  Notes     : The XUDL* keys are the central-bank series codes for each GBP
              cross rate.
==============================================================================
*/
  WITH CTE_FX_RATE AS(
  SELECT
    SOURCE_S3_URI_KEY
    , DELTA_RAW_DIFF_KEY
    , DELTA_RAW_KEY
    , DELTA_RAW_TIMESTAMP
    , ABS(HASH(DELTA_RECORD['Date']::VARCHAR)) AS FX_DATE_KEY
    , DELTA_RECORD['Date']::DATE AS FX_DATE
    , DELTA_RECORD['XUDLSER']::NUMBER(38, 4) AS GBP_EUR -- divide by rate
    , DELTA_RECORD['XUDLSFS']::NUMBER(38, 4) AS CHF_GBP -- divide by rate
    , DELTA_RECORD['XUDLUSS']::NUMBER(38, 4) AS USD_GBP -- divide by rate
    , DELTA_RECORD['XUDLERS']::NUMBER(38, 4) AS EUR_GBP -- divide by rate
    , DELTA_RECORD['XUDLNKS']::NUMBER(38, 4) AS NOK_GBP -- divide by rate
    , DELTA_RECORD['XUDLBK25']::NUMBER(38, 4) AS CZK_GBP -- divide by rate
    , DELTA_RECORD['XUDLDKS']::NUMBER(38, 4) AS DKK_GBP -- divide by rate
    , DELTA_RECORD['XUDLBK47']::NUMBER(38, 4) AS PLN_GBP -- divide by rate
    , DELTA_RECORD['XUDLSKS']::NUMBER(38, 4) AS SEK_GBP -- divide by rate
    , DELTA_RECORD['CHF/EUR']::NUMBER(38, 4) AS CHF_EUR -- divide by rate
    , DELTA_RECORD['NOK/EUR']::NUMBER(38, 4) AS NOK_EUR -- divide by rate
    , DELTA_RECORD['USD/EUR']::NUMBER(38, 4) AS USD_EUR -- divide by rate
    , DELTA_RECORD['DKK/EUR']::NUMBER(38, 4) AS DKK_EUR -- divide by rate
    , DELTA_RECORD['SEK/EUR']::NUMBER(38, 4) AS SEK_EUR -- divide by rate
    , DELTA_RECORD['CZK/EUR']::NUMBER(38, 4) AS CZK_EUR -- divide by rate
    , DELTA_RECORD['PLN/EUR']::NUMBER(38, 4) AS PLN_EUR -- divide by rate
    , DELTA_RECORD['is_weekend']::VARCHAR AS IS_WEEKEND
    , DELTA_RECORD['is_friday_rate']::VARCHAR AS IS_FRIDAY_RATE
    -- if a day is re-sent, keep the latest rates
    , ROW_NUMBER() OVER (PARTITION BY DELTA_RECORD['Date']::DATE ORDER BY DELTA_RAW_TIMESTAMP DESC) AS ROW_NUMBER
  FROM {{ source('raw_retailer', 'raw_fx_rates') }}
)

SELECT
  DELTA_RAW_DIFF_KEY AS RECORD_HASHKEY
  , DELTA_RAW_KEY AS SOURCE_HASHKEY
  , DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP
  , FX_DATE_KEY
  , FX_DATE
  , GBP_EUR
  , CHF_GBP
  , USD_GBP
  , EUR_GBP
  , NOK_GBP
  , CZK_GBP
  , DKK_GBP
  , PLN_GBP
  , SEK_GBP
  , CHF_EUR
  , NOK_EUR
  , USD_EUR
  , DKK_EUR
  , SEK_EUR
  , CZK_EUR
  , PLN_EUR
  , IS_WEEKEND
  , IS_FRIDAY_RATE
FROM CTE_FX_RATE
WHERE
  ROW_NUMBER = 1
  