/*
==============================================================================
  Model     : tb_brand_share
  Layer     : Dashboard | table
  Purpose   : Brand share dataset: sales by brand / category / channel /
              product attributes.
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
      i.TRANSACTION_DATE as BRAND_TRANSACTION_DATE,
      i.transaction_concat_key as BRAND_TRANSACTION_CONCAT_KEY,
      d.month_number as BRAND_MONTH_NUMBER,
      d.calendar_year_number as BRAND_CALENDAR_YEAR_NUMBER,
      -- brand
      COALESCE(NULLIF(TRIM(b.brand_description), ''), 'Unknown Brand') AS BRAND_NAME,
      CASE WHEN b.brand_id IS NULL THEN -1 ELSE b.brand_id END AS BRAND_ID,
      COALESCE(NULLIF(TRIM(e.brand_group), ''), 'Unknown Brand Group') AS BRAND_GROUP,
      CASE WHEN e.brand_group_id IS NULL THEN -1 ELSE e.brand_group_id END AS BRAND_GROUP_ID,
      COALESCE(NULLIF(TRIM(a.product_department), ''), 'Unknown Department') AS BRAND_PRODUCT_DEPARTMENT,
      COALESCE(NULLIF(TRIM(g.sales_channel), ''), 'Unknown Sales Channel') AS BRAND_SALES_CHANNEL,
      COALESCE(NULLIF(TRIM(g.sales_channel_group), ''), 'Unknown Sales Channel group') AS BRAND_SALES_CHANNEL_GROUP,
      COALESCE(NULLIF(TRIM(p.product_category), ''), 'Unknown Product Category') AS BRAND_PRODUCT_CATEGORY,
      COALESCE(NULLIF(TRIM(c.jacket_type), ''), 'Unknown Jacket Type') AS BRAND_JACKET_TYPE,
      COALESCE(NULLIF(TRIM(c.layer_position), ''), 'Unknown Layer Position') AS BRAND_LAYER_POSITION,
      COALESCE(NULLIF(TRIM(c.waterproof_technology), ''), 'Unknown Waterproof Technology') AS BRAND_WATERPROOF_TECHNOLOGY,
      COALESCE(NULLIF(TRIM(c.weight_class), ''), 'Unknown Weight Class') AS BRAND_WEIGHT_CLASS,
      COALESCE(NULLIF(TRIM(c.primary_use), ''), 'Unknown Primary Use') AS BRAND_PRIMARY_USE,
      COALESCE(NULLIF(TRIM(c.insulation_type), ''), 'Unknown Insulation Type') AS BRAND_INSULATION_TYPE,
      COALESCE(NULLIF(TRIM(c.shell_construction), ''), 'Unknown Shell Construction') AS BRAND_SHELL_CONSTRUCTION,
      --COALESCE(f.RETAILER_SEGMENT, 'Unknown Retailer Segment') AS BRAND_SEGMENT,
      COALESCE(NULLIF(TRIM(j.product_sub_category), ''), 'Unknown Product_Sub_category') AS BRAND_PRODUCT_SUB_CATEGORY,
      COALESCE(NULLIF(TRIM(c.product_name), ''), 'Unknown product') AS BRAND_PRODUCT_NAME,
      

      -- Measures: local-currency value, GBP and EUR converted value, units
      SUM(i.TRANSACTION_VALUE)        AS brand_sales,
      SUM(i.GBP_FX_TRANSACTION_VALUE) AS gbp_brand_sales,
      SUM(i.EUR_FX_TRANSACTION_VALUE) AS eur_brand_sales,
      SUM(i.TRANSACTION_QUANTITY)     AS brand_quantity

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
      b.brand_description,
      b.brand_id,
      e.brand_group,
      e.brand_group_id,
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
      j.product_sub_category,
      d.month_number,
      c.product_name,
      d.calendar_year_number
