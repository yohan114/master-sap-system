# 11 — Data Migration Strategy

Move from **Excel files + old-system backups + manual records** into the MMS in controlled stages,
validating everything **before** it posts (core rule 9). Golden rule: **nothing enters live tables until
it passes validation and is reconciled.**

## 11.1 Migration architecture — three layers

```mermaid
flowchart LR
  SRC[Sources: Excel · old DB backups · manual sheets] --> STG[Staging: stg_* raw load]
  STG --> VAL[Validation & cleansing rules]
  VAL --> MAP[Mapping: map_* old→new codes]
  MAP --> LOAD[Controlled load into m_* / l_* / t_*]
  LOAD --> REC[Reconciliation & sign-off]
```

## 11.2 Staging tables (`stg_*`)

One staging table per source object, mirroring the sheet columns **plus** control columns. Load is raw
(text) so nothing is rejected at import; validation happens next.

| Staging table | Loads | Control columns (on every stg_) |
|---|---|---|
| `stg_item` | item lists from all books | `load_batch_id`, `source_file`, `source_row`, `row_status` (`NEW/VALID/ERROR/LOADED/SKIPPED`), `error_msg`, `loaded_id` |
| `stg_supplier` | supplier/vendor lists | ″ |
| `stg_asset` | vehicles & machines | ″ |
| `stg_location` | sites / stores / bins | ″ |
| `stg_price` | price lists & history | ″ |
| `stg_opening_stock` | on-hand qty & value per item×loc | ″ |
| `stg_lube_issue` | historic lube issue log | ″ |
| `stg_battery` | battery register (serial, warranty, vehicle) | ″ |
| `stg_battery_history` | battery movement log | ″ |
| `stg_open_jobcard` | in-flight job cards | ″ |
| `stg_txn_history` | optional historic movements | ″ |

## 11.3 Mapping tables (`map_*`)

Cross-reference old codes to new surrogate keys, so relationships survive the move.

| Mapping table | Resolves |
|---|---|
| `map_item_code` | old item code → `item_id` |
| `map_supplier_code` | old supplier code → `supplier_id` |
| `map_asset_code` | old vehicle/plate → `asset_id` |
| `map_location_code` | old store name → `location_id` |
| `map_uom` | free-text unit → `uom_id` |

Mapping tables are also the **de-duplication anchor**: two source rows that map to the same new code are
detected as duplicates.

## 11.4 Validation rules

Run as a rule set that stamps `row_status` + `error_msg`; only `VALID` rows are eligible to load.

| Rule | Applies to | Check |
|---|---|---|
| Mandatory key present | all | `item_code`/`serial_no`/`asset_code` not blank |
| Duplicate detection | masters | no two rows map to the same business key |
| Valid UoM | items, stock | unit resolves via `map_uom` |
| Date validity | dates | parseable, not future (for historic), warranty ≥ manufacture |
| Quantity validity | stock, issues | numeric, ≥ 0 (negatives flagged) |
| Value/price sanity | price, stock | ≥ 0; price within ±X% of peer items (outlier flag) |
| Orphan FK | relationships | referenced item/asset/supplier exists in mapping |
| Serial uniqueness | battery | `serial_no` unique across load + existing |
| Balance = qty×cost | opening stock | `opening_value ≈ opening_qty × unit_cost` (tolerance) |
| Category assigned | items | maps to a valid `m_item_category` |

Cleansing helpers: trim/normalize codes, standardize UoM synonyms (`LTR`→`L`), collapse duplicate
suppliers (fuzzy match to a survivor), default missing categories to a review bucket.

## 11.5 Duplicate & reconciliation controls

- **Duplicate check:** unique constraints on business keys + a pre-load report of collisions to resolve
  (merge or rename) before loading.
- **Opening stock reconciliation:** total qty and value per location in `stg_opening_stock` must tie to
  the old system's closing balance report; loaded opening `l_stock_ledger` (`OPENING` rows) is re-summed
  and compared — variance must be **zero** before sign-off.
- **Control totals:** row counts and value sums logged per `load_batch_id`; source vs staged vs loaded
  compared at each hop.
- **Sample audits:** N random items per category physically/visually verified post-load.

## 11.6 Opening stock as ledger entries

Opening balances are **not** a special stock field — each becomes an `OPENING` movement in
`l_stock_ledger` (`qty_in = opening_qty`, `unit_cost` = last cost, `running_balance` seeded). This keeps
the ledger the single source of truth from day one and makes the first monthly close correct.

## 11.7 Phased migration plan

| Phase | What migrates | Depends on | Exit criteria |
|---|---|---|---|
| **M0 · Prep** | Source inventory, template design, mapping tables seeded | — | Every source catalogued; templates signed off |
| **M1 · Masters** | Items, categories, UoM, suppliers, brands, sites/locations, assets, employees, GL | M0 | Masters de-duplicated; mapping complete; counts reconciled |
| **M2 · Prices** | Current prices + price history (`m_price`/`h_price`) | M1 | Effective ranges continuous; no gaps/overlaps |
| **M3 · Opening stock** | On-hand qty & value → `OPENING` ledger | M1, M2 | Opening value ties to old system (zero variance) |
| **M4 · Battery serials** | Battery register + movement history | M1, M3 | Every in-service battery has current asset + lineage |
| **M5 · Open job cards** | In-flight jobs, partial costs, pending items | M1–M4 | Open jobs re-createable with correct status & costs |
| **M6 · History (optional)** | Historic transactions, lube issues | M1–M5 | Sampled totals match legacy reports |

## 11.8 Cutover approach

1. **Dry runs** on a copy — repeat until validation error rate ≈ 0 and reconciliation is clean.
2. **Parallel run** (recommended 1 month): operate MMS alongside the old books; compare closing balances.
3. **Freeze & final delta load** at cutover weekend: lock old system, migrate the last movements.
4. **Go-live sign-off:** inventory_controller + finance_reviewer confirm reconciled balances.
5. **Rollback plan:** old system stays read-only for N months; batches are reversible by `load_batch_id`.

## 11.9 Migration controls & audit

- Every loaded row keeps `loaded_id` back-reference to its `stg_` origin (full lineage from Excel cell to
  live record).
- Loads run under the `system_administrator` role and are captured in `h_audit_log` with the batch id.
- No hand-editing of live tables during migration — corrections go back through staging.
