/*
==============================================================================
  Model     : tb_market_share
  Layer     : Dashboard | table
  Purpose   : Total-market dataset: sales by department / category / brand /
              technical attributes.
  Grain     : One row per transaction_concat_key and attribute combination
              (pre-aggregated SUMs of value / quantity).
  Depends on: fct_transaction + dim_brand, dim_brand_group, dim_retailer,
              dim_sales_channel, dim_store, dim_product, dim_department,
              dim_product_category, dim_product_sub_category, dim_date
  Notes     : Region filter: United Kingdom. Display labels: English. Missing
              dimension values are replaced with 'Unknown ...' labels so the
              BI tool never shows blanks.
==============================================================================
*/
SELECT
      -- DATE
      i.TRANSACTION_DATE,
      i.transaction_concat_key,
      d.month_number,
      d.calendar_year_number,
      COALESCE(NULLIF(TRIM(a.product_department), ''), 'Unknown Department') AS PRODUCT_DEPARTMENT,
      COALESCE(NULLIF(TRIM(g.sales_channel), ''), 'Unknown Sales Channel') AS SALES_CHANNEL,
      COALESCE(NULLIF(TRIM(g.sales_channel_group), ''), 'Unknown Sales Channel Group') AS SALES_CHANNEL_GROUP,
      COALESCE(NULLIF(TRIM(p.product_category), ''), 'Unknown Product Category') AS PRODUCT_CATEGORY,
      COALESCE(NULLIF(TRIM(j.product_sub_category), ''), 'Unknown Product Subcategory') AS PRODUCT_SUB_CATEGORY,
      COALESCE(NULLIF(TRIM(b.brand_description), ''), 'Unknown brand') AS MARKET_BRAND_NAME,
      COALESCE(NULLIF(TRIM(c.product_name), ''), 'Unknown product') AS PRODUCT_NAME,
      

      -- Measures: local-currency value, GBP and EUR converted value, units
      SUM(i.TRANSACTION_VALUE)        AS market_sales,
      SUM(i.GBP_FX_TRANSACTION_VALUE) AS gbp_market_sales,
      SUM(i.EUR_FX_TRANSACTION_VALUE) AS eur_market_sales,
      SUM(i.TRANSACTION_QUANTITY)     AS market_quantity,

      --attribute
      COALESCE(NULLIF(TRIM(c.jacket_type), ''), 'Unknown Jacket Type') AS JACKET_TYPE,
      COALESCE(NULLIF(TRIM(c.layer_position), ''), 'Unknown Layer Position') AS LAYER_POSITION,
      COALESCE(NULLIF(TRIM(c.waterproof_technology), ''), 'Unknown Waterproof Technology') AS WATERPROOF_TECHNOLOGY,
      COALESCE(NULLIF(TRIM(c.weight_class), ''), 'Unknown Weight Class') AS WEIGHT_CLASS,
      COALESCE(NULLIF(TRIM(c.primary_use), ''), 'Unknown Primary Use') AS PRIMARY_USE,
      COALESCE(NULLIF(TRIM(c.insulation_type), ''), 'Unknown Insulation Type') AS INSULATION_TYPE,
      COALESCE(NULLIF(TRIM(c.shell_construction), ''), 'Unknown Shell Construction') AS SHELL_CONSTRUCTION,
      COALESCE(NULLIF(TRIM(f.RETAILER_SEGMENT), ''), 'Unknown Retailer Segment') AS SEGMENT

    -- Star join: fact table + dimensions. LEFT JOINs keep every fact row even

    -- if a dimension row is missing (the COALESCEs above then show 'Unknown').

    FROM {{ ref('fct_transaction') }} i 
        LEFT JOIN {{ ref('dim_brand') }} b ON b.brand_id = i.brand_id
        LEFT JOIN {{ ref('dim_brand_group') }} e ON e.brand_group_id = i.brand_group_id
        LEFT JOIN {{ ref('dim_retailer') }} f ON f.retailer_id = i.retailer_id
        LEFT JOIN {{ ref('dim_sales_channel') }} g ON g.sales_mapping_key = i.sales_mapping_key
        LEFT JOIN {{ ref('dim_store') }} h ON h.store_key = i.transaction_store_key
        LEFT JOIN  {{ ref('dim_product') }} c ON c.ean_upc_key = i.transaction_ean_upc_key
        LEFT JOIN {{ ref('dim_department') }} a ON a.department_id = i.product_department_id
        LEFT JOIN {{ ref('dim_product_category') }} p ON p.product_category_id = i.product_category_id
        LEFT JOIN {{ ref('dim_product_sub_category') }} j ON j.sub_category_id = i.product_sub_category_id
        LEFT JOIN {{ ref('dim_date') }} d on i.transaction_date = d.CALENDAR_DATE
    -- Only categorised products + the region filter for this dataset.
    WHERE p.PRODUCT_CATEGORY IS NOT NULL
      AND LOWER(f.retailer_transaction_country) = 'united kingdom'--- UK country
    -- Aggregate to the dashboard grain (every non-measure column above).
    GROUP BY
    i.TRANSACTION_DATE,
    i.transaction_concat_key,
    a.product_department,
    g.sales_channel,
    g.sales_channel_group,
    p.product_category,
    c.jacket_type,
    c.layer_position,
    c.waterproof_technology,
    c.weight_class,
    c.primary_use,
    c.insulation_type,
    c.shell_construction,
    f.RETAILER_SEGMENT,
    j.product_sub_category,
    d.month_number,
    b.brand_description,
    c.product_name, 
    d.calendar_year_number
    