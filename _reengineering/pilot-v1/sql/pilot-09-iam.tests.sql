-- اختبارات IAM — ✅ حارس التصعيد EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول)
--  ESC1 موظف يرفع دوره لـadmin        → PASS (رُفض)
--  ESC2 موظف يعطّل نفسه (is_active)    → PASS (رُفض)
--  ESC3 موظف يعدّل اسمه (حقل ملف)      → PASS (نجح)
--  ESC4 أدمن يغيّر دور مستخدم          → PASS (نجح)
-- ⏳ NOT EXECUTED — REQUIRES SUPABASE STAGING:
--  RLS1 غير الإدارة لا يكتب role_permissions (منع رفع صلاحيات الدور).
--  RLS2 المستخدم يرى تجاوزاته فقط في user_permission_overrides.
--  RLS3 REVOKE SELECT(password_plain): استعلام PostgREST كـauthenticated يفشل
--       على العمود، بينما verify_login (DEFINER) يظل يعمل.
--  RLS4 غير الإدارة لا يُنشئ/يحذف مستخدمين.
\set ON_ERROR_STOP 0
set session pilot.uid='30'; set session pilot.role='employee';
update users set role='admin' where id=30;         -- ESC1 ERROR
update users set is_active=false where id=30;       -- ESC2 ERROR
update users set full_name='محدّث' where id=30;     -- ESC3 OK
set session pilot.uid='10'; set session pilot.role='admin';
update users set role='branch_manager' where id=30; -- ESC4 OK
select 'verify' t, role from users where id=30;     -- branch_manager
update users set role='employee', full_name='موظف فرع1' where id=30;  -- restore
