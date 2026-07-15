-- =====================================================================
-- 07 — IMPORT LOADER (stg_* -> live, validated, parent-child safe)
-- Implements §5 (load), §6 (parent-child / stubs), §8 (row-level validation).
-- Flow per batch: \copy CSV -> stg_*  ->  fn_load_batch(batch_id)
--   valid rows -> live tables (row_status=LOADED, loaded_id set)
--   invalid rows -> import_error_log (+ row_status=ERROR); the batch is NOT aborted.
-- created_by = 0 (system) for imported rows.
-- =====================================================================

-- ---------- Safe casts (return NULL for blank OR unparseable) ----------
CREATE OR REPLACE FUNCTION fn_to_date(p text) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF nullif(btrim(p),'') IS NULL THEN RETURN NULL; END IF;
    RETURN btrim(p)::date;
EXCEPTION WHEN others THEN RETURN NULL;
END; $$;

CREATE OR REPLACE FUNCTION fn_to_num(p text) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF nullif(btrim(p),'') IS NULL THEN RETURN NULL; END IF;
    RETURN btrim(p)::numeric;
EXCEPTION WHEN others THEN RETURN NULL;
END; $$;

-- ---------- Error logger ----------
CREATE OR REPLACE FUNCTION fn_import_error(p_batch bigint, p_phase int, p_row int, p_key text,
                                           p_rule text, p_msg text, p_sev text, p_raw jsonb)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO import_error_log(batch_id,phase,source_row_no,business_key,rule_code,error_msg,severity,raw_row)
    VALUES (p_batch,p_phase,p_row,p_key,p_rule,p_msg,p_sev,p_raw)
    ON CONFLICT (batch_id,source_row_no,rule_code) DO NOTHING;
$$;

-- ---------- Ensure a JOB_CARD 'DRAFT' status exists (for stubs / new headers) ----------
CREATE OR REPLACE FUNCTION fn_jobcard_draft_status() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
    SELECT status_id INTO v FROM status_master WHERE doc_type='JOB_CARD' AND status_code='DRAFT';
    IF v IS NULL THEN
        INSERT INTO status_master(doc_type,status_code,name,sort_order,created_by)
        VALUES ('JOB_CARD','DRAFT','Draft',1,0) RETURNING status_id INTO v;
    END IF;
    RETURN v;
END; $$;

-- ---------- Resolve jc_no -> job_card_id, optionally creating a controlled stub ----------
CREATE OR REPLACE FUNCTION fn_resolve_job_card(p_jc_no text, p_auto_stub boolean) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
    SELECT job_card_id INTO v FROM job_card_header WHERE jc_no = p_jc_no;
    IF v IS NOT NULL THEN RETURN v; END IF;
    IF p_auto_stub THEN
        INSERT INTO job_card_header(jc_no,status_id,is_stub,created_by)
        VALUES (p_jc_no, fn_jobcard_draft_status(), true, 0) RETURNING job_card_id INTO v;
    END IF;
    RETURN v;   -- NULL if not found and stubbing disabled
END; $$;

-- ---------- Finalize batch counters ----------
CREATE OR REPLACE FUNCTION fn_finalize_batch(p_batch bigint, p_table text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_total int; v_loaded int; v_err int;
BEGIN
    EXECUTE format(
      'SELECT count(*), count(*) FILTER (WHERE row_status=''LOADED''), count(*) FILTER (WHERE row_status=''ERROR'') FROM %I WHERE batch_id=$1',
      p_table) INTO v_total, v_loaded, v_err USING p_batch;
    UPDATE import_batch_log
       SET total_rows=v_total, loaded_rows=v_loaded, valid_rows=v_loaded,
           rejected_rows=v_err, status='COMPLETED'
     WHERE batch_id=p_batch;
END; $$;

-- ---------- Open a new import batch (returns batch_id) ----------
CREATE OR REPLACE FUNCTION fn_new_batch(p_phase int, p_object text, p_auto_stub boolean DEFAULT false,
                                        p_file text DEFAULT NULL, p_by bigint DEFAULT 0)
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO import_batch_log(phase,object_name,file_name,auto_stub,uploaded_by,status)
    VALUES (p_phase,p_object,p_file,p_auto_stub,p_by,'RUNNING')
    RETURNING batch_id;
$$;

-- =====================================================================
-- PHASE 1 — job_card_header (root; completes a stub if one exists)
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase1_header(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_veh bigint; v_site bigint; v_jt bigint; v_jc bigint;
        v_start date; v_end date; v_est numeric; v_mm text; v_bad boolean;
BEGIN
  FOR r IN SELECT * FROM stg_job_card_header WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN
        PERFORM fn_import_error(p_batch,1,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r));
        UPDATE stg_job_card_header SET row_status='ERROR', error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE;
    END IF;
    SELECT vehicle_id INTO v_veh FROM vehicle_master WHERE vehicle_code=btrim(r.vehicle_code) AND is_active;
    SELECT site_id    INTO v_site FROM site_master   WHERE site_code=btrim(r.site_code) AND is_active;
    SELECT job_type_id INTO v_jt FROM job_type_master WHERE job_type_code=btrim(r.job_type_code);
    v_start := fn_to_date(r.start_date); v_end := fn_to_date(r.end_date); v_est := fn_to_num(r.estimated_cost);
    v_mm := nullif(upper(btrim(r.major_minor)),'');

    IF v_veh  IS NULL THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-VEH','Unknown vehicle: '||coalesce(r.vehicle_code,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_site IS NULL THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-SITE','Unknown site: '||coalesce(r.site_code,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.start_date),'') IS NOT NULL AND v_start IS NULL THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-DATE-BAD','Bad start_date','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.end_date),'')   IS NOT NULL AND v_end   IS NULL THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-DATE-BAD','Bad end_date','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_start IS NOT NULL AND v_end IS NOT NULL AND v_end < v_start THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-DATE-ORDER','end_date before start_date','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_mm IS NOT NULL AND v_mm NOT IN ('MAJOR','MINOR') THEN PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-ENUM','major_minor must be MAJOR/MINOR','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_bad THEN UPDATE stg_job_card_header SET row_status='ERROR', error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;

    SELECT job_card_id INTO v_jc FROM job_card_header WHERE jc_no=btrim(r.jc_no);
    IF v_jc IS NOT NULL THEN
        IF (SELECT is_stub FROM job_card_header WHERE job_card_id=v_jc) THEN
            UPDATE job_card_header SET vehicle_id=v_veh, site_id=v_site, job_type_id=v_jt,
                   repair_description=r.repair_description, major_minor=v_mm, start_date=v_start,
                   end_date=v_end, estimated_cost=coalesce(v_est,0), remarks=r.remarks,
                   source_ref=r.source_ref, is_stub=false, updated_at=now()
             WHERE job_card_id=v_jc;
            UPDATE stg_job_card_header SET row_status='LOADED', loaded_id=v_jc WHERE stg_id=r.stg_id;
        ELSE
            PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-JC-DUP','Duplicate job card '||r.jc_no,'REJECT',to_jsonb(r));
            UPDATE stg_job_card_header SET row_status='ERROR', error_msg='duplicate job card' WHERE stg_id=r.stg_id;
        END IF;
        CONTINUE;
    END IF;

    INSERT INTO job_card_header(jc_no,vehicle_id,site_id,job_type_id,repair_description,major_minor,
           start_date,end_date,estimated_cost,remarks,source_ref,status_id,created_by)
    VALUES (btrim(r.jc_no),v_veh,v_site,v_jt,r.repair_description,v_mm,v_start,v_end,
           coalesce(v_est,0),r.remarks,r.source_ref,fn_jobcard_draft_status(),0)
    RETURNING job_card_id INTO v_jc;
    UPDATE stg_job_card_header SET row_status='LOADED', loaded_id=v_jc WHERE stg_id=r.stg_id;
   EXCEPTION WHEN others THEN
    PERFORM fn_import_error(p_batch,1,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r));
    UPDATE stg_job_card_header SET row_status='ERROR', error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 2 — job_card_mrn_items
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase2_mrn(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_auto boolean; v_job bigint; v_item bigint; v_uom bigint;
        v_qreq numeric; v_qiss numeric; v_src text; v_rt text; v_ln smallint; v_new bigint; v_bad boolean;
BEGIN
  SELECT auto_stub INTO v_auto FROM import_batch_log WHERE batch_id=p_batch;
  FOR r IN SELECT * FROM stg_job_card_mrn_items WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r)); UPDATE stg_job_card_mrn_items SET row_status='ERROR',error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    IF nullif(btrim(r.item_code),'') IS NULL THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-ITEM-MISS','Missing item_code','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    SELECT item_id INTO v_item FROM item_master WHERE item_code=btrim(r.item_code) AND is_active;
    SELECT uom_id  INTO v_uom  FROM uom_master  WHERE uom_code=btrim(r.uom);
    v_qreq := fn_to_num(r.qty_requested); v_qiss := coalesce(fn_to_num(r.qty_issued),0);
    v_src := coalesce(nullif(upper(btrim(r.source)),''),'STOCK');
    v_rt  := coalesce(nullif(upper(btrim(r.request_type)),''),'INTERNAL');
    v_ln  := coalesce(fn_to_num(r.line_no),1)::smallint;

    IF nullif(btrim(r.item_code),'') IS NOT NULL AND v_item IS NULL THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-ITEM-UNK','Unknown material code: '||r.item_code,'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_uom IS NULL THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-UOM','Unknown uom: '||coalesce(r.uom,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_qreq IS NULL OR v_qreq<=0 THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-QTY-MISS','qty_requested missing/<=0','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_src NOT IN ('STOCK','PURCHASE') THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-ENUM','source must be STOCK/PURCHASE','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_rt NOT IN ('INTERNAL','EXTERNAL') THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-ENUM','request_type must be INTERNAL/EXTERNAL','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_bad THEN UPDATE stg_job_card_mrn_items SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;

    v_job := fn_resolve_job_card(btrim(r.jc_no), v_auto);
    IF v_job IS NULL THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-CHILD-ORPHAN','No parent job card '||r.jc_no,'REVIEW',to_jsonb(r)); UPDATE stg_job_card_mrn_items SET row_status='ERROR',error_msg='child without parent' WHERE stg_id=r.stg_id; CONTINUE; END IF;

    INSERT INTO job_card_mrn_items(job_card_id,jc_no,item_id,qty_requested,qty_issued,uom_id,source,request_type,line_no,created_by)
    VALUES (v_job,btrim(r.jc_no),v_item,v_qreq,v_qiss,v_uom,v_src,v_rt,v_ln,0) RETURNING mrn_item_id INTO v_new;
    UPDATE stg_job_card_mrn_items SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION
    WHEN unique_violation THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-LINE-DUP','Duplicate MRN line (job,item,line_no)','REJECT',to_jsonb(r)); UPDATE stg_job_card_mrn_items SET row_status='ERROR',error_msg='duplicate line' WHERE stg_id=r.stg_id;
    WHEN others THEN PERFORM fn_import_error(p_batch,2,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_job_card_mrn_items SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 3 — job_card_general_items
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase3_general(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_auto boolean; v_job bigint; v_item bigint; v_uom bigint; v_qty numeric; v_ln smallint; v_new bigint; v_bad boolean;
BEGIN
  SELECT auto_stub INTO v_auto FROM import_batch_log WHERE batch_id=p_batch;
  FOR r IN SELECT * FROM stg_job_card_general_items WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r)); UPDATE stg_job_card_general_items SET row_status='ERROR',error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    SELECT item_id INTO v_item FROM item_master WHERE item_code=btrim(r.item_code) AND is_active;
    SELECT uom_id  INTO v_uom  FROM uom_master  WHERE uom_code=btrim(r.uom);
    v_qty := fn_to_num(r.qty); v_ln := coalesce(fn_to_num(r.line_no),1)::smallint;
    IF nullif(btrim(r.item_code),'') IS NULL THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-ITEM-MISS','Missing item_code','REJECT',to_jsonb(r)); v_bad:=true;
    ELSIF v_item IS NULL THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-ITEM-UNK','Unknown material code: '||r.item_code,'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_uom IS NULL THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-UOM','Unknown uom','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_qty IS NULL OR v_qty<=0 THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-QTY-MISS','qty missing/<=0','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_bad THEN UPDATE stg_job_card_general_items SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    v_job := fn_resolve_job_card(btrim(r.jc_no), v_auto);
    IF v_job IS NULL THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-CHILD-ORPHAN','No parent job card','REVIEW',to_jsonb(r)); UPDATE stg_job_card_general_items SET row_status='ERROR',error_msg='child without parent' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    INSERT INTO job_card_general_items(job_card_id,jc_no,item_id,qty,uom_id,line_no,created_by)
    VALUES (v_job,btrim(r.jc_no),v_item,v_qty,v_uom,v_ln,0) RETURNING general_item_id INTO v_new;
    UPDATE stg_job_card_general_items SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION
    WHEN unique_violation THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-LINE-DUP','Duplicate general line','REJECT',to_jsonb(r)); UPDATE stg_job_card_general_items SET row_status='ERROR',error_msg='duplicate line' WHERE stg_id=r.stg_id;
    WHEN others THEN PERFORM fn_import_error(p_batch,3,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_job_card_general_items SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 4 — job_card_daily_work
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase4_daily(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_auto boolean; v_job bigint; v_tech bigint; v_wd date; v_hours numeric; v_pct numeric; v_seq smallint; v_new bigint; v_bad boolean;
BEGIN
  SELECT auto_stub INTO v_auto FROM import_batch_log WHERE batch_id=p_batch;
  FOR r IN SELECT * FROM stg_job_card_daily_work WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r)); UPDATE stg_job_card_daily_work SET row_status='ERROR',error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    v_wd := fn_to_date(r.work_date); v_hours := fn_to_num(r.hours); v_pct := fn_to_num(r.pct_complete);
    IF v_wd IS NULL THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,r.jc_no,'V-DATE-BAD','Missing/bad work_date','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.work_done),'') IS NULL THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,r.jc_no,'V-REQ','Missing work_done','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.technician_code),'') IS NOT NULL THEN
        SELECT employee_id INTO v_tech FROM employee_master WHERE employee_code=btrim(r.technician_code) AND is_active;
        IF v_tech IS NULL THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,r.jc_no,'V-EMP-UNK','Unknown technician: '||r.technician_code,'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    ELSE v_tech := NULL; END IF;
    IF v_bad THEN UPDATE stg_job_card_daily_work SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    v_job := fn_resolve_job_card(btrim(r.jc_no), v_auto);
    IF v_job IS NULL THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,r.jc_no,'V-CHILD-ORPHAN','No parent job card','REVIEW',to_jsonb(r)); UPDATE stg_job_card_daily_work SET row_status='ERROR',error_msg='child without parent' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    SELECT coalesce(max(seq),0)+1 INTO v_seq FROM job_card_daily_work WHERE job_card_id=v_job AND work_date=v_wd;
    INSERT INTO job_card_daily_work(job_card_id,jc_no,work_date,work_done,technician_id,hours,pct_complete,seq,entered_by,created_by)
    VALUES (v_job,btrim(r.jc_no),v_wd,r.work_done,v_tech,v_hours,v_pct,v_seq,0,0) RETURNING daily_work_id INTO v_new;
    UPDATE stg_job_card_daily_work SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION WHEN others THEN PERFORM fn_import_error(p_batch,4,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_job_card_daily_work SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 5 — job_card_labour (rate resolved if blank; WARN if unresolved)
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase5_labour(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_auto boolean; v_job bigint; v_emp bigint; v_wd date; v_hours numeric; v_rate numeric; v_cost numeric; v_seq smallint; v_new bigint; v_bad boolean;
BEGIN
  SELECT auto_stub INTO v_auto FROM import_batch_log WHERE batch_id=p_batch;
  FOR r IN SELECT * FROM stg_job_card_labour WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r)); UPDATE stg_job_card_labour SET row_status='ERROR',error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    SELECT employee_id INTO v_emp FROM employee_master WHERE employee_code=btrim(r.employee_code) AND is_active;
    v_wd := fn_to_date(r.work_date); v_hours := fn_to_num(r.hours); v_rate := fn_to_num(r.hourly_rate);
    IF v_emp IS NULL THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-EMP-UNK','Unknown employee: '||coalesce(r.employee_code,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_wd IS NULL THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-DATE-BAD','Missing/bad work_date','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_hours IS NULL OR v_hours<=0 THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-QTY-MISS','hours missing/<=0','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_bad THEN UPDATE stg_job_card_labour SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    v_job := fn_resolve_job_card(btrim(r.jc_no), v_auto);
    IF v_job IS NULL THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-CHILD-ORPHAN','No parent job card','REVIEW',to_jsonb(r)); UPDATE stg_job_card_labour SET row_status='ERROR',error_msg='child without parent' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    IF v_rate IS NULL THEN v_rate := fn_effective_rate(v_emp, v_wd); END IF;
    IF v_rate IS NULL THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-RATE-MISS','No rate; loaded cost-pending','WARN',to_jsonb(r)); END IF;
    v_cost := CASE WHEN v_rate IS NOT NULL THEN v_hours*v_rate END;
    SELECT coalesce(max(seq),0)+1 INTO v_seq FROM job_card_labour WHERE job_card_id=v_job AND employee_id=v_emp AND work_date=v_wd;
    INSERT INTO job_card_labour(job_card_id,jc_no,employee_id,work_date,hours,hourly_rate,line_cost,task_ref,remarks,seq,created_by)
    VALUES (v_job,btrim(r.jc_no),v_emp,v_wd,v_hours,v_rate,v_cost,nullif(btrim(r.task_ref),''),nullif(btrim(r.remarks),''),v_seq,0) RETURNING labour_id INTO v_new;
    UPDATE stg_job_card_labour SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION WHEN others THEN PERFORM fn_import_error(p_batch,5,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_job_card_labour SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 6 — job_card_outside_repair
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase6_outside(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_auto boolean; v_job bigint; v_sup bigint; v_sent date; v_exp date; v_recv date; v_quote numeric; v_actual numeric; v_seq smallint; v_new bigint; v_bad boolean;
BEGIN
  SELECT auto_stub INTO v_auto FROM import_batch_log WHERE batch_id=p_batch;
  FOR r IN SELECT * FROM stg_job_card_outside_repair WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    IF nullif(btrim(r.jc_no),'') IS NULL THEN PERFORM fn_import_error(p_batch,6,r.source_row_no,NULL,'V-JCNO-MISS','Missing jc_no','REJECT',to_jsonb(r)); UPDATE stg_job_card_outside_repair SET row_status='ERROR',error_msg='Missing jc_no' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    SELECT supplier_id INTO v_sup FROM supplier_master WHERE supplier_code=btrim(r.supplier_code) AND is_active;
    v_sent := fn_to_date(r.sent_date); v_exp := fn_to_date(r.expected_date); v_recv := fn_to_date(r.received_date);
    v_quote := fn_to_num(r.quoted_cost); v_actual := fn_to_num(r.actual_cost);
    IF v_sup IS NULL THEN PERFORM fn_import_error(p_batch,6,r.source_row_no,r.jc_no,'V-SUP-UNK','Unknown supplier: '||coalesce(r.supplier_code,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.description),'') IS NULL THEN PERFORM fn_import_error(p_batch,6,r.source_row_no,r.jc_no,'V-REQ','Missing description','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_bad THEN UPDATE stg_job_card_outside_repair SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    v_job := fn_resolve_job_card(btrim(r.jc_no), v_auto);
    IF v_job IS NULL THEN PERFORM fn_import_error(p_batch,6,r.source_row_no,r.jc_no,'V-CHILD-ORPHAN','No parent job card','REVIEW',to_jsonb(r)); UPDATE stg_job_card_outside_repair SET row_status='ERROR',error_msg='child without parent' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    SELECT coalesce(max(seq),0)+1 INTO v_seq FROM job_card_outside_repair WHERE job_card_id=v_job AND supplier_id=v_sup;
    INSERT INTO job_card_outside_repair(job_card_id,jc_no,supplier_id,description,sent_date,expected_date,received_date,quoted_cost,actual_cost,seq,created_by)
    VALUES (v_job,btrim(r.jc_no),v_sup,r.description,v_sent,v_exp,v_recv,v_quote,v_actual,v_seq,0) RETURNING outside_repair_id INTO v_new;
    UPDATE stg_job_card_outside_repair SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION WHEN others THEN PERFORM fn_import_error(p_batch,6,r.source_row_no,r.jc_no,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_job_card_outside_repair SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- PHASE 7 — prices / valuation (closes prior open range, appends new)
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_phase7_price(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_item bigint; v_sup bigint; v_price numeric; v_from date; v_pt text; v_new bigint; v_bad boolean;
BEGIN
  FOR r IN SELECT * FROM stg_price WHERE batch_id=p_batch AND row_status='NEW' ORDER BY source_row_no LOOP
   BEGIN
    v_bad := false;
    SELECT item_id INTO v_item FROM item_master WHERE item_code=btrim(r.item_code) AND is_active;
    v_price := fn_to_num(r.unit_price); v_from := fn_to_date(r.effective_from);
    v_pt := coalesce(nullif(upper(btrim(r.price_type)),''),'PURCHASE');
    IF nullif(btrim(r.item_code),'') IS NULL OR v_item IS NULL THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-ITEM-UNK','Unknown material code: '||coalesce(r.item_code,''),'REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_price IS NULL OR v_price<0 THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-PRICE-NEG','Missing/negative unit_price','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_from IS NULL THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-DATE-BAD','Missing/bad effective_from','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF v_pt NOT IN ('PURCHASE','STANDARD','LAST','WAC') THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-ENUM','Bad price_type','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    IF nullif(btrim(r.supplier_code),'') IS NOT NULL THEN
        SELECT supplier_id INTO v_sup FROM supplier_master WHERE supplier_code=btrim(r.supplier_code);
        IF v_sup IS NULL THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-SUP-UNK','Unknown supplier','REJECT',to_jsonb(r)); v_bad:=true; END IF;
    ELSE v_sup := NULL; END IF;
    IF v_bad THEN UPDATE stg_price SET row_status='ERROR',error_msg='validation failed' WHERE stg_id=r.stg_id; CONTINUE; END IF;
    -- close prior open range for same key
    UPDATE price_history SET effective_to = v_from - 1, updated_at=now()
     WHERE item_id=v_item AND price_type=v_pt AND effective_to IS NULL AND effective_from < v_from
       AND coalesce(supplier_id,-1)=coalesce(v_sup,-1);
    INSERT INTO price_history(item_id,price_type,supplier_id,unit_price,effective_from,source_doc_type,created_by)
    VALUES (v_item,v_pt,v_sup,v_price,v_from,'IMPORT',0) RETURNING price_history_id INTO v_new;
    UPDATE stg_price SET row_status='LOADED', loaded_id=v_new WHERE stg_id=r.stg_id;
   EXCEPTION
    WHEN unique_violation THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-LINE-DUP','Duplicate price (item,type,supplier,from)','REJECT',to_jsonb(r)); UPDATE stg_price SET row_status='ERROR',error_msg='duplicate price' WHERE stg_id=r.stg_id;
    WHEN others THEN PERFORM fn_import_error(p_batch,7,r.source_row_no,r.item_code,'V-DBERR',SQLERRM,'REJECT',to_jsonb(r)); UPDATE stg_price SET row_status='ERROR',error_msg=SQLERRM WHERE stg_id=r.stg_id;
   END;
  END LOOP;
END; $$;

-- =====================================================================
-- Dispatcher — run the loader for a batch by its phase, then finalize counters
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_load_batch(p_batch bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_phase int;
BEGIN
    SELECT phase INTO v_phase FROM import_batch_log WHERE batch_id=p_batch;
    IF v_phase IS NULL THEN RAISE EXCEPTION 'Unknown batch %', p_batch; END IF;
    CASE v_phase
      WHEN 1 THEN PERFORM fn_load_phase1_header(p_batch);  PERFORM fn_finalize_batch(p_batch,'stg_job_card_header');
      WHEN 2 THEN PERFORM fn_load_phase2_mrn(p_batch);     PERFORM fn_finalize_batch(p_batch,'stg_job_card_mrn_items');
      WHEN 3 THEN PERFORM fn_load_phase3_general(p_batch); PERFORM fn_finalize_batch(p_batch,'stg_job_card_general_items');
      WHEN 4 THEN PERFORM fn_load_phase4_daily(p_batch);   PERFORM fn_finalize_batch(p_batch,'stg_job_card_daily_work');
      WHEN 5 THEN PERFORM fn_load_phase5_labour(p_batch);  PERFORM fn_finalize_batch(p_batch,'stg_job_card_labour');
      WHEN 6 THEN PERFORM fn_load_phase6_outside(p_batch); PERFORM fn_finalize_batch(p_batch,'stg_job_card_outside_repair');
      WHEN 7 THEN PERFORM fn_load_phase7_price(p_batch);   PERFORM fn_finalize_batch(p_batch,'stg_price');
      ELSE RAISE EXCEPTION 'Unsupported phase %', v_phase;
    END CASE;
END; $$;
