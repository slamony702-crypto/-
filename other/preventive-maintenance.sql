-- ==========================================
-- Preventive Maintenance + Equipment Registry
-- Safe to re-run.
-- ==========================================

-- 1) Equipment registry per branch
create table if not exists maintenance_equipment (
  id bigserial primary key,
  branch_id bigint references branches(id) on delete set null,
  equipment_name text not null,
  equipment_type text,       -- ac | fridge | freezer | fryer | oven | generator | fire_ext | other
  location text,             -- kitchen | hall | store | office | bathroom | outdoor | other
  serial_number text,
  purchase_date date,
  status text default 'working', -- working | needs_repair | out_of_service
  notes text,
  is_active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_meq_branch on maintenance_equipment(branch_id);

-- 2) Preventive maintenance schedule
create table if not exists maintenance_preventive_schedule (
  id bigserial primary key,
  branch_id bigint references branches(id) on delete set null,
  equipment_id bigint references maintenance_equipment(id) on delete set null,
  task_title text not null,       -- مثال: صيانة دورية للمكيفات
  frequency text default 'monthly', -- weekly | monthly | quarterly | yearly
  scheduled_date date not null,
  completed_date date,
  status text default 'scheduled', -- scheduled | completed | overdue | cancelled
  assigned_to bigint references users(id) on delete set null,
  notes text,
  created_by bigint references users(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_mps_branch on maintenance_preventive_schedule(branch_id);
create index if not exists idx_mps_status on maintenance_preventive_schedule(status);
create index if not exists idx_mps_date on maintenance_preventive_schedule(scheduled_date);

-- RLS: same authenticated-only pattern as the rest of the app
alter table maintenance_equipment enable row level security;
alter table maintenance_preventive_schedule enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'meq_auth_select') then
    create policy meq_auth_select on maintenance_equipment for select to authenticated using (true);
    create policy meq_auth_insert on maintenance_equipment for insert to authenticated with check (true);
    create policy meq_auth_update on maintenance_equipment for update to authenticated using (true) with check (true);
    create policy meq_auth_delete on maintenance_equipment for delete to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'mps_auth_select') then
    create policy mps_auth_select on maintenance_preventive_schedule for select to authenticated using (true);
    create policy mps_auth_insert on maintenance_preventive_schedule for insert to authenticated with check (true);
    create policy mps_auth_update on maintenance_preventive_schedule for update to authenticated using (true) with check (true);
    create policy mps_auth_delete on maintenance_preventive_schedule for delete to authenticated using (true);
  end if;
end $$;
