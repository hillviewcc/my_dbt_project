/*
==============================================================================
  Model     : tb_retailer_share
  Layer     : Dashboard | table
  Purpose   : Retailer share dataset: sales by retailer / segment / channel /
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
      i.TRANSACTION_DATE,
      i.transaction_concat_key,
      d.month_number as RETAILER_MONTH_NUMBER,
      d.calendar_year_number as RETAILER_CALENDAR_YEAR_NUMBER,
      -- retailer
      COALESCE(NULLIF(TRIM(f.RETAILER_NAME), ''), 'Unknown Retailer') AS RETAILER_NAME,
      COALESCE(NULLIF(TRIM(a.product_department), ''), 'Unknown Department') AS RETAILER_PRODUCT_DEPARTMENT,
      COALESCE(NULLIF(TRIM(g.sales_channel), ''), 'Unknown Sales Channel') AS RETAILER_SALES_CHANNEL,
      COALESCE(NULLIF(TRIM(g.sales_channel_group), ''), 'Unknown Sales Channel Group') AS RETAILER_SALES_CHANNEL_GROUP,
      COALESCE(NULLIF(TRIM(p.product_category), ''), 'Unknown Product Ctaegory') AS RETAILER_PRODUCT_CATEGORY,
      COALESCE(NULLIF(TRIM(j.product_sub_category), ''), 'Unknown Product_Sub_category') AS RETAILER_PRODUCT_SUB_CATEGORY,
      

      

      -- Measures: local-currency value, GBP and EUR converted value, units
      SUM(i.TRANSACTION_VALUE)        AS retailer_sales,
      SUM(i.GBP_FX_TRANSACTION_VALUE) AS gbp_retailer_sales,
      SUM(i.EUR_FX_TRANSACTION_VALUE) AS eur_retailer_sales,
      SUM(i.TRANSACTION_QUANTITY)     AS retailer_quantity,

      --attribute
      COALESCE(NULLIF(TRIM(f.retailer_segment), ''), 'Unknown Retailer Segment') AS RETAILER_SEGMENT,
      CASE WHEN f.RETAILER_ID IS NULL THEN -1 ELSE f.RETAILER_ID END AS RETAILER_ID,
      COALESCE(NULLIF(TRIM(c.jacket_type), ''), 'Unknown Jacket Type') AS RETAILER_JACKET_TYPE,
      COALESCE(c.layer_position,        'Unknown Layer Position')                    AS RETAILER_LAYER_POSITION,
      COALESCE(c.waterproof_technology,        'Unknown Waterproof Technology')                    AS RETAILER_WATERPROOF_TECHNOLOGY,
      COALESCE(c.weight_class,        'Unknown Weight Class')                    AS RETAILER_WEIGHT_CLASS,
      COALESCE(c.insulation_type,        'Unknown Insulation Type')                    AS RETAILER_INSULATION_TYPE,
      COALESCE(c.shell_construction,    'Unknown Shell Construction')               AS RETAILER_SHELL_CONSTRUCTION,
      COALESCE(NULLIF(TRIM(c.primary_use), ''), 'Unknown Primary Use') AS RETAILER_PRIMARY_USE

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
      f.RETAILER_NAME,
      f.RETAILER_SEGMENT,
      f.RETAILER_ID,
      c.jacket_type,
      c.layer_position,     
      c.waterproof_technology,
      c.weight_class,
      c.shell_construction,
      c.primary_use,
      c.insulation_type,
      i.transaction_concat_key,
      a.product_department,
      g.sales_channel,
      g.sales_channel_group,
      p.product_category,
      j.product_sub_category,
      d.month_number,
      d.calendar_year_number