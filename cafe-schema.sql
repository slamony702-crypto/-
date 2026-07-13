-- ═══════════════════════════════════════════════════════════
-- ركن الكافيه — الجداول والصلاحيات
-- Safe to re-run.
-- ═══════════════════════════════════════════════════════════

-- 1) منتجات الكافيه
create table if not exists cafe_items (
  id bigserial primary key,
  name text not null,
  category text default 'other',              -- hot_drinks | cold_drinks | snacks | meals | sweets | other
  description text,
  price numeric(10,2) default 0,
  available_quantity integer default 0,
  is_available boolean default true,
  image_url text,
  internal_notes text,
  created_by bigint references users(id) on delete set null,
  is_draft boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_cafe_items_available on cafe_items(is_available);
create index if not exists idx_cafe_items_category on cafe_items(category);

-- 2) طلبات الكافيه
create table if not exists cafe_orders (
  id bigserial primary key,
  order_number text unique,                   -- CF-YYYY-0001
  requested_by bigint references users(id) on delete set null,
  department_id bigint references departments(id) on delete set null,
  status text default 'new',                  -- new | preparing | ready | delivered | cancelled
  notes text,
  delivery_location text,
  total_amount numeric(10,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_cafe_orders_status on cafe_orders(status);
create index if not exists idx_cafe_orders_requester on cafe_orders(requested_by);
create index if not exists idx_cafe_orders_created on cafe_orders(created_at desc);

-- 3) بنود الطلب
create table if not exists cafe_order_items (
  id bigserial primary key,
  order_id bigint references cafe_orders(id) on delete cascade,
  item_id bigint references cafe_items(id) on delete set null,
  item_name text,                              -- نحفظه لضمان استمرار العرض حتى لو حُذف المنتج
  quantity integer default 1,
  unit_price numeric(10,2) default 0,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_cafe_order_items_order on cafe_order_items(order_id);

-- 4) سجل حالة الطلب
create table if not exists cafe_order_status_log (
  id bigserial primary key,
  order_id bigint references cafe_orders(id) on delete cascade,
  status text not null,
  changed_by bigint references users(id) on delete set null,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_cafe_status_log_order on cafe_order_status_log(order_id);

-- 5) دالة توليد رقم الطلب CF-YYYY-####
create or replace function generate_cafe_order_number()
returns text language plpgsql as $$
declare
  y text := to_char(now(), 'YYYY');
  n int;
  next_num int;
begin
  select coalesce(max(cast(split_part(order_number, '-', 3) as int)), 0)
    into n from cafe_orders where order_number like 'CF-' || y || '-%';
  next_num := n + 1;
  return 'CF-' || y || '-' || lpad(next_num::text, 4, '0');
end $$;

-- 6) RLS — نمط النظام: مصادَق فقط
alter table cafe_items enable row level security;
alter table cafe_orders enable row level security;
alter table cafe_order_items enable row level security;
alter table cafe_order_status_log enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'cafe_items_auth_select') then
    create policy cafe_items_auth_select on cafe_items for select to authenticated using (true);
    create policy cafe_items_auth_insert on cafe_items for insert to authenticated with check (true);
    create policy cafe_items_auth_update on cafe_items for update to authenticated using (true) with check (true);
    create policy cafe_items_auth_delete on cafe_items for delete to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_orders_auth_select') then
    create policy cafe_orders_auth_select on cafe_orders for select to authenticated using (true);
    create policy cafe_orders_auth_insert on cafe_orders for insert to authenticated with check (true);
    create policy cafe_orders_auth_update on cafe_orders for update to authenticated using (true) with check (true);
    create policy cafe_orders_auth_delete on cafe_orders for delete to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_order_items_auth_select') then
    create policy cafe_order_items_auth_select on cafe_order_items for select to authenticated using (true);
    create policy cafe_order_items_auth_insert on cafe_order_items for insert to authenticated with check (true);
    create policy cafe_order_items_auth_update on cafe_order_items for update to authenticated using (true) with check (true);
    create policy cafe_order_items_auth_delete on cafe_order_items for delete to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_order_status_log_auth_select') then
    create policy cafe_order_status_log_auth_select on cafe_order_status_log for select to authenticated using (true);
    create policy cafe_order_status_log_auth_insert on cafe_order_status_log for insert to authenticated with check (true);
  end if;
end $$;

-- 7) صلاحيات role_permissions لدور موظف الكافيه (اختياري)
delete from role_permissions where role = 'cafe_staff' and section_key = 'cafe';
insert into role_permissions (role, section_key, can_view, can_manage) values
  ('cafe_staff', 'cafe', true, true),
  ('cafe_staff', 'dashboard', true, false),
  ('cafe_staff', 'conversations', true, true);

-- إضافة صلاحية cafe لكل الأدوار الحالية (view + manage للأدمن، view لغيرهم)
delete from role_permissions where section_key = 'cafe' and role in ('admin','company_manager','department_manager','employee');
insert into role_permissions (role, section_key, can_view, can_manage) values
  ('admin', 'cafe', true, true),
  ('company_manager', 'cafe', true, true),
  ('department_manager', 'cafe', true, false),
  ('employee', 'cafe', true, false);
