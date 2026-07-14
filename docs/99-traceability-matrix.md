# 99 — Cross-Module Traceability & Consistency Matrix

This closes the loop: it proves each requirement and core rule is covered, shows how a transaction flows
across the shared spines, and records the naming-consistency checks.

## 99.1 How to read this blueprint (reading order)

1. [00 — Foundation](00-foundation-and-standards.md) — the shared vocabulary (read first).
2. [01 — Solution Overview](01-solution-overview.md) & [02 — Business Architecture](02-business-architecture.md) — the why & the shape.
3. [03 — Module Breakdown](03-module-breakdown.md) — what each module does.
4. [04](04-database-masters.md) · [05](05-database-transactions.md) · [06](06-database-costing-history-approval.md) — the data model.
5. [07 — Workflows](07-workflow-design.md) & [08 — Costing](08-costing-logic.md) — how it runs & costs.
6. [09](09-dashboards-and-kpis.md) · [10](10-user-roles-and-permissions.md) · [11](11-data-migration-strategy.md) · [12](12-uiux-design-direction.md) · [13](13-reports-and-documents.md) · [14](14-integration-architecture.md) — operate, secure, migrate, present, integrate.
7. [15](15-implementation-roadmap.md) · [16](16-risks-and-controls.md) · [17](17-appendices.md) — deliver & govern.

## 99.2 Requirements coverage

| Requirement area | Covered in |
|---|---|
| A. Stores / Material Management | 03A, 04, 05, 07(a–c,h), 13 |
| B. Oil / Lubricant Stock Book | 03B, 04(§4.4), 05(§5.7), 07(d), 09(§9.3) |
| C. Battery Stock Book | 03C, 04(§4.6), 05(§5.11), 06(§6.4), 07(e) |
| D. Jobcard / Workshop | 03D, 05(§5.10), 06(§6.1), 07(f,g), 08 |
| Shared masters (no duplicates) | 00(§0.3), 02(§2.5), 04 |
| Universal stock ledger | 00(§0.5), 05(§5.2) |
| Approvals | 06(§6.6), 07, 10 |
| Costing & valuation | 06(§6.1–6.2), 08 |
| Dashboards & KPIs | 09 |
| Roles & permissions | 10 |
| Migration | 11 |
| UI/UX | 12, `/prototype` |
| Reports & documents | 13 |
| Integration & future SAP | 14 |
| Roadmap | 15 |
| Risks & controls | 16 |
| Menu / hierarchy / numbering / alerts / MVP | 17 (A–E) |

## 99.3 Core business rule → enforcement

| # | Rule | Table / mechanism | Doc |
|---|---|---|---|
| 1 | Movement → ledger | `l_stock_ledger` post on every txn | 05 |
| 2 | No short issue w/o override | `OVERRIDE_ISSUED` + permission | 05, 07, 10 |
| 3 | Gated job closure | `fn_can_close_job`, `c_pending_price` | 06, 07, 08 |
| 4 | Battery serial history | `h_battery_movement` (append-only) | 06 |
| 5 | Lube traceability | `t_issue.asset_id/site_id/date` | 05 |
| 6 | Effective-date pricing | `m_price`/`h_price` resolution | 06, 08 |
| 7 | Transfers two-sided | paired TRANSFER_OUT/IN via `IN_TRANSIT` | 05 |
| 8 | Full audit | audit cols + `h_audit_log` | 06 |
| 9 | Validated migration | `stg_*` + rules + reconcile | 11 |
| 10 | Ops + management | RBAC + dashboards + replica | 10, 09, 14 |

## 99.4 Data-flow traceability (transaction → ledger → costing → surfacing)

| Transaction | Source doc | Stock-ledger effect | Costing effect | Surfaces in |
|---|---|---|---|---|
| Goods receipt | `t_grn` | `RECEIPT` (+qty, WAC/FIFO update) | may queue `c_pending_price` | GRN register, stock value, pending pricing |
| Material transfer | `t_transfer` | paired `TRANSFER_OUT` + `TRANSFER_IN` | — | transfer register, transfer-by-location |
| General issue | `t_issue(GENERAL)` | `ISSUE` (−qty) | `c_job_cost_detail(GENERAL)` if job-linked | item movement, fast/slow movers |
| Job parts issue | `t_issue(JOB)` | `ISSUE` (−qty) | `c_job_cost_detail(MATERIAL)` | job cost sheet, cost by vehicle |
| Lubricant issue | `t_issue(LUBRICANT)` | `ISSUE` (−qty, asset-tagged) | `MATERIAL` if job-linked | lube issue report, consumption, days-of-cover |
| Battery punch | `t_battery_txn(PUNCH)` | `ISSUE` (battery stock) | — | battery-by-vehicle, lifecycle |
| Labour | `t_job_labour` | — | `c_job_cost_detail(LABOUR)` | labour summary, utilization |
| Outside repair | `t_outside_repair`→`t_grn` | `RECEIPT` if part | `c_job_cost_detail(OUTSIDE)` | outside-repair spend, job cost |
| Job closure | `t_job_card→CLOSED` | — | finalizes `c_job_cost_summary` | variance report, monthly spend |
| Stock adjustment | `t_stock_adjustment` | `ADJUSTMENT` (±qty) | — | stock accuracy, audit trail |

Every ledger and costing row carries `source_doc_type` + `source_doc_id` + `source_doc_no`, so each flow
above is **drillable both ways** — KPI tile ⇄ source document.

## 99.5 Naming-consistency checks

| Check | Result |
|---|---|
| Table names in 04–06 match the registry in [00 §0.3–0.8] | ✔ consistent (`m_`/`t_`/`l_`/`h_`/`a_`/`c_` prefixes applied throughout) |
| Status values in workflows (07) match [00 §0.9] | ✔ same UPPER_SNAKE flows; `DELAYED`/`ON_HOLD` documented as job-card flags |
| Numbering masks in 07/13/17 match [00 §0.10] | ✔ identical masks & examples (single source in 00, re-tabled in 17C) |
| Role names in 10 match [00 §0.12] | ✔ all 14 roles consistent |
| Costing elements (LABOUR/MATERIAL/GENERAL/OUTSIDE) consistent 06/08/09/13 | ✔ |
| Lubricants/batteries modelled as `m_item` categories (no duplicate item lists) | ✔ stated in 02, 03, 04, 17B |
| Assets unified under `m_asset` (vehicle/machine/equipment) | ✔ used consistently in costing, lube, battery |

**Overall:** the blueprint is internally consistent — one foundation, reused verbatim across all
sections. No contradictory table, status, numbering or role definitions were found.
