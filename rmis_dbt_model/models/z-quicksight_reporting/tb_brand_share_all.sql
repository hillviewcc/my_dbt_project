/*
==============================================================================
  Model     : tb_brand_share_all
  Layer     : Dashboard | table
  Purpose   : Brand share dataset across all regions, with a derived region
              (UK / DACH / France / Other).
  Grain     : One row per transaction_concat_key and attribute combination
              (pre-aggregated SUMs of value / quantity).
  Depends on: fct_transaction + dim_brand, dim_brand_group, dim_retailer,
              dim_sales_channel, dim_store, dim_product, dim_department,
              dim_product_category, dim_product_sub_category, dim_date
  Notes     : Region filter: all countries except France. Display labels:
              English. Missing dimension values are replaced with 'Unknown
              ...' labels so the BI tool never shows blanks.
==============================================================================
*/
SELECT
      --this is same as tb_brand_share.sql except the country filter is removed to include all countries
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
      COALESCE(NULLIF(TRIM(p.product_category), ''), 'Unknown Product Ctaegory') AS BRAND_PRODUCT_CATEGORY,
      COALESCE(NULLIF(TRIM(j.product_sub_category), ''), 'Unknown Product_Sub_category') AS BRAND_PRODUCT_SUB_CATEGORY,
      COALESCE(NULLIF(TRIM(c.product_name), ''), NULLIF(TRIM(sp.product_name), ''), 'Unknown Product') AS BRAND_PRODUCT_NAME,
      COALESCE(NULLIF(TRIM(f.retailer_transaction_country), ''), 'Unknown country') AS BRAND_TRANSACTION_COUNTRY,
     case
        when f.retailer_transaction_country  = 'United Kingdom' then 'United Kingdom'
        when(f.retailer_transaction_country in ('Germany','Switzerland', 'Austria')) then 'DACH'
        when(f.retailer_transaction_country in ('France','FR')) then 'France'
        else 'Other'
      End as BRAND_REGION,

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
        LEFT JOIN {{ref('dim_product_gipfelhaus') }} sp on sp.ean_upc_key = i.transaction_ean_upc_key -- to get product name from gipfelhaus dimension, since they have a separate product table
        LEFT JOIN {{ ref('dim_department') }} a ON a.department_id = i.product_department_id
        LEFT JOIN {{ ref('dim_product_category') }} p ON p.product_category_id = i.product_category_id
        LEFT JOIN {{ ref('dim_product_sub_category') }} j ON j.sub_category_id = i.product_sub_category_id
        LEFT JOIN {{ ref('dim_date') }} d on i.transaction_date = d.CALENDAR_DATE
    -- Only categorised products + the region filter for this dataset.
    WHERE p.PRODUCT_CATEGORY IS NOT NULL
     AND LOWER(f.retailer_transaction_country) <> 'france'--- exclude france for now, will include in future iteration
    -- Aggregate to the dashboard grain (every non-measure column above).
    GROUP BY
      i.TRANSACTION_DATE,
      f.retailer_transaction_country,
      sp.product_name,
      b.brand_description,
      b.brand_id,
      e.brand_group,
      e.brand_group_id,
      i.transaction_concat_key,
      a.product_department,
      g.sales_channel,
      g.sales_channel_group,
      p.product_category,
      j.product_sub_category,
      d.month_number,
      c.product_name,
      d.calendar_year_number
