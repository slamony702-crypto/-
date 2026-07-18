-- ═══════════════════════════════════════════════════════════
-- المشتريات — تصلّب طبقة الاعتماد (مراجعة الجولة الثانية)
-- Wave: purchase-orders-wave1 (feature branch)
-- التاريخ: 2026-07-18 (بعد مراجعة نقاط الأمان الثمان)
-- ═══════════════════════════════════════════════════════════
-- يجب تطبيق proc-approval-1.sql أولًا قبل هذا الملف.
-- ═══════════════════════════════════════════════════════════
-- التغييرات:
--   A) جدول إعدادات ذو صف واحد لتحكم قابلية عمل النمط القديم (legacy)
--   B) proc_submit_requisition الآن يفشل صراحة إذا لم توجد قاعدة
--      إلا إذا فُعّل flag allow_legacy_approval (توافق انتقالي)
--   C) Triggers تمنع:
--      - تغيير status إلى approved/rejected مباشرة عبر UPDATE
--        من العميل عندما توجد سلسلة اعتماد.
--      - تعديل branch_id / department_id بعد التقديم.
--      - تعديل بنود طلب غير مسودة.
--      - إنشاء أمر شراء لطلب غير مُعتمَد بالكامل.
--      - انتقال الطلب من حالة نهائية.
--      - رفض بلا سبب.
--   D) RPC جديدة proc_legacy_decide_requisition لاعتماد/رفض
--      في النمط القديم (يحل محل UPDATE المباشر).
--   E) proc_approve_step / proc_reject_step:
--      - pg_advisory_xact_lock على الطلب لمنع السباقات.
--      - رفض عندما المستخدم غير مصادَق (auth.uid() NULL).
--      - رفض عندما المستخدم غير نشط (is_active = FALSE).
--   F) جدول proc_requisitions يخزن snapshot_amount_at_submit للمقارنة.
--
-- كل شيء idempotent وقابل لإعادة التشغيل.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- A) proc_approval_settings — إعدادات وحيدة الصف
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_approval_settings (
  id                      BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE),
  allow_legacy_approval   BOOLEAN NOT NULL DEFAULT FALSE,
  legacy_grace_note       TEXT,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by              BIGINT REFERENCES users(id) ON DELETE SET NULL
);
INSERT INTO proc_approval_settings (id, allow_legacy_approval, legacy_grace_note)
VALUES (TRUE, FALSE, 'افتراضيًا مُعطَّل — عند التفعيل يُسمح بالنمط القديم مؤقتًا')
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS proc_approval_settings_updated_at ON proc_approval_settings;
CREATE TRIGGER proc_approval_settings_updated_at BEFORE UPDATE ON proc_approval_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE proc_approval_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS proc_appr_settings_sel ON proc_approval_settings;
CREATE POLICY proc_appr_settings_sel ON proc_approval_settings FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS proc_appr_settings_wr ON proc_approval_settings;
CREATE POLICY proc_appr_settings_wr ON proc_approval_settings FOR UPDATE TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager', 'procurement_manager', 'finance_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager', 'procurement_manager', 'finance_manager'));

-- ───────────────────────────────────────────────────────────
-- B) proc_requisitions: تخزين snapshot للإجمالي عند التقديم
--    عمود جديد فقط — لا نغيّر أي عمود قائم
-- ───────────────────────────────────────────────────────────
ALTER TABLE proc_requisitions
  ADD COLUMN IF NOT EXISTS amount_at_submit NUMERIC(14,2);
ALTER TABLE proc_requisitions
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- C) Trigger guards — تُنفَّذ فقط عندما الكاتب هو دور العميل
-- ═══════════════════════════════════════════════════════════
-- الفكرة: RPCs تعمل SECURITY DEFINER بمالك الدالة (postgres/service)
--         فيصبح current_user غير 'authenticated'/'anon'، فتُتخطى الحماية.
--         الاستعلامات المباشرة من العميل عبر PostgREST تعمل بدور
--         authenticated، فتُطبق الحماية.
-- ═══════════════════════════════════════════════════════════

-- Guard 1: تغييرات proc_requisitions من العميل
CREATE OR REPLACE FUNCTION proc_req_update_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_chain BOOLEAN;
BEGIN
  -- تجاهُل: RPCs (تعمل بمالك الدالة، ليس authenticated)
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- هل يوجد سلسلة اعتماد لهذا الطلب؟
  SELECT EXISTS (SELECT 1 FROM proc_requisition_approvals WHERE requisition_id = OLD.id)
    INTO v_has_chain;

  -- (1) عندما توجد سلسلة، ممنوع تغيير status إلى approved/rejected
  --     أو أي انتقال حالة مباشر — يجب المرور عبر RPCs.
  IF v_has_chain
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('approved', 'rejected', 'cancelled', 'converted') THEN
    RAISE EXCEPTION 'APPROVAL_MULTI_LEVEL_ACTIVE: استخدم proc_approve_step / proc_reject_step / proc_cancel_requisition_approval بدل UPDATE المباشر';
  END IF;

  -- (2) بعد التقديم أو الاعتماد، ممنوع تعديل الحقول المؤثرة على مطابقة القواعد
  IF OLD.status IN ('submitted', 'approved')
     AND (NEW.branch_id IS DISTINCT FROM OLD.branch_id
          OR NEW.department_id IS DISTINCT FROM OLD.department_id) THEN
    RAISE EXCEPTION 'REQ_LOCKED_FIELDS: لا يمكن تعديل الفرع أو القسم بعد التقديم — ألغِ المسار أولًا';
  END IF;

  -- (3) الرفض يستوجب سببًا واضحًا (لا نصوصًا فارغة أو NULL)
  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
      RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: سبب الرفض مطلوب';
    END IF;
  END IF;

  -- (4) الحالات النهائية لا يُخرَج منها
  IF OLD.status IN ('rejected', 'cancelled', 'converted')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'REQ_TERMINAL_STATE: الطلب في حالة نهائية (%) — لا يمكن تغييرها', OLD.status;
  END IF;

  -- (5) لا يمكن الرجوع من submitted إلى draft عبر UPDATE مباشر
  IF OLD.status = 'submitted' AND NEW.status = 'draft' THEN
    RAISE EXCEPTION 'REQ_INVALID_TRANSITION: لا يُسمح بإرجاع الطلب إلى draft — استخدم إلغاء المسار';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_req_update_guard_trg ON proc_requisitions;
CREATE TRIGGER proc_req_update_guard_trg
  BEFORE UPDATE ON proc_requisitions
  FOR EACH ROW EXECUTE FUNCTION proc_req_update_guard();

-- Guard 2: تعديل بنود الطلب — يمنع أي INSERT/UPDATE/DELETE إذا الطلب ليس مسودة
CREATE OR REPLACE FUNCTION proc_req_items_write_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req_id BIGINT;
  v_status TEXT;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_req_id := COALESCE(NEW.requisition_id, OLD.requisition_id);
  SELECT status INTO v_status FROM proc_requisitions WHERE id = v_req_id;

  IF v_status IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'REQ_ITEMS_LOCKED: لا يمكن تعديل بنود الطلب — الحالة الحالية %', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS proc_req_items_write_guard_trg ON proc_requisition_items;
CREATE TRIGGER proc_req_items_write_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON proc_requisition_items
  FOR EACH ROW EXECUTE FUNCTION proc_req_items_write_guard();

-- Guard 3: منع إنشاء أمر شراء لطلب لم يكتمل اعتماده
CREATE OR REPLACE FUNCTION proc_po_creation_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status  TEXT;
  v_pending INT;
BEGIN
  -- هذا الحرس عام — يُنفَّذ حتى للـSECURITY DEFINER لأن دفاع بعمق
  IF NEW.requisition_id IS NULL THEN
    RETURN NEW;  -- PO بدون requisition (شراء مباشر) — يمر
  END IF;

  SELECT status INTO v_status FROM proc_requisitions WHERE id = NEW.requisition_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'REQ_NOT_FOUND: طلب الشراء المرتبط غير موجود';
  END IF;

  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'PO_BEFORE_APPROVAL: لا يمكن إنشاء أمر شراء قبل اكتمال الاعتماد (الحالة: %)', v_status;
  END IF;

  SELECT COUNT(*) INTO v_pending
    FROM proc_requisition_approvals
    WHERE requisition_id = NEW.requisition_id AND status = 'pending';
  IF v_pending > 0 THEN
    RAISE EXCEPTION 'PO_STEPS_PENDING: توجد % خطوات اعتماد لم تُحسم بعد', v_pending;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_po_creation_guard_trg ON proc_purchase_orders;
CREATE TRIGGER proc_po_creation_guard_trg
  BEFORE INSERT ON proc_purchase_orders
  FOR EACH ROW EXECUTE FUNCTION proc_po_creation_guard();

-- ═══════════════════════════════════════════════════════════
-- D) إعادة كتابة proc_submit_requisition:
--    - يستدعي فحص المصادقة والنشاط
--    - يستخدم advisory lock لمنع تقديمين متزامنين لنفس الطلب
--    - يفشل بـAPPROVAL_CONFIGURATION_MISSING إذا لم توجد قاعدة
--      ولم يُفعَّل flag legacy
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_submit_requisition(p_req_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req         RECORD;
  v_caller      BIGINT := current_app_user_id();
  v_role        TEXT   := current_app_role();
  v_amount      NUMERIC;
  v_rule        RECORD;
  v_steps       INT := 0;
  v_mode        TEXT;
  v_allow_leg   BOOLEAN;
  v_caller_ok   BOOLEAN;
BEGIN
  -- (0) فحص المصادقة
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  -- (1) قفل الطلب على مستوى المعاملة (Advisory Lock)
  --     نستخدم توقيع (integer, integer) لأن (bigint, bigint) غير موجود.
  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), p_req_id::INT);

  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQ_NOT_FOUND: الطلب غير موجود'; END IF;

  IF v_req.requested_by <> v_caller AND NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: ليس لديك صلاحية تقديم هذا الطلب';
  END IF;

  IF v_req.status <> 'draft' THEN
    RAISE EXCEPTION 'REQ_INVALID_STATE: الطلب في حالة % — لا يمكن تقديمه', v_req.status;
  END IF;

  -- (2) اقرأ flag النمط القديم
  SELECT allow_legacy_approval INTO v_allow_leg FROM proc_approval_settings WHERE id = TRUE;
  v_allow_leg := COALESCE(v_allow_leg, FALSE);

  v_amount := proc_requisition_total(p_req_id);

  -- (3) امسح خطوات قديمة (في حال إعادة تقديم لطلب رجع لأي سبب)
  DELETE FROM proc_requisition_approvals WHERE requisition_id = p_req_id;

  -- (4) طابِق القواعد وأنشئ الخطوات
  FOR v_rule IN
    SELECT * FROM proc_match_approval_rules(v_amount, v_req.branch_id, v_req.department_id)
  LOOP
    INSERT INTO proc_requisition_approvals (
      requisition_id, step_no, required_role, status, rule_snapshot
    ) VALUES (
      p_req_id, v_rule.step_order, v_rule.required_role, 'pending',
      json_build_object(
        'rule_id', v_rule.rule_id,
        'rule_name', v_rule.rule_name,
        'specificity', v_rule.specificity,
        'amount_at_submit', v_amount
      )
    );
    v_steps := v_steps + 1;
  END LOOP;

  -- (5) لا توجد قاعدة مطابقة؟
  IF v_steps = 0 THEN
    IF NOT v_allow_leg THEN
      RAISE EXCEPTION 'APPROVAL_CONFIGURATION_MISSING: لا توجد قواعد اعتماد مطابقة (مبلغ=%، فرع=%، قسم=%). أضف قاعدة اعتماد قبل التقديم.',
        v_amount, v_req.branch_id, v_req.department_id;
    END IF;
    v_mode := 'legacy';
  ELSE
    v_mode := 'multi';
  END IF;

  -- (6) تحديث حالة الطلب وحفظ snapshot المبلغ ووقت التقديم
  UPDATE proc_requisitions
  SET status = 'submitted',
      amount_at_submit = v_amount,
      submitted_at     = now()
  WHERE id = p_req_id;

  -- (7) سجل النشاط
  INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
  VALUES (
    p_req_id,
    CASE WHEN v_mode = 'multi' THEN 'submitted' ELSE 'legacy_submit' END,
    v_caller, v_role,
    CASE WHEN v_mode = 'multi'
      THEN 'تم التقديم مع ' || v_steps || ' خطوة اعتماد'
      ELSE 'تم التقديم بالنمط القديم (flag مفعّل)'
    END,
    json_build_object('mode', v_mode, 'amount', v_amount, 'steps', v_steps)
  );

  RETURN json_build_object(
    'success',       TRUE,
    'mode',          v_mode,
    'steps_created', v_steps,
    'amount',        v_amount
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- E) إعادة كتابة proc_approve_step:
--    - Advisory Lock على الطلب لمنع السباقات على خطوات مختلفة
--    - Auth check + Active user check
--    - إعادة تأكيد status='pending' بعد الحصول على القفل
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_approve_step(
  p_step_id BIGINT,
  p_comment TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step         RECORD;
  v_req_id       BIGINT;
  v_req          RECORD;
  v_caller       BIGINT := current_app_user_id();
  v_role         TEXT   := current_app_role();
  v_prev_pending INT;
  v_remaining    INT;
  v_is_final     BOOLEAN := FALSE;
  v_caller_ok    BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  -- اقرأ requisition_id من الخطوة (بدون قفل بعد)
  SELECT requisition_id INTO v_req_id
    FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_req_id IS NULL THEN
    RAISE EXCEPTION 'STEP_NOT_FOUND: خطوة الاعتماد غير موجودة';
  END IF;

  -- Advisory Lock على الطلب — أي عملية اعتماد/رفض على نفس الطلب تنتظر
  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), v_req_id::INT);

  -- الآن اقفل الخطوة والطلب معًا وأعد قراءتهما
  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'STEP_NOT_PENDING: الخطوة في حالة % — لا يمكن اعتمادها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  -- منع الاعتماد الذاتي (سياسة صارمة افتراضيًا)
  IF v_req.requested_by = v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'SELF_APPROVAL_BLOCKED: لا يمكنك اعتماد طلبك';
  END IF;

  -- فحص الدور (admin يتخطى)
  IF v_role <> 'admin' AND v_role <> v_step.required_role THEN
    RAISE EXCEPTION 'ROLE_MISMATCH: دورك (%) لا يطابق الدور المطلوب (%)', v_role, v_step.required_role;
  END IF;

  -- تخصيص محدد لمستخدم؟
  IF v_step.assigned_to IS NOT NULL AND v_step.assigned_to <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'STEP_ASSIGNED_TO_OTHER: الخطوة معينة لمستخدم آخر';
  END IF;

  -- كل الخطوات الأقدم مُعتمَدة؟
  SELECT COUNT(*) INTO v_prev_pending FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id
      AND step_no < v_step.step_no
      AND status <> 'approved';
  IF v_prev_pending > 0 THEN
    RAISE EXCEPTION 'STEP_ORDER_VIOLATED: توجد % خطوات سابقة لم تُعتمَد', v_prev_pending;
  END IF;

  -- الاعتماد
  UPDATE proc_requisition_approvals
  SET status = 'approved', decided_by = v_caller, decided_at = now(), comment = p_comment
  WHERE id = p_step_id;

  SELECT COUNT(*) INTO v_remaining FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id AND status = 'pending';
  IF v_remaining = 0 THEN
    v_is_final := TRUE;
    UPDATE proc_requisitions
    SET status = 'approved', approved_by = v_caller, approved_at = now()
    WHERE id = v_step.requisition_id;
  END IF;

  INSERT INTO proc_approval_activity (requisition_id, approval_id, action, actor_id, actor_role, note)
  VALUES (v_step.requisition_id, p_step_id, 'approved', v_caller, v_role, p_comment);

  RETURN json_build_object(
    'success',         TRUE,
    'step_no',         v_step.step_no,
    'is_final',        v_is_final,
    'remaining_steps', v_remaining
  );
END;
$$;

-- إعادة كتابة proc_reject_step بنفس تحسينات القفل والمصادقة
CREATE OR REPLACE FUNCTION proc_reject_step(
  p_step_id BIGINT,
  p_reason  TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step         RECORD;
  v_req_id       BIGINT;
  v_req          RECORD;
  v_caller       BIGINT := current_app_user_id();
  v_role         TEXT   := current_app_role();
  v_caller_ok    BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: سبب الرفض مطلوب';
  END IF;

  SELECT requisition_id INTO v_req_id FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_req_id IS NULL THEN
    RAISE EXCEPTION 'STEP_NOT_FOUND: خطوة الاعتماد غير موجودة';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), v_req_id::INT);

  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'STEP_NOT_PENDING: الخطوة في حالة % — لا يمكن رفضها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  IF v_role <> 'admin' AND v_role <> v_step.required_role THEN
    RAISE EXCEPTION 'ROLE_MISMATCH: دورك (%) لا يطابق الدور المطلوب (%)', v_role, v_step.required_role;
  END IF;

  IF v_step.assigned_to IS NOT NULL AND v_step.assigned_to <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'STEP_ASSIGNED_TO_OTHER: الخطوة معينة لمستخدم آخر';
  END IF;

  UPDATE proc_requisition_approvals
  SET status = 'rejected', decided_by = v_caller, decided_at = now(), comment = p_reason
  WHERE id = p_step_id;

  UPDATE proc_requisition_approvals
  SET status = 'cancelled', decided_at = now()
  WHERE requisition_id = v_step.requisition_id
    AND step_no > v_step.step_no
    AND status = 'pending';

  UPDATE proc_requisitions
  SET status = 'rejected', approved_by = v_caller, approved_at = now(), rejection_reason = p_reason
  WHERE id = v_step.requisition_id;

  INSERT INTO proc_approval_activity (requisition_id, approval_id, action, actor_id, actor_role, note)
  VALUES (v_step.requisition_id, p_step_id, 'rejected', v_caller, v_role, p_reason);

  RETURN json_build_object('success', TRUE, 'step_no', v_step.step_no);
END;
$$;

-- Advisory lock + auth للـcancel أيضًا
CREATE OR REPLACE FUNCTION proc_cancel_requisition_approval(
  p_req_id BIGINT,
  p_reason TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req      RECORD;
  v_caller   BIGINT := current_app_user_id();
  v_role     TEXT   := current_app_role();
  v_caller_ok BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), p_req_id::INT);

  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQ_NOT_FOUND: الطلب غير موجود'; END IF;

  IF v_req.requested_by <> v_caller AND NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: ليس لديك صلاحية إلغاء الطلب';
  END IF;

  IF v_req.status <> 'submitted' THEN
    RAISE EXCEPTION 'REQ_INVALID_STATE: الإلغاء متاح فقط عندما الطلب في حالة submitted';
  END IF;

  UPDATE proc_requisition_approvals
  SET status = 'cancelled', decided_at = now()
  WHERE requisition_id = p_req_id AND status = 'pending';

  UPDATE proc_requisitions
  SET status = 'cancelled', rejection_reason = COALESCE(rejection_reason, p_reason)
  WHERE id = p_req_id;

  INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note)
  VALUES (p_req_id, 'cancelled', v_caller, v_role, p_reason);

  RETURN json_build_object('success', TRUE);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- F) RPC جديدة: proc_legacy_decide_requisition
--    يحل محل UPDATE المباشر للنمط القديم في DAL.
--    يعمل فقط عندما:
--     - flag allow_legacy_approval = TRUE
--     - لا توجد سلسلة اعتماد للطلب (v_steps = 0)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_legacy_decide_requisition(
  p_req_id   BIGINT,
  p_decision TEXT,   -- 'approve' or 'reject'
  p_reason   TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req        RECORD;
  v_caller     BIGINT := current_app_user_id();
  v_role       TEXT   := current_app_role();
  v_caller_ok  BOOLEAN;
  v_allow_leg  BOOLEAN;
  v_has_chain  BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  IF p_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION: القرار يجب أن يكون approve أو reject';
  END IF;

  IF p_decision = 'reject' AND (p_reason IS NULL OR length(trim(p_reason)) = 0) THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: سبب الرفض مطلوب';
  END IF;

  SELECT allow_legacy_approval INTO v_allow_leg FROM proc_approval_settings WHERE id = TRUE;
  IF NOT COALESCE(v_allow_leg, FALSE) THEN
    RAISE EXCEPTION 'LEGACY_DISABLED: النمط القديم غير مفعّل — أضف قاعدة اعتماد واستخدم proc_approve_step';
  END IF;

  IF NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: يشترط دور مدير مشتريات/مالية';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), p_req_id::INT);

  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQ_NOT_FOUND: الطلب غير موجود'; END IF;

  IF v_req.status <> 'submitted' THEN
    RAISE EXCEPTION 'REQ_INVALID_STATE: الطلب في حالة % — لا يمكن اتخاذ قرار', v_req.status;
  END IF;

  IF v_req.requested_by = v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'SELF_APPROVAL_BLOCKED: لا يمكنك اعتماد طلبك';
  END IF;

  -- التأكد من عدم وجود سلسلة (مسار قديم فعلًا)
  SELECT EXISTS (SELECT 1 FROM proc_requisition_approvals WHERE requisition_id = p_req_id)
    INTO v_has_chain;
  IF v_has_chain THEN
    RAISE EXCEPTION 'LEGACY_NOT_APPLICABLE: توجد سلسلة اعتماد — استخدم proc_approve_step / proc_reject_step';
  END IF;

  IF p_decision = 'approve' THEN
    UPDATE proc_requisitions
    SET status = 'approved', approved_by = v_caller, approved_at = now()
    WHERE id = p_req_id;
    INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note)
    VALUES (p_req_id, 'legacy_approve', v_caller, v_role, p_reason);
  ELSE
    UPDATE proc_requisitions
    SET status = 'rejected', approved_by = v_caller, approved_at = now(), rejection_reason = p_reason
    WHERE id = p_req_id;
    INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note)
    VALUES (p_req_id, 'legacy_reject', v_caller, v_role, p_reason);
  END IF;

  RETURN json_build_object('success', TRUE, 'decision', p_decision);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- ═══════════════════════════════════════════════════════════
-- 1) SELECT * FROM proc_approval_settings;  -- يجب أن يوجد صف واحد
-- 2) SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'proc_requisitions'
--    AND column_name IN ('amount_at_submit','submitted_at');
-- 3) SELECT tgname FROM pg_trigger WHERE tgname LIKE 'proc_%_guard_trg';
-- 4) اختبار: بدون قاعدة + flag OFF، proc_submit_requisition يجب أن يرفع
--    APPROVAL_CONFIGURATION_MISSING.
-- 5) اختبار: UPDATE مباشر على proc_requisitions لتغيير status إلى approved
--    عندما توجد chain — يجب أن يرفع APPROVAL_MULTI_LEVEL_ACTIVE.
-- 6) اختبار: INSERT في proc_purchase_orders بـrequisition_id لطلب draft
--    — يجب أن يرفع PO_BEFORE_APPROVAL.
-- ═══════════════════════════════════════════════════════════
