-- Scope-aware audit failures must fail dbt build rather than only populate a table.
select * from {{ ref('audit_transaction_pipeline') }}
where check_type = 'INTEGRITY_CHECK' and status = 'FAIL'
