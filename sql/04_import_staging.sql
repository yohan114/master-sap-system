-- =====================================================================
-- 04 — IMPORT / STAGING (phased Excel/legacy upload; parent-child safe)
-- Implements §5, §6, §8. Raw text staging -> validate -> load; rejects to import_error_log.
-- =====================================================================

-- ---------- Import batch log (one row per uploaded file/batch) ----------
CREATE TABLE import_batch_log (
    batch_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    phase         smallint NOT NULL,            -- 1..7
    object_name   varchar(40) NOT NULL,         -- job_card_header, job_card_mrn_items, ...
    file_name     varchar(200),
    uploaded_by   bigint,
    uploaded_at   timestamptz NOT NULL DEFAULT now(),
    total_rows    integer DEFAULT 0,
    valid_rows    integer DEFAULT 0,
    rejected_rows integer DEFAULT 0,
    loaded_rows   integer DEFAULT 0,
    auto_stub     boolean NOT NULL DEFAULT false,   -- allow controlled stub parents?
    status        varchar(15) NOT NULL DEFAULT 'RUNNING'
                  CHECK (status IN ('RUNNING','COMPLETED','FAILED','ROLLED_BACK'))
);

-- ---------- Import error / exception log (one row per rejected/review row) ----------
CREATE TABLE import_error_log (
    error_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id      bigint NOT NULL REFERENCES import_batch_log(batch_id),
    phase         smallint NOT NULL,
    source_row_no integer NOT NULL,
    business_key  varchar(80),                  -- jc_no / item_code / etc.
    rule_code     varchar(20) NOT NULL,         -- V-VEH, V-ITEM-UNK, V-CHILD-ORPHAN, ...
    error_msg     varchar(300) NOT NULL,
    severity      varchar(10) NOT NULL DEFAULT 'REJECT'
                  CHECK (severity IN ('REJECT','WARN','REVIEW')),
    raw_row       jsonb,
    resolved_flag boolean NOT NULL DEFAULT false,
    resolved_at   timestamptz,
    resolved_by   bigint,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ux_import_err UNIQUE (batch_id, source_row_no, rule_code)
);
CREATE INDEX ix_err_batch ON import_error_log(batch_id);
CREATE INDEX ix_err_open ON import_error_log(resolved_flag) WHERE resolved_flag = false;

-- ---------- Staging tables (raw text; one per phase) ----------
-- Common control columns: batch_id, source_row_no, row_status, error_msg, loaded_id
CREATE TABLE stg_job_card_header (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, vehicle_code text, site_code text, job_type_code text,
    repair_description text, major_minor text, start_date text, end_date text,
    estimated_cost text, remarks text, source_ref text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_job_card_mrn_items (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, item_code text, qty_requested text, qty_issued text, uom text,
    source text, request_type text, line_no text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_job_card_general_items (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, item_code text, qty text, uom text, line_no text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_job_card_daily_work (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, work_date text, work_done text, technician_code text, hours text, pct_complete text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_job_card_labour (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, employee_code text, work_date text, hours text, hourly_rate text, task_ref text, remarks text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_job_card_outside_repair (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    jc_no text, supplier_code text, description text, sent_date text, expected_date text,
    received_date text, quoted_cost text, actual_cost text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);

CREATE TABLE stg_price (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES import_batch_log(batch_id),
    source_row_no integer NOT NULL,
    item_code text, unit_price text, effective_from text, supplier_code text, price_type text,
    row_status varchar(10) NOT NULL DEFAULT 'NEW'
        CHECK (row_status IN ('NEW','VALID','ERROR','LOADED','SKIPPED')),
    error_msg text, loaded_id bigint
);
