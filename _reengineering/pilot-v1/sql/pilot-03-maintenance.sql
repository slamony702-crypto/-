-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 03 — تصليب موديول الصيانة
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING — لا تُطبَّق على Production قبل اختبارها على
-- Staging، ولأن سياسات RLS تعتمد على current_app_user_id()/auth.uid() فإن
-- تفعيلها الفعلي مرهون بترحيل Supabase Auth (المستخدمون غير المُرحَّلين
-- سيُحجبون). يعتمد على pilot-01-foundation.sql (تريجرز التدقيق).
--
-- يعالج فجوات الصيانة من مصفوفة الفجوات:
--   • RLS `using(true)` → RLS مقيّدة بالفرع/الدور فعليًا.
--   • لا فرض لانتقالات الحالة → حارس تريجر بجدول انتقالات صريح.
--   • لا حماية للسجل النهائي → rejected نهائي، closed لا يُعدَّل إلا بإعادة فتح.
--   • مراحل ناقصة → حالة awaiting_quality_check + إعادة الفتح (in_progress).
--   • تعديل التكلفة بعد الاعتماد بلا سجل → يُلتقط في pilot_audit_log.
--   • تعارض severity الافتراضي → توحيد الافتراضي إلى medium (دون كسر القديم).
--
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── (1) أعمدة تتبّع مفقودة ────────────────────────────────────────────
ALTER TABLE maintenance_requests ADD COLUMN IF NOT EXISTS updated_by BIGINT;
ALTER TABLE maintenance_requests ADD COLUMN IF NOT EXISTS reopen_count INT NOT NULL DEFAULT 0;

-- توحيد الافتراضي (السجلات القديمة بقيمة 'normal' تبقى كما هي)
ALTER TABLE maintenance_requests ALTER COLUMN severity SET DEFAULT 'medium';

-- ─── (2) قيد الحالة (NOT VALID: يُطبَّق على الصفوف الجديدة فقط) ─────────
-- يشمل كل الحالات المكتوبة فعليًا + الحالة الجديدة awaiting_quality_check.
-- الحالتان الميتتان under_review/awaiting_approval مستبعدتان عمدًا.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'mr_status_chk') THEN
    ALTER TABLE maintenance_requests ADD CONSTRAINT mr_status_chk CHECK (
      status IN ('new','awaiting_inspection','inspection_reported','awaiting_quotes',
                 'awaiting_finance','in_progress','awaiting_quality_check',
                 'awaiting_receipt','closed','rejected')
    ) NOT VALID;
  END IF;
END $$;

-- ─── (3) حارس انتقالات الحالة + حماية السجل النهائي (SECURITY INVOKER) ──
-- INVOKER ليعكس current_app_role() الفاعل الحقيقي لا مالك الدالة.
CREATE OR REPLACE FUNCTION mr_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  v_role TEXT := current_app_role();
  v_ok   BOOLEAN := FALSE;
BEGIN
  -- لا تغيير في الحالة → مرّ (تعديل حقول أخرى) إلا لو السجل نهائي
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status = 'rejected' THEN
      RAISE EXCEPTION 'الطلب مرفوض ولا يمكن تعديله';
    END IF;
    IF OLD.status = 'closed' THEN
      RAISE EXCEPTION 'الطلب مغلق — أعد فتحه أولًا قبل أي تعديل';
    END IF;
    RETURN NEW;
  END IF;

  -- جدول الانتقالات المسموحة (old → new)
  v_ok := CASE
    WHEN OLD.status = 'new'                  AND NEW.status IN ('awaiting_inspection','rejected')        THEN TRUE
    WHEN OLD.status = 'awaiting_inspection'  AND NEW.status IN ('inspection_reported','rejected')        THEN TRUE
    WHEN OLD.status = 'inspection_reported'  AND NEW.status IN ('awaiting_quotes','awaiting_finance','rejected') THEN TRUE
    WHEN OLD.status = 'awaiting_quotes'      AND NEW.status IN ('awaiting_finance','rejected')           THEN TRUE
    WHEN OLD.status = 'awaiting_finance'     AND NEW.status IN ('in_progress','rejected')                THEN TRUE
    WHEN OLD.status = 'in_progress'          AND NEW.status IN ('awaiting_quality_check')                THEN TRUE
    WHEN OLD.status = 'awaiting_quality_check' AND NEW.status IN ('awaiting_receipt','in_progress')      THEN TRUE
    WHEN OLD.status = 'awaiting_receipt'     AND NEW.status IN ('closed','in_progress')                  THEN TRUE
    -- إعادة فتح المغلق (فشل الإصلاح) — للإدارة/مدير الفرع فقط
    WHEN OLD.status = 'closed' AND NEW.status = 'in_progress'
         AND v_role IN ('admin','company_manager','maintenance_officer','operations_manager','branch_manager','deputy_manager') THEN TRUE
    ELSE FALSE
  END;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'انتقال غير مسموح: % ← %', OLD.status, NEW.status;
  END IF;

  -- عدّاد إعادة الفتح
  IF OLD.status = 'closed' AND NEW.status = 'in_progress' THEN
    NEW.reopen_count := COALESCE(OLD.reopen_count,0) + 1;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_mr_guard ON maintenance_requests;
CREATE TRIGGER trg_mr_guard BEFORE UPDATE ON maintenance_requests
  FOR EACH ROW EXECUTE FUNCTION mr_guard_transition();

-- ─── (4) تريجرز التتبّع والتدقيق ───────────────────────────────────────
DROP TRIGGER IF EXISTS trg_mr_touch ON maintenance_requests;
CREATE TRIGGER trg_mr_touch BEFORE UPDATE ON maintenance_requests
  FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();

DROP TRIGGER IF EXISTS trg_mr_audit ON maintenance_requests;
CREATE TRIGGER trg_mr_audit AFTER INSERT OR UPDATE OR DELETE ON maintenance_requests
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- تدقيق الجداول الفرعية الحسّاسة (اعتمادات مالية، إصلاحات، عروض)
DROP TRIGGER IF EXISTS trg_mfa_audit ON maintenance_finance_approvals;
CREATE TRIGGER trg_mfa_audit AFTER INSERT OR UPDATE OR DELETE ON maintenance_finance_approvals
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();
DROP TRIGGER IF EXISTS trg_mrep_audit ON maintenance_repairs;
CREATE TRIGGER trg_mrep_audit AFTER INSERT OR UPDATE OR DELETE ON maintenance_repairs
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();
DROP TRIGGER IF EXISTS trg_mq_audit ON maintenance_quotes;
CREATE TRIGGER trg_mq_audit AFTER INSERT OR UPDATE OR DELETE ON maintenance_quotes
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══════════════════════════════════════════════════════════════════════
-- (5) RLS الحقيقية — استبدال سياسات using(true)
-- ═══════════════════════════════════════════════════════════════════════
-- دالة مساعدة: هل المستخدم الحالي من الإدارة ذات الوصول الكامل للصيانة؟
CREATE OR REPLACE FUNCTION mr_is_maint_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager','maintenance_officer','operations_manager');
$$;

-- دالة مساعدة: هل الطلب ضمن فرع المستخدم الحالي؟
CREATE OR REPLACE FUNCTION mr_user_in_branch(p_branch BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = current_app_user_id() AND u.branch_id = p_branch
  );
$$;

-- ── maintenance_requests ──
DROP POLICY IF EXISTS mr_all ON maintenance_requests;
DROP POLICY IF EXISTS mr_sel ON maintenance_requests;
DROP POLICY IF EXISTS mr_ins ON maintenance_requests;
DROP POLICY IF EXISTS mr_upd ON maintenance_requests;
DROP POLICY IF EXISTS mr_del ON maintenance_requests;

CREATE POLICY mr_sel ON maintenance_requests FOR SELECT TO authenticated USING (
  mr_is_maint_admin()
  OR mr_user_in_branch(branch_id)
  OR requester_id = current_app_user_id()
);
CREATE POLICY mr_ins ON maintenance_requests FOR INSERT TO authenticated WITH CHECK (
  requester_id = current_app_user_id()
  AND (mr_is_maint_admin() OR mr_user_in_branch(branch_id) OR branch_id IS NULL)
);
CREATE POLICY mr_upd ON maintenance_requests FOR UPDATE TO authenticated
  USING (mr_is_maint_admin() OR mr_user_in_branch(branch_id))
  WITH CHECK (mr_is_maint_admin() OR mr_user_in_branch(branch_id));
-- الحذف للإدارة العليا فقط (الطلبات تُرفَض لا تُحذَف)
CREATE POLICY mr_del ON maintenance_requests FOR DELETE TO authenticated USING (
  current_app_role() IN ('admin','company_manager')
);

-- ── الجداول الفرعية: مربوطة بالطلب الأب عبر request_id ──
-- نمط موحّد: من يرى/يدير الطلب الأب يرى/يدير سجلاته الفرعية.
DO $$
DECLARE
  child TEXT;
  old_name TEXT;
  children TEXT[] := ARRAY['maintenance_inspections','maintenance_quotes',
    'maintenance_finance_approvals','maintenance_repairs','maintenance_receipts',
    'maintenance_attachments','maintenance_timeline'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    -- إسقاط السياسة القديمة المعروفة using(true)
    old_name := CASE child
        WHEN 'maintenance_inspections' THEN 'mi_all'
        WHEN 'maintenance_quotes' THEN 'mq_all'
        WHEN 'maintenance_finance_approvals' THEN 'mfa_all'
        WHEN 'maintenance_repairs' THEN 'mrep_all'
        WHEN 'maintenance_receipts' THEN 'mrc_all'
        WHEN 'maintenance_attachments' THEN 'mat_all'
        WHEN 'maintenance_timeline' THEN 'mtl_all'
      END;
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', old_name, child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
    -- اسم السياسة (%1$s) آمن لأنه من قائمة ثابتة؛ الجدول (%1$I) مقتبَس
    EXECUTE format($f$
      CREATE POLICY %1$s_sel ON %1$I FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM maintenance_requests r WHERE r.id = %1$I.request_id
                AND (mr_is_maint_admin() OR mr_user_in_branch(r.branch_id) OR r.requester_id = current_app_user_id()))
      )$f$, child);
    EXECUTE format($f$
      CREATE POLICY %1$s_wr ON %1$I FOR ALL TO authenticated
      USING (
        EXISTS (SELECT 1 FROM maintenance_requests r WHERE r.id = %1$I.request_id
                AND (mr_is_maint_admin() OR mr_user_in_branch(r.branch_id)))
      )
      WITH CHECK (
        EXISTS (SELECT 1 FROM maintenance_requests r WHERE r.id = %1$I.request_id
                AND (mr_is_maint_admin() OR mr_user_in_branch(r.branch_id)))
      )$f$, child);
  END LOOP;
END $$;

-- ── branches: قراءة للجميع المسجّلين، تعديل للإدارة العليا ──
DROP POLICY IF EXISTS br_all ON branches;
DROP POLICY IF EXISTS br_sel ON branches;
DROP POLICY IF EXISTS br_wr ON branches;
CREATE POLICY br_sel ON branches FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
CREATE POLICY br_wr ON branches FOR ALL TO authenticated
  USING (current_app_role() IN ('admin','company_manager'))
  WITH CHECK (current_app_role() IN ('admin','company_manager'));

-- ═══════════════════════════════════════════════════════════════════════
-- تأكيد
-- ═══════════════════════════════════════════════════════════════════════
SELECT 'maintenance policies' AS object,
       (SELECT count(*)::text FROM pg_policies WHERE tablename='maintenance_requests') AS req_policies,
       (SELECT count(*)::text FROM pg_policies WHERE tablename LIKE 'maintenance_%') AS all_policies;
