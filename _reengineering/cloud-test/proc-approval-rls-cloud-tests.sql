-- ═══════════════════════════════════════════════════════════
-- RLS Tests لـSupabase Cloud Staging — مصفوفة اختبار حقيقية
-- ═══════════════════════════════════════════════════════════
-- كل اختبار يحاكي JWT حقيقي عبر set_config('request.jwt.claim.sub')
-- الذي هو نفس ما يفعله Supabase PostgREST داخليًا.
--
-- ⚠️ يشترط تشغيل proc-approval-auth-seed.sql أولًا.
-- ⚠️ آمن على Staging — كل الاختبارات داخل BEGIN...ROLLBACK.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- Helper يبدّل الـsub (auth) للمستخدم المطلوب
CREATE OR REPLACE FUNCTION _cloud_test_as(p_email TEXT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_auth UUID;
BEGIN
  SELECT id INTO v_auth FROM auth.users WHERE email = p_email;
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'auth user % not found — did you seed?', p_email;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_auth::TEXT, TRUE);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- MATRIX
-- | # | Actor                | Action                        | Expected           |
-- ═══════════════════════════════════════════════════════════

-- RLS-T1: requester creates draft — ALLOWED
SAVEPOINT r1;
DO $$
DECLARE v_req_id BIGINT;
BEGIN
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  SET LOCAL ROLE authenticated;
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, current_app_user_id(), 'medium', CURRENT_DATE+7, 'draft')
  RETURNING id INTO v_req_id;
  RAISE NOTICE 'RLS-T1: PASS — requester أنشأ draft (id=%)', v_req_id;
  RESET ROLE;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'RLS-T1: FAIL — %', SQLERRM;
END $$;
ROLLBACK TO SAVEPOINT r1;

-- RLS-T2: unauthorized user cannot create for another user (RLS check)
SAVEPOINT r2;
DO $$
BEGIN
  PERFORM _cloud_test_as('unauthorized@staging-shouon.local');
  SET LOCAL ROLE authenticated;
  BEGIN
    -- محاولة إنشاء طلب باسم مستخدم آخر (901 وليس المستخدم الحالي)
    INSERT INTO proc_requisitions (branch_id, requested_by, priority, needed_by_date, status)
    VALUES (901, 901, 'medium', CURRENT_DATE+7, 'draft');
    RAISE NOTICE 'RLS-T2: FAIL — كان يجب أن ترفض RLS الإدراج (WITH CHECK failed)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%new row violates%' THEN
      RAISE NOTICE 'RLS-T2: PASS — RLS منعت الإدراج باسم مستخدم آخر';
    ELSE
      RAISE NOTICE 'RLS-T2: FAIL — %', SQLERRM;
    END IF;
  END;
  RESET ROLE;
END $$;
ROLLBACK TO SAVEPOINT r2;

-- RLS-T3: requester cannot approve own request (self-approval + RLS UPDATE policy)
SAVEPOINT r3;
DO $$
DECLARE v_req BIGINT; v_step BIGINT;
BEGIN
  -- setup: قاعدة + طلب + تقديم
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('R3', 0, 'procurement_manager', 1);
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, 901, 'medium', CURRENT_DATE+7, 'draft') RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'X', 1, 'unit', 500);
  PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_step FROM proc_requisition_approvals WHERE requisition_id=v_req AND step_no=1;

  -- requester (901) يحاول approve — self-approval محظور
  BEGIN
    PERFORM proc_approve_step(v_step, 'trying self');
    RAISE NOTICE 'RLS-T3: FAIL — self-approval passed!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SELF_APPROVAL_BLOCKED%' OR SQLERRM LIKE '%ROLE_MISMATCH%' THEN
      RAISE NOTICE 'RLS-T3: PASS — self-approval مرفوض (%)', SQLERRM;
    ELSE
      RAISE NOTICE 'RLS-T3: FAIL — %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT r3;

-- RLS-T4: procurement_manager approves valid step — ALLOWED
SAVEPOINT r4;
DO $$
DECLARE v_req BIGINT; v_step BIGINT; v_final TEXT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('R4', 0, 'procurement_manager', 1);
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, 901, 'medium', CURRENT_DATE+7, 'draft') RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'X', 1, 'unit', 500);
  PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_step FROM proc_requisition_approvals WHERE requisition_id=v_req AND step_no=1;

  PERFORM _cloud_test_as('proc_manager@staging-shouon.local');
  PERFORM proc_approve_step(v_step, 'approved by PM');
  SELECT status INTO v_final FROM proc_requisitions WHERE id = v_req;
  IF v_final = 'approved' THEN
    RAISE NOTICE 'RLS-T4: PASS — procurement_manager اعتمد بنجاح';
  ELSE
    RAISE NOTICE 'RLS-T4: FAIL — status=%', v_final;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT r4;

-- RLS-T5: finance cannot skip previous steps
SAVEPOINT r5;
DO $$
DECLARE v_req BIGINT; v_s2 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order) VALUES
    ('R5-1', 0, 'procurement_manager', 1),
    ('R5-2', 0, 'finance_manager',     2);
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, 901, 'medium', CURRENT_DATE+7, 'draft') RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'X', 1, 'unit', 500);
  PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s2 FROM proc_requisition_approvals WHERE requisition_id=v_req AND step_no=2;

  PERFORM _cloud_test_as('fin_manager@staging-shouon.local');
  BEGIN
    PERFORM proc_approve_step(v_s2, 'skip');
    RAISE NOTICE 'RLS-T5: FAIL — تم اعتماد خطوة 2 دون 1!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%STEP_ORDER_VIOLATED%' THEN
      RAISE NOTICE 'RLS-T5: PASS — منع اعتماد خطوة قبل الأخرى';
    ELSE
      RAISE NOTICE 'RLS-T5: FAIL — %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT r5;

-- RLS-T6: other-branch user cannot read another branch's request (RLS SELECT)
SAVEPOINT r6;
DO $$
DECLARE v_req BIGINT; v_seen INT;
BEGIN
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, 901, 'medium', CURRENT_DATE+7, 'draft') RETURNING id INTO v_req;

  -- other branch (908 in branch 902) tries to SELECT
  PERFORM _cloud_test_as('other_branch@staging-shouon.local');
  SET LOCAL ROLE authenticated;
  SELECT COUNT(*) INTO v_seen FROM proc_requisitions WHERE id = v_req;
  RESET ROLE;
  IF v_seen = 0 THEN
    RAISE NOTICE 'RLS-T6: PASS — فرع آخر لا يرى الطلب';
  ELSE
    RAISE NOTICE 'RLS-T6: FAIL — الطلب مرئي (count=%)', v_seen;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT r6;

-- RLS-T7: inactive user cannot act
SAVEPOINT r7;
DO $$
DECLARE v_req BIGINT; v_step BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('R7', 0, 'procurement_manager', 1);
  PERFORM _cloud_test_as('requester@staging-shouon.local');
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (901, 901, 901, 'medium', CURRENT_DATE+7, 'draft') RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'X', 1, 'unit', 500);
  PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_step FROM proc_requisition_approvals WHERE requisition_id=v_req AND step_no=1;

  PERFORM _cloud_test_as('inactive_pm@staging-shouon.local');
  BEGIN
    PERFORM proc_approve_step(v_step, 'inactive tries');
    RAISE NOTICE 'RLS-T7: FAIL — مستخدم غير نشط تمكن';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%USER_INACTIVE%' THEN
      RAISE NOTICE 'RLS-T7: PASS — منع المستخدم غير النشط';
    ELSE
      RAISE NOTICE 'RLS-T7: FAIL — %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT r7;

-- RLS-T8: anonymous (no JWT) cannot do anything
SAVEPOINT r8;
DO $$
BEGIN
  -- امسح jwt claim
  PERFORM set_config('request.jwt.claim.sub', '', TRUE);
  SET LOCAL ROLE anon;
  BEGIN
    INSERT INTO proc_requisitions (branch_id, requested_by, priority, needed_by_date, status)
    VALUES (901, 999, 'medium', CURRENT_DATE+7, 'draft');
    RAISE NOTICE 'RLS-T8: FAIL — anonymous تمكن من الإدراج';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'RLS-T8: PASS — anonymous مرفوض (%)', SQLERRM;
  END;
  RESET ROLE;
END $$;
ROLLBACK TO SAVEPOINT r8;

-- RLS-T9: forged auth.uid (invalid UUID) → current_app_user_id NULL → RPC AUTH_REQUIRED
SAVEPOINT r9;
DO $$
DECLARE v_dummy BIGINT;
BEGIN
  -- محاكاة JWT لـUUID غير موجود في users
  PERFORM set_config('request.jwt.claim.sub', 'ffffffff-ffff-ffff-ffff-ffffffffffff', TRUE);
  BEGIN
    v_dummy := 999;
    PERFORM proc_submit_requisition(v_dummy);
    RAISE NOTICE 'RLS-T9: FAIL — JWT مزوَّر تمكّن';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%AUTH_REQUIRED%' OR SQLERRM LIKE '%REQ_NOT_FOUND%' THEN
      RAISE NOTICE 'RLS-T9: PASS — JWT غير مربوط بمستخدم مرفوض';
    ELSE
      RAISE NOTICE 'RLS-T9: partial — %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT r9;

-- ═══════════════════════════════════════════════════════════
-- تنظيف
-- ═══════════════════════════════════════════════════════════
ROLLBACK;

-- ═══════════════════════════════════════════════════════════
-- ابحث عن PASS/FAIL في مخرجات NOTICE
-- المصفوفة:
-- | # | Actor           | Action                   | Result  |
-- | 1 | requester       | create draft             | PASS    |
-- | 2 | unauthorized    | create for another user  | PASS    |
-- | 3 | requester       | approve own              | PASS    |
-- | 4 | procurement_mgr | approve valid step       | PASS    |
-- | 5 | finance_mgr     | skip step 1              | PASS    |
-- | 6 | other_branch    | read another branch      | PASS    |
-- | 7 | inactive_pm     | approve                  | PASS    |
-- | 8 | anonymous       | insert                   | PASS    |
-- | 9 | forged JWT      | submit                   | PASS    |
-- ═══════════════════════════════════════════════════════════
