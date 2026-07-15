# Import Templates — Phased Excel/CSV Upload

Upload **masters first**, then the 7 job-card phases **in order**. Each file loads into its `stg_*`
staging table (raw text), is validated row-by-row, and only `VALID` rows load into the live tables;
rejects go to `import_error_log`. See [../docs/jobcard-centric-import-and-data-model.md](../docs/jobcard-centric-import-and-data-model.md) §5–§8
and the schema in [../sql](../sql).

## Upload order
```
Masters (vehicle, item, site, employee, supplier, job_type, status)
  → Phase 1  job_card_header
  → Phase 2  job_card_mrn_items
  → Phase 3  job_card_general_items
  → Phase 4  job_card_daily_work
  → Phase 5  job_card_labour
  → Phase 6  job_card_outside_repair
  → Phase 7  prices / valuation
```

## Golden rules
- **Parent first.** A child row whose `jc_no` has no `job_card_header` is sent to the review queue
  (`import_error_log`, severity `REVIEW`) or, if the batch enables it, attaches to a controlled **stub**
  header (`is_stub=true`) that cannot be approved/closed until completed.
- **No free-text material.** `item_code` must resolve in `item_master`; unknown/blank codes are rejected
  (`V-ITEM-UNK`).
- **Rejects don't block the batch.** Valid rows still load; fix rejects from the Import Error Log screen
  and re-upload.

## Per-phase specification

| Phase | File | Required columns | Optional columns | Business (dedup) key |
|---|---|---|---|---|
| 1 | `phase1_job_card_header.csv` | jc_no, vehicle_code, site_code, start_date, repair_description | end_date, major_minor, job_type_code, estimated_cost, remarks, source_ref | `jc_no` |
| 2 | `phase2_job_card_mrn_items.csv` | jc_no, item_code, qty_requested, uom | qty_issued, source, request_type, line_no | (`jc_no`,`item_code`,`line_no`) |
| 3 | `phase3_job_card_general_items.csv` | jc_no, item_code, qty, uom | line_no | (`jc_no`,`item_code`,`line_no`) |
| 4 | `phase4_job_card_daily_work.csv` | jc_no, work_date, work_done | technician_code, hours, pct_complete | (`jc_no`,`work_date`,seq) |
| 5 | `phase5_job_card_labour.csv` | jc_no, employee_code, work_date, hours | hourly_rate, task_ref, remarks | (`jc_no`,`employee_code`,`work_date`,seq) |
| 6 | `phase6_job_card_outside_repair.csv` | jc_no, supplier_code, description | sent_date, expected_date, received_date, quoted_cost, actual_cost | (`jc_no`,`supplier_code`,seq) |
| 7 | `phase7_price_updates.csv` | item_code, unit_price, effective_from | supplier_code, price_type | (`item_code`,`price_type`,`effective_from`) |

## Validation applied at load (row-level)

| Rule code | Check | On fail |
|---|---|---|
| V-JCNO-MISS | `jc_no` present | REJECT |
| V-VEH | `vehicle_code` in vehicle_master | REJECT |
| V-SITE | `site_code` in site_master | REJECT |
| V-ITEM-UNK | `item_code` in item_master | REJECT |
| V-QTY-MISS | qty present & > 0 | REJECT |
| V-DATE-BAD / V-DATE-ORDER | dates valid; end ≥ start | REJECT |
| V-JC-DUP | duplicate `jc_no` in header load | REJECT/UPDATE |
| V-LINE-DUP | duplicate line key under same job card | REJECT |
| V-RATE-MISS | labour rate present or resolvable | WARN (loads, cost-pending) |
| V-SUP-UNK / V-EMP-UNK | supplier/employee code resolves | REJECT |
| V-STATUS-BAD | status_code valid | REJECT |
| V-CHILD-ORPHAN | parent `job_card_header` exists | REVIEW (queue/stub) |
| V-PRICE-NEG | unit_price ≥ 0 | REJECT |

## Notes
- **Dates:** use ISO `YYYY-MM-DD`.
- **Numbers:** plain decimals, no thousands separators or currency symbols.
- Leave an optional column **blank** (not `NULL`/`NA`) to omit it.
- Keep the header row exactly as shipped — the loader maps columns by header name.
