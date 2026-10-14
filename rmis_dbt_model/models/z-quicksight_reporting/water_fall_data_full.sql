/*
==============================================================================
  Model     : water_fall_data_full
  Layer     : Dashboard | table
  Purpose   : Waterfall-chart dataset built from combined_data: starts with
              total raw value and subtracts each excluded bucket, ending at
              the value shown on the dashboards.
  Grain     : One row per (year, month, retailer, country, retailer group,
              waterfall step).
  Depends on: combined_data
  Notes     : sort_order controls the order of the bars; exclusions are
              negative values.
==============================================================================
*/
-- Each UNION ALL block is one bar of the waterfall chart:
--   1 Total Raw Data (+)  ->  2 Non-Outdoor (-)  ->  4 Unmatched (-)  ->  5 Unknown Market (-)
-- What remains after the subtractions equals the value shown on the dashboards.

-- Bar 1: everything received from retailers
SELECT 
    year(transaction_date) as transaction_year,
    month(transaction_date) as transaction_month,
    retailer,
    transaction_country,
    retailer_group_id,
    'Total Raw Data' as category, 
    1 as sort_order, 
    SUM(raw_data_value) as value,
    transaction_date as transaction_date
FROM {{ ref('combined_data') }}

GROUP BY 1,2,3,4,5,9

UNION ALL

-- Bar 2: remove products outside the outdoor market
SELECT 
    year(transaction_date) as transaction_year,
    month(transaction_date) as transaction_month,
    retailer,
    transaction_country,
    retailer_group_id,
    'Non-Outdoor Value', 
    2, 
    -SUM(non_outdoor_value),
    transaction_date as transaction_date
FROM {{ ref('combined_data') }}
GROUP BY 1,2,3,4,5,9

UNION ALL

SELECT 
    year(transaction_date) as transaction_year,
    month(transaction_date) as transaction_month,
    retailer,
    transaction_country,
    retailer_group_id,
    'Unmatched Value',       -- Bar 4: remove outdoor sales with no product match
    4, 
    -SUM(unmatched_value),
    transaction_date as transaction_date
FROM {{ ref('combined_data') }}
GROUP BY 1,2,3,4,5,9
UNION ALL

SELECT 
    year(transaction_date) as transaction_year,
    month(transaction_date) as transaction_month,
    retailer,
    transaction_country,
    retailer_group_id,
    'Unknown Market',        -- Bar 5: remove sales with no market information
    5, 
    -SUM(unmatched_unknown_market),
    transaction_date as transaction_date
FROM {{ ref('combined_data') }}
GROUP BY 1,2,3,4,5,9

ORDER BY retailer, sort_order