# dbt CI/CD Pipeline

This document describes the automated GitHub Actions pipeline that replaces manually running `dbt test` / `dbt run` against dev and prod. It covers what the pipeline does, why it's built the way it is, and how to operate or extend it.

## Overview

Two workflows, both in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `dbt-monthly-refresh.yml` | Scheduled (15th of every month, 06:13 UTC) or manual (`workflow_dispatch`) | Runs `dbt test` on landing models, then `dbt run` for the full project against **dev**. On success, opens (or reuses) a PR that promotes the refresh to prod. |
| `dbt-prod-refresh.yml` | Only when the promotion PR above is merged | Runs `dbt run` for the full project against **prod**. |

The gate between dev and prod is a **human reviewing the actual dev data** the first workflow just refreshed — not a code review. Approving and merging the promotion PR is the signal that the data looks right and it's safe to refresh prod.

## Flow, step by step

1. **Scheduled or manually triggered:** `dbt-monthly-refresh.yml` runs `dbt test --select path:rmis_dbt_model/models/landing --target dev`, then `dbt run --target dev` (full project).
2. **On success**, a second job creates/updates a branch called `dbt-monthly-refresh-promotion` (built fresh off `main` each time) containing a small marker file (`ci/last_dev_refresh.md`) with the refresh timestamp. There's no real code change for a data-only refresh, so this file just gives the workflow something to open a PR from.
3. It opens a PR from that branch into `main` (or reuses an existing open one) titled "Promote monthly dbt dev refresh to prod - \<date\>", and requests review from the `example-org/approvers` GitHub team.
4. **A human checks the dev tables** that were just refreshed (schema, row counts, spot-checking values — whatever the normal data-quality check is) and, if satisfied, approves and merges the PR.
5. Merging that specific PR — and **only** that PR — triggers `dbt-prod-refresh.yml`, which runs `dbt run --target prod` (full project).

Regular code-change PRs merging to `main` do **not** trigger a prod run. Only a merge of the `dbt-monthly-refresh-promotion` branch does. This is enforced by a job-level condition (see [Prod trigger scoping](#why-the-prod-trigger-is-scoped-so-tightly) below).

## Required GitHub setup

### Secrets — repository level (Settings → Secrets and variables → Actions → Secrets)
For **dev**:
- `DEV_SNOWFLAKE_ACCOUNT`
- `DEV_SNOWFLAKE_USER`
- `DEV_SNOWFLAKE_ROLE`
- `DEV_SNOWFLAKE_DATABASE`
- `DEV_SNOWFLAKE_SCHEMA`
- `DEV_SNOWFLAKE_PRIVATE_KEY` — the **full PEM content** of the private key file (open the `.p8` file, copy everything from `-----BEGIN...` to `-----END...`), not a file path.

### Secrets — `production` GitHub Environment (Settings → Environments → production)
For **prod**, same pattern:
- `PRD_SNOWFLAKE_ACCOUNT`, `PRD_SNOWFLAKE_USER`, `PRD_SNOWFLAKE_ROLE`, `PRD_SNOWFLAKE_DATABASE`, `PRD_SNOWFLAKE_SCHEMA`, `PRD_SNOWFLAKE_PRIVATE_KEY` (full PEM content).

Note: the `production` environment exists purely to **scope these secrets**, not as an approval gate. GitHub's "required reviewers" environment protection rule needs GitHub Enterprise for a private repo — Team plan only offers it for public repos. The actual approval gate here is the promotion PR + branch protection on `main`, not an Environment protection rule.

### Variables — repository level (Settings → Secrets and variables → Actions → Variables)
- `RMIS_SNOWFLAKE_WAREHOUSE` — a single value used by **both** dev and prod (`profiles.yml` reads this one variable name for both targets), so it only needs setting once, as a plain variable (not a secret, since it's not sensitive).

### Teams
- `example-org/approvers` has `maintain` access on this repo (added specifically so the promotion PR's review request notifies its members) — matches the same team's role on the sibling `rmis_aws_lambda_functions` and `product_categorisation_pipeline` repos.

### Branch protection on `main`
Standard classic branch protection (1 required approving review) — already in place independently of this pipeline. This is what the promotion PR relies on for its approval gate.

## Why the prod trigger is scoped so tightly

An earlier version of `dbt-prod-refresh.yml` triggered on `push: branches: [main]` — i.e. any merge to main. That mirrored how the org's Lambda deployment pipeline works (`rmis_aws_lambda_functions`), where any approved merge should ship. For dbt, this had a real problem: merging *any* PR to main — including a routine code fix, or even a PR only touching the CI workflow files themselves — would fire a full prod refresh, without dev ever running first. That defeats the purpose of the gate, which is meant to be a data-quality check on a completed dev cycle, not a rubber stamp on a code diff.

The fix: `dbt-prod-refresh.yml` triggers on `pull_request: types: [closed]`, but the job itself only runs when:

```yaml
if: github.event.pull_request.merged == true && github.event.pull_request.head.ref == 'dbt-monthly-refresh-promotion'
```

So prod only ever runs as a direct continuation of a completed dev-refresh cycle — never from an unrelated merge.

## dbt Fusion quirks discovered while building this (all fixed, kept permanently)

- **Install URL:** the project's own `README.md` documents installing via `curl -fsSL https://install.dbtfusion.com/install.sh | sh` — this domain does not resolve at all (not a CI-specific issue; it's broken everywhere). The real installer is:
  ```
  curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update
  ```
  per `docs.getdbt.com/guides/fusion`. Worth fixing the README too.
- **`dbt` vs `dbtf`:** the installer creates a binary literally named `dbt`. `dbtf` is only a bash **alias** written to `~/.bashrc` — non-interactive shells (like each GitHub Actions `run:` step) never source `.bashrc`, so `dbtf` is never found in CI. Both are the same Fusion engine (confirmed via the `dbt-fusion 2.0.0-preview.196` version banner) — CI just has to call it `dbt`.
- **`DBT_PROFILES_DIR`:** this repo's `profiles.yml` lives at `.dbt/profiles.yml`, not the project root or `~/.dbt/` (matching the local dev setup in `open_rmis_with_profiles.cmd`). Without setting `DBT_PROFILES_DIR: ${{ github.workspace }}/.dbt` explicitly, dbt can't find the profile at all in CI.
- **Private key CRLF:** a `.p8` private key copy-pasted from a file edited on Windows can carry CRLF line endings, which break ASN.1 parsing of the key (`asn1: syntax error: sequence truncated`). Fixed by stripping `\r` when writing the key to disk in CI: `printf '%s' "$KEY" | tr -d '\r' > key.p8`.

## Scheduling notes

- The cron is `13 6 15 * *` (06:13 UTC), deliberately **not** on the hour. GitHub Actions scheduled workflows are documented to be more likely delayed at round times (like `:00`) due to platform-wide congestion — shifting a few minutes off reduces that risk.
- GitHub does not guarantee exact-time firing for scheduled workflows; delays of several minutes are normal and expected, especially shortly after a schedule value changes. A schedule change needs some lead time on `main` before its next occurrence to be reliably picked up.
- `workflow_dispatch` is available on `dbt-monthly-refresh.yml` for on-demand runs (Actions tab → "dbt Monthly Dev Refresh + Promote" → Run workflow), independent of the monthly schedule.

## Manually running the pipeline

- **Trigger a dev refresh now:** Actions tab → `dbt Monthly Dev Refresh + Promote` → Run workflow (pick the branch to run from).
- **Promote to prod:** review and merge the auto-opened promotion PR (titled "Promote monthly dbt dev refresh to prod - \<date\>"). There's no manual way to run `dbt-prod-refresh.yml` directly — it only fires from that PR merging, by design.
