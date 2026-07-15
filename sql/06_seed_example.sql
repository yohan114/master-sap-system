-- =====================================================================
-- 06 — WORKED EXAMPLE + SELF-TEST
-- Seeds one full job card (JC-WS-26-00514) end to end, then demonstrates:
--   (a) cost roll-up from linked cost lines,
--   (b) pending-price blocks closure,
--   (c) a Phase-7 price update clears pending and allows closure.
-- Run after 01..05. Expected NOTICEs:
--   BEFORE: total=73420.0000 pending=3150.0000 can_close=f blockers={"Pending price on cost lines"}
--   AFTER : total=73420.0000 pending=0.0000     can_close=t blockers={}
-- =====================================================================
DO $$
DECLARE
  v_ea bigint; v_cat_spare bigint; v_cat_gen bigint; v_site bigint; v_jt bigint;
  v_st_cp bigint; v_sup bigint;
  v_alt bigint; v_bolt bigint; v_belt bigint; v_rag bigint; v_spray bigint;
  v_veh bigint; v_emp bigint; v_jc bigint; v_iss bigint;
  v_l_alt bigint; v_l_bolt bigint; v_l_belt bigint; v_grn bigint; v_or bigint;
  v_total numeric; v_pending numeric; v_var numeric; v_canclose boolean; v_block text[];
BEGIN
  INSERT INTO uom_master(uom_code,name,created_by) VALUES('EA','Each',1) RETURNING uom_id INTO v_ea;
  INSERT INTO item_category(category_code,name,created_by) VALUES('SPARE','Spares',1) RETURNING item_category_id INTO v_cat_spare;
  INSERT INTO item_category(category_code,name,created_by) VALUES('GENERAL','General',1) RETURNING item_category_id INTO v_cat_gen;
  INSERT INTO site_master(site_code,name,location_type,created_by) VALUES('WS','Workshop','WORKSHOP',1) RETURNING site_id INTO v_site;
  INSERT INTO job_type_master(job_type_code,name,category,created_by) VALUES('BRKDN','Breakdown','MAJOR',1) RETURNING job_type_id INTO v_jt;
  INSERT INTO status_master(doc_type,status_code,name,sort_order,requires_costing,created_by)
    VALUES('JOB_CARD','COST_PENDING','Cost Pending',8,true,1) RETURNING status_id INTO v_st_cp;
  INSERT INTO supplier_master(supplier_code,name,supplier_type,created_by)
    VALUES('PDIESEL','Precision Diesel','SUBCONTRACTOR',1) RETURNING supplier_id INTO v_sup;

  INSERT INTO item_master(item_code,description,item_category_id,stock_uom_id,item_type,created_by)
    VALUES('IT-ALT24','Alternator 24V',v_cat_spare,v_ea,'STOCK',1) RETURNING item_id INTO v_alt;
  INSERT INTO item_master(item_code,description,item_category_id,stock_uom_id,item_type,created_by)
    VALUES('IT-BOLT12','Bolt M12',v_cat_spare,v_ea,'STOCK',1) RETURNING item_id INTO v_bolt;
  INSERT INTO item_master(item_code,description,item_category_id,stock_uom_id,item_type,created_by)
    VALUES('IT-BELT','Fan belt',v_cat_spare,v_ea,'STOCK',1) RETURNING item_id INTO v_belt;
  INSERT INTO item_master(item_code,description,item_category_id,stock_uom_id,item_type,created_by)
    VALUES('IT-RAG','Cleaning rags',v_cat_gen,v_ea,'GENERAL',1) RETURNING item_id INTO v_rag;
  INSERT INTO item_master(item_code,description,item_category_id,stock_uom_id,item_type,created_by)
    VALUES('IT-SPRAY','Contact spray',v_cat_gen,v_ea,'GENERAL',1) RETURNING item_id INTO v_spray;

  INSERT INTO vehicle_master(vehicle_code,reg_no,asset_type,site_id,created_by)
    VALUES('CAB-1123','CAB-1123','VEHICLE',v_site,1) RETURNING vehicle_id INTO v_veh;
  INSERT INTO employee_master(employee_code,full_name,is_technician,default_hourly_rate,site_id,created_by)
    VALUES('T001','T. Perera',true,900,v_site,1) RETURNING employee_id INTO v_emp;

  INSERT INTO job_card_header(jc_no,vehicle_id,site_id,job_type_id,repair_description,major_minor,
      start_date,end_date,estimated_cost,tm_approved_by,tm_approved_at,om_approved_by,om_approved_at,status_id,created_by)
    VALUES('JC-WS-26-00514',v_veh,v_site,v_jt,'Alternator + injector pump overhaul','MAJOR',
      DATE '2026-07-10',DATE '2026-07-12',85000,v_emp,now(),v_emp,now(),v_st_cp,1)
    RETURNING job_card_id INTO v_jc;

  INSERT INTO stock_issue_header(issue_no,issue_type,issue_date,location_id,job_card_id,issued_by,created_by)
    VALUES('ISS-WS-26-00733','JOB',DATE '2026-07-10',v_site,v_jc,v_emp,1) RETURNING issue_id INTO v_iss;
  INSERT INTO stock_issue_lines(issue_id,item_id,qty,uom_id,unit_cost,created_by)
    VALUES(v_iss,v_alt,1,v_ea,42500,1) RETURNING issue_line_id INTO v_l_alt;
  INSERT INTO stock_issue_lines(issue_id,item_id,qty,uom_id,unit_cost,created_by)
    VALUES(v_iss,v_bolt,4,v_ea,85,1) RETURNING issue_line_id INTO v_l_bolt;
  INSERT INTO stock_issue_lines(issue_id,item_id,qty,uom_id,unit_cost,is_provisional,created_by)
    VALUES(v_iss,v_belt,1,v_ea,3150,true,1) RETURNING issue_line_id INTO v_l_belt;

  INSERT INTO job_card_mrn_items(job_card_id,jc_no,item_id,qty_requested,qty_issued,uom_id,stock_issue_line_id,line_no,created_by) VALUES
    (v_jc,'JC-WS-26-00514',v_alt,1,1,v_ea,v_l_alt,1,1),
    (v_jc,'JC-WS-26-00514',v_bolt,4,4,v_ea,v_l_bolt,1,1),
    (v_jc,'JC-WS-26-00514',v_belt,1,1,v_ea,v_l_belt,1,1);

  INSERT INTO job_card_general_items(job_card_id,jc_no,item_id,qty,uom_id,line_no,created_by) VALUES
    (v_jc,'JC-WS-26-00514',v_rag,10,v_ea,1,1),
    (v_jc,'JC-WS-26-00514',v_spray,1,v_ea,1,1);

  INSERT INTO job_card_labour(job_card_id,jc_no,employee_id,work_date,hours,hourly_rate,line_cost,seq,created_by) VALUES
    (v_jc,'JC-WS-26-00514',v_emp,DATE '2026-07-10',4,900,3600,1,1),
    (v_jc,'JC-WS-26-00514',v_emp,DATE '2026-07-11',2.5,900,2250,2,1),
    (v_jc,'JC-WS-26-00514',v_emp,DATE '2026-07-11',3,750,2250,3,1);

  INSERT INTO grn_header(grn_no,grn_date,supplier_id,job_card_id,is_priced,price_received_date,created_by)
    VALUES('GRN-WS-26-01200',DATE '2026-07-12',v_sup,v_jc,true,DATE '2026-07-12',1) RETURNING grn_id INTO v_grn;
  INSERT INTO job_card_outside_repair(job_card_id,jc_no,supplier_id,description,sent_date,received_date,quoted_cost,actual_cost,grn_id,seq,created_by)
    VALUES(v_jc,'JC-WS-26-00514',v_sup,'Injector pump overhaul',DATE '2026-07-10',DATE '2026-07-12',18000,18600,v_grn,1,1) RETURNING outside_repair_id INTO v_or;

  INSERT INTO job_card_cost_line(job_card_id,cost_element,source_doc_type,source_doc_id,item_id,qty,unit_cost,line_cost,price_source,is_provisional,created_by) VALUES
    (v_jc,'MATERIAL','ISSUE',v_l_alt,v_alt,1,42500,42500,'WAC',false,1),
    (v_jc,'MATERIAL','ISSUE',v_l_bolt,v_bolt,4,85,340,'WAC',false,1),
    (v_jc,'MATERIAL','ISSUE',v_l_belt,v_belt,1,3150,3150,'EFFECTIVE_PRICE',true,1),   -- provisional price
    (v_jc,'GENERAL','ISSUE',NULL,v_rag,10,25,250,'WAC',false,1),
    (v_jc,'GENERAL','ISSUE',NULL,v_spray,1,480,480,'WAC',false,1),
    (v_jc,'LABOUR','LABOUR',NULL,NULL,4,900,3600,'RATE',false,1),
    (v_jc,'LABOUR','LABOUR',NULL,NULL,2.5,900,2250,'RATE',false,1),
    (v_jc,'LABOUR','LABOUR',NULL,NULL,3,750,2250,'RATE',false,1),
    (v_jc,'OUTSIDE','OUTSIDE_REPAIR',v_or,NULL,NULL,NULL,18600,'INVOICE',false,1);

  PERFORM fn_recompute_job_cost(v_jc);
  SELECT total_cost,pending_cost,variance_amount INTO v_total,v_pending,v_var FROM job_card_cost_summary WHERE job_card_id=v_jc;
  v_canclose := fn_job_card_can_close(v_jc);
  v_block := fn_job_card_close_blockers(v_jc);
  RAISE NOTICE 'BEFORE price fix: total=% pending=% variance=% can_close=% blockers=%', v_total, v_pending, v_var, v_canclose, v_block;

  -- Phase 7: price update resolves the provisional line (fan belt now priced)
  UPDATE job_card_cost_line SET is_provisional=false WHERE job_card_id=v_jc AND is_provisional;
  UPDATE stock_issue_lines  SET is_provisional=false WHERE issue_line_id=v_l_belt;
  PERFORM fn_recompute_job_cost(v_jc);
  SELECT total_cost,pending_cost,variance_amount INTO v_total,v_pending,v_var FROM job_card_cost_summary WHERE job_card_id=v_jc;
  v_canclose := fn_job_card_can_close(v_jc);
  v_block := fn_job_card_close_blockers(v_jc);
  RAISE NOTICE 'AFTER  price fix: total=% pending=% variance=% can_close=% blockers=%', v_total, v_pending, v_var, v_canclose, v_block;
END $$;
