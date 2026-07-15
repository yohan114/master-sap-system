# 08 — Costing Logic

All job cost is **derived from real postings** — never typed by hand. Every formula below is computed
into `c_job_cost_detail` (line level) and rolled into `c_job_cost_summary` (job level).

## 8.1 Cost elements & formulas

Notation: `Σ` = sum over the job's lines.

### Labour cost
```
line_cost(labour)  = hours × effective_hourly_rate(employee, work_date)
labour_cost(job)   = Σ line_cost(labour)     over t_job_labour where job_card_id = J
```
`effective_hourly_rate` resolves from `m_technician_rate` where
`work_date BETWEEN effective_from AND coalesce(effective_to,'9999-12-31')`, else
`m_employee.default_hourly_rate`.

### Material cost
```
line_cost(material) = qty_issued × effective_unit_cost(item, issue_date)
material_cost(job)  = Σ line_cost(material)   over t_issue(JOB) lines where job_card_id = J
```
`effective_unit_cost` = WAC/FIFO ledger cost at issue (stock draw) or effective `m_price` (direct-to-job).

### General item cost
```
general_cost(job)   = Σ (qty × effective_unit_cost)  over t_issue(GENERAL) lines linked to J
```
General items (consumables, shop supplies) are costed identically to materials but tracked as element
`GENERAL` for reporting separation.

### Outside / subcontract repair cost
```
outside_cost(job)   = Σ actual_cost   over t_outside_repair where job_card_id = J and status = COSTED
```
`actual_cost` comes from the priced GRN/invoice of the subcontract work (not the quote).

### Total job cost
```
total_cost(job) = labour_cost + material_cost + general_cost + outside_cost
```

### Estimated vs actual & variance
```
variance_amount = total_cost − estimated_cost
variance_pct    = variance_amount / NULLIF(estimated_cost, 0) × 100
```
`estimated_cost` is captured on `t_job_card` at approval; a positive variance = over budget.

## 8.2 Price-effective-date rules

1. **Issue from stock** → use the **ledger valuation** (WAC average or consumed FIFO layers) at
   `issue_date`. This is the true cost of what left the shelf.
2. **Direct-to-job purchase** (no stock basis) → use the **priced GRN cost**; if not yet priced, use the
   **effective `m_price`** at `issue_date`, flagged `is_provisional`.
3. **Labour** → rate effective on `work_date`.
4. **Outside repair** → the priced invoice (`actual_cost`), effective at `received_date`.

**Tie-breaks:** most specific wins — (supplier-specific price) > (item price of type `PURCHASE`) >
(WAC). Among equal specificity, the **latest `effective_from` not after the transaction date** wins.
All resolutions record `price_source` and `effective_price_date` on the cost line for audit.

## 8.3 Missing price & pending valuation rules

| Situation | Behaviour |
|---|---|
| GRN received without price | Stock still posts (provisional cost); a `c_pending_price` row is queued; item usable |
| Job consumes an unpriced item | `c_job_cost_detail.is_provisional = true`; job may progress but **cannot close** |
| Outside repair not yet invoiced | OR stays `RECEIVED/INVOICED`, not `COSTED`; blocks closure |
| Price entered later (true-up) | Ledger `unit_cost` corrected, `c_job_cost_detail` re-costed, `c_job_cost_summary` recomputed, `c_pending_price.resolved_flag=true` |

**Closure gate rule (core rule 3):** `c_job_cost_summary.has_provisional` must be `false` and no
`c_pending_price` may reference the job before status can reach `COSTED → CLOSED`.

## 8.4 Rounding & precision

- Store all money/qty at `numeric(18,4)`; **round only for display** (2 dp money, item-specific qty dp).
- Compute line costs at full precision; round the **line**, then sum (avoids penny drift on rollups).
- Currency single-tenant assumed; `m_price.currency` reserved for future multi-currency.

## 8.5 Worked example — Job `JC-WS-26-00514` (vehicle CAB-1123)

**Estimated cost at approval:** `85,000.00`

### Labour (`t_job_labour`)
| Technician | Date | Hours | Rate (effective) | Line cost |
|---|---|---|---|---|
| T. Perera | 2026-07-10 | 4.0 | 900.00 | 3,600.00 |
| T. Perera | 2026-07-11 | 2.5 | 900.00 | 2,250.00 |
| A. Silva | 2026-07-11 | 3.0 | 750.00 | 2,250.00 |
| **labour_cost** | | **9.5** | | **8,100.00** |

### Material (`t_issue JOB`, WAC at issue date)
| Item | Qty | Unit cost | Line cost | Price source |
|---|---|---|---|---|
| Alternator 24V | 1 | 42,500.0000 | 42,500.00 | WAC |
| Bolt M12 | 4 | 85.0000 | 340.00 | WAC |
| Fan belt | 1 | 3,150.0000 | 3,150.00 | EFFECTIVE_PRICE |
| **material_cost** | | | **45,990.00** | |

### General items (`t_issue GENERAL`)
| Item | Qty | Unit cost | Line cost |
|---|---|---|---|
| Cleaning rags | 10 | 25.0000 | 250.00 |
| Contact spray | 1 | 480.0000 | 480.00 |
| **general_cost** | | | **730.00** |

### Outside repair (`t_outside_repair`, priced invoice)
| Work | Supplier | Actual cost |
|---|---|---|
| Injector pump overhaul | Precision Diesel | 18,600.00 |
| **outside_cost** | | **18,600.00** |

### Roll-up (`c_job_cost_summary`)
| Element | Amount |
|---|---|
| Labour | 8,100.00 |
| Material | 45,990.00 |
| General | 730.00 |
| Outside | 18,600.00 |
| **Total actual** | **73,420.00** |
| Estimated | 85,000.00 |
| **Variance** | **−11,580.00** |
| **Variance %** | **−13.62%** |

Result: job came in **13.62% under budget**. Every figure traces to a posting — 8,100 labour to three
`t_job_labour` rows, 45,990 material to `ISSUE` ledger rows on CAB-1123's parts, 18,600 to the priced OR
invoice. Nothing was estimated at close.

## 8.6 Derived costing views (for dashboards & reports)

```sql
-- Job cost by vehicle (period)
SELECT a.asset_code, count(*) jobs, sum(s.total_cost) total_cost,
       sum(s.labour_cost) labour, sum(s.material_cost) material,
       sum(s.outside_cost) outside
FROM   c_job_cost_summary s
JOIN   t_job_card jc ON jc.job_card_id = s.job_card_id
JOIN   m_asset a     ON a.asset_id = jc.asset_id
WHERE  jc.jc_date BETWEEN :from AND :to
GROUP  BY a.asset_code
ORDER  BY total_cost DESC;
```

This single view answers "what did we spend maintaining CAB-1123 this quarter?" — the question that was
impossible across the old separate books.
