/*
==============================================================================
  Model     : dim_date
  Layer     : Date | table
  Purpose   : Calendar dimension generated in SQL (no source table needed):
              day, week, month, quarter, year, fiscal, season and UK holiday
              attributes.
  Grain     : One row per calendar date from 2010-01-01 (20,000 days).
  Depends on: none - generated with Snowflake GENERATOR()
  Notes     : Joined by every dashboard model on transaction_date =
              calendar_date.
==============================================================================
*/
WITH date_dimension AS (
  -- Generate date series
  SELECT 
    DATEADD('day', seq4(), '2010-01-01'::DATE) as calendar_date
  FROM TABLE(GENERATOR(ROWCOUNT => 20000))  -- Generates ~54 years of dates
),

final AS (
  SELECT
    -- Key fields
    TO_CHAR(calendar_date, 'YYYYMMDD')::NUMBER as date_id,
    calendar_date as date_key,
    calendar_date as calendar_date,
    TO_CHAR(calendar_date, 'YYYY-MM-DD') as calendar_date_char,
    
    -- Day attributes
    TO_CHAR(calendar_date, 'Dy') as day_name_short,
    CASE DAYOFWEEK(calendar_date)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_name_long,
    CASE 
      WHEN DAYOFMONTH(calendar_date) IN (1,21,31) THEN DAYOFMONTH(calendar_date)::STRING || 'st'
      WHEN DAYOFMONTH(calendar_date) IN (2,22) THEN DAYOFMONTH(calendar_date)::STRING || 'nd'
      WHEN DAYOFMONTH(calendar_date) IN (3,23) THEN DAYOFMONTH(calendar_date)::STRING || 'rd'
      ELSE DAYOFMONTH(calendar_date)::STRING || 'th'
    END as day_of_month,
    DAYOFWEEK(calendar_date) + 1 as day_of_week_number,
    DAYOFMONTH(calendar_date) as day_of_month_number,
    CASE WHEN DAYOFWEEK(calendar_date) IN (0,6) THEN 0 ELSE 1 END as weekday_ind,
    
    -- Month attributes
    TO_CHAR(calendar_date, 'YYYYMM')::NUMBER as year_month_number,
    TO_CHAR(calendar_date, 'MMYYYY')::NUMBER as month_year_number,
    TO_CHAR(calendar_date, 'Mon-YYYY') as month_year_desc,
    MONTH(calendar_date) as month_number,
    TO_CHAR(calendar_date, 'MMMM') as calendar_month_name_long,
    TO_CHAR(calendar_date, 'Mon') as calendar_month_name_short,
    DATE_TRUNC('MONTH', calendar_date)::DATE as first_day_of_month,
    LAST_DAY(calendar_date)::DATE as last_day_of_month,
    
    -- Quarter attributes
    CASE 
      WHEN MONTH(calendar_date) <= 3 THEN 3
      WHEN MONTH(calendar_date) <= 6 THEN 6
      WHEN MONTH(calendar_date) <= 9 THEN 9
      ELSE 12
    END - MONTH(calendar_date) + 1 as month_of_calendar_quarter,
    (YEAR(calendar_date) * 10 + QUARTER(calendar_date))::NUMBER as calendar_year_quarter_number,
    'CY' || YEAR(calendar_date) || ' Q' || QUARTER(calendar_date) as calendar_year_quarter_desc,
    QUARTER(calendar_date) as calendar_quarter_number,
    'Q' || QUARTER(calendar_date) as calendar_quarter_desc,
    CASE QUARTER(calendar_date)
      WHEN 1 THEN 'First'
      WHEN 2 THEN 'Second'
      WHEN 3 THEN 'Third'
      WHEN 4 THEN 'Fourth'
    END as calendar_quarter_name,
    DATE_TRUNC('QUARTER', calendar_date)::DATE as first_day_of_calendar_quarter,
    LAST_DAY(DATEADD('MONTH', 2, DATE_TRUNC('QUARTER', calendar_date)))::DATE as last_day_of_calendar_quarter,
    
    -- Year attributes
    YEAR(calendar_date) as calendar_year_number,
    'CY' || YEAR(calendar_date) as calendar_year_desc,
    DAYOFYEAR(calendar_date) as calendar_year_day_number,
    
    -- Week attributes
    DATE_TRUNC('WEEK', calendar_date)::DATE as week_commencing,
    DATEADD('DAY', 6, DATE_TRUNC('WEEK', calendar_date))::DATE as week_ending,
    WEEKOFYEAR(calendar_date) as calendar_week_number,
    YEAR(calendar_date) || '-wk' || LPAD(WEEKOFYEAR(calendar_date)::STRING, 2, '0') as calendar_week_desc,
    
    -- Fiscal attributes (assuming fiscal year starts in January)
    'FY' || YEAR(calendar_date) || '-' || RIGHT((YEAR(calendar_date) + 1)::STRING, 2) as fiscal_year_desc,
    'p' || MONTH(calendar_date) as fiscal_period_desc,
    MONTH(calendar_date) as fiscal_period_number,
    YEAR(calendar_date) || '-wk' || LPAD(WEEKOFYEAR(calendar_date)::STRING, 2, '0') as fiscal_week_desc,
    WEEKOFYEAR(calendar_date) as fiscal_week_number,
    
    -- Additional attributes
    CASE 
      WHEN MONTH(calendar_date) IN (3,4,5) THEN 'Spring'
      WHEN MONTH(calendar_date) IN (6,7,8) THEN 'Summer'
      WHEN MONTH(calendar_date) IN (9,10,11) THEN 'Autumn'
      ELSE 'Winter'
    END as season,
    
    -- UK/Europe Holiday indicators
    CASE
      WHEN MONTH(calendar_date) = 1 AND DAYOFMONTH(calendar_date) = 1 THEN 'New Year''s Day'
      WHEN MONTH(calendar_date) = 12 AND DAYOFMONTH(calendar_date) = 25 THEN 'Christmas Day'
      WHEN MONTH(calendar_date) = 12 AND DAYOFMONTH(calendar_date) = 26 THEN 'Boxing Day'
      WHEN MONTH(calendar_date) = 5 AND DAYOFMONTH(calendar_date) = 1 THEN 'May Day Bank Holiday'
      WHEN MONTH(calendar_date) = 8 AND DAYOFWEEK(calendar_date) = 1 
        AND DAYOFMONTH(calendar_date) BETWEEN 25 AND 31 THEN 'Summer Bank Holiday'
      
      ELSE NULL
    END as holiday_name,
    
    -- Additional indicators
    CASE 
      WHEN MOD(YEAR(calendar_date), 4) = 0 
        AND (MOD(YEAR(calendar_date), 100) != 0 
        OR MOD(YEAR(calendar_date), 400) = 0) 
      THEN 1 
      ELSE 0 
    END as leap_year_ind,
    
    -- Time intelligence
    DATEADD('YEAR', -1, calendar_date)::DATE as prior_year_date,
    DATEADD('MONTH', -1, calendar_date)::DATE as prior_month_date,
    DATEADD('DAY', -1, calendar_date)::DATE as prior_day_date

  FROM date_dimension
)

SELECT * FROM final