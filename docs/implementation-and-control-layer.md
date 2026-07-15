# Implementation & Control Layer — Migration, Dashboards, Security & Roadmap

> Phase 4. The implementation and control layer over [Phase 1 Architecture](master-architecture-and-data-model.md),
> [Phase 2 Stores/Lube/Battery](process-design-stores-lubricant-battery.md) and
> [Phase 3 Job Card & Costing](process-design-jobcard-and-costing.md). Consistent with
> [00 Foundation](00-foundation-and-standards.md); expands [09 Dashboards](09-dashboards-and-kpis.md),
> [10 Roles](10-user-roles-and-permissions.md), [11 Migration](11-data-migration-strategy.md),
> [14 Integration](14-integration-architecture.md), [15 Roadmap](15-implementation-roadmap.md),
> [16 Risks](16-risks-and-controls.md).

**What this layer adds on top of the earlier phases:**
1. **Site-based row-level security** — normal users see only their own site; managers see broader scope by role.
2. **Dashboards by user role** — each role lands on the right dashboard, scoped to what they may see.
3. **Auditable control plane** — every approval, reversal, and cost/price edit is logged and reportable.

---

## PART A — DATA MIGRATION PLAN

### A.1 Strategy (three layers)

```
Sources (Excel · old backups · manual) ─► stg_* staging (raw) ─► validate + cleanse
   ─► map_* cross-reference ─► controlled load into m_/l_/t_ ─► reconcile ─► sign-off
```
**Golden rule:** nothing enters live tables until it passes validation **and** reconciles.

### A.2 Staging-table approach (`stg_*`)

One staging table per source object, mirroring the sheet columns **plus** control columns.

| Staging table | Loads | Control columns (on every `stg_`) |
|---|---|---|
| `stg_item`, `stg_supplier`, `stg_asset`, `stg_location` | masters | `load_batch_id`, `source_file`, `source_row`, `row_status` (`NEW/VALID/ERROR/LOADED/SKIPPED`), `error_msg`, `loaded_id` |
| `stg_price` | current + historic prices | ″ |
| `stg_opening_stock` | on-hand qty & value per item×location | ″ |
| `stg_battery`, `stg_battery_history` | serials + movement log | ″ |
| `stg_open_jobcard` | in-flight jobs + partial costs | ″ |
| `stg_txn_history` | optional historic movements | ″ |

Load is raw (text) so nothing is rejected at import; validation runs next and stamps `row_status`.

### A.3 Mapping (`map_*`) — cleansing & cross-reference

| Mapping table | Resolves |
|---|---|
| `map_item_code` | old item code → `item_id` |
| `map_supplier_code` | old supplier code → `supplier_id` |
| `map_asset_code` | old plate/fleet no → `asset_id` |
| `map_location_code` | old store name → `location_id` |
| `map_uom` | free-text unit → `uom_id` |

Cleansing: trim/normalize codes, standardize UoM synonyms (`LTR→L`), collapse duplicate suppliers to a
survivor, bucket unknown categories for review. Mapping tables are also the **de-dup anchor**.

### A.4 Validation & reconciliation rules

| Rule | Applies | Check |
|---|---|---|
| Mandatory key | all | business key not blank |
| Valid UoM | items, stock | resolves via `map_uom` |
| Date validity | dates | parseable; warranty ≥ manufacture; not implausibly future |
| Quantity validity | stock, issues | numeric, ≥ 0 (negatives flagged) |
| Price sanity | price, stock | ≥ 0; within ±X% of peer items (outlier flag) |
| Orphan FK | relationships | referenced master exists in mapping |
| Serial uniqueness | battery | `serial_no` unique across load + existing |
| Value tie | opening stock | `opening_value ≈ opening_qty × unit_cost` (tolerance) |

**Reconciliation:** opening stock qty & value per location must tie to the old system's closing report;
loaded `OPENING` ledger is re-summed and compared — **zero variance** before sign-off. Control totals
(row counts, value sums) logged per `load_batch_id` and compared source→staged→loaded. Sample audits per
category.

### A.5 Duplicate detection logic

**Deterministic (hard) match** → auto-merge candidate:
- Item: same normalized `item_code`; or identical (description + category + UoM).
- Supplier: same `tax_id`; or same normalized name + phone.
- Asset: same `reg_no`/`chassis_no`.
- Battery: same `serial_no` (**must** be unique — hard block).

**Fuzzy (soft) match** → review queue: normalized-string similarity (e.g. trigram/Levenshtein ≥ 0.85) on
name/description; flag near-duplicates for a steward decision.

**Survivorship rule:** keep the record with the most complete/mastered data as the **survivor**;
deactivate the loser (`is_active=false`); repoint all references via `map_*`. Nothing is deleted.

### A.6 Phased migration & cutover

`M1 Masters → M2 Prices → M3 Opening stock (as OPENING ledger) → M4 Battery serials → M5 Open job
cards → M6 History (optional)`. Dry-runs until error rate ≈ 0 → parallel run (≈1 month, compare closing
balances) → freeze + final delta load at cutover → sign-off by inventory_controller + finance_reviewer.
Batches are reversible by `load_batch_id`; old system kept read-only as fallback. Full detail:
[11 Migration](11-data-migration-strategy.md).

---

## PART B — SECURITY & ACCESS CONTROL

### B.1 Two independent dimensions

Access = **what you can do** (RBAC) **×** **which data you can see** (site scope). Both are enforced;
neither alone is sufficient.

### B.2 RBAC (what you can do)
`m_user → m_role → m_permission`. Roles per [10](10-user-roles-and-permissions.md): store_keeper,
receiving_clerk, pricing_officer, inventory_controller, lubricant_officer, battery_custodian,
transport_officer, transport_manager, operational_manager, workshop_supervisor, technician,
finance_reviewer, management_viewer, system_administrator.

### B.3 Site-based visibility (which data you can see) — row-level security

Every user has a **data scope**; every transactional/ledger row carries or resolves a `site_id`
(directly, or via `location_id → m_location.site_id`).

**Scope model** — `m_user_site_scope(scope_id, user_id, site_id)` plus `m_user.scope_type`:

| scope_type | Sees | Typical roles |
|---|---|---|
| `SINGLE_SITE` | only the user's own site (one row in `m_user_site_scope`) | store_keeper, receiving_clerk, technician, transport_officer, lubricant_officer |
| `MULTI_SITE` | an explicit set of sites | workshop_supervisor, inventory_controller (cluster) |
| `REGION` | all sites where `m_site.region = user's region` | operational_manager |
| `GLOBAL` | all sites | finance_reviewer, management_viewer, system_administrator |

**Enforcement (defence in depth):**
- **Session context:** on login the app resolves the user's allowed `site_id` set and sets it as a
  request/session variable.
- **Database Row-Level Security (Postgres RLS)** on every site-bearing table, so scope can't be bypassed
  even by direct queries:
  ```sql
  ALTER TABLE t_job_card ENABLE ROW LEVEL SECURITY;
  CREATE POLICY p_jc_site ON t_job_card USING (
      current_setting('app.scope_type') = 'GLOBAL'
      OR site_id = ANY (string_to_array(current_setting('app.user_sites'), ',')::bigint[])
  );
  ```
- **Application layer** additionally injects the same site filter on every list/report/dashboard query.
- **Ledger:** `l_stock_ledger.location_id → m_location.site_id` is the scope join; a materialized
  `site_id` column (or indexed view) keeps the filter fast.

**Rules:**
- A `SINGLE_SITE` user **cannot** see, edit, approve, or report on another site's stock, jobs, or costs.
- A user can never approve/receive/issue against a site outside their scope.
- Cross-site actions (e.g. inter-site transfers) require a user whose scope covers **both** sites, or a
  two-party hand-off (source user dispatches; destination user receives) — each acting within scope.
- Managers' broader scope is granted **by role + scope_type**, never ad hoc per record.

### B.4 Auditability of approvals, reversals, and cost/price edits

| Event | Logged where |
|---|---|
| Every approval (approve/reject/return) | `a_approval_action` (who, step, when, comment) + `h_audit_log` |
| Every reversal | reversing `l_stock_ledger` row (`reversal_of_ledger_id`) + `h_audit_log(action=REVERSE)` with reason |
| Every price change | append-only `h_price` (old range closed) + `h_audit_log` on `m_price` |
| Every cost edit | costs are **derived, not hand-edited**; any override/true-up writes `c_job_cost_detail` history + `h_audit_log` |
| Every master/config change | `h_audit_log` old→new jsonb |

**Immutable trails:** ledger, `h_*` and audit tables are append-only (reverse-not-delete). Cost and price
changes are therefore fully reconstructable — satisfying "all edits to cost and price data must be
auditable."

---

## PART C — PERMISSION MATRIX (user-role, with data scope)

Legend: **C**reate · **R**ead · **U**pdate · **A**pprove · **X** reverse · **Z** close · **P** report · **—** none.
"Scope" = default data visibility.

| Action / Role | store_keeper | receiving_clerk | pricing_officer | inventory_controller | lubricant_officer | battery_custodian | transport_officer | transport_manager | operational_manager | workshop_supervisor | technician | finance_reviewer | mgmt_viewer | sys_admin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Data scope** | SINGLE | SINGLE | MULTI | MULTI | SINGLE | MULTI | SINGLE | MULTI | REGION | MULTI | SINGLE | GLOBAL | GLOBAL | GLOBAL |
| MRN | C R U | R | R | A | R | — | R | R | R | R | — | R P | R | R |
| Purchase (LPO/HPR) | C R | R | R | A | — | — | — | R | A(HPR) | R | — | R P | R | R |
| GRN / receiving | R | C R U | R(price) | R | R | R | — | R | R | R | — | R P | R | R |
| Price / effective price | R | R | **C R U** | R | R | R | — | R | R | — | — | R P | R | C R U |
| Issue (gen/job/lube) | C R | R | R | R U | C R(lube) | — | — | R | R | R | R(req) | R P | R | R |
| Transfer | C R | R | R | A | R | — | — | R | R | R | — | R | R | R |
| Adjustment | C R | R | R | C R | R | R | — | R | R | R | — | **A** | R | R |
| Reverse movement | — | — | — | **X** | — | — | — | — | — | — | — | **X** | — | X |
| Battery txn | R | R | R | R | R | C R U | — | R | R | C R | — | R | R | R |
| Battery warranty/scrap | — | — | — | R | — | **C** | — | — | R | R | — | **A** | R | R |
| Job card | R | R | R | R | R | R | **C R U** | **A**(L1) | **A**(L2) | R U | R | R P | R | R |
| Labour | — | — | — | — | — | — | — | R | R | C R U | **C R** | R | R | R |
| Parts request | R | — | — | R | — | — | R | R | R | C R | **C R** | R | R | R |
| Outside repair | — | R | R(price) | — | — | — | — | R | **A** | C R U | — | R P | R | R |
| Close job card | — | — | — | — | — | — | — | — | R | **Z** | — | **Z** | — | R |
| Dashboards / reports | R P | R P | R P | R P | R P | R P | R P | R P | R P | R P | R | **R P** | **R P** | R P |
| Users / roles / workflow | — | — | — | — | — | — | — | — | — | — | — | — | — | **C R U** |
| Data migration | — | — | — | R | — | — | — | — | — | — | — | R | — | **C R U** |

**SoD:** receive ≠ price · create ≠ approve · two distinct job approvers · issue ≠ adjust · cost review independent · reverse restricted.

---

## PART D — DASHBOARD CATALOG (by role, site-scoped)

### D.1 Which role lands where

| Role | Default dashboard | Scope applied |
|---|---|---|
| store_keeper | Stores | own site |
| receiving_clerk | Stores (receiving view) | own site |
| pricing_officer | Exception (pending pricing) | assigned sites |
| inventory_controller | Stores + Exception | assigned sites |
| lubricant_officer | Lubricant | own site |
| battery_custodian | Battery | assigned sites |
| transport_officer | Workshop (my job cards) | own site |
| transport_manager | Approval Queue + Workshop | assigned sites |
| operational_manager | Executive + Approval Queue | region |
| workshop_supervisor | Workshop (job board) | assigned sites |
| technician | Workshop (my tasks) | own site |
| finance_reviewer | Executive + Exception | global |
| management_viewer | Executive | global |
| system_administrator | Admin + all | global |

### D.2 The seven dashboards

| Dashboard | Primary widgets | Key KPIs |
|---|---|---|
| **Executive** | KPI band · maintenance-spend trend · job-status donut · exception panel | total stock value · pending pricing · open/overdue jobs · monthly spend · supplier spend · warranty exposure · stock accuracy |
| **Stores** | stock value · receipts/issues today · reorder list · movers | total stock value · low/critical stock · fast/slow movers · pending pricing · transfer volume by location · open MRNs |
| **Lubricant** | consumption trend · days-of-cover strip · top consumers | monthly lubricant consumption · avg usage (L/1000km, L/hr) · days-of-cover · reorder list · consumption by asset/site |
| **Battery** | fleet status map · warranty gauge · lifecycle | warranty due/expired · avg life achieved · swaps this month · frequent-swap vehicles · battery stock value |
| **Workshop** | job kanban · utilization · cost-by-vehicle · blockers | open/pending/delayed/completed · labour utilization · avg turnaround · job cost by vehicle · outside-repair spend |
| **Approval Queue** | my-pending list with SLA burndown | items awaiting me · age vs SLA · value pending · breaches |
| **Exception** | exception feed (drillable) | pending pricing · overrides used · consumed-but-unpriced · delayed jobs · stuck transfers · broken serials · warranty overdue |

### D.3 KPI definitions (named)

| KPI | Formula | Source | Scope |
|---|---|---|---|
| Total stock value | `Σ running_balance_value` latest per item×loc | `l_stock_ledger` | site |
| Pending pricing | count & value unresolved | `c_pending_price` | site |
| Low stock | `on_hand ≤ reorder_level` | ledger + `m_item` | site |
| Fast-moving items | top N by issue qty (90d) | ledger ISSUE | site |
| Slow-moving items | zero issues in N days, on_hand>0 | ledger | site |
| Monthly lubricant consumption | `Σ issue qty` LUBRICANT per month | `l_stock_balance_month` | site |
| Battery warranty due | `warranty_expiry` within window | `m_battery` | scope |
| Open job cards | `status ∉ (CLOSED,CANCELLED)` | `t_job_card` | scope |
| Overdue job cards | open & past `planned_end` | `t_job_card` | scope |
| Labour utilization | `Σ labour hrs ÷ available tech hrs` | `t_job_labour`,`m_employee` | site |
| Job cost by vehicle | `Σ total_cost` by asset | `c_job_cost_summary` | scope |
| Supplier spend | `Σ GRN value` by supplier | `t_grn` | scope |
| Transfer volume by location | `Σ TRANSFER_OUT` by loc | `l_stock_ledger` | scope |

### D.4 Site-restricted dashboard rules

- Every tile, chart, grid and drill-down inherits the viewer's **site scope filter** — the *same* filter
  as RLS, so a KPI can never total data the user may not see.
- `SINGLE_SITE` users see single-site figures with no site selector.
- `MULTI_SITE`/`REGION`/`GLOBAL` users get a **site selector** (default "All my sites") and can slice
  by site; totals recompute within scope.
- Drill-through respects scope: clicking a KPI opens only in-scope source documents.
- Exports/reports carry the same scope; a scoped user cannot export out-of-scope rows.

---

## PART E — REPORT CATALOG

All parameterized, **site-scoped**, exportable (PDF/Excel/CSV), schedulable, drill-to-source.

| Report | Purpose | Formats |
|---|---|---|
| Stock Ledger | every movement + running balance | PDF/Excel |
| Item Movement | consolidated in/out/balance | PDF/Excel |
| MRN Register / GRN Register | requisitions / receipts & valuation | PDF/Excel |
| Pending Pricing | unpriced receipts/consumption | Excel |
| Stock Balance (item/location/category/date) | on-hand & value | PDF/Excel |
| Monthly Stock Balance | opening/receipts/issues/closing | PDF/Excel |
| Reorder / Critical Stock | at/below threshold + days-of-cover | Excel |
| Transfer Register | paired OUT/IN, net by location | Excel |
| Lubricant Issue / Consumption vs Forecast | usage by asset; ADC & variance | PDF/Excel |
| Lube Price History | price trend | PDF |
| Battery Lifecycle / Battery by Vehicle | serial life / fleet view | PDF/Excel |
| Warranty Due / Expired | action window | Excel |
| Open Job Card / Delayed Jobs | WIP & overdue | PDF/Excel |
| Job Costing Sheet | full cost of one job | PDF |
| Labour Summary | technician hours & cost | PDF/Excel |
| Variance (est vs actual) | by vehicle/dept | Excel |
| Supplier Spend | purchasing by supplier | Excel |
| Audit Trail | who changed what (incl. approvals/reversals/price edits) | PDF/Excel |

Printable documents: MRN, GRN, Material Transfer Note, Lubricant Issue Voucher, Battery Issue/Serial
Voucher, Job Cost Sheet, Job Card — with document number, signatures and optional QR. Detail:
[13 Reports](13-reports-and-documents.md).

---

## PART F — ALERT & NOTIFICATION FRAMEWORK

**Engine:** event → rule → severity → channel → recipient, driven by a transactional **outbox** so no
event is lost. Rules are configurable (threshold, severity, channel, recipient role). Channels: in-app,
email, WhatsApp, SMS. Recipients resolved by role **and site scope** (site users get their site's alerts;
managers get their scope's).

| Alert | Trigger | Severity | Channel | Recipient |
|---|---|---|---|---|
| Critical / low stock | `on_hand ≤ min_qty` / `≤ reorder_level` | High / Med | in-app+email / in-app | store_keeper, inventory_controller |
| Missing price | GRN unpriced > 3d | Med | in-app | pricing_officer |
| Consumed but unpriced | job uses provisional-cost item | Med | in-app | pricing_officer, supervisor |
| Stock override used | `OVERRIDE_ISSUED` posted | High | in-app+email | inventory_controller, finance |
| Unmatched serial | battery txn serial mismatch | High | in-app | battery_custodian |
| Pending receipt | PO past expected_date | Med | in-app | store_keeper |
| Stuck transfer | `IN_TRANSIT` > N days | Med | in-app | both store_keepers |
| Lube days-of-cover low | `days_of_cover < lead_time` | High | in-app+email | inventory_controller |
| Abnormal lube consumption | asset > μ+2σ | Med | in-app | lubricant_officer |
| Battery warranty due/expired | within/over window | Med | in-app+WhatsApp | battery_custodian |
| Approval pending | > SLA hours | Med | in-app+WhatsApp | transport/operational_manager |
| Job delayed | open past planned_end | High | in-app | workshop_supervisor |
| Job closure blocked | gate fails > N days | Med | in-app | pricing_officer, supervisor |
| Outside repair overdue | not returned by expected_date | Med | in-app | workshop_supervisor |

---

## PART G — FUTURE-READY / INTEGRATION READINESS

| Capability | Design |
|---|---|
| **API readiness** | REST/OData, OAuth2/JWT (RBAC + site scope in the token), versioned `/v1`, **idempotency keys** on posting endpoints |
| **Barcode / QR** | item/bin labels, battery serial QR; scan-to-open, scan-to-issue, scan-to-confirm-location |
| **Image upload (battery serial proof)** | capture at punch → `m_battery.image_url` (original + thumbnail, EXIF date) for warranty evidence |
| **Attachment handling** | invoices/quotes/photos on GRN, job card, outside repair; storage abstraction (local/S3), URLs in DB |
| **Email / WhatsApp alerts** | pluggable channel adapters behind the notification outbox; delivery tracked, retried |
| **BI integration** | read replica + star-schema views (`v_fact_ledger`, `v_fact_jobcost`, `dim_*`); same facts as in-app dashboards |
| **SAP-style integration (future)** | object mapping — item→Material Master, GRN→MIGO, PO→ME21N, job card→PM order, cost→CO order — via IDoc/BAPI/OData adapters |

Detail: [14 Integration](14-integration-architecture.md).

---

## PART H — IMPLEMENTATION ROADMAP

| Phase | Scope | Exit criteria |
|---|---|---|
| **P1 · Foundation + Stores** | masters, RBAC + **site scope**, stock ledger, MRN/PO/GRN/pricing/issue/transfer/adjust; migration M1–M3 | opening stock reconciled (zero variance); every movement posts a ledger row |
| **P2 · Lubricant + Battery** | lube issue+consumption+monthly balance+reorder; battery serials+lifecycle; M4 | every in-service battery has current asset + unbroken lineage; lube days-of-cover live |
| **P3 · Job Card + Costing** | job card, 2-level approval, parts/labour/outside, self-assembling costing, closure gate; M5 | job cannot close with pending price/missing labour/uncosted OR; cost sheet ties to postings |
| **P4 · Dashboards + Automation** | role dashboards (site-scoped), alerts/notification engine, exception monitoring, scheduled reports, audit reporting | KPIs reconcile to source; alerts route by role+scope; audit trail complete |
| **P5 · Integrations + Mobile** | REST/OData API, QR scan-to-act, image/attachment service, WhatsApp/email channels, BI star views, mobile; SAP-readiness | posting idempotency proven; BI datasets certified |

Sequencing rule: masters + ledger + site scope must exist before costing and dashboards. Detail:
[15 Roadmap](15-implementation-roadmap.md).

---

## PART I — RISK REGISTER (implementation & control focus)

| # | Risk | Impact | Likelihood | Mitigation / control | Owner |
|---|---|---|---|---|---|
| 1 | Duplicate/dirty masters from Excel | High | High | staging + deterministic+fuzzy dedup + survivorship + `map_*` | sys_admin |
| 2 | Opening stock doesn't reconcile | High | Med | M3 zero-variance gate + parallel run | inventory_controller |
| 3 | Site data leakage across sites | High | Med | RLS + app filter + scoped exports (defence in depth) | sys_admin |
| 4 | Over-broad manager access | Med | Med | scope_type by role only; no ad-hoc grants; periodic access review | finance_reviewer |
| 5 | Missing prices hide working capital | High | Med | `c_pending_price` + alert + closure gate | pricing_officer |
| 6 | Un-audited cost/price edits | High | Low | derived costs only; `h_price`/`h_audit_log` append-only | finance_reviewer |
| 7 | Approval/reversal not logged | High | Low | `a_approval_action` + `h_audit_log(REVERSE)` mandatory | sys_admin |
| 8 | Low adoption / revert to Excel | High | Med | phased rollout, training, fast scoped dashboards, super-users | sponsor |
| 9 | Alert fatigue | Med | Med | severity tiers, scope-targeted routing, tunable thresholds | ops team |
| 10 | Data loss / outage | High | Low | backups, PITR, DR, read replica | sys_admin |
| 11 | Scope creep delays go-live | Med | Med | MVP-first (Part J) + phase gates | architect |
| 12 | Concurrency double-posting via API | Med | Low | idempotency keys + row locks | backend lead |

---

## PART J — MVP vs ADVANCED

| Area | MVP | Advanced |
|---|---|---|
| **Migration** | masters, prices, opening stock, battery serials, open jobs; deterministic dedup | full historic load; fuzzy-match review UI; auto-survivorship rules |
| **Security** | RBAC + site scope (SINGLE/GLOBAL); audit log | REGION/MULTI granular scope UI; delegation; access certification |
| **Dashboards** | Executive, Stores, Workshop, Approval Queue, Exception (site-scoped) | Lubricant/Battery analytics, cost-of-ownership, reliability heatmap, forecasting |
| **KPIs** | stock value, pending pricing, low stock, open/overdue jobs, supplier spend | movers, days-of-cover, utilization, warranty analytics, transfer analytics |
| **Alerts** | in-app + email, critical set | WhatsApp/SMS, full configurable rule engine, SLA burndown |
| **Reports** | ledger, GRN/MRN, monthly balance, job cost sheet, audit trail | scheduled distribution, BI star schema, custom report builder |
| **Integration** | Excel import/export, attachments, image upload | QR scan-to-act, REST/OData API, Power BI, SAP interfaces |
| **Mobile** | responsive web | native-feel shop-floor & approver apps, offline scan |

**Why this MVP:** it delivers **trustworthy, site-scoped stock and truly-costed jobs with a complete
audit trail** — the control layer that makes the operational data safe to rely on — while deferring
analytics depth and external integrations that build cleanly on top later.
