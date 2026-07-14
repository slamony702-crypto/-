-- ==========================================
-- Missing tables: company_vision + department_goals
-- (صفحة رؤية الشركة وأهداف الأقسام)
-- ==========================================

create table if not exists company_vision (
  id bigserial primary key,
  vision_text text,
  updated_by bigint references users(id) on delete set null,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

create table if not exists department_goals (
  id bigserial primary key,
  department_id bigint references departments(id) on delete cascade,
  title text not null,
  description text,
  assigned_to bigint references users(id) on delete set null,
  priority text,
  start_date date,
  duration_days int,
  target_date date,
  status text default 'in_progress',
  progress_percent int default 0,
  notes text,
  created_by bigint references users(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_dg_dept on department_goals(department_id);

alter table company_vision enable row level security;
alter table department_goals enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'cv_all') then
    create policy cv_all on company_vision for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'dg_all') then
    create policy dg_all on department_goals for all using (true) with check (true);
  end if;
end $$;
