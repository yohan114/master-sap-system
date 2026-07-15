-- =====================================================================
-- 05 — VIEWS & FUNCTIONS (cost roll-up, effective pricing, closure gate)
-- Implements §3 linking/roll-up, §4 formulas, §10.7 closure rules.
-- =====================================================================

-- ---------- Effective price as of a date (§4.3) ----------
CREATE OR REPLACE FUNCTION fn_effective_price(p_item_id bigint, p_on_date date, p_price_type varchar DEFAULT 'PURCHASE')
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT unit_price
    FROM   price_history
    WHERE  item_id = p_item_id
      AND  price_type = p_price_type
      AND  p_on_date >= effective_from
      AND  p_on_date <  COALESCE(effective_to, DATE '9999-12-31')
    ORDER  BY effective_from DESC
    LIMIT  1;
$$;

-- ---------- Effective technician rate as of a date ----------
CREATE OR REPLACE FUNCTION fn_effective_rate(p_employee_id bigint, p_on_date date)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT hourly_rate FROM employee_rate
          WHERE employee_id = p_employee_id
            AND p_on_date >= effective_from
            AND p_on_date <  COALESCE(effective_to, DATE '9999-12-31')
          ORDER BY effective_from DESC LIMIT 1),
        (SELECT default_hourly_rate FROM employee_master WHERE employee_id = p_employee_id)
    );
$$;

-- ---------- Live cost roll-up per job (from cost lines) ----------
CREATE OR REPLACE VIEW v_job_card_cost AS
SELECT h.job_card_id,
       h.jc_no,
       COALESCE(SUM(cl.line_cost) FILTER (WHERE cl.cost_element = 'MATERIAL'), 0) AS material_cost,
       COALESCE(SUM(cl.line_cost) FILTER (WHERE cl.cost_element = 'GENERAL'),  0) AS general_cost,
       COALESCE(SUM(cl.line_cost) FILTER (WHERE cl.cost_element = 'LABOUR'),   0) AS labour_cost,
       COALESCE(SUM(cl.line_cost) FILTER (WHERE cl.cost_element = 'OUTSIDE'),  0) AS outside_cost,
       COALESCE(SUM(cl.line_cost), 0)                                            AS total_cost,
       COALESCE(SUM(cl.line_cost) FILTER (WHERE cl.is_provisional), 0)           AS pending_cost,
       bool_or(cl.is_provisional)                                                AS has_pending_price,
       h.estimated_cost
FROM   job_card_header h
LEFT   JOIN job_card_cost_line cl ON cl.job_card_id = h.job_card_id AND cl.is_active
GROUP  BY h.job_card_id, h.jc_no, h.estimated_cost;

-- ---------- Recompute & persist the cost summary for one job (§3.3) ----------
CREATE OR REPLACE FUNCTION fn_recompute_job_cost(p_job_card_id bigint)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v record;
BEGIN
    SELECT * INTO v FROM v_job_card_cost WHERE job_card_id = p_job_card_id;
    IF NOT FOUND THEN RETURN; END IF;

    INSERT INTO job_card_cost_summary AS s (
        job_card_id, material_cost, general_cost, labour_cost, outside_cost,
        total_cost, estimated_cost, variance_amount, variance_pct,
        pending_cost, has_pending_price, is_final, computed_at, created_by)
    VALUES (
        p_job_card_id, v.material_cost, v.general_cost, v.labour_cost, v.outside_cost,
        v.total_cost, v.estimated_cost,
        v.total_cost - v.estimated_cost,
        CASE WHEN v.estimated_cost <> 0 THEN (v.total_cost - v.estimated_cost) / v.estimated_cost * 100 END,
        v.pending_cost, COALESCE(v.has_pending_price,false), false, now(), 0)
    ON CONFLICT (job_card_id) DO UPDATE SET
        material_cost = EXCLUDED.material_cost,
        general_cost  = EXCLUDED.general_cost,
        labour_cost   = EXCLUDED.labour_cost,
        outside_cost  = EXCLUDED.outside_cost,
        total_cost    = EXCLUDED.total_cost,
        estimated_cost = EXCLUDED.estimated_cost,
        variance_amount = EXCLUDED.variance_amount,
        variance_pct  = EXCLUDED.variance_pct,
        pending_cost  = EXCLUDED.pending_cost,
        has_pending_price = EXCLUDED.has_pending_price,
        computed_at   = now(),
        updated_at    = now();

    -- keep the header's denormalised actual_cost in step
    UPDATE job_card_header SET actual_cost = v.total_cost, updated_at = now()
    WHERE job_card_id = p_job_card_id;
END;
$$;

-- ---------- Closure-gate status per job (one row per open job; §10.7, D) ----------
CREATE OR REPLACE VIEW v_job_card_closure_status AS
SELECT h.job_card_id, h.jc_no,
    NOT EXISTS (SELECT 1 FROM job_card_mrn_items m
                 WHERE m.job_card_id = h.job_card_id AND m.qty_issued < m.qty_requested)      AS parts_all_issued,
    NOT EXISTS (SELECT 1 FROM job_card_cost_line cl
                 WHERE cl.job_card_id = h.job_card_id AND cl.is_provisional)                  AS no_pending_price,
    NOT EXISTS (SELECT 1 FROM grn_header g
                 WHERE g.job_card_id = h.job_card_id AND g.is_priced = false)                 AS grns_priced,
    EXISTS     (SELECT 1 FROM job_card_labour l WHERE l.job_card_id = h.job_card_id)          AS labour_captured,
    NOT EXISTS (SELECT 1 FROM job_card_outside_repair o
                 WHERE o.job_card_id = h.job_card_id AND o.actual_cost IS NULL)               AS outside_costed,
    (h.tm_approved_at IS NOT NULL AND h.om_approved_at IS NOT NULL)                           AS approvals_complete
FROM job_card_header h;

-- ---------- Boolean closure gate (fn_job_card_can_close) ----------
CREATE OR REPLACE FUNCTION fn_job_card_can_close(p_job_card_id bigint)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT parts_all_issued AND no_pending_price AND grns_priced
       AND labour_captured AND outside_costed AND approvals_complete
    FROM v_job_card_closure_status
    WHERE job_card_id = p_job_card_id;
$$;

-- ---------- Human-readable blockers for the Closure Validation screen ----------
CREATE OR REPLACE FUNCTION fn_job_card_close_blockers(p_job_card_id bigint)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT ARRAY_REMOVE(ARRAY[
        CASE WHEN NOT parts_all_issued   THEN 'Unissued/partial MRN parts' END,
        CASE WHEN NOT no_pending_price   THEN 'Pending price on cost lines' END,
        CASE WHEN NOT grns_priced        THEN 'Unpriced GRN on job' END,
        CASE WHEN NOT labour_captured    THEN 'No labour captured' END,
        CASE WHEN NOT outside_costed     THEN 'Outside repair not costed' END,
        CASE WHEN NOT approvals_complete THEN 'Missing TM/OM approval' END
    ], NULL)
    FROM v_job_card_closure_status
    WHERE job_card_id = p_job_card_id;
$$;
