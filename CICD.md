# dbt workflow reference

These workflows are retained as examples from the anonymised production project. They cannot run successfully in this portfolio without Snowflake credentials and equivalent source/reference tables. No live Snowflake validation has been performed on the portfolio fixes.

## Disabled by default

There is no scheduled trigger. Set repository variable `ENABLE_SNOWFLAKE_WORKFLOWS=true` only in a deliberately configured deployment. A manual dev workflow runs `dbt build --target dev`, which builds resources and runs their selected tests. Only a successful build opens or updates the promotion PR. Merging `dbt-monthly-refresh-promotion` triggers `dbt build --target prod` when execution is enabled. Integration assertions now fail the build for reconciliation errors.

## Prerequisites

- A Snowflake environment containing the RAW_DB sources and configured dev/prod databases and schemas.
- Dev secrets: `DEV_SNOWFLAKE_ACCOUNT`, `DEV_SNOWFLAKE_USER`, `DEV_SNOWFLAKE_ROLE`, `DEV_SNOWFLAKE_DATABASE`, `DEV_SNOWFLAKE_SCHEMA`, `DEV_SNOWFLAKE_PRIVATE_KEY` (full PEM content).
- Production environment secrets: corresponding `PRD_` values, including `PRD_SNOWFLAKE_PRIVATE_KEY`.
- Repository variable `RMIS_SNOWFLAKE_WAREHOUSE`.
- Actions permission to create pull requests, and branch protection requiring human approval. The workflow does not itself enforce approval; the placeholder organisation reviewer has been removed.
- Check compatibility with an explicitly selected Fusion version before deployment. The example installer currently follows the latest release; the original implementation recorded preview.196.

The workflows write private keys to temporary files with restricted permissions and use `.dbt/profiles.yml`. No private keys are committed. Reporting access grants are disabled by default and can be explicitly enabled with `grant_reporting_access`; they are read-only and restricted to the current target's reporting schema.

## Promotion limitation

This inherited data-refresh pattern creates a marker PR from main. It does not pin the dev-tested code revision or source-data snapshot: changes merged between dev validation and production can alter the result. Before operational reuse, pin the validated revision and define data-snapshot/revalidation controls. Treat this repository as a reviewable example, not a ready-to-enable deployment.

## Verification

Offline checks cover YAML parsing, Jinja syntax, model references and static regression checks. They do not prove SQL compilation, permissions, adapter compatibility, data correctness, incremental idempotency or successful deployment. Those require the configured Snowflake environment.
