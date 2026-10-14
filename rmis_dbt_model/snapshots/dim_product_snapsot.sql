{#
==============================================================================
  Snapshot  : ean_upc_snapshot
  Purpose   : Type-2 slowly changing dimension history of the product master.
              Every time a product's name, category, department, market or
              brand changes, dbt closes the old row (dbt_valid_to) and inserts
              a new one, so past reports can be reproduced with the
              categorisation that was in place at the time.
  Strategy  : 'check' - compares the check_cols below on every run (the source
              has no reliable updated_at column to use the 'timestamp'
              strategy).
  Run with  : dbt snapshot
==============================================================================
#}
{% snapshot ean_upc_snapshot %}

{{
  config(
    target_database=target.database,
    target_schema='snapshots',
    unique_key='ean_upc_key',
    strategy='check',
    check_cols=[
      'product_name',
      'product_category_id',
      'product_sub_category_id',
      'product_department_id',
      'product_market',
      'brand_id',
      'brand_group_id'
    ]
  )
}}

SELECT 
  lp.ean_upc                       AS ean_upc,
  ABS(HASH(lp.ean_upc))            AS ean_upc_key, 
  lp.product_name                  AS product_name, 
  lp.category_id                   AS product_category_id, 
  lp.sub_category_id               AS product_sub_category_id,
  lp.department_id                 AS product_department_id, 
  lp.gender                        AS product_gender, 
  lp.colour                        AS product_colour, 
  lp.size                          AS product_size, 
  lp.sustainability                AS sustainability, 
  lp.market                        AS product_market, 
  lp.brand_id                      AS brand_id, 
  lp.brand_group_id                AS brand_group_id, 
  lp.loaded_timestamp              AS loaded_datetime,
  CURRENT_TIMESTAMP()              AS last_updated_datetime,
  CURRENT_USER()                   AS last_updated_by
FROM {{ ref('lnd_product') }} lp

{% endsnapshot %}
