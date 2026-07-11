-- ==========================================
-- Maintenance Module — Schema
-- Run this once in Supabase SQL Editor.
-- Safe to re-run (uses IF NOT EXISTS).
-- ==========================================

-- 1) Branches
create table if not exists branches (
  id bigserial primary key,
  name text not null,
  address text,
  manager_id bigint references users(id) on delete set null,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- 2) Suppliers
create table if not exists maintenance_suppliers (
  id bigserial primary key,
  name text not null,
  activity text,
  phone text,
  email text,
  rating numeric(2,1) default 0,
  works_count int default 0,
  notes text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- 3) Maintenance Requests
create table if not exists maintenance_requests (
  id bigserial primary key,
  request_no text unique,
  branch_id bigint references branches(id) on delete set null,
  affected_area text,
  description text,
  cause text,
  severity text default 'normal',
  affects_operation boolean default false,
  status text default 'new',
  requester_id bigint references users(id) on delete set null,
  current_owner_id bigint references users(id) on delete set null,
  reported_at timestamptz default now(),
  reject_reason text,
  estimated_cost numeric,
  final_cost numeric,
  selected_quote_id bigint,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_mr_status on maintenance_requests(status);
create index if not exists idx_mr_branch on maintenance_requests(branch_id);
create index if not exists idx_mr_severity on maintenance_requests(severity);

-- Auto-generate request_no like MR-2026-000012
create or replace function gen_maintenance_request_no()
returns trigger language plpgsql as $$
begin
  if new.request_no is null then
    new.request_no := 'MR-' || to_char(now(),'YYYY') || '-' || lpad(new.id::text, 6, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_mr_request_no on maintenance_requests;
create trigger trg_mr_request_no
  before insert on maintenance_requests
  for each row execute function gen_maintenance_request_no();

-- 4) Inspections
create table if not exists maintenance_inspections (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  cause text,
  fix_type text,
  estimated_cost numeric,
  needs_spare_parts boolean default false,
  spare_parts_details text,
  recommendation text,
  notes text,
  inspector_id bigint references users(id) on delete set null,
  created_at timestamptz default now()
);

-- 5) Quotes
create table if not exists maintenance_quotes (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  supplier_id bigint references maintenance_suppliers(id) on delete set null,
  supplier_name text,
  price numeric,
  duration_days int,
  warranty_months int,
  spare_parts_details text,
  notes text,
  attachment_url text,
  is_selected boolean default false,
  created_at timestamptz default now()
);

-- 6) Finance approvals
create table if not exists maintenance_finance_approvals (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  approved boolean,
  approved_amount numeric,
  payment_method text,
  po_number text,
  reject_reason text,
  approver_id bigint references users(id) on delete set null,
  created_at timestamptz default now()
);

-- 7) Repairs
create table if not exists maintenance_repairs (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  technician_name text,
  supplier_id bigint references maintenance_suppliers(id) on delete set null,
  started_at timestamptz,
  ended_at timestamptz,
  branch_partially_closed boolean default false,
  execution_notes text,
  what_was_fixed text,
  final_cost numeric,
  spare_parts_used text,
  before_photos_url text,
  after_photos_url text,
  warranty_details text,
  technician_notes text,
  created_at timestamptz default now()
);

-- 8) Receipts (branch closure confirmation)
create table if not exists maintenance_receipts (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  closure_status text,
  confirmer_id bigint references users(id) on delete set null,
  notes text,
  created_at timestamptz default now()
);

-- 9) Attachments
create table if not exists maintenance_attachments (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  stage text,
  file_url text,
  file_name text,
  file_type text,
  uploaded_by bigint references users(id) on delete set null,
  uploaded_at timestamptz default now()
);

-- 10) Timeline
create table if not exists maintenance_timeline (
  id bigserial primary key,
  request_id bigint references maintenance_requests(id) on delete cascade,
  event_type text,
  from_status text,
  to_status text,
  note text,
  actor_id bigint references users(id) on delete set null,
  created_at timestamptz default now()
);
create index if not exists idx_mt_request on maintenance_timeline(request_id);

-- 11) Role permissions for the new "maintenance" section
insert into role_permissions (role, section_key, can_view, can_manage, scope) values
  ('admin','maintenance', true, true, 'company_wide'),
  ('company_manager','maintenance', true, true, 'company_wide'),
  ('department_manager','maintenance', true, true, 'own_department'),
  ('maintenance_officer','maintenance', true, true, 'company_wide'),
  ('operations_manager','maintenance', true, true, 'company_wide'),
  ('finance','maintenance', true, false, 'company_wide'),
  ('employee','maintenance', true, false, 'own_department')
on conflict do nothing;

-- Optional: enable RLS with permissive default (adjust as needed)
alter table maintenance_requests enable row level security;
alter table maintenance_suppliers enable row level security;
alter table maintenance_inspections enable row level security;
alter table maintenance_quotes enable row level security;
alter table maintenance_finance_approvals enable row level security;
alter table maintenance_repairs enable row level security;
alter table maintenance_receipts enable row level security;
alter table maintenance_attachments enable row level security;
alter table maintenance_timeline enable row level security;
alter table branches enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'mr_all') then
    create policy mr_all on maintenance_requests for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'ms_all') then
    create policy ms_all on maintenance_suppliers for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mi_all') then
    create policy mi_all on maintenance_inspections for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mq_all') then
    create policy mq_all on maintenance_quotes for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mfa_all') then
    create policy mfa_all on maintenance_finance_approvals for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mrep_all') then
    create policy mrep_all on maintenance_repairs for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mrc_all') then
    create policy mrc_all on maintenance_receipts for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mat_all') then
    create policy mat_all on maintenance_attachments for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mtl_all') then
    create policy mtl_all on maintenance_timeline for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'br_all') then
    create policy br_all on branches for all using (true) with check (true);
  end if;
end $$;
