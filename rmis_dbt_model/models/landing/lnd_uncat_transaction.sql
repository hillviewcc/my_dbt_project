/*
==============================================================================
  Model     : lnd_uncat_transaction
  Layer     : Landing | view
  Purpose   : Transactions whose EAN/UPC does not exist in the product master,
              i.e. products that still need to be categorised.
  Grain     : One row per (TRANSACTION_EAN_UPC, RETAILER_GROUP_ID).
  Depends on: lnd_transaction, lnd_product
  Notes     : Feeds the monthly 'uncategorised products' work list sent to the
              product categorisation pipeline.
==============================================================================
*/

-- Active logic: LEFT JOIN transactions to the product master and keep the
-- rows with no match (p.ean_upc IS NULL) = products that are not categorised yet.
with tran_prod AS (
  SELECT
  t.loaded_timestamp AS SRC_LOADED_TIME,
    t.transaction_ean_upc,
    t.retailer,
    t.retailer_group_id,
    t.TRANSACTION_PRODUCT_NAME,
    t.TRANSACTION_PRODUCT_CATEGORY,
    t.TRANSACTION_PRODUCT_SUB_CATEGORY,
    t.TRANSACTION_PRODUCT_BRAND,
    t.TRANSACTION_PRODUCT_SIZE,
    t.TRANSACTION_PRODUCT_COLOUR,
    t.TRANSACTION_MARKET,
    t.TRANSACTION_PRODUCT_GENDER as GENDER,
    '' AS TRANSACTION_PRODUCT_DEPARTMENT,
     ROW_NUMBER() OVER (
      PARTITION BY t.transaction_ean_upc, t.retailer_group_id  -- Changed
      ORDER BY t.LOADED_TIMESTAMP DESC
    ) AS rowno
from {{ ref('lnd_transaction') }} t
LEFT JOIN {{ ref('lnd_product') }} p ON t.transaction_ean_upc = p.ean_upc
  WHERE p.ean_upc IS NULL
)

SELECT 
    SRC_LOADED_TIME,
    transaction_ean_upc,
    retailer,
    retailer_group_id,
    TRANSACTION_PRODUCT_NAME ,
    TRANSACTION_PRODUCT_CATEGORY,
    TRANSACTION_PRODUCT_SUB_CATEGORY,
    TRANSACTION_PRODUCT_BRAND,
    TRANSACTION_PRODUCT_SIZE,
    TRANSACTION_PRODUCT_COLOUR,
    TRANSACTION_MARKET,
    GENDER,
    TRANSACTION_PRODUCT_DEPARTMENT
    
FROM tran_prod
WHERE rowno = 1   -- one row per product per retailer group (latest load)
ORDER BY retailer_group_id
