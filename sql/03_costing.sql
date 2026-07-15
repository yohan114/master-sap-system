-- =====================================================================
-- 03 — COSTING TABLES (every cost event rolls up to the job card)
-- Implements §4. Costs are DERIVED from real events (cost lines), never hand-entered.
-- =====================================================================

-- ---------- Job card cost line (one row per real cost event) ----------
CREATE TABLE job_card_cost_line (
    cost_line_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id      bigint NOT NULL REFERENCES job_card_header(job_card_id),
    cost_element     varchar(10) NOT NULL
                     CHECK (cost_element IN ('MATERIAL','GENERAL','LABOUR','OUTSIDE')),
    source_doc_type  varchar(20) NOT NULL,   -- ISSUE / LABOUR / GRN / OUTSIDE_REPAIR / RETURN
    source_doc_id    bigint,
    item_id          bigint REFERENCES item_master(item_id),   -- null for labour/outside
    qty              numeric(18,4),
    unit_cost        numeric(18,4),
    line_cost        numeric(18,4) NOT NULL,
    price_source     varchar(20)  -- WAC / FIFO / EFFECTIVE_PRICE / INVOICE / RATE
                     CHECK (price_source IN ('WAC','FIFO','EFFECTIVE_PRICE','INVOICE','RATE') OR price_source IS NULL),
    is_provisional   boolean NOT NULL DEFAULT false,
    is_return        boolean NOT NULL DEFAULT false,  -- true => negative line (return against job)
    effective_price_date date,
    posted_at        timestamptz NOT NULL DEFAULT now(),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_costline_job ON job_card_cost_line(job_card_id);
CREATE INDEX ix_costline_elem ON job_card_cost_line(job_card_id, cost_element);
CREATE INDEX ix_costline_pending ON job_card_cost_line(job_card_id) WHERE is_provisional;

-- ---------- Job card cost summary (one row per job card) ----------
CREATE TABLE job_card_cost_summary (
    cost_summary_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id      bigint NOT NULL UNIQUE REFERENCES job_card_header(job_card_id),
    material_cost    numeric(18,4) NOT NULL DEFAULT 0,
    general_cost     numeric(18,4) NOT NULL DEFAULT 0,
    labour_cost      numeric(18,4) NOT NULL DEFAULT 0,
    outside_cost     numeric(18,4) NOT NULL DEFAULT 0,
    total_cost       numeric(18,4) NOT NULL DEFAULT 0,
    estimated_cost   numeric(18,4) NOT NULL DEFAULT 0,
    variance_amount  numeric(18,4) NOT NULL DEFAULT 0,
    variance_pct     numeric(9,4),
    pending_cost     numeric(18,4) NOT NULL DEFAULT 0,
    has_pending_price boolean NOT NULL DEFAULT false,
    is_final         boolean NOT NULL DEFAULT false,
    computed_at      timestamptz NOT NULL DEFAULT now(),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
