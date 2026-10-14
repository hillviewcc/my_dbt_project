{#
==============================================================================
  Test      : unique_case_insensitive(model, column_name)
  Purpose   : Custom generic test - like dbt's built-in `unique`, but ignores
              case and surrounding whitespace.
  Why       : The built-in test passed on dim_brand.brand_description even
              though it contained duplicates such as 'Brandex' and 'BRANDEX',
              because the comparison is case-sensitive. To the business these
              are the same brand, and the duplicate would split its sales
              across two rows in the dashboards.
  Fails when: the query returns any rows (each row = one duplicated value).
  Usage     : in schema.yml
                  columns:
                    - name: brand_description
                      data_tests:
                        - unique_case_insensitive
==============================================================================
#}

{% test unique_case_insensitive(model, column_name) %}

SELECT
  UPPER(TRIM({{ column_name }})) as normalised_value,   -- 'Brandex ' and 'BRANDEX' both become 'BRANDEX'
  COUNT(*) as duplicate_count
FROM {{ model }}
GROUP BY UPPER(TRIM({{ column_name }}))
HAVING COUNT(*) > 1                                     -- only return values that occur more than once

{% endtest %}
