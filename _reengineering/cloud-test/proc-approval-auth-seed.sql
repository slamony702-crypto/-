-- ═══════════════════════════════════════════════════════════
-- Auth Users Seed لـSupabase Cloud Staging
-- ═══════════════════════════════════════════════════════════
-- يُنشئ:
--   1) سجلات في auth.users (Supabase Auth) بـUUIDs محددة
--   2) سجلات مقابلة في users (app) مربوطة بـauth_id
--
-- ⚠️ استخدم فقط على Staging — لا Production
-- ⚠️ لا passwords حقيقية — نستخدم encrypted_password صوري
--    (تسجيل الدخول عبر UI سيحتاج password reset أو magic link)
-- ═══════════════════════════════════════════════════════════
-- المستخدمون المُنشَؤون:
--   requester@staging-shouon.local        — employee
--   dept_manager@staging-shouon.local     — department_manager
--   proc_manager@staging-shouon.local     — procurement_manager
--   fin_manager@staging-shouon.local      — finance_manager
--   gen_manager@staging-shouon.local      — company_manager
--   unauthorized@staging-shouon.local     — employee (لن يمر role checks)
--   inactive_pm@staging-shouon.local      — procurement_manager (is_active=FALSE)
--   other_branch@staging-shouon.local     — branch_manager في فرع مختلف
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- Seed branches + departments إذا لم توجد
INSERT INTO branches (id, name, is_active) VALUES
  (901, 'STAGING Branch A', TRUE),
  (902, 'STAGING Branch B', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO departments (id, name) VALUES
  (901, 'STAGING Purchasing'),
  (902, 'STAGING Finance')
ON CONFLICT (id) DO NOTHING;

-- ─── auth.users ─────────────────────────────────────────────
-- ملاحظة: Supabase تُدير auth.users بشكل خاص. نُدخل بأبسط شكل
-- ممكن — password reset لاحقًا من UI.
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES
  ('a0000001-0000-4000-a000-000000000001'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'requester@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000002'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'dept_manager@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000003'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'proc_manager@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000004'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'fin_manager@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000005'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'gen_manager@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000006'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'unauthorized@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000007'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'inactive_pm@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB),
  ('a0000001-0000-4000-a000-000000000008'::UUID,
   '00000000-0000-0000-0000-000000000000'::UUID,
   'authenticated', 'authenticated',
   'other_branch@staging-shouon.local',
   crypt('staging_placeholder_reset_needed', gen_salt('bf')),
   now(), now(), now(),
   '{"provider":"email"}'::JSONB, '{}'::JSONB)
ON CONFLICT (id) DO NOTHING;

-- ─── users (app) مربوطة بـauth ─────────────────────────────
INSERT INTO users (id, auth_id, full_name, email, role, branch_id, department_id, is_active) VALUES
  (901, 'a0000001-0000-4000-a000-000000000001'::UUID, 'STAGING Requester',      'requester@staging-shouon.local',     'employee',            901, 901, TRUE),
  (902, 'a0000001-0000-4000-a000-000000000002'::UUID, 'STAGING Dept Manager',   'dept_manager@staging-shouon.local',  'branch_manager',      901, 901, TRUE),
  (903, 'a0000001-0000-4000-a000-000000000003'::UUID, 'STAGING Proc Manager',   'proc_manager@staging-shouon.local',  'procurement_manager', 901, 901, TRUE),
  (904, 'a0000001-0000-4000-a000-000000000004'::UUID, 'STAGING Fin Manager',    'fin_manager@staging-shouon.local',   'finance_manager',     901, 902, TRUE),
  (905, 'a0000001-0000-4000-a000-000000000005'::UUID, 'STAGING Gen Manager',    'gen_manager@staging-shouon.local',   'company_manager',     901, NULL,TRUE),
  (906, 'a0000001-0000-4000-a000-000000000006'::UUID, 'STAGING Unauthorized',   'unauthorized@staging-shouon.local',  'employee',            901, 901, TRUE),
  (907, 'a0000001-0000-4000-a000-000000000007'::UUID, 'STAGING Inactive PM',    'inactive_pm@staging-shouon.local',   'procurement_manager', 901, 901, FALSE),
  (908, 'a0000001-0000-4000-a000-000000000008'::UUID, 'STAGING Other Branch',   'other_branch@staging-shouon.local',  'branch_manager',      902, NULL,TRUE)
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- ─── Verification ─────────────────────────────────────────
SELECT 'auth.users seeded' AS check_type, COUNT(*) AS count
FROM auth.users WHERE id::TEXT LIKE 'a0000001-%';

SELECT 'app users linked' AS check_type, COUNT(*) AS count,
       STRING_AGG(role || ':' || COALESCE(is_active::TEXT, 'null'), ', ') AS roles_status
FROM users WHERE id BETWEEN 901 AND 908;

-- تنبيه:
-- passwords غير مضبوطة للتسجيل عبر UI مباشرة.
-- لتفعيل تسجيل الدخول عبر الواجهة:
--   1) من Dashboard → Auth → Users → عدّل password أو أرسل magic link
--   2) أو استخدم Supabase Admin API لتعيين passwords عبر service_role key
