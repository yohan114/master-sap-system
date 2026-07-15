-- =====================================================================
-- 02 — TRANSACTION TABLES (job card at the center)
-- Implements §2. Every child links to job_card_header by job_card_id (FK) + jc_no (business key).
-- =====================================================================

-- ---------- Job card header (the anchor) ----------
CREATE TABLE job_card_header (
    job_card_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jc_no                 varchar(30)  NOT NULL UNIQUE,        -- e.g. JC-WS-26-00514
    vehicle_id            bigint       NOT NULL REFERENCES vehicle_master(vehicle_id),
    site_id               bigint       NOT NULL REFERENCES site_master(site_id),
    job_type_id           bigint       REFERENCES job_type_master(job_type_id),
    repair_description    varchar(500),
    major_minor           varchar(10)  CHECK (major_minor IN ('MAJOR','MINOR')),
    priority              varchar(10)  CHECK (priority IN ('LOW','MED','HIGH','CRITICAL')),
    start_date            date,
    end_date              date,
    odometer_in           numeric(18,2),
    hours_in              numeric(18,2),
    reported_by           bigint REFERENCES employee_master(employee_id),
    transport_officer_id  bigint REFERENCES employee_master(employee_id),
    tm_approved_by        bigint REFERENCES employee_master(employee_id),
    tm_approved_at        timestamptz,
    om_approved_by        bigint REFERENCES employee_master(employee_id),
    om_approved_at        timestamptz,
    workshop_supervisor_id bigint REFERENCES employee_master(employee_id),
    remarks               varchar(500),
    estimated_cost        numeric(18,4) DEFAULT 0,
    actual_cost           numeric(18,4) DEFAULT 0,
    status_id             bigint NOT NULL REFERENCES status_master(status_id),
    is_stub               boolean NOT NULL DEFAULT false,   -- controlled stub from child-first import
    source_ref            varchar(50),                      -- legacy job/request number
    closed_by             bigint, closed_at timestamptz,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_jc_dates CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);
CREATE INDEX ix_jc_vehicle ON job_card_header(vehicle_id);
CREATE INDEX ix_jc_site ON job_card_header(site_id);
CREATE INDEX ix_jc_status ON job_card_header(status_id);

-- ---------- Job card status & approval history ----------
CREATE TABLE job_card_status_history (
    status_history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    from_status_id bigint REFERENCES status_master(status_id),
    to_status_id  bigint NOT NULL REFERENCES status_master(status_id),
    action        varchar(15) NOT NULL
                  CHECK (action IN ('CREATE','SUBMIT','APPROVE','REJECT','HOLD','RESUME','CLOSE','CANCEL','REOPEN')),
    acted_by      bigint NOT NULL,
    acted_at      timestamptz NOT NULL DEFAULT now(),
    comments      varchar(300),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_jcsh_job ON job_card_status_history(job_card_id);

-- ---------- Stock issue header / lines (issues against a job card) ----------
CREATE TABLE stock_issue_header (
    issue_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    issue_no     varchar(30) NOT NULL UNIQUE,
    issue_type   varchar(15) NOT NULL DEFAULT 'JOB' CHECK (issue_type IN ('JOB','GENERAL','LUBRICANT')),
    issue_date   date NOT NULL,
    location_id  bigint NOT NULL REFERENCES site_master(site_id),
    job_card_id  bigint REFERENCES job_card_header(job_card_id),
    issued_by    bigint REFERENCES employee_master(employee_id),
    override_flag boolean NOT NULL DEFAULT false,
    override_by  bigint,
    status_id    bigint REFERENCES status_master(status_id),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_issue_job ON stock_issue_header(job_card_id);

CREATE TABLE stock_issue_lines (
    issue_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    issue_id      bigint NOT NULL REFERENCES stock_issue_header(issue_id),
    item_id       bigint NOT NULL REFERENCES item_master(item_id),   -- no free-text material
    qty           numeric(18,4) NOT NULL CHECK (qty > 0),
    uom_id        bigint NOT NULL REFERENCES uom_master(uom_id),
    unit_cost     numeric(18,4),
    is_provisional boolean NOT NULL DEFAULT false,
    line_no       smallint,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_issue_line_item ON stock_issue_lines(item_id);

-- ---------- GRN header / lines (receipts; job-linked purchases & OR invoices) ----------
CREATE TABLE grn_header (
    grn_id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grn_no             varchar(30) NOT NULL UNIQUE,
    grn_date           date NOT NULL,
    supplier_id        bigint REFERENCES supplier_master(supplier_id),
    po_ref             varchar(30),
    job_card_id        bigint REFERENCES job_card_header(job_card_id),
    location_id        bigint REFERENCES site_master(site_id),
    invoice_no         varchar(40),
    price_received_date date,
    is_priced          boolean NOT NULL DEFAULT false,
    status_id          bigint REFERENCES status_master(status_id),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_grn_job ON grn_header(job_card_id);

CREATE TABLE grn_lines (
    grn_line_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grn_id       bigint NOT NULL REFERENCES grn_header(grn_id),
    item_id      bigint NOT NULL REFERENCES item_master(item_id),
    qty_received numeric(18,4) NOT NULL CHECK (qty_received > 0),
    uom_id       bigint NOT NULL REFERENCES uom_master(uom_id),
    unit_cost    numeric(18,4),
    is_priced    boolean NOT NULL DEFAULT false,
    batch_no     varchar(30),
    expiry_date  date,
    line_no      smallint,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_grn_line_item ON grn_lines(item_id);

-- ---------- Job card MRN item lines (material; no free-text) ----------
CREATE TABLE job_card_mrn_items (
    mrn_item_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    jc_no         varchar(30) NOT NULL,
    item_id       bigint NOT NULL REFERENCES item_master(item_id),
    qty_requested numeric(18,4) NOT NULL CHECK (qty_requested > 0),
    qty_issued    numeric(18,4) NOT NULL DEFAULT 0,
    uom_id        bigint NOT NULL REFERENCES uom_master(uom_id),
    source        varchar(10) NOT NULL DEFAULT 'STOCK' CHECK (source IN ('STOCK','PURCHASE')),
    request_type  varchar(10) NOT NULL DEFAULT 'INTERNAL' CHECK (request_type IN ('INTERNAL','EXTERNAL')),
    stock_issue_line_id bigint REFERENCES stock_issue_lines(issue_line_id),
    grn_line_id   bigint REFERENCES grn_lines(grn_line_id),
    status_id     bigint REFERENCES status_master(status_id),
    line_no       smallint NOT NULL DEFAULT 1,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_jc_mrn_line UNIQUE (job_card_id, item_id, line_no)
);
CREATE INDEX ix_mrn_job ON job_card_mrn_items(job_card_id);

-- ---------- Job card general item lines ----------
CREATE TABLE job_card_general_items (
    general_item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    jc_no         varchar(30) NOT NULL,
    item_id       bigint NOT NULL REFERENCES item_master(item_id),
    qty           numeric(18,4) NOT NULL CHECK (qty > 0),
    uom_id        bigint NOT NULL REFERENCES uom_master(uom_id),
    stock_issue_line_id bigint REFERENCES stock_issue_lines(issue_line_id),
    line_no       smallint NOT NULL DEFAULT 1,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_jc_gen_line UNIQUE (job_card_id, item_id, line_no)
);
CREATE INDEX ix_gen_job ON job_card_general_items(job_card_id);

-- ---------- Job card daily work done ----------
CREATE TABLE job_card_daily_work (
    daily_work_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    jc_no         varchar(30) NOT NULL,
    work_date     date NOT NULL,
    work_done     varchar(1000) NOT NULL,
    technician_id bigint REFERENCES employee_master(employee_id),
    hours         numeric(18,4),
    pct_complete  numeric(5,2),
    seq           smallint NOT NULL DEFAULT 1,
    entered_by    bigint,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_jc_daily UNIQUE (job_card_id, work_date, seq)
);
CREATE INDEX ix_daily_job ON job_card_daily_work(job_card_id);

-- ---------- Job card labour ----------
CREATE TABLE job_card_labour (
    labour_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    jc_no         varchar(30) NOT NULL,
    employee_id   bigint NOT NULL REFERENCES employee_master(employee_id),
    work_date     date NOT NULL,
    hours         numeric(18,4) NOT NULL CHECK (hours > 0),
    hourly_rate   numeric(18,4),
    line_cost     numeric(18,4),
    task_ref      varchar(60),
    remarks       varchar(300),
    seq           smallint NOT NULL DEFAULT 1,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_jc_labour UNIQUE (job_card_id, employee_id, work_date, seq)
);
CREATE INDEX ix_labour_job ON job_card_labour(job_card_id);

-- ---------- Job card outside / subcontract repair ----------
CREATE TABLE job_card_outside_repair (
    outside_repair_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_card_id   bigint NOT NULL REFERENCES job_card_header(job_card_id),
    jc_no         varchar(30) NOT NULL,
    supplier_id   bigint NOT NULL REFERENCES supplier_master(supplier_id),
    description   varchar(500) NOT NULL,
    sent_date     date,
    expected_date date,
    received_date date,
    quoted_cost   numeric(18,4),
    actual_cost   numeric(18,4),
    grn_id        bigint REFERENCES grn_header(grn_id),
    status_id     bigint REFERENCES status_master(status_id),
    seq           smallint NOT NULL DEFAULT 1,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_jc_or UNIQUE (job_card_id, supplier_id, seq)
);
CREATE INDEX ix_or_job ON job_card_outside_repair(job_card_id);

-- ---------- Effective-dated price history ----------
CREATE TABLE price_history (
    price_history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id       bigint NOT NULL REFERENCES item_master(item_id),
    price_type    varchar(20) NOT NULL DEFAULT 'PURCHASE'
                  CHECK (price_type IN ('PURCHASE','STANDARD','LAST','WAC')),
    supplier_id   bigint REFERENCES supplier_master(supplier_id),
    unit_price    numeric(18,4) NOT NULL CHECK (unit_price >= 0),
    currency      varchar(3) DEFAULT 'LKR',
    effective_from date NOT NULL,
    effective_to  date,
    source_doc_type varchar(20),
    source_doc_id bigint,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_price UNIQUE (item_id, price_type, supplier_id, effective_from),
    CONSTRAINT ck_price_range CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
CREATE INDEX ix_price_item ON price_history(item_id);
