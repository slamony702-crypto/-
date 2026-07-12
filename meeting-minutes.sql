-- ==========================================
-- Meeting Minutes: add columns to meetings table
-- Safe to re-run.
-- ==========================================
alter table meetings add column if not exists minutes_file_url text;
alter table meetings add column if not exists minutes_file_name text;
alter table meetings add column if not exists minutes_uploaded_at timestamptz;
alter table meetings add column if not exists minutes_uploaded_by bigint references users(id) on delete set null;
alter table meetings add column if not exists minutes_notes text;
