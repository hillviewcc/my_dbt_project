{#
==============================================================================
  Macro     : last_n_months_filter(ts_col, n_months=1)
  Purpose   : Returns a WHERE-clause predicate that keeps rows whose timestamp
              falls in the current calendar month or the previous
              (n_months - 1) months.
  Status    : Not currently used - kept as a helper for limiting the scope of
              expensive tests on large tables.
  Example   : in a schema.yml test config
                  - not_null:
                      config:
                        where: "last_n_months_filter('loaded_timestamp', 2)"
                                (wrapped in double curly braces)
              -> current month + last month only.
==============================================================================
#}
{% macro last_n_months_filter(ts_col, n_months=1) -%}
{# lower bound: first day of the month (n_months - 1) months ago #}
{{ ts_col }} >= dateadd(month, -(n_months-1), date_trunc('month', current_timestamp()))
{# upper bound: first day of next month (exclusive) #}
AND {{ ts_col }} <  dateadd(month, 1, date_trunc('month', current_timestamp()))
{%- endmacro %}
