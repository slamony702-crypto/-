-- ==========================================
-- Quality Module — Schema (editable checklist)
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ==========================================

-- 1) Template: sections
create table if not exists quality_sections (
  id bigserial primary key,
  title text not null,
  sort_order int default 0,
  corrective_options text[] default '{}',
  is_active boolean default true,
  created_at timestamptz default now()
);

-- 2) Template: standard items per section
create table if not exists quality_items (
  id bigserial primary key,
  section_id bigint references quality_sections(id) on delete cascade,
  text text not null,
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_qi_section on quality_items(section_id);

-- 3) Visits
create table if not exists quality_visits (
  id bigserial primary key,
  visit_no text unique,
  branch_id bigint references branches(id) on delete set null,
  inspector_id bigint references users(id) on delete set null,
  inspector_name text,
  visit_type text default 'daily',
  visit_date date default current_date,
  started_at timestamptz,
  ended_at timestamptz,
  status text default 'draft',            -- draft | completed
  total_items int default 0,
  conform_count int default 0,
  follow_up_count int default 0,
  non_conform_count int default 0,
  na_count int default 0,
  compliance_pct numeric default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_qv_branch on quality_visits(branch_id);
create index if not exists idx_qv_status on quality_visits(status);

-- Auto visit number QV-YYYY-000001
create or replace function gen_quality_visit_no()
returns trigger language plpgsql as $$
begin
  if new.visit_no is null then
    new.visit_no := 'QV-' || to_char(now(),'YYYY') || '-' || lpad(new.id::text, 6, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_qv_no on quality_visits;
create trigger trg_qv_no before insert on quality_visits
  for each row execute function gen_quality_visit_no();

-- 4) Per-item result in a visit
create table if not exists quality_visit_items (
  id bigserial primary key,
  visit_id bigint references quality_visits(id) on delete cascade,
  section_id bigint,
  item_id bigint,
  item_text text,
  status text,          -- conform | follow_up | non_conform | na | null
  created_at timestamptz default now()
);
create index if not exists idx_qvi_visit on quality_visit_items(visit_id);

-- 5) Per-section extras in a visit
create table if not exists quality_visit_sections (
  id bigserial primary key,
  visit_id bigint references quality_visits(id) on delete cascade,
  section_id bigint,
  section_title text,
  corrective_actions text,
  severity text,             -- low | medium | high | immediate
  execution_status text,     -- done | in_progress | not_started
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_qvs_visit on quality_visit_sections(visit_id);

-- 6) Attachments (photos) per visit/section
create table if not exists quality_attachments (
  id bigserial primary key,
  visit_id bigint references quality_visits(id) on delete cascade,
  section_id bigint,
  file_url text,
  file_name text,
  file_type text,
  uploaded_by bigint references users(id) on delete set null,
  uploaded_at timestamptz default now()
);
create index if not exists idx_qa_visit on quality_attachments(visit_id);

-- 7) Role permissions for the "quality" section
insert into role_permissions (role, section_key, can_view, can_manage, scope) values
  ('admin','quality', true, true, 'company_wide'),
  ('company_manager','quality', true, true, 'company_wide'),
  ('department_manager','quality', true, true, 'own_department'),
  ('quality_manager','quality', true, true, 'company_wide'),
  ('operations_manager','quality', true, true, 'company_wide'),
  ('maintenance_officer','quality', true, false, 'company_wide'),
  ('employee','quality', true, false, 'own_department')
on conflict do nothing;

-- 8) RLS (permissive default — adjust later)
alter table quality_sections enable row level security;
alter table quality_items enable row level security;
alter table quality_visits enable row level security;
alter table quality_visit_items enable row level security;
alter table quality_visit_sections enable row level security;
alter table quality_attachments enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname='qs_all') then
    create policy qs_all on quality_sections for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname='qi_all') then
    create policy qi_all on quality_items for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname='qv_all') then
    create policy qv_all on quality_visits for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname='qvi_all') then
    create policy qvi_all on quality_visit_items for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname='qvs_all') then
    create policy qvs_all on quality_visit_sections for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname='qa_all') then
    create policy qa_all on quality_attachments for all using (true) with check (true);
  end if;
end $$;
