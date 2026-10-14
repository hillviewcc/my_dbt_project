/*
==============================================================================
  Model     : dim_product_gipfelhaus
  Layer     : Reporting | table
  Purpose   : Product dimension for the Gipfelhaus supplier (kept separate
              from dim_product because its EANs are regenerated monthly).
  Grain     : One row per generated ean_upc.
  Depends on: stg_product_gipfelhaus
  Notes     : Reporting models LEFT JOIN this table to fall back to its
              product names.
==============================================================================
*/
select *
from {{ ref('stg_product_gipfelhaus') }}