-- A reference mapping update must be reflected in the fact after rebuilding.
select f.transaction_concat_key
from {{ ref('fct_transaction') }} f
join {{ ref('stg_transaction') }} s on s.transaction_concat_key = f.transaction_concat_key
join {{ ref('dim_retailer') }} d
  on lower(s.retailer) = lower(d.transaction_mapping)
where f.retailer_id <> d.retailer_id or f.retailer_id is null
