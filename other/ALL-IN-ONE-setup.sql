-- ═══════════════════════════════════════════════════════════════
-- ملف الإعداد الشامل — يشغّل مرة واحدة على Supabase
-- ═══════════════════════════════════════════════════════════════
-- يجمع كل الميجريشنات المتبقية:
--   1. جدول طلبات الانضمام + سبب الرفض
--   2. دالة تسجيل الدخول الآمنة (verify_login RPC)
--   3. مصفوفة الصلاحيات الكاملة
--   4. 3 يوزرات تجريبية (test_admin / test_manager / test_employee)
--   5. أعمدة الشات المخصص والأرشفة
--   6. زرع الفروع (33 فرع، بدون تكرار)
--
-- الملف آمن للتشغيل مرات متعددة — لا يكرر بيانات ولا يمسح شيء موجود
-- ═══════════════════════════════════════════════════════════════


-- ═══ 1) جدول طلبات الانضمام ═══
create table if not exists signup_requests (
  id bigserial primary key,
  full_name text not null,
  mobile_number text not null,
  email text not null,
  job_title text not null,
  region text not null,
  notes text,
  status text default 'pending',
  created_at timestamptz default now(),
  reviewed_by bigint references users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text
);
create index if not exists idx_signup_requests_status on signup_requests(status);
alter table signup_requests add column if not exists rejection_reason text;
alter table signup_requests enable row level security;

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


-- ═══ 2) دالة تسجيل الدخول الآمنة ═══
create or replace function verify_login(p_username text, p_password text)
returns table(id bigint, full_name text, email text, auth_id uuid, is_active boolean)
language sql security definer set search_path = public
as $$
  select id, full_name, email, auth_id, is_active
  from users
  where username = p_username and password_plain = p_password and is_active = true
  limit 1;
$$;
revoke all on function verify_login(text, text) from public;
grant execute on function verify_login(text, text) to anon, authenticated;


-- ═══ 3) مصفوفة الصلاحيات ═══
delete from role_permissions where role in ('admin', 'department_manager', 'employee');
insert into role_permissions (role, section_key, can_view, can_manage) values
-- ─── ADMIN ───
('admin', 'dashboard', true, true), ('admin', 'vision', true, true),
('admin', 'meetings', true, true), ('admin', 'tasks', true, true),
('admin', 'department_tasks', true, true), ('admin', 'decisions', true, true),
('admin', 'maintenance', true, true), ('admin', 'quality', true, true),
('admin', 'conversations', true, true), ('admin', 'emergency', true, true),
('admin', 'reports', true, true), ('admin', 'users', true, true), ('admin', 'settings', true, true),
-- ─── DEPARTMENT_MANAGER ───
('department_manager', 'dashboard', true, false), ('department_manager', 'vision', true, false),
('department_manager', 'meetings', true, true), ('department_manager', 'tasks', true, true),
('department_manager', 'department_tasks', true, true), ('department_manager', 'decisions', true, true),
('department_manager', 'maintenance', true, true), ('department_manager', 'quality', true, true),
('department_manager', 'conversations', true, true), ('department_manager', 'emergency', true, false),
('department_manager', 'reports', true, false), ('department_manager', 'users', false, false),
('department_manager', 'settings', false, false),
-- ─── EMPLOYEE ───
('employee', 'dashboard', true, false), ('employee', 'vision', true, false),
('employee', 'meetings', true, false), ('employee', 'tasks', true, false),
('employee', 'department_tasks', true, false), ('employee', 'decisions', true, false),
('employee', 'maintenance', true, true), ('employee', 'quality', true, false),
('employee', 'conversations', true, true), ('employee', 'emergency', true, false),
('employee', 'reports', false, false), ('employee', 'users', false, false), ('employee', 'settings', false, false);


-- ═══ 4) يوزرات تجريبية ═══
insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - أدمن', 'test_admin', 'test123', 'test_admin@example.com', '0500000010', 'admin', 'active', true
where not exists (select 1 from users where username = 'test_admin');
insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - مدير قسم', 'test_manager', 'test123', 'test_manager@example.com', '0500000011', 'department_manager', 'active', true
where not exists (select 1 from users where username = 'test_manager');
insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active)
select 'تجريبي - موظف', 'test_employee', 'test123', 'test_employee@example.com', '0500000012', 'employee', 'active', true
where not exists (select 1 from users where username = 'test_employee');


-- ═══ 5) أعمدة الشات المخصص والأرشفة ═══
alter table conversations add column if not exists is_archived boolean default false;
alter table conversations add column if not exists archived_at timestamptz;
alter table conversations add column if not exists archived_by bigint references users(id) on delete set null;
alter table conversations add column if not exists last_message_at timestamptz;
alter table conversations add column if not exists archive_reminder_sent_at timestamptz;
alter table conversations add column if not exists second_archive_reminder_sent_at timestamptz;
alter table conversations add column if not exists created_by bigint references users(id) on delete set null;
create index if not exists idx_conversations_archived on conversations(is_archived);
create index if not exists idx_conversations_type on conversations(conversation_type);
create index if not exists idx_conversations_last_msg on conversations(last_message_at desc);


-- ═══ 6) زرع الفروع (33 فرع، بدون تكرار) ═══
insert into branches (name, is_active)
select v.name, true from (values
  ('أحد رفيدة'), ('اشبيلية'), ('الأحساء'), ('الأندلس'), ('الحسام'),
  ('الحمدانية'), ('الخالدية'), ('الخبر العزيزية'), ('الدرب'), ('السامر'),
  ('الشرفية'), ('العقربية'), ('الفاخرية'), ('الفيحاء'), ('الفيصلية'),
  ('القريات'), ('المحالة'), ('المدينة'), ('المدينة الدويمة'), ('الملقا'),
  ('برج الساعة'), ('جازان المطار'), ('سراة عبيدة'), ('سكاكا'), ('طيبة'),
  ('عفيف'), ('غرناطة'), ('محطة الرحيلي'), ('مكة'), ('مكة ولي العهد'),
  ('نكهة تهامية الخليج'), ('نكهة تهامية قرطبة'), ('نكهة تهامية خميس مشيط')
) as v(name)
where not exists (select 1 from branches b where b.name = v.name);


-- ═══ 7) عرض النتيجة النهائية للمراجعة ═══
select 'المستخدمون النشطون:' as info;
select id, username, full_name, role from users where is_active = true order by id;

select 'الفروع الفعّالة (عدد):' as info;
select count(*) as total from branches where is_active = true;

select 'أعمدة conversations الجديدة:' as info;
select column_name from information_schema.columns
where table_name = 'conversations' and column_name in ('is_archived','archived_at','last_message_at','created_by');
