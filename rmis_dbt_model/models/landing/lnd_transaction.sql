/*
==============================================================================
  Model     : lnd_transaction
  Layer     : Landing | view
  Purpose   : The core sales feed. Parses each retailer's raw JSON transaction
              record, cleans the inconsistencies between suppliers (date
              formats, sign of returns, missing retailer names, legacy store
              ids) and keeps only in-scope retailers.
  Grain     : One row per unique transaction (TRANSACTION_CONCAT_KEY), 2023
              onwards.
  Depends on: source raw_retailer.raw_transaction
  Notes     : Some retailers send line-level unit prices and others send pre-
              aggregated line values; TRANSACTION_VALUE is normalised to a
              line value here so every downstream model can simply SUM it.
==============================================================================
*/

-- ---------------------------------------------------------------------------
-- Step 1: parse the raw JSON record (DELTA_RECORD) into typed columns and
--         apply supplier-specific clean-up rules.
-- ---------------------------------------------------------------------------
WITH RETAILER_TRANSACTION
 AS (
  SELECT
    -- load metadata (hash keys + load time) carried through for auditing
    SOURCE_S3_URI_KEY,
    DELTA_RAW_DIFF_KEY,
    DELTA_RAW_KEY,
    DELTA_RAW_TIMESTAMP,
    DELTA_RECORD['retailer_group_id']::NUMBER AS RETAILER_GROUP_ID,

    -- Retailer name: some suppliers omit it or changed naming conventions over
    -- time, so legacy values are rewritten to the name used in the retailer
    -- reference list (lnd_static_retailer.transaction_mapping).
    CASE
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 1 AND DELTA_RECORD['retailer']::VARCHAR IS NULL THEN 'PEAKLINE'
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 11 AND DELTA_RECORD['retailer']::VARCHAR IS NULL THEN 'Campforge'
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 20 AND TRIM(LOWER(DELTA_RECORD['retailer']::VARCHAR)) = 'granite peak' THEN CONCAT(DELTA_RECORD['retailer']::VARCHAR, '_', 'United Kingdom')
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['retailer']::VARCHAR)) = 'trailstep.com' THEN CONCAT(DELTA_RECORD['retailer']::VARCHAR, '/', 'UK')
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 23 AND TRIM(LOWER(DELTA_RECORD['retailer']::VARCHAR)) = 'fox hollow' THEN 'Fox Hollow_United Kingdom'
       WHEN DELTA_RECORD['retailer']::VARCHAR IS NULL THEN 'unknown retailer'
       ELSE COALESCE(NULLIF(TRIM(DELTA_RECORD['retailer']::VARCHAR), ''), TRIM(DELTA_RECORD['retailer']::VARCHAR))
     END AS RETAILER,
     DELTA_RECORD['transaction_id']::VARCHAR AS TRANSACTION_ID,

-- Transaction date: suppliers send dates in several formats. Each format is
-- tried in turn (ISO-8601 with 'Z', 'YYYY-MM-DD HH24:MI:SS', 'YYYY/MM/DD ...',
-- date only) and normalised to one string before converting. TRY_ functions
-- return NULL instead of failing the whole load on a bad value.
TO_DATE(
    TRY_TO_TIMESTAMP_TZ(
        CASE
            WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z') IS NOT NULL THEN
                TO_CHAR(TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z'), 'YYYY-MM-DD HH24:MI:SS')
            WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD HH24:MI:SS') IS NOT NULL THEN
                DELTA_RECORD['transaction_datetime']::STRING
            WHEN TRY_TO_TIMESTAMP_TZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY/MM/DD HH24:MI:SS') IS NOT NULL THEN
                REPLACE(DELTA_RECORD['transaction_datetime']::STRING, '/', '-')
            WHEN TRY_TO_DATE(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD') IS NOT NULL THEN
                DELTA_RECORD['transaction_datetime']::STRING || ' 00:00:00'
            ELSE
                NULL
        END, 'YYYY-MM-DD HH24:MI:SS'
    )
) AS TRANSACTION_DATE,

    TO_DATE(TRY_TO_TIMESTAMP_TZ(
        CASE
            WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z') IS NOT NULL THEN
                TO_CHAR(TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DDTHH24:MI:SS.000Z'), 'YYYY-MM-DD HH24:MI:SS')
            WHEN TRY_TO_TIMESTAMP_NTZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD HH24:MI:SS') IS NOT NULL THEN
                DELTA_RECORD['transaction_datetime']::STRING
            WHEN TRY_TO_TIMESTAMP_TZ(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY/MM/DD HH24:MI:SS') IS NOT NULL THEN
                REPLACE(DELTA_RECORD['transaction_datetime']::STRING, '/', '-')
            WHEN TRY_TO_DATE(DELTA_RECORD['transaction_datetime']::STRING, 'YYYY-MM-DD') IS NOT NULL THEN
                DELTA_RECORD['transaction_datetime']::STRING || ' 00:00:00'
            ELSE
                NULL
        END, 'YYYY-MM-DD HH24:MI:SS'
    )) AS TRANSACTION_DATETIME,

    DELTA_RECORD['transaction_channel']::VARCHAR AS TRANSACTION_CHANNEL,

  -- Store id: older files used placeholder or website-style store ids; these
  -- are mapped to the ids used in the store master. Falls back to 'store_id'
  -- for suppliers that use that key name instead of 'transaction_store_id'.
  CASE
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(NULLIF(COALESCE(DELTA_RECORD['transaction_store_id']::VARCHAR, DELTA_RECORD['store_id']::VARCHAR), ''))) = 'trailstep.com'
       THEN 'Trailstep.com/UK'
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 20 AND TRIM(LOWER(NULLIF(COALESCE(DELTA_RECORD['transaction_store_id']::VARCHAR, DELTA_RECORD['store_id']::VARCHAR), ''))) = '0'  
       THEN 'GB'
       WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 7 AND TRIM(LOWER(NULLIF(COALESCE(DELTA_RECORD['transaction_store_id']::VARCHAR, DELTA_RECORD['store_id']::VARCHAR), ''))) = 'summitgear.store'  
       THEN 'summitgear.store_GB'
       ELSE
       COALESCE(NULLIF(TRIM(DELTA_RECORD['transaction_store_id']::VARCHAR), ''), DELTA_RECORD['store_id']::VARCHAR)
       END AS TRANSACTION_STORE_ID,
    DELTA_RECORD['transaction_ean_upc']::NUMBER AS TRANSACTION_EAN_UPC,  -- product barcode = join key to the product master

    -- Returns: a return must have BOTH a negative quantity and a negative value.
    -- Suppliers are inconsistent (some send -qty with +value), so the sign of
    -- the value is aligned to the sign of the quantity here...
    CASE
    -- Both negative (return) - keep value negative
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER < 0 
       THEN  DELTA_RECORD['transaction_value']::NUMBER(38, 2)
    
    -- Negative quantity, positive value - make value negative  
    WHEN DELTA_RECORD['transaction_quantity']::NUMBER < 0 AND DELTA_RECORD['transaction_value']::NUMBER > 0
         THEN -ABS(DELTA_RECORD['transaction_value']::NUMBER(38, 2))
    
    -- Both positive (normal sale) - keep as is
    ELSE DELTA_RECORD['transaction_value']::NUMBER(38, 2)
END AS TRANSACTION_VALUE,
    
    -- ...and the sign of the quantity is aligned to the sign of the value.
    -- Note: some files contain the key with a leading space (' transaction_quantity'),
    -- hence the COALESCE over both spellings.
    CASE
    -- Both negative (return) - keep quantity negative
    WHEN DELTA_RECORD['transaction_value']::NUMBER < 0 AND 
         COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER) < 0
    THEN COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
    
    -- Negative value, positive quantity - make quantity negative
    WHEN DELTA_RECORD['transaction_value']::NUMBER < 0 AND 
         COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER) > 0
    THEN -COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
    
    
    -- Both positive (normal sale) - keep as is
    ELSE COALESCE(DELTA_RECORD['transaction_quantity']::NUMBER, DELTA_RECORD[' transaction_quantity']::NUMBER)
END AS TRANSACTION_QUANTITY,
    DELTA_RECORD['transaction_market']::VARCHAR AS TRANSACTION_MARKET,
    COALESCE(DELTA_RECORD['transaction_currency_new']::VARCHAR, 'GBP')  AS TRANSACTION_CURRENCY, -- UK suppliers often omit currency

    -- Country: derived from the store id for suppliers that sell several
    -- countries through one feed; otherwise taken from the record, defaulting
    -- to the UK (the original and largest market).
    CASE
    WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'trailstep.com/de'
        THEN 'Germany'
    WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 9 AND TRIM(LOWER(DELTA_RECORD['transaction_store_id']::VARCHAR)) = 'trailstep.com/fr'
        THEN 'France'
    WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 1 AND TRIM(LOWER(DELTA_RECORD['transaction_country']::VARCHAR)) = 'gbr'
        THEN 'United Kingdom'
    ELSE COALESCE(NULLIF(NULLIF(TRIM(DELTA_RECORD['transaction_country']::VARCHAR), ''), ' '), 'United Kingdom')
    END AS TRANSACTION_COUNTRY,

    -- descriptive product fields as sent by the retailer (used for uncategorised products)
    COALESCE(DELTA_RECORD['product_name']::VARCHAR, DELTA_RECORD[' product_name']::VARCHAR) AS TRANSACTION_PRODUCT_NAME,
    DELTA_RECORD['category']::VARCHAR AS TRANSACTION_PRODUCT_CATEGORY,
    DELTA_RECORD['sub_category']::VARCHAR AS TRANSACTION_PRODUCT_SUB_CATEGORY,
    DELTA_RECORD['color']::VARCHAR AS TRANSACTION_PRODUCT_COLOUR,
    DELTA_RECORD['size']::VARCHAR AS TRANSACTION_PRODUCT_SIZE,
    DELTA_RECORD['brand']::VARCHAR AS TRANSACTION_PRODUCT_BRAND,
    DELTA_RECORD['gender']::VARCHAR AS TRANSACTION_PRODUCT_GENDER,   -- raw retailer value (normalised only in lnd_product)
    DELTA_RECORD['mpn']::VARCHAR AS TRANSACTION_PRODUCT_MPN,
    DELTA_RECORD['sku']::VARCHAR AS TRANSACTION_PRODUCT_SKU,
    DELTA_RECORD['plu']::VARCHAR AS TRANSACTION_PRODUCT_PLU

  FROM {{ source('raw_retailer', 'raw_transaction') }}
  
-- A transaction without a barcode can never be matched to a product, so drop it.
WHERE TRIM(DELTA_RECORD['transaction_ean_upc']::NUMBER) IS NOT NULL
  AND TRIM(DELTA_RECORD['transaction_ean_upc']::NUMBER) <> ''
  /* Allow-list of in-scope retailers. Only these retailers are reported on,
     and keeping the list explicit is important for the back-filling logic in
     stg_transaction: a retailer that is NOT in this list must never be
     treated as "missing data" and estimated. */
  AND TRIM(
      COALESCE(
        DELTA_RECORD['retailer']::VARCHAR,
        CASE 
          WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 1  THEN 'Peakline'
          WHEN DELTA_RECORD['retailer_group_id']::NUMBER = 11 THEN 'Campforge'
          ELSE NULL
        END
      )
    ) IN (
      'Peakline',
      'Peakline_FRA',
      'DealTrail',
      'Trailhead Analytics',
      'RBL',
      'RMI',
      'RUO',
      'RGO',
      'RGE',
      'Velocita Bikes',
      'Stride Fitness',
      'Summitgear',
      'Summitgear_AT',
      'Summitgear_DE',
      'Summitgear_FR',
      'Kitcraft',
      'Trailstep.com',
      'Trailstep.com/UK',
      'Trailstep.com/FR',
      'Trailstep.com/DE',
      'WebOutfitters',
      'Coastline Group Ltd',
      'Pace Hub',
      'RJ Harper',
      'VALLEY OUTDOORS LTD',
      'Frost Ridge London',
      'Kestrel Packs',
      'glenmore mountain sports',
      'chalk bag climbing',
      'Granite Peak',
      'Granite Peak_United Kingdom',
      'Granite Peak_Switzerland',
      'Granite Peak_Austria',
      'Granite Peak_Germany',
      'Granite Peak_France',
      'Edgeworks Ltd',
      'Tentora',
      'Fox Hollow',
      'Fox Hollow_United Kingdom',
      'Fox Hollow_Germany',
      'Fox Hollow_France',
      'Fox Hollow_Austria',
      'Fox Hollow_Switzerland',
      'Basecamp Store',
      'SportPlus',
      'HM Mountain Centre',
      'Shore to Peak_United Kingdom',
      'Shore to Peak_France',
      'Shore to Peak_Germany',
      'www.cyclemart.fr',
      'www.cyclemart.de',
      'ALLSPORT',
      'ALLSPORT_DE',
      'Nordic Imports_France',
      'Nordic Imports_Allemagne',
      'Avalo_France',
      'Avalo_Allemagne',
      'Avalo_Autriche',
      'Sporthaus Berger',
      'Trekwise',
      'Ridge Path',
      'Coastal Outdoor',
      'True Adventure',
      'Peak To Shore',
      'Valley Leisure',
      'Alpine Mountain Group',
      'Alpzeit_CH',
      'Alpzeit_DE',
      'Alpzeit_AT',
      'Alpzeit_FR',
      'Gipfelhaus_UK',
      'Gipfelhaus_DE',
      'Gipfelhaus_AT',
      'Gipfelhaus_FR',
      'Gipfelhaus_CH',
      'SportPlusGermany',
      'sportvillage_Germany',
      'sportvillage_France',
      'Cascadia_United Kingdom',
      'Cascadia_Germany',
      'Cascadia_France',
      'Cascadia_Switzerland',
      'Cascadia_Austria',
      'Wanderweg Backpacking AG',
      'Harlow Mountain',
      'WRAPZ_Germany',
      'WRAPZ_France',
      'WRAPZ_United Kingdom',
      '9c_Germany',
      'runshoes_GB',
      'runshoes_DE',
      'runshoes_AT',
      'runshoes_FR',
      'runshoes_CH',
      'FlowFit_United Kingdom',
      'FlowFit_Germany',
      'FlowFit_Austria',
      'FlowFit_France',
      'FlowFit_Switzerland',
      'INSOLA_Suisse',
     'INSOLA_France',
     'INSOLA_Austria',
     'INSOLA_Allemagne',
     'ALPINO Sportartikel GmbH_DE',
     'ALPINO Sportartikel GmbH_AT',
    'ALPINO Sportartikel GmbH_CH',
    'ALPINO Sportartikel GmbH_FR',
    'Montaria S.L._DEU',
    'TREKKA_United Kingdom',
    'TREKKA_Germany',
    'TREKKA_France',
    'TREKKA_Austria'

    

    )

  AND DELTA_RECORD['retailer_group_id']::NUMBER <> 8 -- retailer group 8 no longer shares data

),

-- ---------------------------------------------------------------------------
-- Step 2: normalise TRANSACTION_VALUE to a line total and limit history.
-- ---------------------------------------------------------------------------
CTE_TRANSACTION_CLEAN as
(
SELECT
  DELTA_RAW_DIFF_KEY AS RECORD_HASHKEY,
  DELTA_RAW_KEY AS SOURCE_HASHKEY,
  DELTA_RAW_TIMESTAMP AS LOADED_TIMESTAMP,
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_ID,
  TRANSACTION_DATE,
  TRANSACTION_DATETIME,
  TRANSACTION_CHANNEL,
  TRANSACTION_STORE_ID,
  TRANSACTION_EAN_UPC,
  -- These retailer groups already send the line total (price x quantity);
  -- everyone else sends the unit price, so multiply by quantity.
  -- ABS(quantity) keeps the sign set in step 1: a return (-price) x ABS(-qty)
  -- stays negative instead of becoming (-) x (-) = positive.
  CASE
        WHEN RETAILER_GROUP_ID IN (1,4,7,9,15,17,22,24,25,27,29,38,39,40,46,48,49,50) THEN COALESCE(TRANSACTION_VALUE, 0) -- already a line total
        ELSE
        COALESCE(TRANSACTION_VALUE, 0) *  ABS(TRANSACTION_QUANTITY)
        END AS TRANSACTION_VALUE,
  TRANSACTION_MARKET,
  TRANSACTION_QUANTITY,
  TRANSACTION_CURRENCY,
  TRANSACTION_COUNTRY,
  TRANSACTION_PRODUCT_NAME,
  TRANSACTION_PRODUCT_CATEGORY,
  TRANSACTION_PRODUCT_SUB_CATEGORY,
  TRANSACTION_PRODUCT_COLOUR,
  TRANSACTION_PRODUCT_SIZE,
  TRANSACTION_PRODUCT_BRAND,
  TRANSACTION_PRODUCT_GENDER,
  TRANSACTION_PRODUCT_MPN,
  TRANSACTION_PRODUCT_SKU,
  TRANSACTION_PRODUCT_PLU
FROM RETAILER_TRANSACTION
where year(transaction_date) >= 2023   -- reporting history starts in 2023
),

-- ---------------------------------------------------------------------------
-- Step 3: build the unique transaction key and de-duplicate.
-- Retailers do not provide a globally unique id, so the key is a hash of the
-- fields that together identify one sale line. If the same line is delivered
-- twice (e.g. a file is re-sent), only the first load is kept.
-- ---------------------------------------------------------------------------
CTE_TRANSACTION_FINAL AS (
SELECT
  RECORD_HASHKEY,
  SOURCE_HASHKEY,
  LOADED_TIMESTAMP,
  RETAILER_GROUP_ID,
  RETAILER,
  TRANSACTION_ID,
  TRANSACTION_DATE,
  TRANSACTION_DATETIME,
  TRANSACTION_CHANNEL,
  TRANSACTION_STORE_ID,
  TRANSACTION_EAN_UPC,
  TRANSACTION_VALUE,
  TRANSACTION_MARKET,
  TRANSACTION_QUANTITY,
  TRANSACTION_CURRENCY,
  TRANSACTION_COUNTRY,
  TRANSACTION_PRODUCT_NAME,
  TRANSACTION_PRODUCT_CATEGORY,
  TRANSACTION_PRODUCT_SUB_CATEGORY,
  TRANSACTION_PRODUCT_COLOUR,
  TRANSACTION_PRODUCT_SIZE,
  TRANSACTION_PRODUCT_BRAND,
  TRANSACTION_PRODUCT_GENDER,
  TRANSACTION_PRODUCT_MPN,
  TRANSACTION_PRODUCT_SKU,
  TRANSACTION_PRODUCT_PLU,
  -- the key is built from the CLEANED values (after step 2) so it stays stable
  -- even if the raw value format changes between deliveries
  ABS(HASH(TRANSACTION_ID,RETAILER, TRANSACTION_EAN_UPC, TRANSACTION_QUANTITY, TRANSACTION_PRODUCT_NAME, 
                    TRANSACTION_STORE_ID, TRANSACTION_DATE, TRANSACTION_VALUE)) AS TRANSACTION_CONCAT_KEY,
ROW_NUMBER() OVER (
PARTITION BY TRANSACTION_ID,RETAILER, TRANSACTION_EAN_UPC, TRANSACTION_QUANTITY, TRANSACTION_PRODUCT_NAME, 
                    TRANSACTION_STORE_ID, TRANSACTION_DATE, TRANSACTION_VALUE 
                    ORDER BY LOADED_TIMESTAMP
) as rownumber
FROM CTE_TRANSACTION_CLEAN
)

select * from CTE_TRANSACTION_FINAL
where rownumber = 1   -- keep the first-loaded copy of each transaction

