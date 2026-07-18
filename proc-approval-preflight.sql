-- ═══════════════════════════════════════════════════════════
-- Procurement Approval — Preflight Check (Read-Only)
-- ═══════════════════════════════════════════════════════════
-- ⚠️ Read-Only بالكامل — لا يعدّل شيئًا
-- ⚠️ مصمَّم لـSupabase SQL Editor — كل النتائج في جدول واحد
-- ═══════════════════════════════════════════════════════════

WITH
  -- (1) DB info
  q1 AS (
    SELECT '01. DB_INFO' AS check_step,
           current_database() AS item,
           'INFO' AS status,
           'PostgreSQL ' || current_setting('server_version') AS detail
  ),
  -- (2) هل الجداول الأصلية موجودة؟
  q2 AS (
    SELECT '02. REQUIRED_TABLE' AS check_step,
           t.name AS item,
           CASE WHEN c.relname IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status,
           '' AS detail
    FROM (VALUES
      ('users'), ('branches'), ('departments'), ('notifications'),
      ('proc_requisitions'), ('proc_requisition_items'),
      ('proc_purchase_orders'), ('proc_purchase_order_items'),
      ('proc_goods_receipts'), ('proc_goods_receipt_items'),
      ('acct_vendors'), ('acct_bills'), ('acct_bill_lines'),
      ('acct_chart_of_accounts'), ('acct_journal_entries')
    ) t(name)
    LEFT JOIN pg_class c
      ON c.relname = t.name
      AND c.relnamespace = 'public'::regnamespace
      AND c.relkind = 'r'
  ),
  -- (3) أنواع مفاتيح المستخدم والطلب
  q3 AS (
    SELECT '03. KEY_TYPE' AS check_step,
           table_name || '.' || column_name AS item,
           data_type AS status,
           udt_name AS detail
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND (table_name, column_name) IN (
        ('proc_requisitions', 'id'),
        ('proc_requisitions', 'requested_by'),
        ('proc_requisitions', 'branch_id'),
        ('users', 'id'),
        ('users', 'auth_id'),
        ('users', 'role'),
        ('users', 'is_active')
      )
  ),
  -- (4) توزيع حالات proc_requisitions
  q4 AS (
    SELECT '04. REQ_STATUS' AS check_step,
           COALESCE(status, '(null)') AS item,
           COUNT(*)::TEXT AS status,
           '' AS detail
    FROM proc_requisitions
    GROUP BY status
  ),
  -- (5) دوال المصادقة الأساسية
  q5 AS (
    SELECT '05. AUTH_HELPER' AS check_step,
           p.proname AS item,
           CASE p.prosecdef WHEN TRUE THEN 'EXISTS (DEFINER)' ELSE 'EXISTS (INVOKER)' END AS status,
           pg_get_function_result(p.oid) AS detail
    FROM pg_proc p
    WHERE p.proname IN ('current_app_user_id', 'current_app_role', 'is_procurement_manager')
      AND p.pronamespace = 'public'::regnamespace
  ),
  -- (6) auth.uid (Supabase Auth)
  q6 AS (
    SELECT '06. AUTH_UID' AS check_step,
           'auth.uid()' AS item,
           CASE WHEN EXISTS (
             SELECT 1 FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'auth' AND p.proname = 'uid'
           ) THEN 'EXISTS' ELSE 'MISSING' END AS status,
           'Supabase Auth JWT function' AS detail
  ),
  -- (7) الجلسة الحالية — هل مربوطة بمستخدم؟
  q7 AS (
    SELECT '07. SESSION_USER' AS check_step,
           'current_app_user_id()' AS item,
           CASE WHEN current_app_user_id() IS NULL
                THEN 'NULL (Editor session — RPCs will require JWT)'
                ELSE 'AUTHENTICATED' END AS status,
           COALESCE(current_app_user_id()::TEXT, '') AS detail
  ),
  -- (8) RLS policies الحالية على جداول المشتريات
  q8 AS (
    SELECT '08. RLS_POLICY' AS check_step,
           tablename || '.' || policyname AS item,
           cmd AS status,
           roles::TEXT AS detail
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename LIKE 'proc_%'
  ),
  -- (9) تعارض أسماء (هل موجود بعد Migration؟)
  q9 AS (
    SELECT '09. NAME_CONFLICT' AS check_step,
           x.obj_name AS item,
           CASE WHEN x.found THEN 'ALREADY EXISTS' ELSE 'CLEAR (safe to create)' END AS status,
           x.obj_kind AS detail
    FROM (
      SELECT 'TABLE' AS obj_kind, t.n AS obj_name,
             EXISTS(SELECT 1 FROM pg_class WHERE relname = t.n AND relnamespace = 'public'::regnamespace) AS found
      FROM (VALUES
        ('proc_approval_rules'),
        ('proc_requisition_approvals'),
        ('proc_approval_activity'),
        ('proc_approval_settings'),
        ('proc_approval_rules_history')
      ) t(n)
      UNION ALL
      SELECT 'FUNCTION', f.n,
             EXISTS(SELECT 1 FROM pg_proc WHERE proname = f.n AND pronamespace = 'public'::regnamespace)
      FROM (VALUES
        ('proc_submit_requisition'),
        ('proc_approve_step'),
        ('proc_reject_step'),
        ('proc_match_approval_rules'),
        ('proc_requisition_total'),
        ('proc_legacy_decide_requisition')
      ) f(n)
    ) x
  ),
  -- (10) بيانات قد تفشل constraints
  q10 AS (
    SELECT '10. DATA_HEALTH' AS check_step,
           'items_without_price' AS item,
           COUNT(*)::TEXT AS status,
           'proc_requisition_items where estimated_price IS NULL' AS detail
    FROM proc_requisition_items
    WHERE estimated_price IS NULL
    UNION ALL
    SELECT '10. DATA_HEALTH',
           'legacy_approved_reqs',
           COUNT(*)::TEXT,
           'approved requests with no chain (pre-migration)'
    FROM proc_requisitions WHERE status = 'approved'
    UNION ALL
    SELECT '10. DATA_HEALTH',
           'inflight_submitted_reqs',
           COUNT(*)::TEXT,
           'submitted requests currently open'
    FROM proc_requisitions WHERE status = 'submitted'
  ),
  -- (11) الأدوار الحالية
  q11 AS (
    SELECT '11. ROLE' AS check_step,
           role AS item,
           COUNT(*)::TEXT AS status,
           'active=' || COUNT(*) FILTER (WHERE is_active = TRUE) || ', inactive=' || COUNT(*) FILTER (WHERE is_active = FALSE) AS detail
    FROM users
    GROUP BY role
  ),
  -- (12) أدوار المشتريات ولديها مستخدم نشط؟
  q12 AS (
    SELECT '12. PROC_ROLE_HAS_USER' AS check_step,
           r.expected_role AS item,
           CASE WHEN EXISTS (
             SELECT 1 FROM users WHERE role = r.expected_role AND is_active = TRUE
           ) THEN 'HAS_USER' ELSE 'NO_ACTIVE_USER' END AS status,
           '' AS detail
    FROM (VALUES
      ('branch_manager'), ('procurement_manager'), ('finance_manager'),
      ('company_manager'), ('admin')
    ) r(expected_role)
  ),
  -- (13) حساب المصروف الافتراضي 5101
  q13 AS (
    SELECT '13. EXPENSE_ACCOUNT_5101' AS check_step,
           '5101 (تكلفة المواد الغذائية)' AS item,
           CASE WHEN EXISTS (SELECT 1 FROM acct_chart_of_accounts WHERE code = '5101')
                THEN 'EXISTS' ELSE 'MISSING (proc_receive_goods will fail on GRN)' END AS status,
           '' AS detail
  ),
  -- (14) دالة set_updated_at
  q14 AS (
    SELECT '14. SET_UPDATED_AT' AS check_step,
           'set_updated_at()' AS item,
           CASE WHEN EXISTS (
             SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at'
                                     AND pronamespace = 'public'::regnamespace
           ) THEN 'EXISTS' ELSE 'MISSING (migration triggers will fail)' END AS status,
           '' AS detail
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
