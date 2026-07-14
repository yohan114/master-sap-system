# 09 — Dashboards & KPI Design

Two tiers: an **Executive dashboard** (cross-module health) and **Operational dashboards** (Stores,
Lubricant, Battery, Workshop). Every KPI is a query over the shared ledger/costing tables and **drills
down to the source document**.

## 9.1 Executive dashboard (management_viewer, operational_manager, finance_reviewer)

Top KPI band (large tiles), then trend + exception panels.

| KPI | Definition / formula | Source | Drill-down | Refresh | Chart |
|---|---|---|---|---|---|
| **Total stock value** | `Σ running_balance_value` latest per item×loc | `l_stock_ledger` | by location/category | 15 min | KPI + donut by category |
| **Pending pricing** | count & value of `c_pending_price` unresolved | `c_pending_price` | list to pricing queue | 5 min | KPI + red badge |
| **Open job cards** | jobs not `CLOSED/CANCELLED` | `t_job_card` | job list | 5 min | KPI + status donut |
| **Overdue job cards** | open jobs past `planned_end` | `t_job_card` | delayed list | 5 min | KPI + trend |
| **Monthly maintenance spend** | `Σ total_cost` jobs closed in month | `c_job_cost_summary` | by vehicle/dept | hourly | column trend |
| **Purchase spend (MTD)** | `Σ grn value` | `t_grn` | by supplier | hourly | bar by supplier |
| **Battery warranty exposure** | in-service batteries within/over warranty | `m_battery` | warranty list | daily | gauge |
| **Stock accuracy** | 1 − |adjust qty|/throughput | `t_stock_adjustment` | cycle-count report | daily | gauge |

## 9.2 Stores / Material dashboard

| KPI | Formula | Source | Threshold |
|---|---|---|---|
| Total stock value | `Σ balance_value` | ledger | — |
| Low-stock items | `on_hand ≤ reorder_level` | ledger vs `m_item` | count > 0 → amber |
| Critical-stock items | `on_hand ≤ min_qty` | ledger vs `m_item` | any → red |
| Fast-moving items | top N by issue qty (rolling 90d) | ledger ISSUE | top 10 |
| Slow-moving / dead stock | zero issues in N days, on_hand > 0 | ledger | > 180d → flag |
| Pending pricing | unresolved `c_pending_price` | pending | > 3d → alert |
| Today's receipts / issues | count & value | ledger by date | — |
| Open MRNs | not `CLOSED` | `t_mrn` | aging |
| Transfer volume by location | `Σ TRANSFER_OUT` by loc | ledger | trend |

## 9.3 Lubricant dashboard

| KPI | Formula | Source |
|---|---|---|
| Critical lube stock | `on_hand ≤ reorder_level` (LUBRICANT) | ledger + `m_item` |
| Average usage | issue qty ÷ km or machine-hr (rolling) | `t_issue`, `m_asset` |
| **Days-of-cover / days left** | `on_hand ÷ avg_daily_consumption` | ledger + rolling avg |
| Monthly consumption | `Σ issue qty` per month | `l_stock_balance_month` |
| Transaction counts | issues/receipts per period | ledger |
| Top consuming assets | `Σ qty` by `asset_id` | `t_issue` |
| Consumption by site/project | `Σ qty` grouped | `t_issue` |
| Abnormal-consumption flags | asset issue > μ + kσ | `t_issue` rolling stats |

## 9.4 Battery dashboard

| KPI | Formula | Source |
|---|---|---|
| Fleet battery status | count by `current_status` | `m_battery` |
| Warranty due (≤ N days) | `warranty_expiry` within window | `m_battery` |
| Warranty expired in service | `warranty_expiry < today AND IN_SERVICE` | `m_battery` |
| Average life achieved | avg(scrap_date − punch_date) | `h_battery_lifecycle` |
| Swaps this month | `count t_battery_txn TRANSFER/REPLACEMENT` | txn |
| Frequent-swap vehicles | vehicles with ≥ k swaps / 12m | `h_battery_movement` |
| Battery stock value | `Σ` unassigned battery value | ledger + `m_battery` |

## 9.5 Workshop dashboard

| KPI | Formula | Source |
|---|---|---|
| Open / Pending / Delayed / Completed | counts by status/flag | `t_job_card` |
| Jobs by status (kanban) | group by `status_code` | `t_job_card` |
| Labour utilization | `Σ labour hours ÷ available tech hours` | `t_job_labour`, `m_employee` |
| Avg turnaround time | avg(`actual_end − actual_start`) closed | `t_job_card` |
| Job cost by vehicle | `Σ total_cost` by asset | `c_job_cost_summary` |
| Outside-repair spend | `Σ outside_cost` | `c_job_cost_summary` |
| Top failure categories | group by complaint/task category | `t_job_task` |
| Closure blockers | jobs `WORK_COMPLETED` w/ pending price / no labour | gate query |

## 9.6 Alert logic & exception monitoring

Alerts are **event → rule → severity → channel → recipient**. Evaluated by a scheduled rules engine and
in real time on posting.

| Alert | Trigger condition | Severity | Channel | Recipient |
|---|---|---|---|---|
| Critical stock | `on_hand ≤ min_qty` | High | in-app + email | store_keeper, inventory_controller |
| Reorder point | `on_hand ≤ reorder_level` | Medium | in-app | store_keeper |
| Negative-stock override used | issue `OVERRIDE_ISSUED` posted | High | in-app + email | inventory_controller, finance_reviewer |
| GRN pending pricing | unpriced GRN > 3 days | Medium | in-app | pricing_officer |
| Abnormal lube consumption | asset issue > μ+2σ | Medium | in-app | lubricant_officer |
| Lube days-of-cover low | days_left < lead_time | High | in-app + email | inventory_controller |
| Battery warranty due | `warranty_expiry` ≤ 30d | Medium | in-app + WhatsApp | battery_custodian |
| Battery warranty expired in service | expired & IN_SERVICE | Medium | in-app | battery_custodian |
| Job awaiting approval | `SUBMITTED/TM_APPROVED` > SLA hours | Medium | in-app + WhatsApp | transport/operational_manager |
| Job delayed | open past `planned_end` | High | in-app | workshop_supervisor |
| Job closure blocked | `WORK_COMPLETED` + pending price | Medium | in-app | pricing_officer, supervisor |
| Outside repair overdue | not returned by `expected_date` | Medium | in-app | workshop_supervisor |
| Price variance | new price > ±X% vs last | Low | in-app | pricing_officer |

**Exception monitoring** is a dedicated dashboard panel that surfaces "things that shouldn't be true":
overrides used, negative balances, unpriced-but-consumed items, jobs stuck > N days, batteries with
broken lineage (no current asset but IN_SERVICE), MRNs approved but never issued. Each exception links
straight to its record for resolution.

## 9.7 Creative management widgets

- **Cost-of-ownership card per vehicle** — combines maintenance (`c_job_cost_summary`), lubricant burn,
  battery swaps and downtime days into a single per-asset running cost.
- **"Money stuck" tile** — total value of stock that is received-but-unpriced + jobs blocked from
  closing; a direct pointer to working capital and revenue recognition friction.
- **Reliability heatmap** — vehicles × failure category, coloured by job count, to spot chronic assets.
- **Days-of-cover strip** — a horizontal bar per critical item shading green→red as cover shrinks.
- **Approval SLA burndown** — pending approvals against their SLA clock, so managers see what will breach.
