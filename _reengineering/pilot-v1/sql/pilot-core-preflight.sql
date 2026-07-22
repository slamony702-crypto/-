-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — PREFLIGHT (READ ONLY)
-- ═══════════════════════════════════════════════════════════════════════
-- الغرض: التقاط البنية الفعلية الحالية لجداول الموديولات التسعة قبل أي
-- Migration، حتى تُبنى الترحيلات على الواقع لا على التخمين.
--
-- ⚠️ هذا الملف للقراءة فقط — لا ينشئ ولا يعدّل ولا يحذف أي شيء.
-- شغّله في Supabase → SQL Editor → Run، ثم أرسل ناتج كل قسم.
-- (محرر Supabase يعرض نتيجة آخر SELECT فقط؛ لذلك كل قسم موحَّد داخل
--  استعلام واحد عبر UNION ALL ويظهر كجدول واحد.)
--
-- جداول النطاق (الموديولات التسعة): الاجتماعات، المهام، القرارات،
-- الصيانة، الجودة، الطوارئ، المستخدمون/الصلاحيات، طلبات تطبيقات التوصيل.
-- ═══════════════════════════════════════════════════════════════════════

-- الجداول المتوقعة داخل النطاق (نفحص وجودها فعليًا لا نفترضه)
WITH scope_tables(t) AS (
  VALUES
    ('meetings'), ('meeting_attendees'), ('meeting_minutes'), ('meeting_agenda_items'),
    ('meeting_attachments'), ('meeting_requests'),
    ('tasks'), ('action_items'), ('department_tasks'), ('task_comments'),
    ('task_attachments'), ('task_updates'), ('task_sub_responsibles'),
    ('decisions'), ('decision_sub_responsibles'), ('decision_updates'),
    ('maintenance_requests'), ('maintenance_suppliers'), ('maintenance_quotes'),
    ('maintenance_equipment'), ('maintenance_attachments'), ('preventive_maintenance'),
    ('quality_visits'), ('quality_visit_items'), ('quality_visit_sections'),
    ('quality_items'), ('quality_sections'), ('quality_attachments'),
    ('emergencies'), ('emergency_events'), ('emergency_attachments'),
    ('users'), ('role_permissions'), ('user_permission_overrides'),
    ('branches'), ('departments'),
    ('branch_delivery_requests'), ('delivery_companies'),
    ('pilot_audit_log')
)

-- ═══ (1) الجداول الموجودة فعليًا + عدد الأعمدة + هل RLS مفعّل ═══
SELECT
  '1_TABLES' AS section,
  st.t AS object_name,
  CASE WHEN c.relname IS NULL THEN 'MISSING'
       ELSE 'cols=' || (SELECT count(*)::text FROM information_schema.columns col
                        WHERE col.table_schema='public' AND col.table_name=st.t)
            || ' | rls=' || CASE WHEN c.relrowsecurity THEN 'ON' ELSE 'OFF' END
            || ' | policies=' || (SELECT count(*)::text FROM pg_policies p
                                  WHERE p.schemaname='public' AND p.tablename=st.t)
  END AS detail
FROM scope_tables st
LEFT JOIN pg_class c ON c.relname = st.t AND c.relnamespace = 'public'::regnamespace AND c.relkind='r'

UNION ALL

-- ═══ (2) الأعمدة لكل جدول موجود (اسم النوع + هل NULL مسموح + الافتراضي) ═══
SELECT
  '2_COLUMNS' AS section,
  col.table_name || '.' || col.column_name AS object_name,
  col.data_type
    || CASE WHEN col.is_nullable='NO' THEN ' NOT NULL' ELSE '' END
    || COALESCE(' default ' || col.column_default, '') AS detail
FROM information_schema.columns col
WHERE col.table_schema='public'
  AND col.table_name IN (SELECT t FROM scope_tables)

UNION ALL

-- ═══ (3) القيود (PK / FK / CHECK / UNIQUE) ═══
SELECT
  '3_CONSTRAINTS' AS section,
  con.conrelid::regclass::text || ' [' || con.contype::text || ']' AS object_name,
  con.conname || ' :: ' || pg_get_constraintdef(con.oid) AS detail
FROM pg_constraint con
WHERE con.connamespace='public'::regnamespace
  AND con.conrelid::regclass::text IN (SELECT t FROM scope_tables)

UNION ALL

-- ═══ (4) الفهارس ═══
SELECT
  '4_INDEXES' AS section,
  idx.tablename || '.' || idx.indexname AS object_name,
  idx.indexdef AS detail
FROM pg_indexes idx
WHERE idx.schemaname='public'
  AND idx.tablename IN (SELECT t FROM scope_tables)

UNION ALL

-- ═══ (5) سياسات RLS ═══
SELECT
  '5_POLICIES' AS section,
  pol.tablename || '.' || pol.policyname AS object_name,
  pol.cmd || ' | roles=' || array_to_string(pol.roles, ',')
    || ' | USING=' || COALESCE(pol.qual, '-')
    || ' | CHECK=' || COALESCE(pol.with_check, '-') AS detail
FROM pg_policies pol
WHERE pol.schemaname='public'
  AND pol.tablename IN (SELECT t FROM scope_tables)

UNION ALL

-- ═══ (6) التريجرز على جداول النطاق ═══
SELECT
  '6_TRIGGERS' AS section,
  tg.tgrelid::regclass::text || '.' || tg.tgname AS object_name,
  CASE tg.tgenabled::text WHEN 'O' THEN 'enabled' WHEN 'D' THEN 'DISABLED' ELSE tg.tgenabled::text END
    || ' :: ' || pg_get_triggerdef(tg.oid) AS detail
FROM pg_trigger tg
WHERE NOT tg.tgisinternal
  AND tg.tgrelid::regclass::text IN (SELECT t FROM scope_tables)

UNION ALL

-- ═══ (7) دوال RLS المساعدة الموجودة (نتأكد من current_app_user_id/role) ═══
SELECT
  '7_HELPER_FNS' AS section,
  p.proname AS object_name,
  pg_get_function_identity_arguments(p.oid)
    || ' returns ' || pg_get_function_result(p.oid)
    || ' | security ' || CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS detail
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('current_app_user_id','current_app_role','verify_login')

UNION ALL

-- ═══ (8) توزيع الأدوار الحالي (نعرف من هو مدير الفرع فعليًا) ═══
SELECT
  '8_ROLE_COUNTS' AS section,
  COALESCE(u.role,'(null)') AS object_name,
  count(*)::text || ' users' AS detail
FROM users u
GROUP BY u.role

ORDER BY 1, 2;
