-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — staging-rls-prep.sql  (STAGING فقط — بعد pilot-01، قبل pilot-02)
-- ═══════════════════════════════════════════════════════════════════════
-- يجعل Staging مطابقًا لحالة Production من ناحية RLS:
--   (1) تفعيل RLS على كل جداول الموديولات (على Staging الفارغ كانت معطّلة،
--       فبدونها لن تُفرَض سياسات pilot-02..09 — عزل زائف).
--   (2) إنشاء سياسات التوصيل الأساسية (delivery_companies + bdr_select/insert/
--       delete) التي يفترض pilot-05 وجودها مسبقًا (كانت في delivery-requests-schema).
--
-- ملاحظة: بعد تفعيل RLS تصبح الجداول التي لم تُنشأ سياساتها بعد «deny-all»
-- مؤقتًا حتى يضيف ملف الموديول التالي سياساتها — سلوك متوقع وآمن على Staging.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

-- (1) تفعيل RLS على كل جداول الموديولات التسعة
DO $$
DECLARE t TEXT;
  tbls TEXT[] := ARRAY[
    'users','branches','departments','role_permissions','user_permission_overrides',
    'meetings','meeting_attendees','meeting_minutes','meeting_requests',
    'action_items','department_tasks','decisions','decision_sub_responsibles',
    'decision_viewers','decision_activity_log','decision_acknowledgments',
    'emergency_alerts','emergency_recipients','emergency_activity_log',
    'maintenance_requests','maintenance_suppliers','maintenance_inspections','maintenance_quotes',
    'maintenance_finance_approvals','maintenance_repairs','maintenance_receipts',
    'maintenance_attachments','maintenance_timeline',
    'quality_sections','quality_items','quality_visits','quality_visit_items',
    'quality_visit_sections','quality_attachments',
    'delivery_companies','branch_delivery_requests'];
BEGIN
  FOREACH t IN ARRAY tbls LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- (2) سياسات التوصيل الأساسية (يعتمد عليها pilot-05)
DROP POLICY IF EXISTS delivery_companies_read ON delivery_companies;
CREATE POLICY delivery_companies_read ON delivery_companies
  FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
DROP POLICY IF EXISTS delivery_companies_write ON delivery_companies;
CREATE POLICY delivery_companies_write ON delivery_companies
  FOR ALL TO authenticated
  USING (current_app_role() IN ('admin','company_manager'))
  WITH CHECK (current_app_role() IN ('admin','company_manager'));

DROP POLICY IF EXISTS bdr_select ON branch_delivery_requests;
CREATE POLICY bdr_select ON branch_delivery_requests FOR SELECT TO authenticated USING (
  current_app_role() IN ('admin','company_manager')
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = branch_delivery_requests.branch_id)
);
DROP POLICY IF EXISTS bdr_insert ON branch_delivery_requests;
CREATE POLICY bdr_insert ON branch_delivery_requests FOR INSERT TO authenticated WITH CHECK (
  current_app_role() IN ('admin','company_manager')
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.role IN ('branch_manager','deputy_manager') AND u.branch_id = branch_delivery_requests.branch_id)
);
DROP POLICY IF EXISTS bdr_delete ON branch_delivery_requests;
CREATE POLICY bdr_delete ON branch_delivery_requests FOR DELETE TO authenticated USING (
  current_app_role() IN ('admin','company_manager') OR created_by = current_app_user_id()
);

-- ═══ تأكيد ═══
SELECT 'rls_enabled_tables' AS what,
       count(*)::text AS n
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity=TRUE
  AND c.relname = ANY (ARRAY[
    'users','branches','meetings','action_items','decisions','emergency_alerts',
    'maintenance_requests','quality_visits','delivery_companies','branch_delivery_requests']);
