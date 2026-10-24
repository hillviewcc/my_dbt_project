{% macro grant_reporting_read_access() %}
  {% if execute and var('grant_reporting_access', false) %}
    {% set reporting_database = (var('prod_reporting_db') if target.name == 'prod' else var('dev_db')) | upper %}
    {% set reporting_schema = (target.schema ~ '_REPORTING') | upper %}
    grant usage on database {{ adapter.quote(reporting_database) }} to role reporting_reader;
    grant usage on schema {{ adapter.quote(reporting_database) }}.{{ adapter.quote(reporting_schema) }} to role reporting_reader;
    grant select on all tables in schema {{ adapter.quote(reporting_database) }}.{{ adapter.quote(reporting_schema) }} to role reporting_reader;
    grant select on all views in schema {{ adapter.quote(reporting_database) }}.{{ adapter.quote(reporting_schema) }} to role reporting_reader;
    grant select on future tables in schema {{ adapter.quote(reporting_database) }}.{{ adapter.quote(reporting_schema) }} to role reporting_reader;
    grant select on future views in schema {{ adapter.quote(reporting_database) }}.{{ adapter.quote(reporting_schema) }} to role reporting_reader;
  {% endif %}
{% endmacro %}
