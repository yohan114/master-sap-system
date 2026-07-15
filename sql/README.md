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
| `07_loader.sql` | **import loader**: `stg_*` → live, per-phase validation, `jc_no`→`job_card_id` resolution (parent-first + controlled stubs), reject routing to `import_error_log` (`fn_new_batch`, `fn_load_batch`, `fn_load_phase1..7`) |
| `08_posting.sql` | **posting/costing layer**: derive `job_card_cost_line` from imported/entered rows and recompute the summary (`fn_rebuild_job_costs`, `fn_rebuild_all_job_costs`, `fn_refresh_pending_prices`) |
| `install.sql` | includes 01–05 + 07 + 08 in dependency order |
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

## Loading data (per phase)

The loader moves each `stg_*` staging table into the live tables with validation. Flow per file:

```sql
-- 1. open a batch (auto_stub=false rejects orphan children to the review queue;
--    auto_stub=true attaches them to a controlled stub job card instead)
SELECT fn_new_batch(2, 'job_card_mrn_items', false) AS batch_id;   -- phase 2 example

-- 2. \copy the CSV into a temp table, then INSERT into stg_* with (batch_id, source_row_no, cols)
--    (see ../import-templates and the harness described below)

-- 3. run the loader for that batch
SELECT fn_load_batch(:batch_id);

-- 4. inspect results
SELECT * FROM import_batch_log      WHERE batch_id = :batch_id;   -- total/loaded/rejected
SELECT * FROM import_error_log      WHERE batch_id = :batch_id;   -- rule_code, severity, raw_row
```

Valid rows land in the live tables (`row_status='LOADED'`, `loaded_id` set); invalid rows go to
`import_error_log` with a rule code (`V-VEH`, `V-ITEM-UNK`, `V-CHILD-ORPHAN`, `V-LINE-DUP`, …) — the
batch is **never aborted** by a bad row.

### Loader — validated behaviour (PostgreSQL 16)
Loading the 7 [`../import-templates`](../import-templates) CSVs plus negative tests produced:

| Case | Result |
|---|---|
| Phases 1–7 template rows | all loaded, 0 rejected |
| Orphan child, `auto_stub=false` | `V-CHILD-ORPHAN` (REVIEW) — not loaded |
| Orphan child, `auto_stub=true` | controlled **stub** job card created, child attached |
| Unknown `item_code` | `V-ITEM-UNK` — rejected (no free-text material) |
| Duplicate line under same job | `V-LINE-DUP` — rejected |
| Labour with blank rate | resolved via `fn_effective_rate`; unresolved → `V-RATE-MISS` (WARN, loads cost-pending) |

## Costing after import (posting layer)

Loading fills the operational tables; **posting** turns them into cost. After a bulk import:

```sql
SELECT fn_rebuild_all_job_costs();      -- derive cost lines + summary for every real job
-- ...later, when prices are loaded (phase 7):
SELECT fn_refresh_pending_prices();     -- re-cost only jobs still carrying provisional lines
```
`fn_rebuild_job_costs(job_card_id)` derives MATERIAL (issued MRN lines), GENERAL, LABOUR (hours×rate)
and OUTSIDE cost lines, resolving each price as of the job's cost date. Any line with no resolvable
price is flagged `is_provisional` → the job is **cost-pending** and the closure gate stays shut.

### Posting — validated behaviour (PostgreSQL 16)
End-to-end on the imported example job `JC-WS-26-00514`:

| Stage | material | general | labour | outside | total | pending? | can_close |
|---|--:|--:|--:|--:|--:|:--:|:--:|
| After import, before all prices | 45,650 | 0 | 8,100 | 18,600 | 72,350 | **yes** | f (pending price) |
| After price update + refresh | 45,990 | 730 | 8,100 | 18,600 | **73,420** | no | f (`Missing TM/OM approval`) |
| After approvals recorded | — | — | — | — | 73,420 | no | **t** |

Variance vs the 85,000 estimate = **−11,580 (−13.62%)**. This is the full chain: import → derive cost
lines → roll up → provisional until priced → price update refreshes → closure gate enforces approvals.

## Design notes
- Every child table carries `job_card_id` (FK) — the job card is the hub; costs aggregate via
  `job_card_cost_line` → `fn_recompute_job_cost` → `job_card_cost_summary`.
- **No free-text material:** all material/general/issue/grn lines FK to `item_master`.
- `created_by`/`updated_by` are app-user ids kept as `bigint` (no FK) so the schema is self-contained;
  wire them to your user table when integrating with the broader [blueprint](../docs/00-foundation-and-standards.md).
- Posting an issue/labour/outside-repair (in the app) inserts a `job_card_cost_line` then calls
  `fn_recompute_job_cost(job_card_id)`; a price update flips `is_provisional=false` and recomputes.
