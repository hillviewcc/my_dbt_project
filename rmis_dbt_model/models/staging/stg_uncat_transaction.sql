/*
==============================================================================
  Model     : stg_uncat_transaction
  Layer     : Staging | table
  Purpose   : Uncategorised products (EANs not in the product master) with the
              descriptive fields the categorisation team needs.
  Grain     : One row per (ean_upc, retailer_group_id).
  Depends on: lnd_uncat_transaction
  Notes     : Used for the monthly report of products still waiting to be
              categorised.
==============================================================================
*/
--Fetch uncategorised transactions from the landing layer into table that can be used for monthly reporting of uncategorised products
select 
  i.transaction_ean_upc as ean_upc,
  i.retailer,
  i.retailer_group_id,
  i.transaction_product_name as product_name,
  i.transaction_product_category as product_category,
  i.transaction_product_sub_category as product_sub_category,
  i.transaction_product_brand as brand,
  i.transaction_product_size as size,
  i.transaction_product_colour as colour,
  i.transaction_market as market
from {{ ref('lnd_uncat_transaction') }} i

