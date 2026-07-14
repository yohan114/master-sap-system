# 16 — Risks & Controls

## 16.1 Risk register

| # | Risk | Category | Impact | Likelihood | Mitigation / control | Owner |
|---|---|---|---|---|---|---|
| R1 | Duplicate/dirty masters carried over from Excel | Data | High | High | Staging + de-dup + mapping tables; pre-load collision report | system_administrator |
| R2 | Opening stock doesn't reconcile | Data | High | Medium | M3 zero-variance gate; parallel run | inventory_controller |
| R3 | Items received but never priced (working capital hidden) | Financial | High | Medium | `c_pending_price` queue + alert + closure gate | pricing_officer |
| R4 | Negative / silent stock | Process | High | Medium | No-negative rule; authorized `OVERRIDE_ISSUED` only + alert | inventory_controller |
| R5 | Job closed with incomplete cost | Financial | High | Medium | `fn_can_close_job` closure gate | finance_reviewer |
| R6 | Battery lineage broken on transfer | Data | Medium | Medium | Append-only `h_battery_movement`; integrity checks | battery_custodian |
| R7 | Approval bypass / self-approval | Process | High | Low | SoD rules; creator≠approver; engine-enforced | operational_manager |
| R8 | Wrong cost due to price-date errors | Financial | Medium | Medium | Effective-date resolution + `price_source` audit | pricing_officer |
| R9 | Low user adoption / revert to Excel | Adoption | High | Medium | Phased rollout, training, fast clerk UX, super-users | project sponsor |
| R10 | Data loss / outage | Technical | High | Low | Backups, PITR, DR, read replica | system_administrator |
| R11 | Unauthorized data access | Technical | High | Low | RBAC, least privilege, audit log, encryption | system_administrator |
| R12 | Scope creep delays go-live | Delivery | Medium | Medium | MVP-first ([17E](17-appendices.md)); phase gates | architect |
| R13 | Concurrency double-posting | Technical | Medium | Low | Row locks on balance; idempotency keys on API posts | backend lead |
| R14 | Numbering gaps/collisions | Process | Low | Low | Central `fn_next_docno` (gap-free, per-site-year) | system_administrator |

## 16.2 Internal controls by objective

### Stock accuracy
- **Mandatory ledger posting** — every movement writes `l_stock_ledger` (core rule 1); on-hand is
  derived, not editable.
- **No negative stock** without authorized override (core rule 2); overrides alert finance.
- **Two-sided transfers** — OUT + IN at equal cost via `IN_TRANSIT` (core rule 7); nothing lost.
- **Cycle counts** via `t_stock_adjustment` (approved, reason-coded); variance posts to ledger and feeds
  a stock-accuracy KPI.

### Costing accuracy
- **Closure gate** blocks premature close (core rule 3).
- **Effective-date pricing** + `price_source` recorded on every cost line (core rule 6).
- **Pending-price queue** flags provisional cost and blocks finalization; later true-up corrects ledger
  + costing.
- **Variance review** by finance before `COSTED`.

### Approval & segregation of duties
- Data-driven approval engine; **creator ≠ approver**; **receive ≠ price**; **two distinct** job
  approvers; delegation is explicit and logged.

### Serial integrity
- `h_battery_movement` / `h_battery_lifecycle` append-only; a battery cannot be `IN_SERVICE` without a
  `current_asset_id`; integrity job flags anomalies.

### Audit
- Per-row audit columns **plus** `h_audit_log` (old/new jsonb) on all tables (core rule 8).
- **Reverse, never delete** — corrections are reversing entries; originals immutable.

### Migration
- Validate-before-post (core rule 9); full lineage from Excel cell (`stg_.loaded_id`) to live record;
  batch-reversible loads.

### Business continuity
- Automated backups + point-in-time recovery; tested DR; read replica isolates reporting load; old
  system kept read-only post-cutover as fallback.

## 16.3 Core-rule → control traceability

| Core rule | Enforcing control |
|---|---|
| 1 Every movement → ledger | Mandatory ledger posting (service + trigger) |
| 2 No issue if short (unless override) | No-negative rule + `OVERRIDE_ISSUED` + alert |
| 3 Gated job closure | `fn_can_close_job` closure gate |
| 4 Battery serial history | Append-only `h_battery_movement` |
| 5 Lube traceability | Mandatory `asset_id/site_id/date` on lube issue |
| 6 Effective-date pricing | `m_price`/`h_price` resolution + `price_source` |
| 7 Transfers reduce/increase | Paired TRANSFER_OUT/IN via `IN_TRANSIT` |
| 8 Full audit fields | Audit columns + `h_audit_log` |
| 9 Validated migration | `stg_*` + validation rules + reconciliation |
| 10 Ops + management | RBAC + dashboards + read replica |
