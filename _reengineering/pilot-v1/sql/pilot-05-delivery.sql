-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 05 — إكمال دورة طلبات تطبيقات التوصيل
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING (RLS تعتمد auth.uid()). يعتمد على
-- pilot-01-foundation.sql و delivery-requests-schema.sql (الجداول موجودة).
--
-- يكمل موديول 9 من مصفوفة الفجوات:
--   • لا مراجعة/قبول/رفض → حالات submitted→under_review→accepted/rejected
--     مع سبب رفض إلزامي ومُراجِع مسجَّل.
--   • لا منع تكرار → فهرس فريد (company_id, order_ref, branch_id) عند وجود رقم.
--   • لا سجل تعديلات → audit + touch triggers.
--   • منع تنفيذ القرار مرتين → القبول/الرفض نهائي (حارس انتقال + حماية).
--   • معالجة تزامن → القبول/الرفض يعتمد على الحالة الحالية داخل تريجر ذرّي.
--
-- ملاحظة صلاحية إدارية (مسجّلة، تتبع القاعدة الموجودة): المراجعة (قبول/رفض)
-- للإدارة أو مدير الفرع؛ الإنشاء لمدير/نائب الفرع. لا تغيير على سياسة مالية.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── (1) أعمدة الحالة والمراجعة والتتبّع ───────────────────────────────
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'submitted';
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS reviewed_by BIGINT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS review_note TEXT;
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE branch_delivery_requests ADD COLUMN IF NOT EXISTS updated_by BIGINT;

-- قيد الحالة (NOT VALID: للصفوف الجديدة)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='bdr_status_chk') THEN
    ALTER TABLE branch_delivery_requests ADD CONSTRAINT bdr_status_chk CHECK (
      status IN ('submitted','under_review','accepted','rejected')
    ) NOT VALID;
  END IF;
END $$;

-- ─── (2) منع التكرار: نفس التطبيق + رقم الطلب + الفرع ──────────────────
-- فريد فقط عند وجود رقم طلب (order_ref) — الطلبات بلا رقم لا تُقيَّد.
CREATE UNIQUE INDEX IF NOT EXISTS bdr_dedup_idx
  ON branch_delivery_requests (company_id, order_ref, branch_id)
  WHERE order_ref IS NOT NULL AND order_ref <> '';

-- ─── (3) حارس انتقالات + حماية نهائية + منع التنفيذ المزدوج ────────────
CREATE OR REPLACE FUNCTION bdr_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    -- لا تغيير حالة: امنع تعديل الطلب المحسوم (accepted/rejected)
    IF OLD.status IN ('accepted','rejected') THEN
      RAISE EXCEPTION 'الطلب حُسم (%): لا يمكن تعديله', OLD.status;
    END IF;
    RETURN NEW;
  END IF;

  -- منع التنفيذ المزدوج: من حالة محسومة لا خروج
  IF OLD.status IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'الطلب محسوم بالفعل (%) — لا يمكن حسمه مرة أخرى', OLD.status;
  END IF;

  v_ok := CASE
    WHEN OLD.status = 'submitted'    AND NEW.status IN ('under_review','accepted','rejected') THEN TRUE
    WHEN OLD.status = 'under_review' AND NEW.status IN ('accepted','rejected')                THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'انتقال غير مسموح لطلب التوصيل: % ← %', OLD.status, NEW.status;
  END IF;

  -- الرفض يتطلب سببًا
  IF NEW.status = 'rejected' AND (NEW.rejection_reason IS NULL OR btrim(NEW.rejection_reason) = '') THEN
    RAISE EXCEPTION 'يجب إدخال سبب الرفض';
  END IF;

  -- ختم المراجعة
  IF NEW.status IN ('accepted','rejected') THEN
    NEW.reviewed_by := current_app_user_id();
    NEW.reviewed_at := NOW();
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bdr_guard ON branch_delivery_requests;
CREATE TRIGGER trg_bdr_guard BEFORE UPDATE ON branch_delivery_requests
  FOR EACH ROW EXECUTE FUNCTION bdr_guard_transition();

DROP TRIGGER IF EXISTS trg_bdr_touch ON branch_delivery_requests;
CREATE TRIGGER trg_bdr_touch BEFORE UPDATE ON branch_delivery_requests
  FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();

DROP TRIGGER IF EXISTS trg_bdr_audit ON branch_delivery_requests;
CREATE TRIGGER trg_bdr_audit AFTER INSERT OR UPDATE OR DELETE ON branch_delivery_requests
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ─── (4) تحديث RLS: المراجعة (قبول/رفض) لإدارة/مدير الفرع فقط ──────────
-- سياسة SELECT/INSERT القائمة من delivery-requests-schema سليمة؛ نعيد فقط
-- سياسة UPDATE لتقييد من يستطيع المراجعة (بدل bdr_update العام على المالك).
DROP POLICY IF EXISTS bdr_update ON branch_delivery_requests;
CREATE POLICY bdr_update ON branch_delivery_requests FOR UPDATE TO authenticated
  USING (
    current_app_role() IN ('admin','company_manager')
    OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
               AND u.role IN ('branch_manager','deputy_manager')
               AND u.branch_id = branch_delivery_requests.branch_id)
  )
  WITH CHECK (
    current_app_role() IN ('admin','company_manager')
    OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
               AND u.role IN ('branch_manager','deputy_manager')
               AND u.branch_id = branch_delivery_requests.branch_id)
  );

SELECT 'delivery' AS object,
       (SELECT count(*)::text FROM pg_policies WHERE tablename='branch_delivery_requests') AS policies,
       (SELECT count(*)::text FROM pg_indexes WHERE indexname='bdr_dedup_idx') AS dedup_index;
