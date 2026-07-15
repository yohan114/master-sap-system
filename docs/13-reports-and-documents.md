# 13 — Reports & Documents

All reports are parameterized, exportable (PDF / Excel / CSV), schedulable, and **drill down to source
documents**. Printable documents carry the standard header/footer, document number and signature blocks.

## 13.1 Reports catalogue

| Report | Purpose | Key columns | Filters | Grouping / totals | Formats | Primary user |
|---|---|---|---|---|---|---|
| **Stock Ledger** | Every movement of an item | date, doc no, movement_type, qty_in/out, unit_cost, running balance | item, location, date range | per item; opening/closing | PDF/Excel | inventory_controller |
| **Item Movement** | Consolidated movement history | date, type, ref, qty, balance | item, category, location | per item | PDF/Excel | store_keeper |
| **MRN Register** | Requisition tracking | mrn_no, date, site/dept, status, lines | site, status, date | by status | PDF/Excel | store_keeper |
| **GRN Register** | Receipts & valuation | grn_no, date, supplier, po_no, value, priced? | supplier, date, priced flag | by supplier | PDF/Excel | receiving_clerk |
| **Lubricant Issue** | Lube consumption detail | date, product, qty, asset, site, odo/hrs | asset, product, site, date | by asset/product | PDF/Excel | lubricant_officer |
| **Monthly Stock Balance** | Frozen opening/closing | item, opening, receipts, issues, closing, value | location, period | per location; grand total | PDF/Excel | inventory_controller |
| **Battery Lifecycle** | One battery's full life | serial, event, from/to vehicle, date, odo, warranty | serial, brand | chronological | PDF | battery_custodian |
| **Battery by Vehicle** | Batteries per asset | vehicle, serial, punch date, warranty, status | vehicle, site | by vehicle | PDF/Excel | workshop_supervisor |
| **Open Job Card** | Work in progress | jc_no, vehicle, status, age, est cost, blockers | status, site, supervisor | by status | PDF/Excel | workshop_supervisor |
| **Job Costing Sheet** | Full cost of one job | element lines, qty, unit cost, totals, variance | job card | by element | PDF | finance_reviewer |
| **Labour Summary** | Technician hours & cost | technician, date, job, hours, rate, cost | technician, date, job | by technician/date | PDF/Excel | workshop_supervisor |
| **Supplier Spend** | Purchasing by supplier | supplier, GRN count, value, avg lead time | supplier, date | by supplier | PDF/Excel | finance_reviewer |
| **Variance** | Estimated vs actual | jc_no, vehicle, est, actual, var, var% | date, site, threshold | by vehicle/dept | PDF/Excel | finance_reviewer |
| **Audit Trail** | Who changed what | table, record, action, user, old→new, time | table, user, date | chronological | PDF/Excel | system_administrator |

### High-value extras
| Report | Purpose |
|---|---|
| **Pending Pricing** | Received/consumed items awaiting price (working-capital & closure blockers) |
| **Reorder / Critical Stock** | Items at/below reorder or min, with days-of-cover |
| **Transfer Register** | Inter-location movements, paired OUT/IN, net by location |
| **Warranty Due / Expired** | Batteries needing action within window |
| **Vehicle Cost of Ownership** | Maintenance + lube + battery + downtime per asset (period) |
| **Slow-Moving / Dead Stock** | Value tied up in non-moving items |

## 13.2 Printable document templates

Common frame: company header · document title & number · date · site · created/approved-by signature
blocks · footer with page & print timestamp · optional QR of the document number.

| Document | Content | Signatures |
|---|---|---|
| **MRN** | Requesting site/dept, item lines (code, desc, qty, uom), purpose | Requested by · Approved by |
| **GRN** | Supplier, PO ref, received lines (qty, unit cost, value), invoice no, price-received date | Received by · Checked by · Priced by |
| **Material Transfer Note** | From/To location, item lines, qty, value | Issued by · Received by |
| **Lubricant Issue Voucher** | Product, qty, vehicle/machine, odo/hrs, site | Issued by · Received by |
| **Battery Issue / Serial Voucher** | Serial, brand, warranty, vehicle, odo, photo | Punched by · Authorized by |
| **Job Cost Sheet** | Vehicle, complaint, labour/material/general/outside tables, totals, est vs actual, variance | Prepared by · Reviewed (finance) · Approved |
| **Job Card (work order)** | Vehicle, complaint, tasks, approvals, assigned technician/bay | Transport mgr · Operational mgr · Supervisor |

## 13.3 Delivery & scheduling

- **On-demand** from any list/detail (context-aware default filters).
- **Scheduled** (daily/weekly/monthly) e-mailed to role recipients (e.g. monthly stock balance to
  finance; weekly open-jobs to operational manager).
- **Export everywhere:** every grid exports its current filtered/sorted view to Excel/CSV; reports
  additionally render print-ready PDF.
- **Drill-through:** report rows link back to the source record (a GRN register row opens the GRN).
