-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Rollback لموديول التوصيل (pilot-05)
-- ═══════════════════════════════════════════════════════════════════════
-- يزيل الحرّاس/التدقيق/الفهرس الفريد ويعيد سياسة UPDATE الأصلية (المالك).
-- لا يحذف بيانات ولا الأعمدة المضافة (status/…/updated_by تبقى بلا ضرر).
-- ═══════════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_bdr_guard ON branch_delivery_requests;
DROP TRIGGER IF EXISTS trg_bdr_touch ON branch_delivery_requests;
DROP TRIGGER IF EXISTS trg_bdr_audit ON branch_delivery_requests;
DROP FUNCTION IF EXISTS bdr_guard_transition();

DROP INDEX IF EXISTS bdr_dedup_idx;
ALTER TABLE branch_delivery_requests DROP CONSTRAINT IF EXISTS bdr_status_chk;

-- إعادة سياسة UPDATE الأصلية (المالك أو الإدارة) من delivery-requests-schema
DROP POLICY IF EXISTS bdr_update ON branch_delivery_requests;
CREATE POLICY bdr_update ON branch_delivery_requests FOR UPDATE TO authenticated
  USING (current_app_role() IN ('admin','company_manager') OR created_by = current_app_user_id())
  WITH CHECK (current_app_role() IN ('admin','company_manager') OR created_by = current_app_user_id());

SELECT 'delivery rollback done' AS status;
