-- Once actual data exists, no estimate should remain for that retailer/month.
select e.transaction_concat_key
from {{ ref('stg_transaction') }} e
where e.data_source_flag = 'ESTIMATED'
  and exists (
    select 1 from {{ ref('stg_transaction') }} a
    where a.data_source_flag = 'ACTUAL' and a.retailer = e.retailer
      and a.retailer_group_id = e.retailer_group_id
      and date_trunc('month', a.transaction_date) = date_trunc('month', e.transaction_date)
  )
