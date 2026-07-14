# 17 — Appendices (A–E)

## Appendix A — Recommended menu structure

```
◈ Dashboard
   · Executive
   · Stores · Lubricant · Battery · Workshop
   · Exceptions

▸ Stores / Materials
   · Items
   · MRN                     (create · list · approve)
   · Purchase
        · Local Purchase (LPO)
        · Head-Office Purchase (HPR)
   · Receiving / GRN
   · Pricing & Pending Prices
   · Issues (General)
   · Transfers
   · Stock Adjustments
   · Stock Balance           (by item · location · category · date)
   · Movement History

▸ Lubricants
   · Products
   · Issues                  (by vehicle/machine/site)
   · Consumption & Mapping
   · Monthly Balance
   · Reorder / Forecast
   · Price History

▸ Batteries
   · Register (serials)
   · Punch / Issue
   · Transfers
   · Return / Replace / Scrap
   · Warranty & Repair
   · Lifecycle

▸ Workshop / Job Cards
   · Job Cards               (create · list · progress board)
   · Approvals               (my queue)
   · Parts Requests
   · Labour
   · Outside Repairs
   · Job Costing
   · Closure Gate

▸ Reports
   · Stores · Lubricant · Battery · Workshop · Finance · Audit

▸ Masters
   · Items · Item Categories · UoM
   · Suppliers · Brands
   · Assets (Vehicles · Machines · Workshop Equipment)
   · Employees & Rates
   · Sites · Locations · Departments · Projects
   · Prices · GL Accounts
   · Approval Roles

▸ Admin
   · Users · Roles · Permissions
   · Approval Workflows
   · Numbering & Reference Data
   · Notifications & Alerts
   · Data Migration
   · Audit Log
```

## Appendix B — Recommended master data hierarchy

```
Organisation
└─ Site (m_site)                         e.g. Head Office, Central Store, Estate-A
   ├─ Location (m_location · STORE/WORKSHOP)
   │    └─ Location (BIN)                lowest stock-holding level
   ├─ Department / Cost Center (m_department)
   └─ Project (m_project)

Item (m_item)
└─ Item Category (m_item_category, self-nesting)
     ├─ SPARE
     ├─ LUBRICANT   → m_lubricant_detail (grade/viscosity/pack)
     ├─ BATTERY_STOCK → m_battery (serial instances)
     ├─ GENERAL
     └─ TYRE ...
   · Unit of Measure (m_uom) + conversions (m_uom_conversion)
   · Price (m_price, effective-dated) → h_price

Asset (m_asset — maintainable object)
├─ VEHICLE (m_vehicle)                   ← job cost, lube, battery attach here
├─ MACHINE (m_machine)
└─ WORKSHOP_EQUIP (m_workshop_asset)

Supplier (m_supplier)
└─ type: LOCAL · HEAD_OFFICE · SUBCONTRACTOR   · Brand (m_brand)

People
└─ Employee (m_employee)
     └─ Technician → Rate (m_technician_rate, effective-dated)
   · User (m_user) → Role (m_role) → Permission (m_permission)
   · Approval Role (m_approval_role) → Workflow steps
```
**Rationale:** one asset key (`asset_id`) unifies vehicle/machine/equipment so cost, lube and battery all
attach to the same object; lubricants and batteries are item categories (not separate item lists) to
avoid duplicate part numbers; location nests Site→Store→Bin so balances roll up cleanly.

## Appendix C — Recommended transaction numbering formats

`{SITE}` site code · `{YY}` 2-digit year · `{NNNNN}` running number, **reset yearly per doc-type per
site**, generated gap-free by `fn_next_docno()`.

| Doc type | Mask | Example | Reset |
|---|---|---|---|
| MRN | `MRN-{SITE}-{YY}-{NNNNN}` | `MRN-HO-26-00042` | year · site |
| Local Purchase Order | `LPO-{SITE}-{YY}-{NNNNN}` | `LPO-CS-26-00301` | year · site |
| Head-Office Purchase Req | `HPR-{YY}-{NNNNN}` | `HPR-26-00088` | year |
| Goods Receipt Note | `GRN-{SITE}-{YY}-{NNNNN}` | `GRN-CS-26-01187` | year · site |
| Material Transfer | `TRF-{FROM}-{YY}-{NNNNN}` | `TRF-CS-26-00210` | year · from-site |
| General Issue | `ISS-{SITE}-{YY}-{NNNNN}` | `ISS-WS-26-00733` | year · site |
| Lubricant Issue | `LUB-{SITE}-{YY}-{NNNNN}` | `LUB-WS-26-00925` | year · site |
| Battery Transaction | `BAT-{YY}-{NNNNN}` | `BAT-26-00377` | year |
| Job Card | `JC-{SITE}-{YY}-{NNNNN}` | `JC-WS-26-00514` | year · site |
| Outside Repair | `OR-{YY}-{NNNNN}` | `OR-26-00061` | year |
| Parts Request | `PR-{JCSEQ}-{NN}` | `PR-JCWS2600514-02` | per job card |
| Stock Adjustment | `ADJ-{SITE}-{YY}-{NNNNN}` | `ADJ-CS-26-00045` | year · site |

## Appendix D — Recommended alerts & exception list

| Alert / exception | Trigger | Severity | Channel | Recipient |
|---|---|---|---|---|
| Critical stock | `on_hand ≤ min_qty` | High | in-app + email | store_keeper, inventory_controller |
| Reorder point | `on_hand ≤ reorder_level` | Medium | in-app | store_keeper |
| Negative-stock override used | `OVERRIDE_ISSUED` posted | High | in-app + email | inventory_controller, finance_reviewer |
| GRN pending pricing | unpriced > 3 days | Medium | in-app | pricing_officer |
| Item consumed but unpriced | job uses provisional-cost item | Medium | in-app | pricing_officer, supervisor |
| Abnormal lube consumption | asset issue > μ+2σ | Medium | in-app | lubricant_officer |
| Lube days-of-cover low | `days_left < lead_time` | High | in-app + email | inventory_controller |
| Battery warranty due | `warranty_expiry ≤ 30d` | Medium | in-app + WhatsApp | battery_custodian |
| Battery warranty expired in service | expired & IN_SERVICE | Medium | in-app | battery_custodian |
| Frequent-swap vehicle | ≥ k battery swaps / 12m | Low | in-app | workshop_supervisor |
| Job awaiting approval | pending > SLA | Medium | in-app + WhatsApp | transport/operational_manager |
| Job delayed | open past `planned_end` | High | in-app | workshop_supervisor |
| Job closure blocked | `WORK_COMPLETED` + pending price/labour | Medium | in-app | pricing_officer, supervisor |
| Outside repair overdue | not returned by `expected_date` | Medium | in-app | workshop_supervisor |
| Price variance | new price > ±X% vs last | Low | in-app | pricing_officer |
| Slow-moving/dead stock | no issue in 180d, on_hand>0 | Low | report | inventory_controller |
| Broken battery lineage | IN_SERVICE with no current asset | High | in-app | battery_custodian |
| MRN approved not issued | approved > N days | Low | in-app | store_keeper |

## Appendix E — MVP vs Advanced version

| Area | MVP (ship first) | Advanced (later) |
|---|---|---|
| **Masters** | Items, suppliers, assets, locations, UoM, employees, prices | GL mapping, projects, multi-currency, delegation |
| **Stores** | MRN, GRN+pricing, issues, transfers, adjustments, stock balance, ledger | Auto-reorder POs, blanket orders, consignment stock |
| **Valuation** | Weighted Average Cost | FIFO layers, standard cost + revaluation |
| **Lubricant** | Issues w/ asset mapping, monthly balance, reorder alert | Forecast models, usage benchmarks (L/1000km) |
| **Battery** | Register, serial, punch/transfer, warranty, lifecycle | Image OCR of serial, predictive replacement |
| **Job Card** | Create, 2-level approval, parts/labour/outside, costing, closure gate | Scheduling/bay planning, estimates library, SLA automation |
| **Pricing** | Effective-date + pending-price queue | Price approval workflow, contract prices |
| **Approvals** | Fixed 2-step job + value-band PO | Fully configurable multi-branch workflows |
| **Dashboards** | Core KPIs per module + exceptions | Cost-of-ownership, reliability heatmap, forecasting |
| **Alerts** | In-app + email, critical set | WhatsApp/SMS, full rule engine |
| **Reports** | Ledger, GRN, MRN, monthly balance, job cost sheet, battery lifecycle, audit | Scheduled distribution, BI star schema |
| **Integration** | Excel import/export, attachments | QR scan-to-act, REST/OData API, Power BI, SAP |
| **Mobile** | Responsive web | Native-feel shop-floor & approver apps, offline scan |
| **Migration** | Masters, prices, opening stock, battery serials, open jobs | Full historic transaction load |

**Why this MVP line:** it makes **stock trustworthy and jobs truly costed** (the two problems that hurt
most) with the least surface area — masters + ledger + GRN/pricing + job costing + closure gate. Every
advanced item builds on that spine without reworking it.
