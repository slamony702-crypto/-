-- ═══════════════════════════════════════════════════════════
-- Preflight — قراءة فقط (Read-Only) — لا يعدل أي بيانات
-- ═══════════════════════════════════════════════════════════
-- ⚠️ شغّل هذا الملف قبل تطبيق أي migration من موجة الاعتماد
-- ⚠️ يعطيك صورة شاملة لجاهزية بيئتك
-- ⚠️ آمن التشغيل على أي بيئة (حتى Production — قراءة فقط)
--     لكن ننصح بتشغيله على Staging لأنك ستطبق migrations هناك
-- ═══════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
--   Procurement Approval — Preflight Check
-- ════════════════════════════════════════════════════════════════

-- (1) معلومات البيئة الأساسية
SELECT
  current_database()               AS db_name,
  current_setting('server_version') AS pg_version,
  now()                            AS check_time;

-- (2) هل الجداول الأصلية للمشتريات موجودة؟
SELECT 'REQUIRED_TABLES' AS check_type,
       t.name           AS table_name,
       CASE WHEN c.relname IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM (VALUES
  ('users'),
  ('branches'),
  ('departments'),
  ('proc_requisitions'),
  ('proc_requisition_items'),
  ('proc_purchase_orders'),
  ('proc_purchase_order_items'),
  ('proc_goods_receipts'),
  ('acct_vendors'),
  ('acct_bills'),
  ('acct_bill_lines'),
  ('acct_chart_of_accounts')
) t(name)
LEFT JOIN pg_class c
       ON c.relname = t.name
      AND c.relnamespace = 'public'::regnamespace
      AND c.relkind = 'r';

-- (3) الأنواع الحقيقية للمفاتيح
SELECT 'KEY_TYPES' AS check_type,
       table_name, column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (table_name, column_name) IN (
    ('proc_requisitions', 'id'),
    ('proc_requisitions', 'requested_by'),
    ('proc_requisitions', 'branch_id'),
    ('proc_requisitions', 'department_id'),
    ('users', 'id'),
    ('users', 'auth_id'),
    ('users', 'role'),
    ('users', 'is_active')
  )
ORDER BY table_name, column_name;

-- (4) الحالات الحالية في proc_requisitions
SELECT 'REQ_STATUS_DISTRIBUTION' AS check_type,
       status, COUNT(*) AS count
FROM proc_requisitions
GROUP BY status
ORDER BY count DESC;

-- (5) تعريف current_app_user_id / current_app_role
SELECT 'AUTH_HELPERS' AS check_type,
       p.proname     AS function_name,
       pg_get_function_result(p.oid)   AS return_type,
       pg_get_function_arguments(p.oid) AS args,
       CASE p.prosecdef WHEN TRUE THEN 'DEFINER' ELSE 'INVOKER' END AS security
FROM pg_proc p
WHERE p.proname IN ('current_app_user_id', 'current_app_role', 'is_procurement_manager')
  AND p.pronamespace = 'public'::regnamespace;

-- (6) هل auth.uid موجودة (Supabase Auth شغّالة)؟
SELECT 'AUTH_UID' AS check_type,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'auth' AND p.proname = 'uid'
       ) THEN 'EXISTS' ELSE 'MISSING (Supabase Auth not initialized?)' END AS status;

-- (7) هل current_app_user_id() ترجع NULL في الجلسة الحالية؟
-- (بدون auth context ترجع NULL — هذا طبيعي في SQL Editor غير JWT)
SELECT 'CURRENT_SESSION_APP_USER' AS check_type,
       current_app_user_id()  AS app_user_id,
       current_app_role()     AS app_role,
       CASE WHEN current_app_user_id() IS NULL
            THEN 'NULL (Editor session — RPCs will require auth JWT)'
            ELSE 'AUTHENTICATED' END AS interpretation;

-- (8) RLS الحالية على proc_requisitions
SELECT 'CURRENT_RLS' AS check_type,
       tablename, policyname, cmd, roles::text AS roles,
       LEFT(qual::text, 100)      AS using_expr_preview,
       LEFT(with_check::text,100) AS check_expr_preview
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'proc_requisitions','proc_requisition_items',
    'proc_purchase_orders','proc_purchase_order_items',
    'proc_goods_receipts','proc_goods_receipt_items'
  )
ORDER BY tablename, policyname;

-- (9) تعارض الأسماء — هل الجداول/الدوال الجديدة موجودة بالفعل؟
SELECT 'NAME_CONFLICTS' AS check_type,
       obj_kind, obj_name,
       CASE WHEN found THEN 'ALREADY EXISTS (migration already applied?)'
            ELSE 'CLEAR (safe to create)' END AS status
FROM (
  -- Tables
  SELECT 'TABLE' AS obj_kind, t.n AS obj_name,
         EXISTS(SELECT 1 FROM pg_class WHERE relname = t.n AND relnamespace = 'public'::regnamespace) AS found
  FROM (VALUES
    ('proc_approval_rules'),
    ('proc_requisition_approvals'),
    ('proc_approval_activity'),
    ('proc_approval_settings')
  ) t(n)
  UNION ALL
  -- Functions
  SELECT 'FUNCTION', f.n,
         EXISTS(SELECT 1 FROM pg_proc WHERE proname = f.n AND pronamespace = 'public'::regnamespace)
  FROM (VALUES
    ('proc_submit_requisition'),
    ('proc_approve_step'),
    ('proc_reject_step'),
    ('proc_cancel_requisition_approval'),
    ('proc_get_approval_chain'),
    ('proc_match_approval_rules'),
    ('proc_requisition_total'),
    ('proc_legacy_decide_requisition'),
    ('proc_req_update_guard'),
    ('proc_req_items_write_guard'),
    ('proc_po_creation_guard')
  ) f(n)
) x
ORDER BY obj_kind, obj_name;

-- (10) البيانات القائمة التي قد تفشل constraints
-- (10.a) بنود بلا estimated_price — لن تُشارك في مطابقة القاعدة (مبلغها = 0)
SELECT 'DATA_HEALTH_no_price' AS check_type,
       COUNT(*) AS items_without_price,
       'These items will contribute 0 to requisition total' AS note
FROM proc_requisition_items
WHERE estimated_price IS NULL;

-- (10.b) طلبات approved قديمة بلا سلسلة اعتماد (legacy tail)
-- بعد التطبيق: هذه الطلبات تبقى كما هي — لا chain
SELECT 'DATA_HEALTH_legacy_approved' AS check_type,
       COUNT(*) AS legacy_approved_reqs,
       'Existing approved requests with no chain (legitimate — pre-migration)' AS note
FROM proc_requisitions
WHERE status = 'approved';

-- (10.c) طلبات submitted حالية بلا chain (ستبقى تحت النمط القديم بعد التطبيق)
-- بعد التطبيق: إن كان allow_legacy_approval = FALSE، لن تتأثر السلوك عليها
-- لكن لن يستطيع اعتمادها إلا بتفعيل flag أو نقلها إلى draft ثم تقديمها ثانية
SELECT 'DATA_HEALTH_inflight_submitted' AS check_type,
       COUNT(*) AS inflight_submitted,
       'These will need legacy flag ON OR manual approval before migration is fully useful' AS note
FROM proc_requisitions
WHERE status = 'submitted';

-- (11) عدد المستخدمين النشطين وأدوارهم
SELECT 'USERS_BY_ROLE' AS check_type,
       role, COUNT(*) FILTER (WHERE is_active = TRUE)  AS active_users,
             COUNT(*) FILTER (WHERE is_active = FALSE) AS inactive_users
FROM users
GROUP BY role
ORDER BY active_users DESC;

-- (12) هل توجد أدوار مطلوبة للاعتماد بلا مستخدم نشط؟
-- (ستكون قواعد الاعتماد على هذه الأدوار غير قابلة للتطبيق)
SELECT 'ROLES_WITHOUT_ACTIVE_USER' AS check_type,
       expected_role,
       CASE WHEN EXISTS (
         SELECT 1 FROM users WHERE role = expected_role AND is_active = TRUE
       ) THEN 'HAS_USER' ELSE 'NO_ACTIVE_USER' END AS status
FROM (VALUES
  ('branch_manager'),
  ('deputy_manager'),
  ('operations_manager'),
  ('procurement_manager'),
  ('finance_manager'),
  ('ap_accountant'),
  ('gl_accountant'),
  ('company_manager'),
  ('admin')
) roles(expected_role);

-- (13) هل حساب المصروف الافتراضي (5101) موجود في دليل الحسابات؟
-- (proc_receive_goods يعتمد عليه)
SELECT 'EXPENSE_ACCOUNT_5101' AS check_type,
       CASE WHEN EXISTS (SELECT 1 FROM acct_chart_of_accounts WHERE code = '5101')
            THEN 'EXISTS' ELSE 'MISSING (proc_receive_goods will fail on GRN)' END AS status;

-- (14) trigger set_updated_at() — دالة مطلوبة لجميع Triggers
SELECT 'set_updated_at' AS check_type,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at'
                                 AND pronamespace = 'public'::regnamespace
       ) THEN 'EXISTS' ELSE 'MISSING (migration triggers will fail)' END AS status;

-- ════════════════════════════════════════════════════════════════
--   Preflight Complete — راجع النتائج قبل تطبيق أي migration
-- ════════════════════════════════════════════════════════════════
SELECT '✅ Preflight complete — راجع الجداول أعلاه' AS status;
