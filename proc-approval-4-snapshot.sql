-- ═══════════════════════════════════════════════════════════
-- المشتريات — Snapshot كامل لمسار الاعتماد (Migration 4)
-- Wave: purchase-orders-wave1 (feature branch)
-- التاريخ: 2026-07-18
-- ═══════════════════════════════════════════════════════════
-- يتطلب: proc-approval-1.sql + proc-approval-2-hardening.sql + proc-approval-3-matching-priority.sql
-- ═══════════════════════════════════════════════════════════
-- ما الذي يفعله:
--   1) يضيف source_rule_id FK على proc_requisition_approvals للربط برقم القاعدة
--   2) يضيف حقول اختيارية على proc_approval_rules:
--        description, allow_self_approval, sla_hours, activation_date
--   3) يعيد كتابة proc_submit_requisition لتخزين snapshot موسّع في rule_snapshot:
--        كل الأدوار والحدود والـPriority والفرع والقسم عند وقت التقديم
--   4) يعدل proc_approve_step ليحترم allow_self_approval من الـsnapshot
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- (A) عمود ربط للقاعدة الأصلية
ALTER TABLE proc_requisition_approvals
  ADD COLUMN IF NOT EXISTS source_rule_id BIGINT REFERENCES proc_approval_rules(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS proc_req_appr_source_rule_idx
  ON proc_requisition_approvals(source_rule_id) WHERE source_rule_id IS NOT NULL;

-- (B) أعمدة إضافية على proc_approval_rules (اختيارية، Backward compatible)
ALTER TABLE proc_approval_rules
  ADD COLUMN IF NOT EXISTS description         TEXT,
  ADD COLUMN IF NOT EXISTS allow_self_approval BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sla_hours           INT     CHECK (sla_hours IS NULL OR sla_hours > 0),
  ADD COLUMN IF NOT EXISTS activation_date     DATE;

COMMENT ON COLUMN proc_approval_rules.description         IS 'وصف اختياري يظهر في شاشة الإدارة والتقارير';
COMMENT ON COLUMN proc_approval_rules.allow_self_approval IS 'إذا TRUE، يُسمح لصاحب الطلب باعتماد خطوة تخصه (نادر — عادةً false)';
COMMENT ON COLUMN proc_approval_rules.sla_hours           IS 'الحد الأقصى لعدد الساعات المتوقعة لهذه الخطوة (للتقارير — لا يفرض على النظام قسريًا)';
COMMENT ON COLUMN proc_approval_rules.activation_date     IS 'تاريخ سريان القاعدة — قواعد قبل هذا التاريخ لا تُطبَّق';

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- (C) إعادة كتابة proc_match_approval_rules لتحترم activation_date
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_match_approval_rules(
  p_amount    NUMERIC,
  p_branch_id BIGINT,
  p_dept_id   BIGINT
) RETURNS TABLE (
  rule_id             BIGINT,
  step_order          INT,
  required_role       TEXT,
  rule_name           TEXT,
  specificity         INT,
  min_amount          NUMERIC,
  max_amount          NUMERIC,
  priority            INT,
  allow_self_approval BOOLEAN,
  sla_hours           INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ambig_step  INT;
  v_ambig_count INT;
BEGIN
  -- كشف التعادل التام على المعايير الأربعة
  SELECT s.step_order, COUNT(*)
    INTO v_ambig_step, v_ambig_count
  FROM (
    SELECT
      r.step_order,
      DENSE_RANK() OVER (
        PARTITION BY r.step_order
        ORDER BY
          ((CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
         + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)) DESC,
          (r.max_amount IS NULL) ASC,
          COALESCE(r.max_amount - r.min_amount, 0) ASC,
          r.priority DESC,
          r.updated_at DESC
      ) AS dr
    FROM proc_approval_rules r
    WHERE r.is_active = TRUE
      AND r.entity_type = 'requisition'
      AND (r.activation_date IS NULL OR r.activation_date <= CURRENT_DATE)
      AND p_amount >= r.min_amount
      AND (r.max_amount IS NULL OR p_amount <= r.max_amount)
      AND (r.branch_id     IS NULL OR r.branch_id     = p_branch_id)
      AND (r.department_id IS NULL OR r.department_id = p_dept_id)
  ) s
  WHERE s.dr = 1
  GROUP BY s.step_order
  HAVING COUNT(*) > 1
  LIMIT 1;

  IF v_ambig_step IS NOT NULL THEN
    RAISE EXCEPTION 'AMBIGUOUS_APPROVAL_RULES: يوجد % قواعد متساوية تمامًا على step_order = % — عدّل priority أو النطاق أو activation_date',
      v_ambig_count, v_ambig_step;
  END IF;

  RETURN QUERY
  WITH scored AS (
    SELECT
      r.id                                        AS rid,
      r.step_order                                AS so,
      r.required_role                             AS rr,
      r.rule_name                                 AS rn,
      ((CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
     + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)) AS sp,
      r.min_amount                                AS mina,
      r.max_amount                                AS maxa,
      r.priority                                  AS pr,
      r.allow_self_approval                       AS asa,
      r.sla_hours                                 AS sla,
      ROW_NUMBER() OVER (
        PARTITION BY r.step_order
        ORDER BY
          ((CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
         + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)) DESC,
          (r.max_amount IS NULL) ASC,
          COALESCE(r.max_amount - r.min_amount, 0) ASC,
          r.priority DESC,
          r.updated_at DESC,
          r.id ASC
      ) AS rn_
    FROM proc_approval_rules r
    WHERE r.is_active = TRUE
      AND r.entity_type = 'requisition'
      AND (r.activation_date IS NULL OR r.activation_date <= CURRENT_DATE)
      AND p_amount >= r.min_amount
      AND (r.max_amount IS NULL OR p_amount <= r.max_amount)
      AND (r.branch_id     IS NULL OR r.branch_id     = p_branch_id)
      AND (r.department_id IS NULL OR r.department_id = p_dept_id)
  )
  SELECT s.rid, s.so, s.rr, s.rn, s.sp, s.mina, s.maxa, s.pr, s.asa, s.sla
  FROM scored s
  WHERE s.rn_ = 1
  ORDER BY s.so ASC;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- (D) إعادة كتابة proc_submit_requisition لتخزين snapshot موسّع
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
  v_sqlstate    TEXT;
  v_sqlerr      TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول';
  END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN
    RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions')::BIGINT, p_req_id);

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
    v_sqlstate := SQLSTATE;
    v_sqlerr   := SQLERRM;
    IF v_sqlerr LIKE '%AMBIGUOUS_APPROVAL_RULES%' THEN
      INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
      VALUES (p_req_id, 'submitted', v_caller, v_role,
              'رفض التقديم: AMBIGUOUS_APPROVAL_RULES',
              json_build_object('error', v_sqlerr, 'amount', v_amount));
      RAISE EXCEPTION '%', v_sqlerr USING ERRCODE = v_sqlstate;
    END IF;
    RAISE EXCEPTION '%', v_sqlerr USING ERRCODE = v_sqlstate;
  END;

  IF v_steps = 0 THEN
    IF NOT v_allow_leg THEN
      RAISE EXCEPTION 'APPROVAL_CONFIGURATION_MISSING: لا توجد قواعد اعتماد مطابقة (مبلغ=%، فرع=%، قسم=%)',
        v_amount, v_req.branch_id, v_req.department_id;
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
-- (E) proc_approve_step يحترم allow_self_approval من snapshot
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
  v_allow_self   BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED: يجب تسجيل الدخول'; END IF;
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN RAISE EXCEPTION 'USER_INACTIVE: المستخدم غير نشط'; END IF;

  SELECT requisition_id INTO v_req_id FROM proc_requisition_approvals WHERE id = p_step_id;
  IF v_req_id IS NULL THEN RAISE EXCEPTION 'STEP_NOT_FOUND: خطوة الاعتماد غير موجودة'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions')::BIGINT, v_req_id);

  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'STEP_NOT_PENDING: الخطوة في حالة % — لا يمكن اعتمادها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  -- Self-approval: تحقق من snapshot (وليس من القاعدة الحية)
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

-- ═══════════════════════════════════════════════════════════
-- (F) توسيع proc_get_approval_chain لتضم بيانات snapshot الكاملة
--     والقاعدة الأصلية (source_rule_id)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_get_approval_chain(p_req_id BIGINT)
RETURNS JSON
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'steps', COALESCE(
      (SELECT json_agg(json_build_object(
        'id',               a.id,
        'step_no',          a.step_no,
        'required_role',    a.required_role,
        'assigned_to',      a.assigned_to,
        'status',           a.status,
        'decided_by',       a.decided_by,
        'decided_by_name',  (SELECT full_name FROM users WHERE id = a.decided_by),
        'decided_at',       a.decided_at,
        'comment',          a.comment,
        'source_rule_id',   a.source_rule_id,
        'source_rule_active', COALESCE((SELECT is_active FROM proc_approval_rules WHERE id = a.source_rule_id), FALSE),
        'rule_snapshot',    a.rule_snapshot
      ) ORDER BY a.step_no)
      FROM proc_requisition_approvals a
      WHERE a.requisition_id = p_req_id
      ), '[]'::json),
    'activity', COALESCE(
      (SELECT json_agg(json_build_object(
        'id',         act.id,
        'action',     act.action,
        'actor_id',   act.actor_id,
        'actor_name', (SELECT full_name FROM users WHERE id = act.actor_id),
        'actor_role', act.actor_role,
        'note',       act.note,
        'created_at', act.created_at
      ) ORDER BY act.created_at DESC)
      FROM proc_approval_activity act
      WHERE act.requisition_id = p_req_id
      ), '[]'::json)
  );
$$;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق بعد التنفيذ:
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'proc_requisition_approvals' AND column_name = 'source_rule_id';
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'proc_approval_rules'
--       AND column_name IN ('description','allow_self_approval','sla_hours','activation_date');
-- ═══════════════════════════════════════════════════════════
