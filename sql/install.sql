-- Install the job-card-centric schema in dependency order.
-- Usage:  psql -d <db> -v ON_ERROR_STOP=1 -f sql/install.sql
--   then (optional worked example / self-test):  psql -d <db> -f sql/06_seed_example.sql
\i 01_masters.sql
\i 02_transactions.sql
\i 03_costing.sql
\i 04_import_staging.sql
\i 05_views_functions.sql
\i 07_loader.sql
\i 08_posting.sql
