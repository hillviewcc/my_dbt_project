# RMIS: Retail Market Intelligence dbt Project

An anonymised portfolio copy of an actual live production dbt project built with **dbt Fusion** on **Snowflake**. It demonstrates how raw retail sales feeds are transformed into a star schema and BI datasets for UK, DACH and France reporting.

**Shared with permission.** This copy has been anonymised for use in job applications: retailer, brand and company names are fictitious, and infrastructure identifiers are placeholders. It contains no production source data or connection credentials.

**This repository cannot be run as supplied.** Execution requires a Snowflake account, authorised credentials, and the upstream raw/reference tables from the original environment, which are not included. I do not currently have access to that Snowflake environment. This repository is provided for code and architecture review; it is not a standalone runnable demo.

The original implementation operated in production. Subsequent portfolio fixes in this copy have received offline structural checks only and **have not been compiled or executed against Snowflake**. The included workflow definitions illustrate the deployment approach; this repository does not provide evidence of successful production runs. Snowflake workflows are opt-in and have no active schedule in this copy.

---

## What the pipeline does

```
 S3 files ──► Snowflake RAW (JSON VARIANT)
                    │
   landing/   (views)    parse JSON, standardise dates/signs/names, de-duplicate,
                         keep in-scope retailers
                    │
   staging/   (incremental tables)  typed + keyed; back-fill missing retailer
                         months with ESTIMATED data from the prior year
                    │
   u-reporting/ (incremental tables)  dim_* dimensions + fct_transaction
                         (FX-converted to GBP & EUR, outdoor scope only)
                    │
   z-quicksight_reporting/ (tables)  pre-aggregated, translated (EN/DE/FR)
                         dashboard datasets + pipeline audit & reconciliation
```

## Engineering highlights

| Area | What to look at |
|---|---|
| **Messy multi-source ingestion** | `landing/lnd_transaction.sql`: handles four date formats, inconsistent signs on returns, unit price vs line total, legacy retailer and store identifiers, and duplicate deliveries via a hashed composite key. |
| **Late-arriving data back-fill** | `staging/stg_transaction.sql`: when a retailer has not delivered for the reporting month, last year's data is copied forward and flagged `ESTIMATED`. A `pre_hook` removes the estimates as soon as the real data lands. |
| **Targeted incremental processing** | `u-reporting/fct_transaction.sql`: besides new rows, it reprocesses only the facts affected by product recategorisation, retailer or channel mapping changes, or FX rates that were missing on the last run. A `post_hook` keeps the fact table in sync with staging. |
| **Multi-currency** | Daily FX dimension; every sale is stored in local currency, GBP and EUR. |
| **Localisation** | `_dach` and `_fr` datasets use German and French labels for departments, categories, channels and technical product attributes. |
| **Data quality & observability** | `audit_transaction_pipeline` checks layer-to-layer row counts, data freshness and how much of the data is back-filled. `combined_data` + `water_fall_data_full` reconcile raw value to dashboard value. `daily_observability` shows which retailers have not delivered. |
| **Custom tests** | `tests/generic/unique_case_insensitive.sql` catches duplicates such as `'Brandex'` vs `'BRANDEX'` that the built-in `unique` test misses. |
| **History** | `snapshots/`: a type-2 SCD snapshot of the product master. |
| **CI/CD** | GitHub Actions: an opt-in manual dev build opens a promotion PR; merging that PR triggers the prod build when configured. Required approval must be enforced through branch protection. See [CICD.md](CICD.md). |

## Project layout

```
dbt_project.yml          project + per-layer config (databases, schemas, materialisations, grants)
selectors.yml            named selectors
.dbt/profiles.yml        Snowflake connection (all values from environment variables)
.github/workflows/       CI/CD pipelines
rmis_dbt_model/
  models/
    sources.yml          raw source definitions
    landing/             lnd_*  views
    staging/             stg_*  incremental tables
    u-reporting/         dim_* / fct_*  star schema
    z-quicksight_reporting/  tb_*  dashboard datasets, audit, reconciliation
    date/                dim_date (generated calendar)
  macros/  snapshots/  tests/
```

Every model starts with a header block that gives its layer, purpose, grain, dependencies and any notable design decisions.

## Reviewing the project

Start with `lnd_transaction.sql` (normalisation and deduplication), `stg_transaction.sql` (actual/estimated replacement), `fct_transaction.sql` (incremental dimensional enrichment), and `audit_transaction_pipeline.sql` (scope-aware reconciliation).

The portfolio changes separate actual-source ingestion watermarks from synthetic estimates, correct retailer change detection, and make reporting grants read-only, target-scoped and opt-in. Focused integration assertions cover estimate replacement, retailer mapping and reconciliation; they remain unexecuted without Snowflake. See [CICD.md](CICD.md) for workflow prerequisites and limitations.

## Execution reference — requires the original-equivalent Snowflake setup

Requires Python ≥ 3.11 and dbt Fusion (`curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update`).

Set the connection environment variables (PowerShell example, repeat with the `PRD_` prefix for prod):

```powershell
$env:DEV_SNOWFLAKE_ACCOUNT = ""
$env:DEV_SNOWFLAKE_USER = ""
$env:DEV_SNOWFLAKE_PRIVATE_KEY_PATH = ""
$env:DEV_SNOWFLAKE_ROLE = ""
$env:DEV_SNOWFLAKE_DATABASE = ""
$env:DEV_SNOWFLAKE_SCHEMA = ""
$env:RMIS_SNOWFLAKE_WAREHOUSE = ""
$env:DBT_PROFILES_DIR = "<path-to-repo>\.dbt"
```

```bash
dbt debug --target dev              # test the connection
dbt build                           # run + test everything (dev)
dbt run --select +fct_transaction   # a model and everything upstream of it
dbt build --selector z_quicksight_reporting   # dashboard datasets only
dbt snapshot                        # product history snapshot
dbt build --target prod             # production
```

### Access grants

Automatic grants are disabled by default. An administrator must provision the `reporting_reader` role first. In a configured environment, `--vars '{grant_reporting_access: true}'` enables SELECT-only grants on the current target's reporting schema. Dev runs do not grant access to production. Database/schema names must match the placeholder configuration before use.

### Runtime and dependencies

The original CI documentation records `dbt-fusion 2.0.0-preview.196`. The example installer follows the current Fusion release rather than pinning it; compatibility must be checked before enabling execution. Generated `dbt_internal_packages/` files are excluded: install the dbt engine instead of committing its bundled adapter code.
