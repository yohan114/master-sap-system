# 10 — User Roles & Permissions

RBAC via `m_role` / `m_permission` / `m_role_permission`; approval authority via `m_approval_role`.
Roles are from [00 §0.12](00-foundation-and-standards.md).

## 10.1 Role definitions

| Role | Primary responsibility | Key rights |
|---|---|---|
| `store_keeper` | Bin accuracy, MRN, issue, transfer | Create MRN/issue/transfer; view stock |
| `receiving_clerk` | Record GRNs against PO/MRN | Create GRN; **cannot price** |
| `pricing_officer` | Enter/maintain prices; clear pending price | Update `m_price`/GRN price; resolve `c_pending_price` |
| `inventory_controller` | Valuation, adjustments, cycle counts, reorder policy | Approve MRN/adjustment; edit reorder levels |
| `lubricant_officer` | Lube issues, consumption, monthly balance | Create lube issue; close lube month |
| `battery_custodian` | Battery serials, punch, transfer, warranty | Create battery txns; manage serials |
| `transport_officer` | Raise job cards | Create job card; view fleet |
| `transport_manager` | Level-1 job approval | Approve `TM_APPROVED` |
| `operational_manager` | Level-2 job & HO/OR approval | Approve `OM_APPROVED`, HPR, outside repair |
| `workshop_supervisor` | Route/schedule, progress, outside repair | Route job; log progress; manage OR & labour |
| `technician` | Execute work, log hours & progress | Create labour & progress; request parts |
| `finance_reviewer` | Cost & variance review, sign-off | Review costing; approve adjustments; close jobs |
| `management_viewer` | Executive read-only | View dashboards & reports only |
| `system_administrator` | Config, users, workflows, masters, migration | Full admin; migration; workflow config |

## 10.2 Permission matrix

Legend: **C**=create · **R**=read · **U**=update · **A**=approve · **X**=reverse/cancel ·
**Z**=close · **P**=report/export · **—**=no access.

| Action / Object | store_keeper | receiving_clerk | pricing_officer | inventory_controller | lubricant_officer | battery_custodian | transport_officer | transport_manager | operational_manager | workshop_supervisor | technician | finance_reviewer | mgmt_viewer | sys_admin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Item master | R | R | R | C R U | R | R | R | R | R | R | R | R | R | C R U |
| Supplier master | R | R | C R U | R | R | R | R | R | R | R | — | R | R | C R U |
| Asset/Vehicle master | R | R | R | R | R | R | R U | R | R | R U | R | R | R | C R U |
| Price / effective price | R | R | **C R U** | R | R | R | — | R | R | — | — | R P | R | C R U |
| MRN | **C R U** | R | R | **A** | R | — | R | R | R | R | — | R P | R | R |
| Purchase (LPO/HPR) | C R | R | R | A | — | — | — | R | **A** (HPR) | R | — | R P | R | R |
| GRN / Receiving | R | **C R U** | R (price) | R | R | R | — | R | R | R | — | R P | R | R |
| General/Job issue | **C R** | R | R | R U | R | — | — | R | R | R | R (request) | R P | R | R |
| Lubricant issue | R | R | R | R | **C R U** | — | — | R | R | R | R | R P | R | R |
| Material transfer | **C R** | R | R | A | R | — | — | R | R | R | — | R | R | R |
| Stock adjustment | C R | R | R | **C R** | R | R | — | R | R | R | — | **A** | R | R |
| Reverse stock movement | — | — | — | **X** | — | — | — | — | — | — | — | **X** | — | X |
| Battery txn | R | R | R | R | R | **C R U** | — | R | R | C R | — | R | R | R |
| Battery warranty/scrap | — | — | — | R | — | **C** | — | — | R | R | — | **A** | R | R |
| Job card | R | R | R | R | R | R | **C R U** | **A** (L1) | **A** (L2) | R U | R | R P | R | R |
| Job labour | — | — | — | — | — | — | — | R | R | C R U | **C R** | R | R | R |
| Job progress | — | — | — | — | — | — | R | R | R | C R U | **C R** | R | R | R |
| Parts request | R | — | — | R | — | — | R | R | R | C R | **C R** | R | R | R |
| Outside repair | — | R | R (price) | — | — | — | — | R | **A** | **C R U** | — | R P | R | R |
| Job costing | R | — | R U | R | — | — | — | R | R | R | — | **R U A** | R | R |
| Close job card | — | — | — | — | — | — | — | — | R | Z | — | **Z** | — | R |
| Dashboards / reports | R P | R P | R P | R P | R P | R P | R P | R P | R P | R P | R | **R P** | **R P** | R P |
| Users / roles / workflow | — | — | — | — | — | — | — | — | — | — | — | — | — | **C R U** |
| Data migration | — | — | — | R | — | — | — | — | — | — | — | R | — | **C R U** |

## 10.3 Segregation of duties (SoD)

Enforced controls that split incompatible duties:

| Control | Rule |
|---|---|
| Receive ≠ Price | `receiving_clerk` records qty; **cannot** enter price — that is `pricing_officer`. Prevents receipt-value manipulation. |
| Create ≠ Approve | The creator of a job card / MRN / PO / adjustment cannot be its approver. |
| Two-level job approval | Transport manager (L1) and operational manager (L2) must be **different** users. |
| Issue ≠ Adjust | The `store_keeper` who issues cannot approve the adjustment that would hide a shortage. |
| Cost review independent | Only `finance_reviewer` (or admin) sets a job `COSTED`; supervisors cannot self-clear costing. |
| Reverse restricted | Reversing posted movements is limited to `inventory_controller`/`finance_reviewer`, always logged. |

## 10.4 Delegation & acting authority

- **Acting manager:** approval authority can be delegated for a date range (`m_approval_delegation`),
  so leave/absence doesn't stall job cards; the delegate's actions are recorded as "acting for X".
- **Escalation:** if an approval breaches its `sla_hours`, it auto-escalates to the next approval level
  and raises an alert.

## 10.5 Override & reversal authorization

- **Stock override** (`stock.override`): granted narrowly (inventory_controller, and optionally a
  duty store_keeper). Every override stamps `override_by`, sets `OVERRIDE_ISSUED`, alerts finance.
- **Reversal** (`ledger.reverse`): posts a reversing entry only; the original is never deleted; both
  rows and the reason are written to `h_audit_log`.
- **Reopen closed job**: admin/finance only; recorded as an audited event with justification.
