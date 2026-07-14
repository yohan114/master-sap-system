# 12 — UI/UX Design Direction

A modern enterprise web app that feels like a **workshop + fleet + stores command center**: fast for
clerks, information-dense for managers, calm under pressure. Light/dark capable, responsive to phone.

> A working, self-contained HTML prototype of this direction lives in [`/prototype/index.html`](../prototype/index.html).

## 12.1 Information architecture

Persistent **left sidebar** (collapsible to icons), **top app bar** (global search, quick-actions,
notifications, theme toggle, user menu), and a **content canvas** that switches between dashboards,
list/grid pages, detail pages, and approval queues.

### Sidebar navigation tree
```
◈ Dashboard
▸ Stores / Materials
    · Items          · MRN            · Purchase (LPO/HPR)
    · Receiving/GRN  · Issues         · Transfers
    · Adjustments    · Stock Balance  · Pending Pricing
▸ Lubricants
    · Products       · Issues         · Consumption
    · Monthly Balance· Reorder/Forecast
▸ Batteries
    · Register       · Punch/Issue    · Transfers
    · Warranty       · Lifecycle
▸ Workshop / Job Cards
    · Job Cards      · Approvals      · Progress Board
    · Parts Requests · Labour         · Outside Repairs
    · Costing
▸ Reports
▸ Masters            (items · suppliers · assets · locations · employees · prices)
▸ Admin              (users · roles · workflows · numbering · migration)
```

## 12.2 App shell & global patterns

- **Top bar:** global search (jump to any item/asset/job/GRN by code), a **＋ Quick Action** menu
  (New MRN, New GRN, New Job Card, New Issue), a **bell** with unread alerts, theme toggle, avatar/menu.
- **Command palette** (`Ctrl/⌘ K`): keyboard-first navigation and actions for power clerks.
- **Breadcrumbs** on every detail page for orientation and drill-back.

## 12.3 Component inventory

| Component | Use |
|---|---|
| **KPI card** | Large number + label + delta + sparkline; click → drill-down |
| **Status chip** | Colored pill mapped to `status_code` (see 12.5) |
| **Alert banner** | Page-top strip for critical exceptions (red/amber) with action link |
| **Data grid** | Sortable, filterable, column presets, saved views, pagination, bulk actions, inline row status |
| **Detail header** | Title + key facts + status + action buttons (Approve/Issue/Close) |
| **Timeline panel** | Vertical event feed (job progress, battery lifecycle, ledger movements) |
| **Approval queue** | Card/list of items awaiting *me*, with approve/reject/return + comment |
| **Cost breakdown** | Stacked bar / table of labour·material·general·outside + variance gauge |
| **Trend chart** | Line/column for consumption, spend, stock value |
| **Drawer / modal** | Quick create & side-detail without leaving context |
| **Empty / loading / error states** | Consistent, reassuring, actionable |

## 12.4 Design tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f5f7fa` | `#0e1420` | app background |
| `--surface` | `#ffffff` | `#161d2b` | cards, grids |
| `--text` | `#1a2233` | `#e7ecf5` | primary text |
| `--muted` | `#5b6b85` | `#93a1bd` | secondary text |
| `--primary` | `#1f6feb` | `#3b82f6` | actions, links |
| `--accent` | `#0e7c5a` | `#22c55e` | positive / success |
| `--warn` | `#b26a00` | `#f59e0b` | warnings |
| `--danger` | `#c0392b` | `#ef4444` | errors / critical |
| `--border` | `#e2e8f0` | `#243040` | separators |

- **Typography:** system UI / Inter; scale 12/14/16/20/28/36; tabular numerals for figures/tables.
- **Spacing:** 4px base grid (4/8/12/16/24/32). **Radius:** 8px cards, 999px chips.
- **Elevation:** subtle (0–2 levels); rely on borders/`--surface` contrast over heavy shadows.
- **Density toggle:** comfortable vs compact grid rows (managers scan; clerks enter).

## 12.5 Status chip color mapping

| Status family | Color |
|---|---|
| Draft / Pending | neutral grey |
| Submitted / In-progress / Sourcing | blue |
| Approved / Priced / Posted / Received | green |
| Pending pricing / Delayed / On-hold / Warranty due | amber |
| Rejected / Cancelled / Override / Scrapped / Expired | red |
| Closed / Completed | slate/solid green |

Chips reuse `ref_status.ui_color` so colours are configured once and consistent across grids, detail
pages and dashboards.

## 12.6 Key screens (wireframe descriptions)

### 1 · Executive Dashboard
Top: **8 KPI cards** (stock value, pending pricing, open jobs, overdue jobs, monthly spend, purchase
spend, warranty exposure, stock accuracy). Middle-left: maintenance-spend trend (column). Middle-right:
job status donut. Bottom: **Exception panel** (overrides, unpriced-but-consumed, delayed jobs) each row
a drill link. A red **alert banner** appears when any critical exception exists.

### 2 · Item / Stock Detail
Header: item code, description, category, on-hand by location, WAC. Tabs: **Movement** (ledger grid with
running balance), **Prices** (effective-date history chart), **Reorder** (level vs on-hand gauge),
**Where used** (jobs/assets consuming it). Quick actions: Issue, Transfer, Adjust.

### 3 · Job Card Detail
Header: `JC-…`, vehicle, status chip, estimated vs actual, variance gauge. Left column: **progress
timeline** (daily work-done). Right column: **cost breakdown** (labour/material/general/outside stacked
bar) + closure-gate checklist showing what still blocks closing. Tabs: Parts Requests, Labour, Outside
Repair, Attachments. Action bar contextual to status (Approve L1/L2 · Route · Complete · Close).

### 4 · Battery Lifecycle
Header: serial, brand, warranty gauge (days left), current vehicle, image thumbnail. Center: **lifecycle
timeline** (punch → transfers → return/replace/scrap) with vehicle at each step and odometer. Side:
key facts + warranty claim button.

### 5 · Approval Queue
"Awaiting my approval" list grouped by doc type. Each row: doc no, requester, value, age vs SLA (amber
when near breach). Inline **Approve / Return / Reject** with a required comment; bulk-approve for
low-value items. Opening a row shows the full document in a drawer.

## 12.7 Responsive & mobile behavior

- **Desktop (workshop office / stores counter):** full sidebar, dense grids, multi-column detail.
- **Tablet (shop floor):** collapsed icon sidebar; large touch targets for **Issue**, **Log labour**,
  **Scan QR**; single-column detail.
- **Phone (manager on the move):** bottom tab bar (Dashboard · Approvals · Alerts · Search); approval
  queue and KPI cards optimized first; scanning battery/item QR opens its record.
- Grids collapse to **stacked cards** on narrow screens; primary action stays reachable (sticky footer).

## 12.8 UX principles for this operation

1. **One-screen posting** — issue/receive/labour done without page hops (drawer + scan).
2. **Never lose the trail** — every number is a link back to its source document.
3. **Show the blocker** — closure-gate and pending-price reasons stated inline, not hidden in errors.
4. **Colour = meaning** — status colours are consistent everywhere; red always means "act now".
5. **Fast for the frequent** — the 5 daily clerk actions are ≤ 2 clicks / a keyboard shortcut away.
