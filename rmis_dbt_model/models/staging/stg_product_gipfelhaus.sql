/*
==============================================================================
  Model     : stg_product_gipfelhaus
  Layer     : Staging | table
  Purpose   : Product attributes for the Gipfelhaus supplier (see
              lnd_product_gipfelhaus), shaped to match stg_product so the two
              can be UNIONed in fct_transaction.
  Grain     : One row per generated ean_upc.
  Depends on: lnd_product_gipfelhaus
  Notes     : Built as a full table (not incremental) because the supplier's
              EANs are regenerated on every monthly load.
==============================================================================
*/

/*
Note on Gipfelhaus supplier:
- Gipfelhaus does not supply granular transaction records at daily level.
- Missing fields: ean_UPC, transaction_id, retailer, and product name.
- No product file provided; generating product file from transaction file.
- EAN_UPC and transaction_id are generated internally.
- Since these fields are randomly generated, a full load is performed monthly, wiping previous month data to avoid duplication as EANs will differ each preprocessing run.
*/

select 
  lp.ean_upc                       as ean_upc,
  abs(hash(lp.ean_upc))            as ean_upc_key, 
  lp.product_name                  as product_name, 
  lp.category_id                   as product_category_id, 
  lp.sub_category_id               as product_sub_category_id,
  lp.department_id                 as product_department_id, 
  lp.gender                        as product_gender, 
  lp.colour                        as product_colour, 
  lp.size                          as product_size, 
  lp.sustainability                as sustainability, 
  lp.shell_construction             as shell_construction,
  lp.insulation_type               as insulation_type,
  lp.primary_use                   as primary_use,
  lp.market                        as product_market, 
  lp.brand_id                      as brand_id, 
  lp.brand_group_id                as brand_group_id, 
  lp.loaded_timestamp              as loaded_datetime
  FROM {{ref('lnd_product_gipfelhaus')}} lp