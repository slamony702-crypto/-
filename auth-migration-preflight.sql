-- ═══════════════════════════════════════════════════════════
-- Auth Migration (B1) — Preflight Check (READ ONLY)
-- ═══════════════════════════════════════════════════════════
-- ⚠️ Read-Only بالكامل: لا INSERT / UPDATE / DELETE / ALTER / DROP / CREATE / GRANT / REVOKE
-- ⚠️ آمن على أي بيئة (لا يعدّل شيئًا) — لكن شغّله على Staging لأنك ستطبّق migrations هناك
-- ⚠️ مصمَّم لـSupabase SQL Editor — كل النتائج في جدول واحد (UNION ALL)
-- ═══════════════════════════════════════════════════════════
-- يقيس جاهزية بيانات المستخدمين للانتقال إلى Supabase Auth عبر دعوة/رابط تعيين.
-- لا يقرأ ولا يعرض أي كلمة مرور.
-- ═══════════════════════════════════════════════════════════

WITH
  -- (1) هل جدول users موجود ونوع المفتاح
  q1 AS (
    SELECT '01. USERS_TABLE' AS check_step,
           'users' AS item,
           CASE WHEN EXISTS (SELECT 1 FROM pg_class WHERE relname='users' AND relnamespace='public'::regnamespace)
                THEN 'EXISTS' ELSE 'MISSING' END AS status,
           COALESCE((SELECT data_type FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='users' AND column_name='id'), '-') AS detail
  ),
  -- (2) الأعمدة المتعلقة بالمصادقة الموجودة حاليًا
  q2 AS (
    SELECT '02. AUTH_COLUMN' AS check_step,
           c.name AS item,
           CASE WHEN col.column_name IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status,
           COALESCE(col.data_type, '-') AS detail
    FROM (VALUES ('id'),('email'),('username'),('auth_id'),('auth_user_id'),
                 ('password_plain'),('is_active'),('role'),('branch_id'),('department_id'),
                 ('auth_status'),('auth_invited_at'),('auth_linked_at'),
                 ('auth_last_error'),('auth_migration_required')) c(name)
    LEFT JOIN information_schema.columns col
      ON col.table_schema='public' AND col.table_name='users' AND col.column_name=c.name
  ),
  -- (3) إجمالي المستخدمين + النشطون/غير النشطين
  q3 AS (
    SELECT '03. USER_COUNTS' AS check_step, 'total_users' AS item,
           COUNT(*)::TEXT AS status, '' AS detail FROM users
    UNION ALL
    SELECT '03. USER_COUNTS', 'active_users',
           COUNT(*) FILTER (WHERE COALESCE(is_active,TRUE)=TRUE)::TEXT, '' FROM users
    UNION ALL
    SELECT '03. USER_COUNTS', 'inactive_users',
           COUNT(*) FILTER (WHERE COALESCE(is_active,TRUE)=FALSE)::TEXT, '' FROM users
  ),
  -- (4) البريد الإلكتروني: ناقص / مكرر / غير صالح
  q4 AS (
    SELECT '04. EMAIL_HEALTH' AS check_step, 'active_missing_email' AS item,
           COUNT(*)::TEXT AS status,
           'مستخدم نشط بلا بريد — لا يمكن دعوته' AS detail
    FROM users
    WHERE COALESCE(is_active,TRUE)=TRUE AND (email IS NULL OR length(trim(email))=0)
    UNION ALL
    SELECT '04. EMAIL_HEALTH', 'active_invalid_email',
           COUNT(*)::TEXT,
           'بريد لا يطابق نمط email بسيط'
    FROM users
    WHERE COALESCE(is_active,TRUE)=TRUE
      AND email IS NOT NULL AND length(trim(email))>0
      AND email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    UNION ALL
    SELECT '04. EMAIL_HEALTH', 'duplicate_emails',
           COUNT(*)::TEXT,
           'عناوين بريد مكررة بين المستخدمين النشطين (تمنع UNIQUE على Auth)'
    FROM (
      SELECT lower(trim(email)) AS e
      FROM users
      WHERE COALESCE(is_active,TRUE)=TRUE AND email IS NOT NULL AND length(trim(email))>0
      GROUP BY lower(trim(email))
      HAVING COUNT(*) > 1
    ) d
  ),
  -- (5) حالة الربط بـauth_id
  q5 AS (
    SELECT '05. AUTH_LINK' AS check_step, 'active_linked' AS item,
           COUNT(*) FILTER (WHERE auth_id IS NOT NULL)::TEXT AS status,
           'مستخدم نشط مربوط بـauth.users بالفعل' AS detail
    FROM users WHERE COALESCE(is_active,TRUE)=TRUE
    UNION ALL
    SELECT '05. AUTH_LINK', 'active_not_linked',
           COUNT(*) FILTER (WHERE auth_id IS NULL)::TEXT,
           'مستخدم نشط غير مربوط — يحتاج دعوة/ترحيل'
    FROM users WHERE COALESCE(is_active,TRUE)=TRUE
  ),
  -- (6) سجلات auth.users الموجودة
  q6 AS (
    SELECT '06. AUTH_USERS' AS check_step, 'auth_users_total' AS item,
           CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                             WHERE n.nspname='auth' AND c.relname='users')
                THEN (SELECT COUNT(*)::TEXT FROM auth.users)
                ELSE 'auth.users NOT ACCESSIBLE' END AS status,
           'إجمالي حسابات Supabase Auth' AS detail
  ),
  -- (7) المستخدمون النشطون المربوطون فعليًا بسجل auth.users سليم
  q7 AS (
    SELECT '07. LINK_INTEGRITY' AS check_step, 'linked_with_valid_auth' AS item,
           CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                             WHERE n.nspname='auth' AND c.relname='users')
                THEN (SELECT COUNT(*)::TEXT FROM users u
                      WHERE u.auth_id IS NOT NULL
                        AND EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.auth_id))
                ELSE 'N/A' END AS status,
           'auth_id يشير إلى سجل auth.users فعلي' AS detail
    UNION ALL
    SELECT '07. LINK_INTEGRITY', 'linked_with_dangling_auth',
           CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                             WHERE n.nspname='auth' AND c.relname='users')
                THEN (SELECT COUNT(*)::TEXT FROM users u
                      WHERE u.auth_id IS NOT NULL
                        AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.auth_id))
                ELSE 'N/A' END,
           'auth_id يشير إلى سجل محذوف (يحتاج معالجة)'
  ),
  -- (8) دوال المصادقة الموجودة
  q8 AS (
    SELECT '08. AUTH_FUNCTION' AS check_step, p.name AS item,
           CASE WHEN pr.proname IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status,
           '' AS detail
    FROM (VALUES ('current_app_user_id'),('current_app_role'),('verify_login')) p(name)
    LEFT JOIN pg_proc pr ON pr.proname=p.name AND pr.pronamespace='public'::regnamespace
  ),
  -- (9) auth.uid متاحة؟
  q9 AS (
    SELECT '09. AUTH_UID' AS check_step, 'auth.uid()' AS item,
           CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                             WHERE n.nspname='auth' AND p.proname='uid')
                THEN 'EXISTS' ELSE 'MISSING' END AS status,
           'Supabase Auth JWT function' AS detail
  ),
  -- (10) verify_login: من يستطيع استدعاءها (تعتمد على password_plain)
  q10 AS (
    SELECT '10. VERIFY_LOGIN_GRANTS' AS check_step,
           COALESCE(grantee, '(none)') AS item,
           COALESCE(privilege_type, '-') AS status,
           'صلاحية تنفيذ verify_login' AS detail
    FROM information_schema.routine_privileges
    WHERE routine_schema='public' AND routine_name='verify_login'
  ),
  -- (11) عدد RLS policies التي تعتمد على دوال الهوية
  q11 AS (
    SELECT '11. RLS_DEPENDENCY' AS check_step, 'policies_using_identity_helpers' AS item,
           COUNT(*)::TEXT AS status,
           'policies تستدعي current_app_user_id/current_app_role' AS detail
    FROM pg_policies
    WHERE schemaname='public'
      AND (qual::text LIKE '%current_app_user_id%' OR qual::text LIKE '%current_app_role%'
           OR with_check::text LIKE '%current_app_user_id%' OR with_check::text LIKE '%current_app_role%')
  ),
  -- (12) الأدوار الحالية
  q12 AS (
    SELECT '12. ROLES' AS check_step, COALESCE(role,'(null)') AS item,
           COUNT(*)::TEXT AS status,
           'active=' || COUNT(*) FILTER (WHERE COALESCE(is_active,TRUE)=TRUE) AS detail
    FROM users GROUP BY role
  ),
  -- (13) is_active توزيع الفروع/الأقسام للمستخدمين النشطين
  q13 AS (
    SELECT '13. SCOPE' AS check_step, 'active_with_branch' AS item,
           COUNT(*) FILTER (WHERE branch_id IS NOT NULL)::TEXT AS status,
           'مستخدم نشط له فرع' AS detail
    FROM users WHERE COALESCE(is_active,TRUE)=TRUE
    UNION ALL
    SELECT '13. SCOPE', 'active_with_department',
           COUNT(*) FILTER (WHERE department_id IS NOT NULL)::TEXT,
           'مستخدم نشط له قسم'
    FROM users WHERE COALESCE(is_active,TRUE)=TRUE
  ),
  -- (14) المستخدمون غير القابلين للدعوة (نشط + غير مربوط + بلا بريد صالح)
  q14 AS (
    SELECT '14. NOT_INVITABLE' AS check_step, 'active_unlinked_no_valid_email' AS item,
           COUNT(*)::TEXT AS status,
           'نشط + بلا auth_id + بلا بريد صالح — يحتاج قرار المالك' AS detail
    FROM users
    WHERE COALESCE(is_active,TRUE)=TRUE
      AND auth_id IS NULL
      AND (email IS NULL OR email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
  )
SELECT * FROM q1
UNION ALL SELECT * FROM q2
UNION ALL SELECT * FROM q3
UNION ALL SELECT * FROM q4
UNION ALL SELECT * FROM q5
UNION ALL SELECT * FROM q6
UNION ALL SELECT * FROM q7
UNION ALL SELECT * FROM q8
UNION ALL SELECT * FROM q9
UNION ALL SELECT * FROM q10
UNION ALL SELECT * FROM q11
UNION ALL SELECT * FROM q12
UNION ALL SELECT * FROM q13
UNION ALL SELECT * FROM q14
ORDER BY check_step, item;
