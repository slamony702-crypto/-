-- ═══════════════════════════════════════════════════════════
-- المشتريات — طبقة اعتماد متعدد المستويات لطلبات الشراء
-- Wave: purchase-orders-wave1 (feature branch)
-- التاريخ: 2026-07-18
-- ═══════════════════════════════════════════════════════════
-- ✅ جميع التغييرات إضافية (Additive Only):
--    - لا يوجد ALTER TABLE على أي جدول قائم.
--    - لا يوجد DROP TABLE أو DROP CONSTRAINT.
--    - جداول جديدة فقط + Functions + RLS Policies.
-- ✅ قابل للتشغيل مرارًا (Idempotent): IF NOT EXISTS + CREATE OR REPLACE.
-- ✅ متوافق مع الخلف (Backward Compatible):
--    إذا لم تُعرَّف قواعد اعتماد، يعود proc_submit_requisition تلقائيًا
--    للسلوك القديم (approved_by واحد فقط) والمُعتمِد الحالي يشتغل زي ما كان.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) proc_approval_rules — مصفوفة قواعد الاعتماد
--    يُعرِّفها المالك عبر شاشة الإدارة (لا نضع بذور افتراضية).
--    كل قاعدة تحدد: أي مبلغ + أي فرع/قسم + أي دور مطلوب + رقم الخطوة.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_approval_rules (
  id                BIGSERIAL PRIMARY KEY,
  rule_name         TEXT NOT NULL,
  entity_type       TEXT NOT NULL DEFAULT 'requisition'
                     CHECK (entity_type IN ('requisition', 'purchase_order')),
  min_amount        NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (min_amount >= 0),
  max_amount        NUMERIC(14,2) CHECK (max_amount IS NULL OR max_amount >= min_amount),
  branch_id         BIGINT REFERENCES branches(id) ON DELETE CASCADE,
  department_id     BIGINT REFERENCES departments(id) ON DELETE CASCADE,
  required_role     TEXT NOT NULL,
  step_order        INT NOT NULL DEFAULT 1 CHECK (step_order >= 1),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  notes             TEXT,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_approval_rules_active_idx
  ON proc_approval_rules(entity_type, is_active, step_order)
  WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS proc_approval_rules_scope_idx
  ON proc_approval_rules(branch_id, department_id, min_amount);

DROP TRIGGER IF EXISTS proc_approval_rules_updated_at ON proc_approval_rules;
CREATE TRIGGER proc_approval_rules_updated_at BEFORE UPDATE ON proc_approval_rules
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) proc_requisition_approvals — نسخة لكل طلب من خطوات الاعتماد
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_requisition_approvals (
  id                BIGSERIAL PRIMARY KEY,
  requisition_id    BIGINT NOT NULL REFERENCES proc_requisitions(id) ON DELETE CASCADE,
  step_no           INT NOT NULL CHECK (step_no >= 1),
  required_role     TEXT NOT NULL,
  assigned_to       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'approved', 'rejected', 'skipped', 'cancelled')),
  decided_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  decided_at        TIMESTAMPTZ,
  comment           TEXT,
  rule_snapshot     JSONB,   -- snapshot للقاعدة اللي أنتجت الخطوة
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (requisition_id, step_no)
);

CREATE INDEX IF NOT EXISTS proc_req_approvals_req_idx
  ON proc_requisition_approvals(requisition_id, step_no);

CREATE INDEX IF NOT EXISTS proc_req_approvals_pending_idx
  ON proc_requisition_approvals(status, required_role)
  WHERE status = 'pending';

-- ───────────────────────────────────────────────────────────
-- 3) proc_approval_activity — سجل تدقيق كامل للاعتماد
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_approval_activity (
  id                BIGSERIAL PRIMARY KEY,
  requisition_id    BIGINT NOT NULL REFERENCES proc_requisitions(id) ON DELETE CASCADE,
  approval_id       BIGINT REFERENCES proc_requisition_approvals(id) ON DELETE SET NULL,
  action            TEXT NOT NULL
                     CHECK (action IN ('submitted','approved','rejected','cancelled',
                                       'resubmitted','skipped','legacy_submit',
                                       'legacy_approve','legacy_reject')),
  actor_id          BIGINT REFERENCES users(id) ON DELETE SET NULL,
  actor_role        TEXT,
  note              TEXT,
  metadata          JSONB,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_approval_activity_req_idx
  ON proc_approval_activity(requisition_id, created_at DESC);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- Helper: مطابقة القواعد لطلب معين
-- ═══════════════════════════════════════════════════════════
-- تُعيد القواعد الفعّالة المرتبة حسب step_order.
-- منطق التخصيص:
--   - القاعدة تُطبَّق إذا total_amount بين min_amount و max_amount (شامل)
--     و (branch_id NULL أو يطابق الفرع)
--     و (department_id NULL أو يطابق القسم)
--   - إذا وُجدت قواعد بنفس step_order، تُختار الأكثر تخصيصًا (branch+dept > branch > dept > global)
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
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  WITH candidates AS (
    SELECT
      r.id            AS rule_id,
      r.step_order,
      r.required_role,
      r.rule_name,
      -- درجة التخصيص: كل قيد محدد يضيف نقطة
      ( (CASE WHEN r.branch_id     IS NOT NULL THEN 2 ELSE 0 END)
      + (CASE WHEN r.department_id IS NOT NULL THEN 1 ELSE 0 END)
      ) AS specificity
    FROM proc_approval_rules r
    WHERE r.is_active = TRUE
      AND r.entity_type = 'requisition'
      AND p_amount >= r.min_amount
      AND (r.max_amount IS NULL OR p_amount <= r.max_amount)
      AND (r.branch_id     IS NULL OR r.branch_id     = p_branch_id)
      AND (r.department_id IS NULL OR r.department_id = p_dept_id)
  ),
  ranked AS (
    SELECT
      c.*,
      ROW_NUMBER() OVER (
        PARTITION BY c.step_order
        ORDER BY c.specificity DESC, c.rule_id ASC
      ) AS rn
    FROM candidates c
  )
  SELECT rule_id, step_order, required_role, rule_name, specificity
  FROM ranked
  WHERE rn = 1
  ORDER BY step_order ASC;
$$;

-- ═══════════════════════════════════════════════════════════
-- Helper: حساب إجمالي طلب الشراء التقديري
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_requisition_total(p_req_id BIGINT)
RETURNS NUMERIC
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(quantity * COALESCE(estimated_price, 0)), 0)::NUMERIC
  FROM proc_requisition_items
  WHERE requisition_id = p_req_id;
$$;

-- ═══════════════════════════════════════════════════════════
-- RPC 1: تقديم طلب شراء للاعتماد
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_submit_requisition(p_req_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req       RECORD;
  v_caller    BIGINT := current_app_user_id();
  v_role      TEXT   := current_app_role();
  v_amount    NUMERIC;
  v_rule      RECORD;
  v_steps     INT := 0;
  v_mode      TEXT;
BEGIN
  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطلب غير موجود'; END IF;

  -- التصريح: المالك يقدر يقدم، ومدير المشتريات كذلك
  IF v_req.requested_by <> v_caller AND NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تقديم هذا الطلب';
  END IF;

  IF v_req.status <> 'draft' THEN
    RAISE EXCEPTION 'الطلب في حالة % ولا يمكن تقديمه', v_req.status;
  END IF;

  v_amount := proc_requisition_total(p_req_id);

  -- امسح أي خطوات قديمة (لو الطلب اترجع وأُعيد تقديمه)
  DELETE FROM proc_requisition_approvals WHERE requisition_id = p_req_id;

  -- طابِق القواعد
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

  -- تحديث الحالة
  UPDATE proc_requisitions SET status = 'submitted' WHERE id = p_req_id;

  v_mode := CASE WHEN v_steps > 0 THEN 'multi' ELSE 'legacy' END;

  -- سجل تدقيق
  INSERT INTO proc_approval_activity (requisition_id, action, actor_id, actor_role, note, metadata)
  VALUES (
    p_req_id,
    CASE WHEN v_steps > 0 THEN 'submitted' ELSE 'legacy_submit' END,
    v_caller, v_role,
    CASE WHEN v_steps > 0
      THEN 'تم تقديم الطلب مع ' || v_steps || ' خطوة اعتماد'
      ELSE 'تم تقديم الطلب (لا توجد قواعد اعتماد — التدفق التقليدي)'
    END,
    json_build_object('mode', v_mode, 'amount', v_amount, 'steps', v_steps)
  );

  RETURN json_build_object(
    'success',        TRUE,
    'mode',           v_mode,
    'steps_created',  v_steps,
    'amount',         v_amount
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RPC 2: اعتماد خطوة
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
  v_req          RECORD;
  v_caller       BIGINT := current_app_user_id();
  v_role         TEXT   := current_app_role();
  v_prev_pending INT;
  v_remaining    INT;
  v_is_final     BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'خطوة الاعتماد غير موجودة'; END IF;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'الخطوة في حالة % ولا يمكن اعتمادها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  -- الحماية 1: منع اعتماد صاحب الطلب لطلبه (سياسة افتراضية آمنة)
  IF v_req.requested_by = v_caller AND v_role NOT IN ('admin') THEN
    RAISE EXCEPTION 'لا يمكن اعتماد طلبك بنفسك';
  END IF;

  -- الحماية 2: الأدوار المطلوبة (admin دائمًا مسموح)
  IF v_role <> 'admin' AND v_role <> v_step.required_role THEN
    RAISE EXCEPTION 'دورك (%) لا يطابق الدور المطلوب لهذه الخطوة (%)', v_role, v_step.required_role;
  END IF;

  -- الحماية 3: assigned_to لازم يكون فارغ أو المستدعي
  IF v_step.assigned_to IS NOT NULL AND v_step.assigned_to <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'هذه الخطوة معينة لمستخدم آخر';
  END IF;

  -- الحماية 4: كل الخطوات الأقدم لازم تكون معتمدة
  SELECT COUNT(*) INTO v_prev_pending FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id
      AND step_no < v_step.step_no
      AND status <> 'approved';
  IF v_prev_pending > 0 THEN
    RAISE EXCEPTION 'توجد خطوات سابقة لم تُعتمَد بعد';
  END IF;

  -- اعتماد
  UPDATE proc_requisition_approvals
  SET status = 'approved', decided_by = v_caller, decided_at = now(), comment = p_comment
  WHERE id = p_step_id;

  -- هل هي آخر خطوة؟
  SELECT COUNT(*) INTO v_remaining FROM proc_requisition_approvals
    WHERE requisition_id = v_step.requisition_id AND status = 'pending';
  IF v_remaining = 0 THEN
    v_is_final := TRUE;
    UPDATE proc_requisitions
    SET status = 'approved', approved_by = v_caller, approved_at = now()
    WHERE id = v_step.requisition_id;
  END IF;

  -- سجل تدقيق
  INSERT INTO proc_approval_activity (requisition_id, approval_id, action, actor_id, actor_role, note)
  VALUES (v_step.requisition_id, p_step_id, 'approved', v_caller, v_role, p_comment);

  RETURN json_build_object(
    'success',           TRUE,
    'step_no',           v_step.step_no,
    'is_final',          v_is_final,
    'remaining_steps',   v_remaining
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RPC 3: رفض خطوة (يرفض الطلب كاملًا)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_reject_step(
  p_step_id BIGINT,
  p_reason  TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_step         RECORD;
  v_req          RECORD;
  v_caller       BIGINT := current_app_user_id();
  v_role         TEXT   := current_app_role();
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'سبب الرفض مطلوب';
  END IF;

  SELECT * INTO v_step FROM proc_requisition_approvals WHERE id = p_step_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'خطوة الاعتماد غير موجودة'; END IF;
  IF v_step.status <> 'pending' THEN
    RAISE EXCEPTION 'الخطوة في حالة % ولا يمكن رفضها', v_step.status;
  END IF;

  SELECT * INTO v_req FROM proc_requisitions WHERE id = v_step.requisition_id FOR UPDATE;

  IF v_role <> 'admin' AND v_role <> v_step.required_role THEN
    RAISE EXCEPTION 'دورك (%) لا يطابق الدور المطلوب لهذه الخطوة (%)', v_role, v_step.required_role;
  END IF;

  IF v_step.assigned_to IS NOT NULL AND v_step.assigned_to <> v_caller AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'هذه الخطوة معينة لمستخدم آخر';
  END IF;

  -- رفض الخطوة الحالية
  UPDATE proc_requisition_approvals
  SET status = 'rejected', decided_by = v_caller, decided_at = now(), comment = p_reason
  WHERE id = p_step_id;

  -- إلغاء الخطوات اللاحقة
  UPDATE proc_requisition_approvals
  SET status = 'cancelled', decided_at = now()
  WHERE requisition_id = v_step.requisition_id
    AND step_no > v_step.step_no
    AND status = 'pending';

  -- رفض الطلب
  UPDATE proc_requisitions
  SET status = 'rejected', approved_by = v_caller, approved_at = now(), rejection_reason = p_reason
  WHERE id = v_step.requisition_id;

  INSERT INTO proc_approval_activity (requisition_id, approval_id, action, actor_id, actor_role, note)
  VALUES (v_step.requisition_id, p_step_id, 'rejected', v_caller, v_role, p_reason);

  RETURN json_build_object('success', TRUE, 'step_no', v_step.step_no);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RPC 4: إلغاء طلب أثناء الاعتماد (المالك أو مدير المشتريات)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_cancel_requisition_approval(
  p_req_id BIGINT,
  p_reason TEXT
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req    RECORD;
  v_caller BIGINT := current_app_user_id();
  v_role   TEXT   := current_app_role();
BEGIN
  SELECT * INTO v_req FROM proc_requisitions WHERE id = p_req_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطلب غير موجود'; END IF;

  IF v_req.requested_by <> v_caller AND NOT is_procurement_manager() THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إلغاء هذا الطلب';
  END IF;

  IF v_req.status NOT IN ('submitted') THEN
    RAISE EXCEPTION 'يمكن الإلغاء فقط عندما يكون الطلب في حالة "مُقدَّم"';
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
-- RPC 5: قراءة سلسلة الاعتماد لطلب
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_get_approval_chain(p_req_id BIGINT)
RETURNS JSON
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'steps', COALESCE(
      (SELECT json_agg(json_build_object(
        'id',            a.id,
        'step_no',       a.step_no,
        'required_role', a.required_role,
        'assigned_to',   a.assigned_to,
        'status',        a.status,
        'decided_by',    a.decided_by,
        'decided_by_name', (SELECT full_name FROM users WHERE id = a.decided_by),
        'decided_at',    a.decided_at,
        'comment',       a.comment,
        'rule_snapshot', a.rule_snapshot
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
-- RLS Policies
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE proc_approval_rules         ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_requisition_approvals  ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_approval_activity      ENABLE ROW LEVEL SECURITY;

-- قواعد الاعتماد: قراءة لكل المرتبطين بالمشتريات + المالية، كتابة للمدراء فقط
DROP POLICY IF EXISTS proc_appr_rules_sel ON proc_approval_rules;
CREATE POLICY proc_appr_rules_sel ON proc_approval_rules FOR SELECT TO authenticated USING (
  is_procurement_manager()
  OR current_app_role() IN ('finance_manager', 'ap_accountant', 'gl_accountant', 'branch_manager', 'deputy_manager')
);

DROP POLICY IF EXISTS proc_appr_rules_wr ON proc_approval_rules;
CREATE POLICY proc_appr_rules_wr ON proc_approval_rules FOR ALL TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager', 'procurement_manager', 'finance_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager', 'procurement_manager', 'finance_manager'));

-- خطوات اعتماد طلب: يشوفها الطالب + المُعتمِد + مدير المشتريات
DROP POLICY IF EXISTS proc_req_appr_sel ON proc_requisition_approvals;
CREATE POLICY proc_req_appr_sel ON proc_requisition_approvals FOR SELECT TO authenticated USING (
  is_procurement_manager()
  OR EXISTS (
    SELECT 1 FROM proc_requisitions r
    WHERE r.id = proc_requisition_approvals.requisition_id
      AND r.requested_by = current_app_user_id()
  )
  OR assigned_to = current_app_user_id()
  OR required_role = current_app_role()
);

-- كتابة الخطوات ممنوعة مباشرة من العميل — تتم فقط عبر RPCs (SECURITY DEFINER)
-- لكن نضع policy تسمح بها في حال احتاجها admin يدويًا:
DROP POLICY IF EXISTS proc_req_appr_wr ON proc_requisition_approvals;
CREATE POLICY proc_req_appr_wr ON proc_requisition_approvals FOR ALL TO authenticated
  USING (current_app_role() IN ('admin'))
  WITH CHECK (current_app_role() IN ('admin'));

-- سجل نشاط الاعتماد: نفس صلاحية القراءة، لا كتابة مباشرة
DROP POLICY IF EXISTS proc_appr_act_sel ON proc_approval_activity;
CREATE POLICY proc_appr_act_sel ON proc_approval_activity FOR SELECT TO authenticated USING (
  is_procurement_manager()
  OR EXISTS (
    SELECT 1 FROM proc_requisitions r
    WHERE r.id = proc_approval_activity.requisition_id
      AND (r.requested_by = current_app_user_id()
           OR current_app_role() IN ('finance_manager', 'ap_accountant', 'gl_accountant'))
  )
);

DROP POLICY IF EXISTS proc_appr_act_wr ON proc_approval_activity;
CREATE POLICY proc_appr_act_wr ON proc_approval_activity FOR INSERT TO authenticated
  WITH CHECK (current_app_role() IN ('admin'));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- ═══════════════════════════════════════════════════════════
-- 1) SELECT relname FROM pg_class WHERE relname IN
--    ('proc_approval_rules','proc_requisition_approvals','proc_approval_activity');
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'proc_%approv%' OR proname = 'proc_submit_requisition';
-- 3) SELECT proc_match_approval_rules(5000, NULL, NULL);  -- يجب أن يعود فارغًا حتى تُدخل قواعد
-- 4) SELECT proc_requisition_total(1);                    -- يعود إجمالي طلب رقم 1
--
-- سلوك افتراضي:
--   - لا توجد قواعد → proc_submit_requisition يرجع mode='legacy'
--     ويعمل النظام القديم (approve مباشر) كما كان.
--   - عند إضافة قواعد → mode='multi' وينشئ خطوات الاعتماد.
-- ═══════════════════════════════════════════════════════════
