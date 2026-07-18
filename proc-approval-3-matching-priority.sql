-- ═══════════════════════════════════════════════════════════
-- المشتريات — priority + AMBIGUOUS_APPROVAL_RULES (Migration 3)
-- Wave: purchase-orders-wave1 (feature branch)
-- التاريخ: 2026-07-18
-- ═══════════════════════════════════════════════════════════
-- يجب تطبيق proc-approval-1.sql و proc-approval-2-hardening.sql أولًا.
-- ═══════════════════════════════════════════════════════════
-- ما الذي يفعله:
--   1) يضيف عمود priority INT DEFAULT 100 إلى proc_approval_rules
--   2) يعيد كتابة proc_match_approval_rules لتستخدم ترتيبًا محددًا (4 معايير):
--        - specificity DESC (branch+dept > branch > dept > global)
--        - range width ASC (نطاق مالي أضيق يفوز)
--        - priority DESC (الأعلى يفوز)
--        - updated_at DESC (الأحدث فقط عند التعادل)
--        - id ASC (Deterministic last-resort — لا يشارك في AMBIGUOUS)
--   3) يرفع AMBIGUOUS_APPROVAL_RULES إذا بقي أكثر من قاعدة بنفس
--      (specificity, range_width, priority, updated_at) لنفس step_order
--   4) يعدّل proc_submit_requisition ليعالج AMBIGUOUS ويعيد الرسالة للعميل
-- ═══════════════════════════════════════════════════════════
-- كل شيء idempotent (ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE)
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- (1) عمود priority جديد
ALTER TABLE proc_approval_rules
  ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 100;

-- أي قواعد سابقة تحصل على priority = 100 (متوسط) — يمكن للمالك تعديلها لاحقًا
COMMENT ON COLUMN proc_approval_rules.priority IS 'رقم أعلى = أولوية أعلى. يُستخدم كـ tiebreaker بعد specificity و range_width.';

-- فهرس مساعد لتسريع فرز القواعد بنفس step_order
CREATE INDEX IF NOT EXISTS proc_approval_rules_rank_idx
  ON proc_approval_rules(entity_type, is_active, step_order, priority DESC);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- (2) إعادة كتابة proc_match_approval_rules
-- ═══════════════════════════════════════════════════════════
-- تحوّلت من SQL بسيطة إلى plpgsql عشان تقدر ترفع AMBIGUOUS
-- عند التعادل التام على المعايير الأربعة الرئيسية.
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_match_approval_rules(
  p_amount    NUMERIC,
  p_branch_id BIGINT,
  p_dept_id   BIGINT
) RETURNS TABLE (
  rule_id       BIGINT,
  step_order    INT,
  required_role TEXT,
  rule_name     TEXT,
  specificity   INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ambig_step INT;
  v_ambig_count INT;
BEGIN
  -- CTE scoring + ranking داخل subquery
  -- نستخدم DENSE_RANK على المعايير الأربعة "المعنوية" (specificity, range,
  -- priority, updated_at). id لا يشارك في التصنيف — يستخدم فقط عند الحاجة
  -- لاختيار deterministic بعد ما ثبت التمييز، لكن TIE على الأربعة = AMBIGUOUS.
  --
  -- (a) اكتشف أول step_order فيه تعادل تام
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
    RAISE EXCEPTION 'AMBIGUOUS_APPROVAL_RULES: يوجد % قواعد متساوية تمامًا على step_order = % — لا يمكن الاختيار. عدّل priority أو حدد نطاقًا أضيق أو اجعل إحدى القواعد غير نشطة.',
      v_ambig_count, v_ambig_step;
  END IF;

  -- (b) إذا لم يكن هناك تعادل، أرجع القواعد المطابقة بترتيبها
  RETURN QUERY
  WITH scored AS (
    SELECT
      r.id AS rid,
      r.step_order AS so,
      r.required_role AS rr,
      r.rule_name AS rn,
      ((CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
     + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)) AS sp,
      ROW_NUMBER() OVER (
        PARTITION BY r.step_order
        ORDER BY
          ((CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
         + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)) DESC,
          (r.max_amount IS NULL) ASC,
          COALESCE(r.max_amount - r.min_amount, 0) ASC,
          r.priority DESC,
          r.updated_at DESC,
          r.id ASC   -- deterministic last resort (لا يشارك في ambiguity check)
      ) AS rn_
    FROM proc_approval_rules r
    WHERE r.is_active = TRUE
      AND r.entity_type = 'requisition'
      AND p_amount >= r.min_amount
      AND (r.max_amount IS NULL OR p_amount <= r.max_amount)
      AND (r.branch_id     IS NULL OR r.branch_id     = p_branch_id)
      AND (r.department_id IS NULL OR r.department_id = p_dept_id)
  )
  SELECT s.rid, s.so, s.rr, s.rn, s.sp
  FROM scored s
  WHERE s.rn_ = 1
  ORDER BY s.so ASC;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- (3) تعديل proc_submit_requisition ليعالج AMBIGUOUS
-- ═══════════════════════════════════════════════════════════
-- الدالة الأصلية تستدعي proc_match_approval_rules داخل FOR loop.
-- المشكلة: إذا رفعت match الاستثناء AMBIGUOUS، ينتشر مباشرة إلى العميل.
-- هذا مقصود — لكن نضيف تسجيل في activity قبل الرفع لتوضيح السبب.
-- نعيد كتابة submit لتلتقط الاستثناء وتسجّل ثم ترفعه ثانية.
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

  -- التقاط استثناء AMBIGUOUS من match، تسجيله، ثم رفعه ثانية
  BEGIN
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
  EXCEPTION WHEN OTHERS THEN
    v_sqlstate := SQLSTATE;
    v_sqlerr   := SQLERRM;
    IF v_sqlerr LIKE '%AMBIGUOUS_APPROVAL_RULES%' THEN
      -- سجل في activity حتى لو ما زال draft
      INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
      VALUES (p_req_id, 'submitted', v_caller, v_role,
              'رفض التقديم: AMBIGUOUS_APPROVAL_RULES',
              json_build_object('error', v_sqlerr, 'amount', v_amount));
      RAISE EXCEPTION '%', v_sqlerr USING ERRCODE = v_sqlstate;
    END IF;
    -- أي خطأ آخر: أعِد رفعه
    RAISE EXCEPTION '%', v_sqlerr USING ERRCODE = v_sqlstate;
  END;

  IF v_steps = 0 THEN
    IF NOT v_allow_leg THEN
      RAISE EXCEPTION 'APPROVAL_CONFIGURATION_MISSING: لا توجد قواعد اعتماد مطابقة (مبلغ=%، فرع=%، قسم=%). أضف قاعدة اعتماد قبل التقديم.',
        v_amount, v_req.branch_id, v_req.department_id;
    END IF;
    v_mode := 'legacy';
  ELSE
    v_mode := 'multi';
  END IF;

  UPDATE proc_requisitions
  SET status = 'submitted',
      amount_at_submit = v_amount,
      submitted_at     = now()
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
-- قائمة تحقق ما بعد التنفيذ:
-- ═══════════════════════════════════════════════════════════
-- 1) SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'proc_approval_rules' AND column_name = 'priority';
--    → يجب أن يعود صف واحد
-- 2) SELECT * FROM proc_match_approval_rules(1000, NULL, NULL);
--    → إما يعود صفوف، أو يرفع AMBIGUOUS_APPROVAL_RULES
-- 3) تجربة تعادل تام:
--    INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order, priority)
--    VALUES ('R1', 0, 'branch_manager', 1, 100), ('R2', 0, 'finance_manager', 1, 100);
--    SELECT * FROM proc_match_approval_rules(500, NULL, NULL);
--    → يجب أن يرفع AMBIGUOUS
-- ═══════════════════════════════════════════════════════════
