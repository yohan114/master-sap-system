-- =====================================================================
-- Job-Card-Centric Master Workshop & Stores System
-- 01 — MASTER DATA MODEL
-- PostgreSQL 16. Implements docs/jobcard-centric-import-and-data-model.md §1.
-- Naming: lower_snake_case; surrogate PK <table>_id; business key <entity>_code UNIQUE;
--         money/qty numeric(18,4); standard audit columns on every table; reverse-not-delete.
-- created_by / updated_by are app-user ids (kept as bigint, no FK, to stay self-contained).
-- =====================================================================

-- Optional: trigram similarity for fuzzy duplicate detection during import
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------- Units of measure ----------
CREATE TABLE uom_master (
    uom_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uom_code          varchar(10)  NOT NULL UNIQUE,
    name              varchar(50)  NOT NULL,
    decimal_precision smallint     NOT NULL DEFAULT 2,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Item category (self-nesting) ----------
CREATE TABLE item_category (
    item_category_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_code     varchar(20)  NOT NULL UNIQUE,
    name              varchar(100) NOT NULL,
    parent_category_id bigint REFERENCES item_category(item_category_id),
    valuation_default varchar(10)  NOT NULL DEFAULT 'WAC'
                      CHECK (valuation_default IN ('WAC','FIFO')),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Site / location (Site -> Store/Workshop -> Bin) ----------
CREATE TABLE site_master (
    site_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_code          varchar(15)  NOT NULL UNIQUE,
    name               varchar(120) NOT NULL,
    region             varchar(60),
    location_type      varchar(20)  NOT NULL DEFAULT 'SITE'
                       CHECK (location_type IN ('SITE','STORE','WORKSHOP','BIN','IN_TRANSIT')),
    parent_location_id bigint REFERENCES site_master(site_id),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Job type (MAJOR / MINOR) ----------
CREATE TABLE job_type_master (
    job_type_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_type_code varchar(20)  NOT NULL UNIQUE,
    name          varchar(100) NOT NULL,
    category      varchar(10)  NOT NULL DEFAULT 'MINOR' CHECK (category IN ('MAJOR','MINOR')),
    sla_days      smallint,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Status master (per doc_type) ----------
CREATE TABLE status_master (
    status_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_type        varchar(20)  NOT NULL,        -- JOB_CARD / MRN_LINE / ISSUE / GRN / OUTSIDE_REPAIR
    status_code     varchar(30)  NOT NULL,
    name            varchar(60)  NOT NULL,
    sort_order      smallint     NOT NULL DEFAULT 0,
    is_terminal     boolean      NOT NULL DEFAULT false,
    requires_costing boolean     NOT NULL DEFAULT false,
    ui_color        varchar(20),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_status_doc_code UNIQUE (doc_type, status_code)
);

-- ---------- Supplier / vendor ----------
CREATE TABLE supplier_master (
    supplier_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_code  varchar(20)  NOT NULL UNIQUE,
    name           varchar(150) NOT NULL,
    supplier_type  varchar(20)  NOT NULL DEFAULT 'LOCAL'
                   CHECK (supplier_type IN ('LOCAL','HEAD_OFFICE','SUBCONTRACTOR')),
    tax_id         varchar(30),
    contact_person varchar(120),
    phone          varchar(40),
    email          varchar(120),
    payment_terms  varchar(40),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Item / material master (single master; general items = item_type GENERAL) ----------
CREATE TABLE item_master (
    item_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_code        varchar(30)  NOT NULL UNIQUE,
    description      varchar(200) NOT NULL,
    item_category_id bigint       NOT NULL REFERENCES item_category(item_category_id),
    stock_uom_id     bigint       NOT NULL REFERENCES uom_master(uom_id),
    item_type        varchar(20)  NOT NULL DEFAULT 'STOCK'
                     CHECK (item_type IN ('STOCK','GENERAL','SERIALIZED','LUBRICANT','SERVICE')),
    valuation_method varchar(10)  NOT NULL DEFAULT 'WAC' CHECK (valuation_method IN ('WAC','FIFO')),
    reorder_level    numeric(18,4) DEFAULT 0,
    min_qty          numeric(18,4) DEFAULT 0,
    max_qty          numeric(18,4),
    barcode          varchar(50),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_item_category ON item_master(item_category_id);
CREATE INDEX ix_item_type ON item_master(item_type);
CREATE INDEX ix_item_desc_trgm ON item_master USING gin (description gin_trgm_ops);

-- ---------- Vehicle / machine master ----------
CREATE TABLE vehicle_master (
    vehicle_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_code  varchar(30)  NOT NULL UNIQUE,   -- fleet no / reg no
    reg_no        varchar(20),
    asset_type    varchar(20)  NOT NULL DEFAULT 'VEHICLE'
                  CHECK (asset_type IN ('VEHICLE','MACHINE','WORKSHOP_EQUIP')),
    make          varchar(60),
    model         varchar(60),
    year          smallint,
    chassis_no    varchar(40),
    engine_no     varchar(40),
    fuel_type     varchar(15),
    odometer      numeric(18,2),
    hours_meter   numeric(18,2),
    site_id       bigint REFERENCES site_master(site_id),
    department    varchar(60),
    status        varchar(20)  NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE','IDLE','DISPOSED')),
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);
CREATE INDEX ix_vehicle_site ON vehicle_master(site_id);

-- ---------- Employee / technician master ----------
CREATE TABLE employee_master (
    employee_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_code      varchar(20)  NOT NULL UNIQUE,
    full_name          varchar(120) NOT NULL,
    designation        varchar(60),
    department         varchar(60),
    site_id            bigint REFERENCES site_master(site_id),
    is_technician      boolean NOT NULL DEFAULT false,
    default_hourly_rate numeric(18,4) DEFAULT 0,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true
);

-- ---------- Effective-dated technician labour rate ----------
CREATE TABLE employee_rate (
    rate_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id    bigint NOT NULL REFERENCES employee_master(employee_id),
    hourly_rate    numeric(18,4) NOT NULL,
    effective_from date NOT NULL,
    effective_to   date,
    created_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    updated_by bigint, updated_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ux_emp_rate UNIQUE (employee_id, effective_from),
    CONSTRAINT ck_emp_rate_range CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
