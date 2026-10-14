/*
==============================================================================
  Model     : tb_market_share_dach
  Layer     : Dashboard | table
  Purpose   : Total-market dataset for the German-speaking markets, with
              jacket attributes translated to German.
  Grain     : One row per transaction_concat_key and attribute combination
              (pre-aggregated SUMs of value / quantity).
  Depends on: fct_transaction + dim_brand, dim_brand_group, dim_retailer,
              dim_sales_channel, dim_store, dim_product, dim_department,
              dim_product_category, dim_product_sub_category, dim_date
  Notes     : Region filter: Germany, Switzerland, Austria. Display labels:
              German. Missing dimension values are replaced with 'Unknown ...'
              labels so the BI tool never shows blanks.
==============================================================================
*/
SELECT
      -- DATE
      i.TRANSACTION_DATE,
      i.transaction_concat_key,
      d.month_number,
      d.calendar_year_number,
      COALESCE(NULLIF(TRIM(a.product_department_de), ''), 'Unknown Department') AS PRODUCT_DEPARTMENT,
      COALESCE(NULLIF(TRIM(g.sales_channel_de), ''), 'Unknown Sales Channel') AS SALES_CHANNEL,
      COALESCE(NULLIF(TRIM(g.sales_channel_group_de), ''), 'Unknown Sales Channel Group') AS SALES_CHANNEL_GROUP,
      COALESCE(NULLIF(TRIM(p.product_category_de), ''), 'Unknown Product Category') AS PRODUCT_CATEGORY,
      COALESCE(NULLIF(TRIM(j.product_sub_category_de), ''), 'Unknown Product Subcategory') AS PRODUCT_SUB_CATEGORY,
      COALESCE(NULLIF(TRIM(b.brand_description), ''), 'Unknown brand') AS MARKET_BRAND_NAME,
      COALESCE(NULLIF(TRIM(c.product_name), ''), NULLIF(TRIM(sp.product_name), ''), 'Unknown Product') AS PRODUCT_NAME,

      -- Measures: local-currency value, GBP and EUR converted value, units
      SUM(i.TRANSACTION_VALUE)        AS market_sales,
      SUM(i.GBP_FX_TRANSACTION_VALUE) AS gbp_market_sales,
      SUM(i.EUR_FX_TRANSACTION_VALUE) AS eur_market_sales,
      SUM(i.TRANSACTION_QUANTITY)     AS market_quantity,

      -- Product attributes translated to German for the DACH dashboards.
      -- Input values are the English labels produced in lnd_product.
      CASE LOWER(c.jacket_type)
        WHEN 'casual lifestyle'       THEN 'Lifestyle / Freizeit'
        WHEN 'fleece jacket'          THEN 'Fleecejacke'
        WHEN 'hardshell'              THEN 'Hardshell'
        WHEN 'hybrid'                 THEN 'Hybrid'
        WHEN 'not applicable'         THEN 'Nicht zutreffend'
        WHEN 'rain jacket'            THEN 'Regenjacke'
        WHEN 'snow jacket'            THEN 'Skijacke'
        WHEN 'softshell'              THEN 'Softshell'
        WHEN 'windbreaker'            THEN 'Windbreaker'
        ELSE 'Jackentyp unbekannt'
      END                                                                       AS JACKET_TYPE,
      CASE LOWER(c.layer_position)
        WHEN 'base layer'             THEN 'Baselayer'
        WHEN 'mid layer'              THEN 'Midlayer'
        WHEN 'not applicable'         THEN 'Nicht zutreffend'
        WHEN 'outer layer'            THEN 'Außenschicht'
        ELSE 'Position im Lagensystem unbekannt'
      END                                                                       AS LAYER_POSITION,
      CASE LOWER(c.waterproof_technology)
        WHEN 'brand membrane'            THEN 'Markeneigene Membran'
        WHEN 'durable water repellent'   THEN 'DWR-Imprägnierung (wasserabweisend)'
        WHEN 'gore-tex'                  THEN 'Gore-Tex'
        WHEN 'not waterproof'            THEN 'Nicht wasserdicht'
        WHEN 'other'                     THEN 'Sonstige'
        WHEN 'pertex shield'             THEN 'Pertex Shield'
        ELSE 'Wasserdichtigkeits-Technologie unbekannt'
      END                                                                       AS WATERPROOF_TECHNOLOGY,
      COALESCE(c.weight_class,        'Unknown Weight Class')                    AS WEIGHT_CLASS,
      CASE LOWER(c.primary_use)
        WHEN 'camping'                THEN 'Camping'
        WHEN 'climbing'               THEN 'Klettern'
        WHEN 'everyday'               THEN 'Alltag'
        WHEN 'hiking'                 THEN 'Wandern'
        WHEN 'running'                THEN 'Running'
        WHEN 'ski'                    THEN 'Ski'
        ELSE 'Haupteinsatzbereich unbekannt'
      END                                                                       AS PRIMARY_USE,
      CASE LOWER(c.insulation_type)
        WHEN 'down'                   THEN 'Daune'
        WHEN 'hybrid'                 THEN 'Hybrid'
        WHEN 'natural'                THEN 'Naturfaser'
        WHEN 'synthetic'              THEN 'Kunstfaser'
        WHEN 'wool'                   THEN 'Wolle'
        ELSE 'Isolationsart unbekannt'
      END                                                                       AS INSULATION_TYPE,
      CASE LOWER(c.shell_construction)
        WHEN '3 in 1'                 THEN '3-in-1'
        WHEN 'unknown'                THEN 'Unbekannt'
        WHEN 'hardshell'              THEN 'Hardshell'
        WHEN 'hybrid'                 THEN 'Hybrid'
        WHEN 'insulated puffer'       THEN 'Isolierte Steppjacke'
        WHEN 'not applicable'         THEN 'Nicht zutreffend'
        WHEN 'soft shell'             THEN 'Softshell'
        ELSE 'Unbekannt'
      END                                                                       AS SHELL_CONSTRUCTION,
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
        LEFT JOIN {{ref('dim_product_gipfelhaus') }} sp on sp.ean_upc_key = i.transaction_ean_upc_key
        LEFT JOIN {{ ref('dim_department') }} a ON a.department_id = i.product_department_id
        LEFT JOIN {{ ref('dim_product_category') }} p ON p.product_category_id = i.product_category_id
        LEFT JOIN {{ ref('dim_product_sub_category') }} j ON j.sub_category_id = i.product_sub_category_id
        LEFT JOIN {{ ref('dim_date') }} d on i.transaction_date = d.CALENDAR_DATE
    -- Only categorised products + the region filter for this dataset.
    WHERE p.PRODUCT_CATEGORY IS NOT NULL
      AND LOWER(f.retailer_transaction_country) IN ('germany','switzerland','austria')--- DACH countries
    -- Aggregate to the dashboard grain (every non-measure column above).
    GROUP BY
    i.TRANSACTION_DATE,
    i.transaction_concat_key,
    a.product_department_de,
    g.sales_channel_de,
    g.sales_channel_group_de,
    p.product_category_de,
    j.product_sub_category_de,
    d.month_number,
    b.brand_description,
    c.product_name,
    sp.product_name,
    c.jacket_type,
    c.layer_position,
    c.waterproof_technology,
    c.weight_class,
    c.primary_use,
    c.insulation_type,
    c.shell_construction,
    f.RETAILER_SEGMENT,
    d.calendar_year_number
    