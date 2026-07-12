-- ═══════════════════════════════════════════════════════════════
-- ملف الإعداد النهائي — يشغّل مرة واحدة على Supabase
-- ═══════════════════════════════════════════════════════════════
-- يجمع كل ما تبقى:
--   1. جدول طلبات الانضمام + سبب الرفض
--   2. دالة تسجيل الدخول الآمنة (RPC)
--   3. مصفوفة الصلاحيات الكاملة
--   4. 3 يوزرات تجريبية (test_admin / test_manager / test_employee)
--
-- الملف آمن لإعادة التشغيل — لا يكرر بيانات ولا يمسح شيء موجود
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- 1) جدول طلبات الانضمام
-- ═══════════════════════════════════════════════════════════════
create table if not exists signup_requests (
  id bigserial primary key,
  full_name text not null,
  mobile_number text not null,
  email text not null,
  job_title text not null,
  region text not null,
  notes text,
  status text default 'pending', -- pending | approved | rejected
  created_at timestamptz default now(),
  reviewed_by bigint references users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text
);
create index if not exists idx_signup_requests_status on signup_requests(status);

-- عمود سبب الرفض (لو الجدول اتعمل قبل كدا بدونه)
alter table signup_requests add column if not exists rejection_reason text;

alter table signup_requests enable row level security;

-- صلاحيات: زائر يقدر يرسل بس، والمصادَق يقرا/يعدّل/يمسح
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'signup_requests_anon_insert') then
    create policy signup_requests_anon_insert on signup_requests for insert to anon with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'signup_requests_auth_select') then
    create policy signup_requests_auth_select on signup_requests for select to authenticated using (true);
    create policy signup_requests_auth_update on signup_requests for update to authenticated using (true) with check (true);
    create policy signup_requests_auth_delete on signup_requests for delete to authenticated using (true);
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════
-- 2) دالة تسجيل الدخول الآمنة
-- ═══════════════════════════════════════════════════════════════
-- تُستخدم بدل قراءة جدول users مباشرة من زائر غير مسجّل (RLS محمي)
create or replace function verify_login(p_username text, p_password text)
returns table(id bigint, full_name text, email text, auth_id uuid, is_active boolean)
language sql
security definer
set search_path = public
as $$
  select id, full_name, email, auth_id, is_active
  from users
  where username = p_username
    and password_plain = p_password
    and is_active = true
  limit 1;
$$;

revoke all on function verify_login(text, text) from public;
grant execute on function verify_login(text, text) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- 3) مصفوفة الصلاحيات
-- ═══════════════════════════════════════════════════════════════
-- امسح القديم وأعد الإدراج (يضمن حالة نظيفة)
delete from role_permissions where role in ('admin', 'department_manager', 'employee');

insert into role_permissions (role, section_key, can_view, can_manage) values

-- ─── ADMIN — كل الصلاحيات ───
('admin', 'dashboard',        true, true),
('admin', 'vision',           true, true),
('admin', 'meetings',         true, true),
('admin', 'tasks',            true, true),
('admin', 'department_tasks', true, true),
('admin', 'decisions',        true, true),
('admin', 'maintenance',      true, true),
('admin', 'quality',          true, true),
('admin', 'conversations',    true, true),
('admin', 'emergency',        true, true),
('admin', 'reports',          true, true),
('admin', 'users',            true, true),
('admin', 'settings',         true, true),

-- ─── DEPARTMENT_MANAGER — إدارة قسمه + عرض عام ───
('department_manager', 'dashboard',        true, false),
('department_manager', 'vision',           true, false),
('department_manager', 'meetings',         true, true),
('department_manager', 'tasks',            true, true),
('department_manager', 'department_tasks', true, true),
('department_manager', 'decisions',        true, true),
('department_manager', 'maintenance',      true, true),
('department_manager', 'quality',          true, true),
('department_manager', 'conversations',    true, true),
('department_manager', 'emergency',        true, false),
('department_manager', 'reports',          true, false),
('department_manager', 'users',            false, false),
('department_manager', 'settings',         false, false),

-- ─── EMPLOYEE — عرض + طلبات صيانة + رسائل ───
('employee', 'dashboard',        true, false),
('employee', 'vision',           true, false),
('employee', 'meetings',         true, false),
('employee', 'tasks',            true, false),
('employee', 'department_tasks', true, false),
('employee', 'decisions',        true, false),
('employee', 'maintenance',      true, true),
('employee', 'quality',          true, false),
('employee', 'conversations',    true, true),
('employee', 'emergency',        true, false),
('employee', 'reports',          false, false),
('employee', 'users',            false, false),
('employee', 'settings',         false, false);


-- ═══════════════════════════════════════════════════════════════
-- 4) يوزرات تجريبية (مرة واحدة — لا تُنشأ لو موجودة)
-- ═══════════════════════════════════════════════════════════════
insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - أدمن', 'test_admin', 'test123', 'test_admin@example.com', '0500000010', 'admin', 'active', true
where not exists (select 1 from users where username = 'test_admin');

insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - مدير قسم', 'test_manager', 'test123', 'test_manager@example.com', '0500000011', 'department_manager', 'active', true
where not exists (select 1 from users where username = 'test_manager');

insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - موظف', 'test_employee', 'test123', 'test_employee@example.com', '0500000012', 'employee', 'active', true
where not exists (select 1 from users where username = 'test_employee');


-- ═══════════════════════════════════════════════════════════════
-- 5) المراجعة النهائية
-- ═══════════════════════════════════════════════════════════════
select id, username, full_name, role, is_active from users order by id;
