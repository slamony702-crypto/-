-- ═══════════════════════════════════════════════════════════
-- extract-core-auth-schema.sql
-- READ ONLY — PRODUCTION METADATA INSPECTION
-- ═══════════════════════════════════════════════════════════
-- الغرض: استخراج بنية جداول المصادقة والصلاحيات (Metadata فقط)
--        لبناء Staging Baseline مطابق — دون قراءة أي صف بيانات.
--
-- ⛔ ممنوع تمامًا في هذا الملف:
--    INSERT / UPDATE / DELETE / CREATE / ALTER / DROP / TRUNCATE
--    قراءة أي صف من public.users أو auth.users أو أي جدول تشغيلي.
--    عرض أي اسم/إيميل/كلمة مرور/توكن.
--
-- ✅ يستخدم فقط: information_schema + pg_catalog (pg_class, pg_attribute,
--    pg_constraint, pg_indexes, pg_policies, pg_trigger, pg_proc,
--    pg_namespace, pg_type, pg_enum). كلها Metadata آمنة.
--
-- النتيجة: جدول موحّد (UNION ALL) بأعمدة:
--   section_order | object_type | schema_name | object_name | sub_object | status | definition | details
-- قابل للتصدير CSV مباشرة من Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════

WITH
  -- قائمة الجداول المستهدفة (نطاق ثابت — لا توسيع تلقائي)
  target_tables(tname) AS (
    VALUES ('users'),('roles'),('permissions'),('departments'),('branches'),
           ('role_permissions'),('user_permission_overrides'),
           ('signup_requests'),('user_activity_log')
  ),
  -- قائمة الدوال المستهدفة
  target_funcs(fname) AS (
    VALUES ('verify_login'),('current_app_user_id'),('current_app_role'),
           ('current_user_id'),('is_admin'),('set_updated_at')
  ),

  -- ═══ (0) وجود الجداول ═══
  s0 AS (
    SELECT 0 AS section_order, 'TABLE_EXISTS' AS object_type, 'public' AS schema_name,
           t.tname AS object_name, NULL::text AS sub_object,
           CASE WHEN c.relname IS NOT NULL THEN 'EXISTS' ELSE 'TABLE_NOT_FOUND' END AS status,
           NULL::text AS definition,
           CASE WHEN c.relkind = 'r' THEN 'ordinary table'
                WHEN c.relkind = 'v' THEN 'view'
                WHEN c.relkind = 'p' THEN 'partitioned'
                ELSE COALESCE(c.relkind::text, '-') END AS details
    FROM target_tables t
    LEFT JOIN pg_class c ON c.relname = t.tname AND c.relnamespace = 'public'::regnamespace
  ),

  -- ═══ (1) الأعمدة: الترتيب، النوع، Nullable، Default ═══
  s1 AS (
    SELECT 1 AS section_order, 'COLUMN' AS object_type, 'public' AS schema_name,
           col.table_name AS object_name,
           col.column_name AS sub_object,
           'ordinal=' || col.ordinal_position AS status,
           col.data_type
             || CASE WHEN col.character_maximum_length IS NOT NULL
                     THEN '(' || col.character_maximum_length || ')'
                     WHEN col.numeric_precision IS NOT NULL
                     THEN '(' || col.numeric_precision || ',' || COALESCE(col.numeric_scale,0) || ')'
                     ELSE '' END AS definition,
           'nullable=' || col.is_nullable
             || '; default=' || COALESCE(col.column_default, '-')
             || '; udt=' || col.udt_name AS details
    FROM information_schema.columns col
    JOIN target_tables t ON t.tname = col.table_name
    WHERE col.table_schema = 'public'
  ),

  -- ═══ (2) القيود: PK / FK / UNIQUE / CHECK ═══
  s2 AS (
    SELECT 2 AS section_order,
           CASE con.contype WHEN 'p' THEN 'PK' WHEN 'f' THEN 'FK'
                            WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK'
                            ELSE con.contype::text END AS object_type,
           'public' AS schema_name,
           rel.relname AS object_name,
           con.conname AS sub_object,
           'contype=' || con.contype::text AS status,
           pg_get_constraintdef(con.oid) AS definition,
           CASE WHEN con.contype = 'f'
                THEN 'references ' || confrel.relname
                ELSE '-' END AS details
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN target_tables t ON t.tname = rel.relname
    LEFT JOIN pg_class confrel ON confrel.oid = con.confrelid
    WHERE rel.relnamespace = 'public'::regnamespace
  ),

  -- ═══ (3) الفهارس ═══
  s3 AS (
    SELECT 3 AS section_order, 'INDEX' AS object_type, 'public' AS schema_name,
           i.tablename AS object_name, i.indexname AS sub_object,
           'index' AS status,
           i.indexdef AS definition, '-' AS details
    FROM pg_indexes i
    JOIN target_tables t ON t.tname = i.tablename
    WHERE i.schemaname = 'public'
  ),

  -- ═══ (4) Sequences المرتبطة (owned by) ═══
  s4 AS (
    SELECT 4 AS section_order, 'SEQUENCE' AS object_type, 'public' AS schema_name,
           tab.relname AS object_name,
           seq.relname AS sub_object,
           'owned_sequence' AS status,
           'column: ' || att.attname AS definition,
           format_type(att.atttypid, att.atttypmod) AS details
    FROM pg_depend dep
    JOIN pg_class seq ON seq.oid = dep.objid AND seq.relkind = 'S'
    JOIN pg_class tab ON tab.oid = dep.refobjid
    JOIN pg_attribute att ON att.attrelid = tab.oid AND att.attnum = dep.refobjsubid
    JOIN target_tables t ON t.tname = tab.relname
    WHERE dep.deptype = 'a' AND tab.relnamespace = 'public'::regnamespace
  ),

  -- ═══ (5) RLS status ═══
  s5 AS (
    SELECT 5 AS section_order, 'RLS_STATUS' AS object_type, 'public' AS schema_name,
           c.relname AS object_name, NULL::text AS sub_object,
           CASE WHEN c.relrowsecurity THEN 'RLS_ENABLED' ELSE 'RLS_DISABLED' END AS status,
           CASE WHEN c.relforcerowsecurity THEN 'FORCE_RLS' ELSE 'no_force' END AS definition,
           '-' AS details
    FROM pg_class c
    JOIN target_tables t ON t.tname = c.relname
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  ),

  -- ═══ (6) Policies كاملة ═══
  s6 AS (
    SELECT 6 AS section_order, 'POLICY' AS object_type, 'public' AS schema_name,
           p.tablename AS object_name, p.policyname AS sub_object,
           p.cmd AS status,
           'USING=' || COALESCE(p.qual::text, '-')
             || ' | CHECK=' || COALESCE(p.with_check::text, '-') AS definition,
           'roles=' || COALESCE(p.roles::text, '-')
             || '; permissive=' || COALESCE(p.permissive, '-') AS details
    FROM pg_policies p
    JOIN target_tables t ON t.tname = p.tablename
    WHERE p.schemaname = 'public'
  ),

  -- ═══ (7) Triggers ═══
  s7 AS (
    SELECT 7 AS section_order, 'TRIGGER' AS object_type, 'public' AS schema_name,
           rel.relname AS object_name, tg.tgname AS sub_object,
           CASE WHEN tg.tgenabled = 'O' THEN 'enabled' ELSE 'state=' || tg.tgenabled::text END AS status,
           pg_get_triggerdef(tg.oid) AS definition,
           'func=' || pr.proname AS details
    FROM pg_trigger tg
    JOIN pg_class rel ON rel.oid = tg.tgrelid
    JOIN target_tables t ON t.tname = rel.relname
    LEFT JOIN pg_proc pr ON pr.oid = tg.tgfoid
    WHERE rel.relnamespace = 'public'::regnamespace
      AND NOT tg.tgisinternal   -- استبعاد triggers الداخلية للـFK
  ),

  -- ═══ (8) Enum Types المستخدمة في أعمدة الجداول المستهدفة ═══
  s8 AS (
    SELECT DISTINCT 8 AS section_order, 'ENUM_TYPE' AS object_type, 'public' AS schema_name,
           typ.typname AS object_name,
           enu.enumlabel AS sub_object,
           'label_order=' || enu.enumsortorder::text AS status,
           NULL::text AS definition, '-' AS details
    FROM pg_type typ
    JOIN pg_enum enu ON enu.enumtypid = typ.oid
    WHERE typ.typnamespace = 'public'::regnamespace
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN target_tables t ON t.tname = c.relname
        WHERE a.atttypid = typ.oid AND c.relnamespace = 'public'::regnamespace
      )
  ),

  -- ═══ (9) الدوال المتعلقة بالمصادقة/الصلاحيات ═══
  s9 AS (
    SELECT 9 AS section_order, 'FUNCTION' AS object_type,
           n.nspname AS schema_name, p.proname AS object_name,
           pg_get_function_identity_arguments(p.oid) AS sub_object,
           CASE WHEN p.prosecdef THEN 'SECURITY_DEFINER' ELSE 'SECURITY_INVOKER' END AS status,
           pg_get_functiondef(p.oid) AS definition,
           'returns=' || pg_get_function_result(p.oid)
             || '; lang=' || l.lanname
             || '; search_path=' || COALESCE(array_to_string(p.proconfig, ','), '-') AS details
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    JOIN target_funcs tf ON tf.fname = p.proname
    WHERE n.nspname = 'public'
  ),

  -- ═══ (10) صلاحيات تنفيذ الدوال المستهدفة ═══
  s10 AS (
    SELECT 10 AS section_order, 'FUNCTION_GRANT' AS object_type,
           rp.routine_schema AS schema_name, rp.routine_name AS object_name,
           rp.grantee AS sub_object,
           rp.privilege_type AS status,
           'grantable=' || rp.is_grantable AS definition, '-' AS details
    FROM information_schema.routine_privileges rp
    JOIN target_funcs tf ON tf.fname = rp.routine_name
    WHERE rp.routine_schema = 'public'
  ),

  -- ═══ (11) اعتماديات على password_plain / auth.uid / auth.users / verify_login ═══
  -- نبحث في تعريفات الدوال والـpolicies (Metadata نصية — لا قراءة صفوف)
  s11 AS (
    -- (11a) أعمدة password_plain في الجداول المستهدفة
    SELECT 11 AS section_order, 'DEP_password_plain' AS object_type, 'public' AS schema_name,
           col.table_name AS object_name, col.column_name AS sub_object,
           'COLUMN_PRESENT' AS status,
           col.data_type AS definition, 'nullable=' || col.is_nullable AS details
    FROM information_schema.columns col
    JOIN target_tables t ON t.tname = col.table_name
    WHERE col.table_schema = 'public' AND col.column_name = 'password_plain'
    UNION ALL
    -- (11b) دوال تشير إلى password_plain
    SELECT 11, 'DEP_password_plain', 'public', p.proname,
           'function_body', 'REFERENCES_password_plain',
           'returns=' || pg_get_function_result(p.oid), '-'
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND pg_get_functiondef(p.oid) ILIKE '%password_plain%'
    UNION ALL
    -- (11c) دوال تشير إلى auth.uid()
    SELECT 11, 'DEP_auth_uid', 'public', p.proname,
           'function_body', 'REFERENCES_auth_uid',
           CASE WHEN p.prosecdef THEN 'SECURITY_DEFINER' ELSE 'SECURITY_INVOKER' END, '-'
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND pg_get_functiondef(p.oid) ILIKE '%auth.uid()%'
    UNION ALL
    -- (11d) policies تشير إلى current_app_user_id / current_app_role / auth.uid
    SELECT 11, 'DEP_identity_in_policy', 'public', pol.tablename,
           pol.policyname,
           'POLICY_USES_IDENTITY',
           CASE WHEN pol.qual::text ILIKE '%auth.uid%' OR pol.with_check::text ILIKE '%auth.uid%' THEN 'auth.uid; ' ELSE '' END
             || CASE WHEN pol.qual::text ILIKE '%current_app_user_id%' OR pol.with_check::text ILIKE '%current_app_user_id%' THEN 'current_app_user_id; ' ELSE '' END
             || CASE WHEN pol.qual::text ILIKE '%current_app_role%' OR pol.with_check::text ILIKE '%current_app_role%' THEN 'current_app_role' ELSE '' END,
           '-'
    FROM pg_policies pol
    WHERE pol.schemaname = 'public'
      AND (pol.qual::text ILIKE '%auth.uid%' OR pol.qual::text ILIKE '%current_app%'
           OR pol.with_check::text ILIKE '%auth.uid%' OR pol.with_check::text ILIKE '%current_app%')
  ),

  -- ═══ (12) auth schema — هل auth.users متاح (بدون قراءة صفوف) ═══
  s12 AS (
    SELECT 12 AS section_order, 'AUTH_SCHEMA' AS object_type, 'auth' AS schema_name,
           'users' AS object_name, NULL::text AS sub_object,
           CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                             WHERE n.nspname='auth' AND c.relname='users')
                THEN 'AUTH_USERS_EXISTS' ELSE 'AUTH_USERS_NOT_ACCESSIBLE' END AS status,
           NULL::text AS definition,
           'metadata only — no rows read' AS details
    UNION ALL
    SELECT 12, 'AUTH_SCHEMA', 'auth', 'uid()', NULL,
           CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                             WHERE n.nspname='auth' AND p.proname='uid')
                THEN 'AUTH_UID_EXISTS' ELSE 'AUTH_UID_MISSING' END,
           NULL, 'JWT identity function'
  )

SELECT * FROM s0
UNION ALL SELECT * FROM s1
UNION ALL SELECT * FROM s2
UNION ALL SELECT * FROM s3
UNION ALL SELECT * FROM s4
UNION ALL SELECT * FROM s5
UNION ALL SELECT * FROM s6
UNION ALL SELECT * FROM s7
UNION ALL SELECT * FROM s8
UNION ALL SELECT * FROM s9
UNION ALL SELECT * FROM s10
UNION ALL SELECT * FROM s11
UNION ALL SELECT * FROM s12
ORDER BY section_order, object_name, sub_object NULLS FIRST;
