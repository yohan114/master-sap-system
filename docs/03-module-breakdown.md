# 03 — Module Breakdown

Each module below lists its **submodules, purpose, masters used, transaction types, approvals,
reports, alerts and dashboards**. Table and status names are from [00 — Foundation](00-foundation-and-standards.md).

---

## A. Stores / Material Management

**Purpose:** control the full life of every stocked item — requisition, purchase, receipt, pricing,
issue, transfer, adjustment — with accurate stock, valuation and movement history by item, location,
category and date.

### Submodules & transaction types

| Submodule | Purpose | Transactions | Masters used |
|---|---|---|---|
| **Requisition (MRN)** | Capture material demand from sites/departments | `t_mrn`, `t_mrn_line` | `m_item`, `m_location`, `m_department` |
| **Local Purchase** | Buy from local suppliers | `t_purchase_order (LOCAL)`, `t_po_line` | `m_supplier`, `m_item`, `m_price` |
| **Head-Office Purchase** | Procure via head office | `t_purchase_order (HEAD_OFFICE)`, `t_po_line` | `m_supplier`, `m_item` |
| **Receiving / GRN** | Record physical receipt + valuation | `t_grn`, `t_grn_line` | `m_supplier`, `m_item`, `m_location` |
| **Pricing & Valuation** | Enter price + `price_received_date`; clear pending price | `m_price`, `h_price`, `c_pending_price` | `m_item`, `m_supplier` |
| **General Items & Issues** | Consumables and their issue | `t_issue (GENERAL)`, `t_issue_line` | `m_item`, `m_department`, `m_asset` |
| **Material Transfers** | Move stock between locations | `t_transfer`, `t_transfer_line` | `m_location` |
| **Stock Balance** | On-hand by item/location/category/date | (query on `l_stock_ledger`, `l_stock_balance_month`) | `m_item`, `m_location` |
| **Movement History** | Full audit trail per item | `v_item_movement` | `m_item` |
| **Adjustments** | Cycle-count / correction postings | `t_stock_adjustment` | `m_item`, `m_location` |

### Masters owned/used
`m_item`, `m_item_category`, `m_uom` + `m_uom_conversion`, `m_supplier`, `m_location`/`m_site`,
`m_department`, `m_price`, `m_gl_account`.

### Approvals
- MRN: `store_keeper` creates → department head/`inventory_controller` approves.
- Purchase (LPO/HPR): raised → approved per value threshold via `a_workflow`.
- Adjustment: `store_keeper`/`inventory_controller` creates → `finance_reviewer` approves before `POSTED`.

### Reports
Stock ledger, item movement, MRN register, GRN register, stock balance (by item/location/category/date),
pending-pricing, reorder/critical-stock, transfer register, valuation summary, supplier spend.

### Alerts
Low/critical stock, negative-stock override used, GRN pending pricing > N days, MRN awaiting issue,
price variance vs last purchase, slow-moving/dead stock.

### Dashboard (Stores)
Total stock value · pending-pricing count/value · low-stock items · fast/slow movers · today's
receipts & issues · open MRNs · transfer volume by location.

---

## B. Oil / Lubricant Stock Book

**Purpose:** a dedicated view of lubricants with the same ledger discipline as stores, plus
**consumption traceability** to the exact vehicle/machine/site/project and **forecasting**.

> Lubricants are `m_item` rows (category `LUBRICANT`) extended by `m_lubricant_detail`. They post to
> the **same** `l_stock_ledger` — the "lubricant book" is a filtered, enriched view, not a separate stock.

### Submodules & transaction types

| Submodule | Purpose | Transactions | Masters used |
|---|---|---|---|
| **Lubricant Master** | Grade, viscosity, pack size, base type | `m_item` + `m_lubricant_detail` | `m_item_category`, `m_brand` |
| **Lube Ledger** | All receipts/issues/adjustments/transfers | `l_stock_ledger` (filtered) | `m_item`, `m_location` |
| **Site Issues** | Issue lubricant at a site | `t_issue (LUBRICANT)` | `m_site`, `m_location` |
| **Asset-wise Consumption** | Issue tagged to vehicle/machine | `t_issue.asset_id` | `m_asset` |
| **Monthly Balance** | Frozen opening/closing per month | `l_stock_balance_month` | `m_item`, `m_location` |
| **Forecast & Reorder** | Consumption planning, reorder alerts | (derived) | `m_item.reorder_level` |
| **Price History** | Track lube cost over time | `h_price`, `m_price` | `m_item` |
| **Consumption Mapping** | Map lube → vehicle/machine/project/site/dept | `t_issue` mapping cols | `m_asset`, `m_project`, `m_department` |

### Approvals
Lube issues follow the standard issue flow; bulk/abnormal issues (> threshold vs asset's average) route
to `workshop_supervisor`/`lubricant_officer` confirmation before `POSTED`.

### Reports
Lubricant issue report, asset-wise consumption, monthly stock balance, consumption vs forecast,
reorder/critical-stock (lube), lube price history, days-of-cover.

### Alerts
Critical lube stock, reorder point breached, abnormal consumption for an asset (spike vs rolling
average), days-of-cover below threshold.

### Dashboard (Lubricant)
Critical-stock items · average usage (L/day, L/1000km, L/machine-hr) · **days left / days-of-cover** ·
monthly consumption trend · transaction counts · top consuming assets · consumption by site/project.

---

## C. Battery Stock Book

**Purpose:** asset-level, **serial-number-true** tracking of every battery from receipt to scrap —
who it's on, where it's been, and its warranty/replacement/repair history.

> Each physical battery is one `m_battery` row keyed by `serial_no`. Battery *stock* (unassigned units)
> still moves on `l_stock_ledger`; battery *lifecycle* is tracked serial-by-serial in `h_battery_*`.

### Submodules & transaction types

| Submodule | Purpose | Transactions | Masters used |
|---|---|---|---|
| **Battery Master** | Brand, type, serial, size, warranty, supplier, price, GRN date | `m_battery` | `m_item`, `m_brand`, `m_supplier` |
| **Serial Tracking** | Unique serial + status per unit | `m_battery.serial_no` | — |
| **Photo Record** | Serial-plate image proof | `m_battery.image_url` | — |
| **Assignment** | Original vs current vehicle | `original_asset_id`, `current_asset_id` | `m_asset` |
| **Punch / Issue** | Assign battery to a vehicle | `t_battery_txn (PUNCH/ISSUE)` | `m_asset` |
| **Transfer History** | Vehicle-to-vehicle moves | `t_battery_txn (TRANSFER)` + `h_battery_movement` | `m_asset` |
| **Return / Replace / Scrap** | End or swap a battery | `t_battery_txn (RETURN/REPLACEMENT/SCRAP)` | `m_asset` |
| **Warranty / Repair** | Claims & repairs | `t_battery_txn (WARRANTY/REPAIR)` + `h_battery_lifecycle` | `m_supplier` |

### Approvals
Warranty claims & scrap require `battery_custodian` creation + `workshop_supervisor`/`finance_reviewer`
confirmation. Punch/transfer are operational (logged, not multi-approved).

### Reports
Battery lifecycle report, battery-by-vehicle report, warranty-due/expired list, transfer history,
scrap register, battery valuation & aging.

### Alerts
Warranty expiring within N days, warranty expired but still in service, battery age > expected life,
frequent-swap vehicles (reliability flag), unreturned old battery after replacement.

### Dashboard (Battery)
Fleet battery map (in-service / spare / scrapped / warranty) · warranty due vs expired · average
battery life achieved · swaps this month · top battery-consuming vehicles · value of battery stock.

---

## D. Jobcard / Workshop Management

**Purpose:** run repairs end-to-end — from transport-section request, through two-level management
approval, workshop execution and progress logging, to a **self-assembling final job cost** that cannot
be closed until it is complete, priced and approved.

### Submodules & transaction types

| Submodule | Purpose | Transactions | Masters used |
|---|---|---|---|
| **Job Card Creation** | Raise a job from the transport section | `t_job_card` | `m_asset`, `m_employee`, `m_site` |
| **Approvals** | Transport-mgr then operational-mgr sign-off | `a_doc_approval`, `a_approval_action` | `m_approval_role` |
| **Workshop Routing** | Assign to workshop/supervisor/bay | `t_job_card` (supervisor, bay) | `m_workshop_asset` |
| **Execution & Progress** | Start dates + daily work-done log | `t_job_task`, `t_job_progress` | `m_employee` |
| **Parts Requests** | Internal & external parts | `t_job_parts_request` | `m_item` |
| **Parts Received** | Receive parts against the job | `t_grn (job_card_id)` | `m_supplier` |
| **Labour** | Technician hours × rate | `t_job_labour` | `m_employee`, `m_technician_rate` |
| **Outside / Subcontract Repair** | Send-out repairs | `t_outside_repair` | `m_supplier` |
| **Costing** | Labour + material + general + outside | `c_job_cost_detail`, `c_job_cost_summary` | — |
| **Closure** | Gated final close | `t_job_card.status → CLOSED` | — |

### Approval chain
`transport_officer` creates → `transport_manager` (`TM_APPROVED`) → `operational_manager`
(`OM_APPROVED`) → `workshop_supervisor` routes (`ROUTED_TO_WORKSHOP`). Configurable in `a_workflow`.

### Closure gate (core rule 3)
A job moves to `CLOSED` only when **all** are true — enforced by `fn_can_close_job`:
1. All `t_job_parts_request` lines are `ISSUED`/`RECEIVED` or explicitly written off.
2. No related item sits in `c_pending_price` (all prices entered).
3. At least the required `t_job_labour` is captured.
4. Every `t_outside_repair` is `COSTED` (or none apply).
5. All approvals complete; GRNs posted where parts were purchased for the job.

### Reports
Open job card report, delayed/overdue jobs, job costing sheet, labour summary (by technician/date),
outside-repair register, parts-request fulfilment, estimated-vs-actual variance, job cost by vehicle.

### Alerts
Job awaiting approval > SLA, job `IN_PROGRESS` past planned end (`DELAYED`), parts request unfulfilled,
job blocked by pending price, outside repair overdue return, job `WORK_COMPLETED` but not costed.

### Dashboards (Workshop)
Open / pending / delayed / completed counts · jobs by status (kanban) · labour utilization · average
turnaround time · cost by vehicle/type · top failure categories · outside-repair spend · closure gate
blockers list.

---

## Module ↔ shared-spine summary

| Module | Reads masters | Writes ledger | Writes costing | Uses approval | Writes history |
|---|---|---|---|---|---|
| Stores/MM | ✅ all | ✅ | via jobs | ✅ (MRN/PO/Adj) | ✅ `h_price`,`h_audit_log` |
| Lubricant | ✅ item/asset | ✅ | via jobs | ✅ (abnormal) | ✅ `h_price` |
| Battery | ✅ item/asset | ✅ (stock) | via jobs | ✅ (warranty/scrap) | ✅ `h_battery_*` |
| Jobcard | ✅ asset/emp | ✅ (issues) | ✅ owns | ✅ (2-level) | ✅ `h_audit_log` |
