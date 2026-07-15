# SQL — Job-Card-Centric Schema (PostgreSQL 16)

Runnable DDL implementing [../docs/jobcard-centric-import-and-data-model.md](../docs/jobcard-centric-import-and-data-model.md).
Validated on PostgreSQL 16 (installs clean; the self-test reproduces the worked example exactly).

## Files (run in order)
| File | Contents |
|---|---|
| `01_masters.sql` | vehicle, item/material (single master), site, employee(+rate), supplier, job type, status, uom, category |
| `02_transactions.sql` | job_card_header + status_history + mrn/general/daily_work/labour/outside_repair, stock_issue_*, grn_*, price_history |
| `03_costing.sql` | job_card_cost_line (detail) + job_card_cost_summary |
| `04_import_staging.sql` | import_batch_log, import_error_log, `stg_*` staging (one per phase) |
| `05_views_functions.sql` | `v_job_card_cost`, `fn_recompute_job_cost`, `fn_effective_price`/`_rate`, closure gate (`fn_job_card_can_close`, `fn_job_card_close_blockers`, `v_job_card_closure_status`) |
| `install.sql` | includes 01–05 in dependency order |
| `06_seed_example.sql` | worked example **and** self-test (job JC-WS-26-00514) |

## Quick start
```bash
createdb mms
psql -d mms -v ON_ERROR_STOP=1 -f sql/install.sql        # run from repo root; install.sql \i's are relative to sql/
psql -d mms -f sql/06_seed_example.sql                    # optional: worked example + self-test
```
> `install.sql` uses `\i 01_masters.sql` style relative includes, so run psql from inside `sql/`
> (`cd sql && psql -d mms -f install.sql`) or pass the files individually.

## Expected self-test output
```
NOTICE:  BEFORE price fix: total=73420.0000 pending=3150.0000 variance=-11580.0000 can_close=f blockers={"Pending price on cost lines"}
NOTICE:  AFTER  price fix: total=73420.0000 pending=0.0000     variance=-11580.0000 can_close=t blockers={}
```
This demonstrates: cost roll-up from linked cost lines → `73,420`; a **provisional price keeps the job in
cost-pending and blocks closure**; a Phase-7 price update clears `pending_cost` and the closure gate opens.

## Design notes
- Every child table carries `job_card_id` (FK) — the job card is the hub; costs aggregate via
  `job_card_cost_line` → `fn_recompute_job_cost` → `job_card_cost_summary`.
- **No free-text material:** all material/general/issue/grn lines FK to `item_master`.
- `created_by`/`updated_by` are app-user ids kept as `bigint` (no FK) so the schema is self-contained;
  wire them to your user table when integrating with the broader [blueprint](../docs/00-foundation-and-standards.md).
- Posting an issue/labour/outside-repair (in the app) inserts a `job_card_cost_line` then calls
  `fn_recompute_job_cost(job_card_id)`; a price update flips `is_provisional=false` and recomputes.
