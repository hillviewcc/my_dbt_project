# RMIS: Retail Market Intelligence dbt Project

A production dbt project, built with **dbt Fusion** on **Snowflake**, that turns raw sales feeds from dozens of retailers into a star schema and a set of BI-ready datasets for market-share, brand-share and retailer-share dashboards across the UK, DACH and France.

> **Note:** Retailer, brand and company names in this repository have been replaced with fictitious ones. Infrastructure identifiers (accounts, databases, roles) are placeholders.

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
| **CI/CD** | GitHub Actions: a monthly dev refresh opens a promotion PR, and prod runs only after that PR is approved. See [CICD.md](CICD.md). |

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

## Running it

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
