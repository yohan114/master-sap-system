-- =====================================================================
-- 08 — POSTING / COSTING LAYER
-- Turns loaded (or live-entered) child rows into job_card_cost_line records,
-- then recomputes job_card_cost_summary. Implements §3 linking/roll-up + §4 costing.
--
-- fn_rebuild_job_costs(job_card_id)  — (re)derive ALL cost lines for one job from its
--     linked children (MRN, general, labour, outside repair), resolving prices as of the
--     job's cost date; lines with no resolvable price are flagged is_provisional (cost-pending).
--     Idempotent: it deletes and re-derives the job's cost lines, then recomputes the summary.
-- fn_rebuild_all_job_costs()         — rebuild every non-stub job (use after a bulk import).
-- fn_refresh_pending_prices()        — after a price update, rebuild only jobs that still
--     carry provisional (pending-price) cost lines, clearing them where a price now exists.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_rebuild_job_costs(p_job_card_id bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_date date; rec record; v_unit numeric; v_prov boolean; v_src varchar;
BEGIN
    SELECT coalesce(start_date, end_date) INTO v_date FROM job_card_header WHERE job_card_id = p_job_card_id;

    -- rebuild from source: clear this job's derived cost lines
    DELETE FROM job_card_cost_line WHERE job_card_id = p_job_card_id;

    -- MATERIAL — from issued MRN lines (prefer the linked stock-issue cost, else effective price)
    FOR rec IN
        SELECT mi.mrn_item_id, mi.item_id, mi.qty_issued, sil.unit_cost AS issue_cost
        FROM   job_card_mrn_items mi
        LEFT   JOIN stock_issue_lines sil ON sil.issue_line_id = mi.stock_issue_line_id
        WHERE  mi.job_card_id = p_job_card_id AND mi.qty_issued > 0
    LOOP
        v_unit := coalesce(rec.issue_cost, fn_effective_price(rec.item_id, coalesce(v_date, CURRENT_DATE)));
        v_prov := (v_unit IS NULL);
        v_src  := CASE WHEN rec.issue_cost IS NOT NULL THEN 'WAC'
                       WHEN v_unit IS NOT NULL THEN 'EFFECTIVE_PRICE' ELSE NULL END;
        INSERT INTO job_card_cost_line(job_card_id,cost_element,source_doc_type,source_doc_id,item_id,
               qty,unit_cost,line_cost,price_source,is_provisional,effective_price_date,created_by)
        VALUES (p_job_card_id,'MATERIAL','MRN',rec.mrn_item_id,rec.item_id,
               rec.qty_issued,coalesce(v_unit,0),rec.qty_issued*coalesce(v_unit,0),v_src,v_prov,v_date,0);
    END LOOP;

    -- GENERAL — from general item lines
    FOR rec IN
        SELECT gi.general_item_id, gi.item_id, gi.qty, sil.unit_cost AS issue_cost
        FROM   job_card_general_items gi
        LEFT   JOIN stock_issue_lines sil ON sil.issue_line_id = gi.stock_issue_line_id
        WHERE  gi.job_card_id = p_job_card_id
    LOOP
        v_unit := coalesce(rec.issue_cost, fn_effective_price(rec.item_id, coalesce(v_date, CURRENT_DATE)));
        v_prov := (v_unit IS NULL);
        v_src  := CASE WHEN rec.issue_cost IS NOT NULL THEN 'WAC'
                       WHEN v_unit IS NOT NULL THEN 'EFFECTIVE_PRICE' ELSE NULL END;
        INSERT INTO job_card_cost_line(job_card_id,cost_element,source_doc_type,source_doc_id,item_id,
               qty,unit_cost,line_cost,price_source,is_provisional,effective_price_date,created_by)
        VALUES (p_job_card_id,'GENERAL','GENERAL_ITEM',rec.general_item_id,rec.item_id,
               rec.qty,coalesce(v_unit,0),rec.qty*coalesce(v_unit,0),v_src,v_prov,v_date,0);
    END LOOP;

    -- LABOUR — hours x rate (provisional if rate could not be resolved)
    FOR rec IN
        SELECT labour_id, hours, hourly_rate FROM job_card_labour WHERE job_card_id = p_job_card_id
    LOOP
        v_prov := (rec.hourly_rate IS NULL);
        INSERT INTO job_card_cost_line(job_card_id,cost_element,source_doc_type,source_doc_id,
               qty,unit_cost,line_cost,price_source,is_provisional,created_by)
        VALUES (p_job_card_id,'LABOUR','LABOUR',rec.labour_id,
               rec.hours,rec.hourly_rate,rec.hours*coalesce(rec.hourly_rate,0),'RATE',v_prov,0);
    END LOOP;

    -- OUTSIDE — actual cost (provisional until invoiced/costed)
    FOR rec IN
        SELECT outside_repair_id, actual_cost FROM job_card_outside_repair WHERE job_card_id = p_job_card_id
    LOOP
        v_prov := (rec.actual_cost IS NULL);
        INSERT INTO job_card_cost_line(job_card_id,cost_element,source_doc_type,source_doc_id,
               line_cost,price_source,is_provisional,created_by)
        VALUES (p_job_card_id,'OUTSIDE','OUTSIDE_REPAIR',rec.outside_repair_id,
               coalesce(rec.actual_cost,0),'INVOICE',v_prov,0);
    END LOOP;

    PERFORM fn_recompute_job_cost(p_job_card_id);
END; $$;

-- Rebuild every real (non-stub) job — use after a bulk historical import
CREATE OR REPLACE FUNCTION fn_rebuild_all_job_costs() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE r bigint; n int := 0;
BEGIN
    FOR r IN SELECT job_card_id FROM job_card_header WHERE is_stub = false AND is_active LOOP
        PERFORM fn_rebuild_job_costs(r);
        n := n + 1;
    END LOOP;
    RETURN n;
END; $$;

-- After price updates: rebuild only jobs that still carry pending-price cost lines
CREATE OR REPLACE FUNCTION fn_refresh_pending_prices() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE r bigint; n int := 0;
BEGIN
    FOR r IN SELECT DISTINCT job_card_id FROM job_card_cost_line WHERE is_provisional LOOP
        PERFORM fn_rebuild_job_costs(r);
        n := n + 1;
    END LOOP;
    RETURN n;
END; $$;
