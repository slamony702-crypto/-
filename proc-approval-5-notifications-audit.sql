-- ═══════════════════════════════════════════════════════════
-- المشتريات — إشعارات + Audit + منع PO مكرر (Migration 5)
-- Wave: purchase-orders-wave1 (feature branch)
-- التاريخ: 2026-07-18
-- ═══════════════════════════════════════════════════════════
-- يتطلب: 1 + 2-hardening + 3-matching-priority + 4-snapshot
-- ═══════════════════════════════════════════════════════════
-- المحتوى:
--   A) جدول proc_approval_rules_history — سجل تدقيق لكل تعديل على قاعدة
--   B) Trigger على proc_approval_rules يسجل INSERT/UPDATE/DELETE
--   C) Trigger على proc_approval_settings يسجل تغيير flag legacy
--   D) Trigger BEFORE DELETE على proc_approval_rules يمنع الحذف
--      إذا استُخدمت في أي workflow (استخدم is_active = FALSE بدلًا)
--   E) UNIQUE constraint على proc_purchase_orders(requisition_id)
--      يمنع إنشاء PO مرتين لنفس الطلب
--   F) إشعارات integrated في RPCs (submit/approve/reject/cancel)
--      - INSERT في notifications (الجدول القائم)
--      - Idempotency: نعتمد على State Machine (كل transition يحدث مرة)
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════
-- (A) proc_approval_rules_history — سجل تدقيق
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS proc_approval_rules_history (
  id            BIGSERIAL PRIMARY KEY,
  rule_id       BIGINT,   -- لا FK: القاعدة قد تُحذف مستقبلًا (لكن نُبقي التاريخ)
  action        TEXT NOT NULL
                 CHECK (action IN ('created','updated','activated','deactivated',
                                   'delete_attempted','delete_blocked','settings_changed')),
  actor_id      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  actor_role    TEXT,
  old_values    JSONB,
  new_values    JSONB,
  changed_keys  TEXT[],
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_appr_rules_hist_rule_idx
  ON proc_approval_rules_history(rule_id, created_at DESC);
CREATE INDEX IF NOT EXISTS proc_appr_rules_hist_actor_idx
  ON proc_approval_rules_history(actor_id, created_at DESC);

-- RLS
ALTER TABLE proc_approval_rules_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS proc_appr_rules_hist_sel ON proc_approval_rules_history;
CREATE POLICY proc_appr_rules_hist_sel ON proc_approval_rules_history FOR SELECT TO authenticated USING (
  current_app_role() IN ('admin','company_manager','procurement_manager','finance_manager')
);
DROP POLICY IF EXISTS proc_appr_rules_hist_wr ON proc_approval_rules_history;
CREATE POLICY proc_appr_rules_hist_wr ON proc_approval_rules_history FOR INSERT TO authenticated
  WITH CHECK (current_app_role() = 'admin');

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- (B) Trigger مسجل التعديلات على proc_approval_rules
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_appr_rules_history_trg_fn()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor        BIGINT := current_app_user_id();
  v_role         TEXT   := current_app_role();
  v_changed_keys TEXT[] := ARRAY[]::TEXT[];
  v_action       TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO proc_approval_rules_history (
      rule_id, action, actor_id, actor_role, new_values, note
    ) VALUES (
      NEW.id, 'created', v_actor, v_role, to_jsonb(NEW),
      'إنشاء قاعدة اعتماد: ' || COALESCE(NEW.rule_name, '(بلا اسم)')
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    -- اجمع الحقول المتغيرة فقط
    IF NEW.rule_name       IS DISTINCT FROM OLD.rule_name       THEN v_changed_keys := array_append(v_changed_keys, 'rule_name'); END IF;
    IF NEW.description     IS DISTINCT FROM OLD.description     THEN v_changed_keys := array_append(v_changed_keys, 'description'); END IF;
    IF NEW.entity_type     IS DISTINCT FROM OLD.entity_type     THEN v_changed_keys := array_append(v_changed_keys, 'entity_type'); END IF;
    IF NEW.min_amount      IS DISTINCT FROM OLD.min_amount      THEN v_changed_keys := array_append(v_changed_keys, 'min_amount'); END IF;
    IF NEW.max_amount      IS DISTINCT FROM OLD.max_amount      THEN v_changed_keys := array_append(v_changed_keys, 'max_amount'); END IF;
    IF NEW.branch_id       IS DISTINCT FROM OLD.branch_id       THEN v_changed_keys := array_append(v_changed_keys, 'branch_id'); END IF;
    IF NEW.department_id   IS DISTINCT FROM OLD.department_id   THEN v_changed_keys := array_append(v_changed_keys, 'department_id'); END IF;
    IF NEW.required_role   IS DISTINCT FROM OLD.required_role   THEN v_changed_keys := array_append(v_changed_keys, 'required_role'); END IF;
    IF NEW.step_order      IS DISTINCT FROM OLD.step_order      THEN v_changed_keys := array_append(v_changed_keys, 'step_order'); END IF;
    IF NEW.priority        IS DISTINCT FROM OLD.priority        THEN v_changed_keys := array_append(v_changed_keys, 'priority'); END IF;
    IF NEW.is_active       IS DISTINCT FROM OLD.is_active       THEN v_changed_keys := array_append(v_changed_keys, 'is_active'); END IF;
    IF NEW.allow_self_approval IS DISTINCT FROM OLD.allow_self_approval THEN v_changed_keys := array_append(v_changed_keys, 'allow_self_approval'); END IF;
    IF NEW.sla_hours       IS DISTINCT FROM OLD.sla_hours       THEN v_changed_keys := array_append(v_changed_keys, 'sla_hours'); END IF;
    IF NEW.activation_date IS DISTINCT FROM OLD.activation_date THEN v_changed_keys := array_append(v_changed_keys, 'activation_date'); END IF;
    IF NEW.notes           IS DISTINCT FROM OLD.notes           THEN v_changed_keys := array_append(v_changed_keys, 'notes'); END IF;

    IF array_length(v_changed_keys, 1) IS NULL THEN
      RETURN NEW;  -- لا تغيير فعلي — لا تسجل
    END IF;

    -- إذا التغيير مقتصر على is_active، سجّل كـactivated/deactivated
    IF v_changed_keys = ARRAY['is_active']::TEXT[] THEN
      v_action := CASE WHEN NEW.is_active THEN 'activated' ELSE 'deactivated' END;
    ELSE
      v_action := 'updated';
    END IF;

    INSERT INTO proc_approval_rules_history (
      rule_id, action, actor_id, actor_role, old_values, new_values, changed_keys, note
    ) VALUES (
      NEW.id, v_action, v_actor, v_role,
      to_jsonb(OLD), to_jsonb(NEW), v_changed_keys,
      'تعديل ' || array_to_string(v_changed_keys, ', ')
    );
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO proc_approval_rules_history (
      rule_id, action, actor_id, actor_role, old_values, note
    ) VALUES (
      OLD.id, 'delete_attempted', v_actor, v_role, to_jsonb(OLD),
      'محاولة حذف قاعدة'
    );
    RETURN OLD;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS proc_appr_rules_history_trg ON proc_approval_rules;
CREATE TRIGGER proc_appr_rules_history_trg
  AFTER INSERT OR UPDATE OR DELETE ON proc_approval_rules
  FOR EACH ROW EXECUTE FUNCTION proc_appr_rules_history_trg_fn();

-- ═══════════════════════════════════════════════════════════
-- (C) Trigger لتسجيل تغيير flag legacy
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_appr_settings_history_trg_fn()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor BIGINT := current_app_user_id();
  v_role  TEXT   := current_app_role();
BEGIN
  IF NEW.allow_legacy_approval IS DISTINCT FROM OLD.allow_legacy_approval THEN
    INSERT INTO proc_approval_rules_history (
      rule_id, action, actor_id, actor_role, old_values, new_values, changed_keys, note
    ) VALUES (
      NULL, 'settings_changed', v_actor, v_role,
      jsonb_build_object('allow_legacy_approval', OLD.allow_legacy_approval),
      jsonb_build_object('allow_legacy_approval', NEW.allow_legacy_approval),
      ARRAY['allow_legacy_approval'],
      CASE WHEN NEW.allow_legacy_approval THEN 'تفعيل النمط القديم' ELSE 'تعطيل النمط القديم' END
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_appr_settings_history_trg ON proc_approval_settings;
CREATE TRIGGER proc_appr_settings_history_trg
  AFTER UPDATE ON proc_approval_settings
  FOR EACH ROW EXECUTE FUNCTION proc_appr_settings_history_trg_fn();

-- ═══════════════════════════════════════════════════════════
-- (D) منع حذف قاعدة مستخدمة — رغم ON DELETE SET NULL
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_appr_rules_delete_guard_fn()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM proc_requisition_approvals
    WHERE source_rule_id = OLD.id;

  IF v_count > 0 THEN
    -- سجّل محاولة الحذف المرفوضة
    INSERT INTO proc_approval_rules_history (
      rule_id, action, actor_id, actor_role, old_values, note
    ) VALUES (
      OLD.id, 'delete_blocked', current_app_user_id(), current_app_role(),
      to_jsonb(OLD),
      'رُفض الحذف: القاعدة مستخدمة في ' || v_count || ' طلب/طلبات'
    );
    RAISE EXCEPTION 'RULE_IN_USE: القاعدة مستخدمة في % طلبات — استخدم التعطيل (is_active=FALSE) بدل الحذف', v_count;
  END IF;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS proc_appr_rules_delete_guard_trg ON proc_approval_rules;
CREATE TRIGGER proc_appr_rules_delete_guard_trg
  BEFORE DELETE ON proc_approval_rules
  FOR EACH ROW EXECUTE FUNCTION proc_appr_rules_delete_guard_fn();

-- ═══════════════════════════════════════════════════════════
-- (E) UNIQUE على proc_purchase_orders(requisition_id) — يمنع PO مرتين
--     partial unique — يسمح بـPO بلا requisition (شراء مباشر) بلا حد
-- ═══════════════════════════════════════════════════════════
CREATE UNIQUE INDEX IF NOT EXISTS proc_po_unique_requisition
  ON proc_purchase_orders(requisition_id)
  WHERE requisition_id IS NOT NULL AND status NOT IN ('cancelled');
-- ملاحظة: نستثني PO المُلغى من UNIQUE لأن التاجر قد يُلغيه ويعيد الإنشاء
-- (لا COMMIT هنا — كل CREATE/ALTER أعلاه في auto-commit خارج BEGIN صريح.
--  BEGIN/COMMIT الوحيدة في هذا الملف كانت لـ Section A فقط.)

-- ═══════════════════════════════════════════════════════════
-- (F) دمج الإشعارات داخل RPCs
-- ═══════════════════════════════════════════════════════════
-- Helper: أرسل إشعارًا للمعتمدين المحتملين لخطوة معينة
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_notify_step_assignees(p_step_id BIGINT)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step    RECORD;
  v_req     RECORD;
  v_count   INT := 0;
BEGIN
  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_step IS NULL OR v_step.status <> 'pending' THEN RETURN 0; END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id;

  IF v_step.assigned_to IS NOT NULL THEN
    -- إشعار موجه لمستخدم محدد
    INSERT INTO notifications (user_id, title, body, link)
    VALUES (
      v_step.assigned_to,
      'طلب شراء ينتظر اعتمادك',
      'رقم الطلب: ' || v_req.requisition_no || ' — الخطوة رقم ' || v_step.step_no,
      '#proc_requisition/' || v_step.requisition_id
    );
    v_count := 1;
  ELSE
    -- إشعار جماعي لكل حاملي الدور النشطين (باستثناء صاحب الطلب)
    INSERT INTO notifications (user_id, title, body, link)
    SELECT u.id,
           'طلب شراء ينتظر اعتمادك',
           'رقم الطلب: ' || v_req.requisition_no || ' — الخطوة رقم ' || v_step.step_no || ' (' || v_step.required_role || ')',
           '#proc_requisition/' || v_step.requisition_id
    FROM users u
    WHERE u.role = v_step.required_role
      AND COALESCE(u.is_active, TRUE) = TRUE
      AND u.id <> v_req.requested_by;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;

  RETURN v_count;
END;
$$;

-- إعادة كتابة proc_submit_requisition لتُشعِر الخطوة الأولى فقط
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
  v_sqlstate    TEXT;
  v_sqlerr      TEXT;
  v_first_step  BIGINT;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول'; END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), p_req_id::INT);

  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQ_NOT_FOUND: الطلب غير موجود'; END IF;

  IF v_req.requested_by <> v_caller AND NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: ليس لديك صلاحية تقديم هذا الطلب';
  END IF;
  IF v_req.status <> 'draft' THEN
    RAISE EXCEPTION 'REQ_INVALID_STATE: الطلب في حالة % — لا يمكن تقديمه', v_req.status;
  END IF;

  SELECT allow_legacy_approval INTO v_allow_leg FROM proc_approval_settings WHERE id = TRUE;
  v_allow_leg := COALESCE(v_allow_leg, FALSE);

  v_amount := proc_requisition_total(p_req_id);

  DELETE FROM proc_requisition_approvals WHERE requisition_id = p_req_id;

  BEGIN
    FOR v_rule IN
      SELECT * FROM proc_match_approval_rules(v_amount, v_req.branch_id, v_req.department_id)
    LOOP
      INSERT INTO proc_requisition_approvals (
        requisition_id, step_no, required_role, status, source_rule_id, rule_snapshot
      ) VALUES (
        p_req_id, v_rule.step_order, v_rule.required_role, 'pending', v_rule.rule_id,
        json_build_object(
          'rule_id',             v_rule.rule_id,
          'rule_name',           v_rule.rule_name,
          'step_order',          v_rule.step_order,
          'required_role',       v_rule.required_role,
          'min_amount',          v_rule.min_amount,
          'max_amount',          v_rule.max_amount,
          'priority',            v_rule.priority,
          'branch_id',           v_req.branch_id,
          'department_id',       v_req.department_id,
          'specificity',         v_rule.specificity,
          'allow_self_approval', v_rule.allow_self_approval,
          'sla_hours',           v_rule.sla_hours,
          'amount_at_submit',    v_amount,
          'snapshot_at',         to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF')
        )
      );
      v_steps := v_steps + 1;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    v_sqlstate := SQLSTATE; v_sqlerr := SQLERRM;
    IF v_sqlerr LIKE '%AMBIGUOUS_APPROVAL_RULES%' THEN
      INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
      VALUES (p_req_id, 'submitted', v_caller, v_role,
              'رفض التقديم: AMBIGUOUS_APPROVAL_RULES',
              json_build_object('error', v_sqlerr, 'amount', v_amount));
      -- إشعار إداري: توجد قواعد متعارضة
      INSERT INTO notifications (user_id, title, body, link)
      SELECT u.id, 'تنبيه إداري: قواعد اعتماد متضاربة',
             'الطلب ' || v_req.requisition_no || ' — قواعد متعارضة تحتاج ضبطًا',
             '#proc_approval_rules'
      FROM users u
      WHERE u.role IN ('admin','company_manager','procurement_manager','finance_manager')
        AND COALESCE(u.is_active, TRUE) = TRUE;
    ELSIF v_sqlerr LIKE '%APPROVAL_CONFIGURATION_MISSING%' THEN
      -- (لن يُرفع من هنا لأن match ما يرفعه؛ سيُرفع أدناه لو v_steps=0)
      NULL;
    END IF;
    RAISE EXCEPTION '%', v_sqlerr USING ERRCODE = v_sqlstate;
  END;

  IF v_steps = 0 THEN
    IF NOT v_allow_leg THEN
      -- إشعار إداري: لا توجد قاعدة مطابقة
      INSERT INTO notifications (user_id, title, body, link)
      SELECT u.id, 'تنبيه إداري: لا توجد قاعدة اعتماد',
             'الطلب ' || v_req.requisition_no || ' — أضف قاعدة اعتماد مناسبة',
             '#proc_approval_rules'
      FROM users u
      WHERE u.role IN ('admin','company_manager','procurement_manager','finance_manager')
        AND COALESCE(u.is_active, TRUE) = TRUE;
      RAISE EXCEPTION 'APPROVAL_CONFIGURATION_MISSING: لا توجد قواعد اعتماد مطابقة';
    END IF;
    v_mode := 'legacy';
  ELSE
    v_mode := 'multi';
  END IF;

  UPDATE proc_requisitions
  SET status = 'submitted', amount_at_submit = v_amount, submitted_at = now()
  WHERE id = p_req_id;

  INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
  VALUES (
    p_req_id,
    CASE WHEN v_mode = 'multi' THEN 'submitted' ELSE 'legacy_submit' END,
    v_caller, v_role,
    CASE WHEN v_mode = 'multi' THEN 'تم التقديم مع ' || v_steps || ' خطوة اعتماد'
                                ELSE 'تم التقديم بالنمط القديم (flag مفعّل)' END,
    json_build_object('mode', v_mode, 'amount', v_amount, 'steps', v_steps)
  );

  -- إشعار الخطوة الأولى فقط (متعدد المستويات) أو مدراء المشتريات (legacy)
  IF v_mode = 'multi' THEN
    SELECT id INTO v_first_step FROM proc_requisition_approvals
    WHERE requisition_id = p_req_id AND step_no = (
      SELECT MIN(step_no) FROM proc_requisition_approvals
      WHERE requisition_id = p_req_id AND status = 'pending'
    );
    IF v_first_step IS NOT NULL THEN
      PERFORM proc_notify_step_assignees(v_first_step);
    END IF;
  ELSE
    -- legacy: إشعار كل مدراء المشتريات
    INSERT INTO notifications (user_id, title, body, link)
    SELECT u.id, 'طلب شراء ينتظر الاعتماد (نمط قديم)',
           'رقم الطلب: ' || v_req.requisition_no,
           '#proc_requisition/' || p_req_id
    FROM users u
    WHERE u.role IN ('admin','company_manager','procurement_manager','finance_manager')
      AND COALESCE(u.is_active, TRUE) = TRUE
      AND u.id <> v_req.requested_by;
  END IF;

  RETURN json_build_object(
    'success',       TRUE,
    'mode',          v_mode,
    'steps_created', v_steps,
    'amount',        v_amount
  );
END;
$$;

-- إعادة كتابة proc_approve_step: بعد الاعتماد يُشعر الخطوة التالية أو صاحب الطلب
CREATE OR REPLACE FUNCTION proc_approve_step(
  p_step_id BIGINT,
  p_comment TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step          RECORD;
  v_req_id        BIGINT;
  v_req           RECORD;
  v_caller        BIGINT := current_app_user_id();
  v_role          TEXT   := current_app_role();
  v_prev_pending  INT;
  v_remaining     INT;
  v_is_final      BOOLEAN := FALSE;
  v_caller_ok     BOOLEAN;
  v_allow_self    BOOLEAN;
  v_next_step_id  BIGINT;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول'; END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط'; END IF;

  SELECT requisition_id INTO v_req_id FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_req_id IS NULL THEN RAISE EXCEPTION 'STEP_NOT_FOUND: خطوة الاعتماد غير موجودة'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions'), v_req_id::INT);

  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'STEP_NOT_PENDING: الخطوة في حالة % — لا يمكن اعتمادها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  v_allow_self := COALESCE((v_step.rule_snapshot->>'allow_self_approval')::BOOLEAN, FALSE);
  IF v_req.requested_by = v_caller AND v_role <> 'admin' AND NOT v_allow_self THEN
    RAISE EXCEPTION 'SELF_APPROVAL_BLOCKED: لا يمكنك اعتماد طلبك';
  END IF;

  IF v_role <> 'admin' AND v_role <> v_step.required_role THEN
    RAISE EXCEPTION 'ROLE_MISMATCH: دورك (%) لا يطابق الدور المطلوب (%)', v_role, v_step.required_role;
  END IF;

  IF v_step.assigned_to IS NOT NULL AND v_step.assigned_to <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'STEP_ASSIGNED_TO_OTHER: الخطوة معينة لمستخدم آخر';
  END IF;

  SELECT COUNT(*) INTO v_prev_pending FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id
      AND step_no < v_step.step_no
      AND status <> 'approved';
  IF v_prev_pending > 0 THEN
    RAISE EXCEPTION 'STEP_ORDER_VIOLATED: توجد % خطوات سابقة لم تُعتمَد', v_prev_pending;
  END IF;

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

    -- إشعار صاحب الطلب بالاعتماد النهائي
    INSERT INTO notifications (user_id, title, body, link)
    VALUES (
      v_req.requested_by,
      'تم اعتماد طلب الشراء نهائيًا',
      'الطلب ' || v_req.requisition_no || ' معتمَد — يمكن الآن تحويله إلى أمر شراء',
      '#proc_requisition/' || v_step.requisition_id
    );
  ELSE
    -- إشعار الخطوة التالية فقط
    SELECT id INTO v_next_step_id FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id
      AND status = 'pending'
      AND step_no > v_step.step_no
    ORDER BY step_no ASC LIMIT 1;
    IF v_next_step_id IS NOT NULL THEN
      PERFORM proc_notify_step_assignees(v_next_step_id);
    END IF;
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

-- إعادة كتابة proc_reject_step: إشعار صاحب الطلب بالرفض
CREATE OR REPLACE FUNCTION proc_reject_step(
  p_step_id BIGINT,
  p_reason  TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step      RECORD;
  v_req_id    BIGINT;
  v_req       RECORD;
  v_caller    BIGINT := current_app_user_id();
  v_role      TEXT   := current_app_role();
  v_caller_ok BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول'; END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط'; END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: سبب الرفض مطلوب';
  END IF;

  SELECT requisition_id INTO v_req_id FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_req_id IS NULL THEN RAISE EXCEPTION 'STEP_NOT_FOUND: خطوة الاعتماد غير موجودة'; END IF;
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

  -- إشعار صاحب الطلب بالرفض
  INSERT INTO notifications (user_id, title, body, link)
  VALUES (
    v_req.requested_by,
    'تم رفض طلب الشراء',
    'الطلب ' || v_req.requisition_no || ' — السبب: ' || p_reason,
    '#proc_requisition/' || v_step.requisition_id
  );

  RETURN json_build_object('success', TRUE, 'step_no', v_step.step_no);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- قائمة التحقق:
--   SELECT relname FROM pg_class WHERE relname = 'proc_approval_rules_history';
--   SELECT tgname FROM pg_trigger WHERE tgname LIKE 'proc_appr_%';
--   SELECT indexname FROM pg_indexes WHERE indexname = 'proc_po_unique_requisition';
--   SELECT proname FROM pg_proc WHERE proname = 'proc_notify_step_assignees';
-- ═══════════════════════════════════════════════════════════
