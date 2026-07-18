-- ═══════════════════════════════════════════════════════════
-- المشتريات — اختبارات طبقة الاعتماد (12 سيناريو)
-- ═══════════════════════════════════════════════════════════
-- ⚠️ حصريًا لبيئة اختبار (Test / Staging / Supabase Branch)
-- ⚠️ لا تُشغّل هذا الملف على Production
-- ═══════════════════════════════════════════════════════════
-- شروط التنفيذ:
--   1) طبِّق أولًا proc-approval-1.sql
--   2) ثم طبِّق proc-approval-2-hardening.sql
--   3) أخيرًا شغّل هذا الملف
--
-- كيف يعمل:
--   - كل الاختبارات داخل معاملة (BEGIN…ROLLBACK) — لا تُغيّر البيانات النهائية
--   - يستخدم SAVEPOINT لعزل كل اختبار (فشل اختبار لا يوقف الباقين)
--   - يعتمد على set_config('request.jwt.claim.sub', ...) لمحاكاة المصادقة
--   - يُخرِج NOTICE بحالة كل اختبار (PASS / FAIL / EXPECTED_ERROR)
--
-- المستخدمون التجريبيون (تُنشأ إن لم توجد):
--   99001 = Requester           (role: employee)
--   99002 = Branch Manager      (role: branch_manager)
--   99003 = Procurement Manager (role: procurement_manager)
--   99004 = Finance Manager     (role: finance_manager)
--   99005 = Inactive User       (role: procurement_manager, is_active=FALSE)
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- إعداد: المستخدمون التجريبيون + auth_ids ثابتة
-- ───────────────────────────────────────────────────────────
INSERT INTO users (id, full_name, role, auth_id, is_active)
VALUES
  (99001, 'TEST Requester',       'employee',            '99999999-0000-0000-0000-000000090001'::UUID, TRUE),
  (99002, 'TEST Branch Manager',  'branch_manager',      '99999999-0000-0000-0000-000000090002'::UUID, TRUE),
  (99003, 'TEST Proc Manager',    'procurement_manager', '99999999-0000-0000-0000-000000090003'::UUID, TRUE),
  (99004, 'TEST Fin Manager',     'finance_manager',     '99999999-0000-0000-0000-000000090004'::UUID, TRUE),
  (99005, 'TEST Inactive PM',     'procurement_manager', '99999999-0000-0000-0000-000000090005'::UUID, FALSE)
ON CONFLICT (id) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- Helper: switch active user (SECURITY DEFINER wrapper)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _test_as(p_user_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_auth UUID;
BEGIN
  SELECT auth_id INTO v_auth FROM users WHERE id = p_user_id;
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'test user % has no auth_id — seed missing', p_user_id;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_auth::TEXT, TRUE);
END;
$$;

-- ───────────────────────────────────────────────────────────
-- Helper: create test requisition with items
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _test_create_req(
  p_amount NUMERIC, p_branch BIGINT DEFAULT NULL, p_dept BIGINT DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
BEGIN
  PERFORM _test_as(99001);  -- as requester
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (p_branch, p_dept, 99001, 'medium', CURRENT_DATE + 7, 'draft')
  RETURNING id INTO v_id;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_id, 'TEST Item', 1, 'unit', p_amount);
  RETURN v_id;
END;
$$;

-- ───────────────────────────────────────────────────────────
-- Reset test state
-- ───────────────────────────────────────────────────────────
UPDATE proc_approval_settings SET allow_legacy_approval = FALSE WHERE id = TRUE;
DELETE FROM proc_approval_rules WHERE rule_name LIKE 'TEST_%';

-- ═══════════════════════════════════════════════════════════
-- TEST 1: no matching rule + legacy flag OFF
--         → proc_submit_requisition يجب أن يفشل بـAPPROVAL_CONFIGURATION_MISSING
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t1;
DO $$
DECLARE
  v_req BIGINT;
BEGIN
  v_req := _test_create_req(500);
  BEGIN
    PERFORM proc_submit_requisition(v_req);
    RAISE NOTICE 'TEST 1: FAIL — كان يجب رفع APPROVAL_CONFIGURATION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%APPROVAL_CONFIGURATION_MISSING%' THEN
      RAISE NOTICE 'TEST 1: PASS — رُفع APPROVAL_CONFIGURATION_MISSING كما هو متوقع';
    ELSE
      RAISE NOTICE 'TEST 1: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t1;

-- ═══════════════════════════════════════════════════════════
-- TEST 2: one level approval — قاعدة واحدة، اعتماد واحد → approved
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t2;
DO $$
DECLARE
  v_req BIGINT;
  v_step_id BIGINT;
  v_final_status TEXT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001);
  PERFORM proc_submit_requisition(v_req);

  SELECT id INTO v_step_id FROM proc_requisition_approvals
    WHERE requisition_id = v_req AND status = 'pending' AND step_no = 1;

  PERFORM _test_as(99003);  -- procurement_manager
  PERFORM proc_approve_step(v_step_id, 'approved by test');

  SELECT status INTO v_final_status FROM proc_requisitions WHERE id = v_req;
  IF v_final_status = 'approved' THEN
    RAISE NOTICE 'TEST 2: PASS — الطلب أصبح approved بعد خطوة واحدة';
  ELSE
    RAISE NOTICE 'TEST 2: FAIL — الحالة الفعلية: %', v_final_status;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t2;

-- ═══════════════════════════════════════════════════════════
-- TEST 3: three level approval — تسلسل
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t3;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT; v_s2 BIGINT; v_s3 BIGINT;
  v_status_after_1 TEXT; v_status_after_2 TEXT; v_status_after_3 TEXT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order) VALUES
    ('TEST_L1', 0, 'branch_manager',      1),
    ('TEST_L2', 0, 'procurement_manager', 2),
    ('TEST_L3', 0, 'finance_manager',     3);

  v_req := _test_create_req(15000);
  PERFORM _test_as(99001);
  PERFORM proc_submit_requisition(v_req);

  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;
  SELECT id INTO v_s2 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 2;
  SELECT id INTO v_s3 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 3;

  -- خطوة 1: branch_manager
  PERFORM _test_as(99002); PERFORM proc_approve_step(v_s1, 'L1');
  SELECT status INTO v_status_after_1 FROM proc_requisitions WHERE id = v_req;

  -- خطوة 2: procurement_manager
  PERFORM _test_as(99003); PERFORM proc_approve_step(v_s2, 'L2');
  SELECT status INTO v_status_after_2 FROM proc_requisitions WHERE id = v_req;

  -- خطوة 3: finance_manager
  PERFORM _test_as(99004); PERFORM proc_approve_step(v_s3, 'L3');
  SELECT status INTO v_status_after_3 FROM proc_requisitions WHERE id = v_req;

  IF v_status_after_1 = 'submitted'
     AND v_status_after_2 = 'submitted'
     AND v_status_after_3 = 'approved' THEN
    RAISE NOTICE 'TEST 3: PASS — تسلسل 3 مستويات صحيح';
  ELSE
    RAISE NOTICE 'TEST 3: FAIL — L1=%, L2=%, L3=%', v_status_after_1, v_status_after_2, v_status_after_3;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t3;

-- ═══════════════════════════════════════════════════════════
-- TEST 4: out of order — اعتماد خطوة 2 قبل خطوة 1
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t4;
DO $$
DECLARE
  v_req BIGINT;
  v_s2 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order) VALUES
    ('TEST_L1', 0, 'branch_manager',      1),
    ('TEST_L2', 0, 'procurement_manager', 2);

  v_req := _test_create_req(3000);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s2 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 2;

  PERFORM _test_as(99003);  -- procurement_manager يحاول اعتماد step 2
  BEGIN
    PERFORM proc_approve_step(v_s2, 'try skip');
    RAISE NOTICE 'TEST 4: FAIL — كان يجب رفع STEP_ORDER_VIOLATED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%STEP_ORDER_VIOLATED%' THEN
      RAISE NOTICE 'TEST 4: PASS — تم منع تجاوز الخطوات';
    ELSE
      RAISE NOTICE 'TEST 4: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t4;

-- ═══════════════════════════════════════════════════════════
-- TEST 5: unauthorized approver — دور خاطئ يحاول الاعتماد
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t5;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'finance_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99002);  -- branch_manager يحاول اعتماد خطوة مطلوب لها finance_manager
  BEGIN
    PERFORM proc_approve_step(v_s1, 'wrong role');
    RAISE NOTICE 'TEST 5: FAIL — كان يجب رفع ROLE_MISMATCH';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ROLE_MISMATCH%' THEN
      RAISE NOTICE 'TEST 5: PASS — تم رفض الدور الخطأ';
    ELSE
      RAISE NOTICE 'TEST 5: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t5;

-- ═══════════════════════════════════════════════════════════
-- TEST 6: duplicate approval — محاولة اعتماد نفس الخطوة مرتين
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t6;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99003);
  PERFORM proc_approve_step(v_s1, 'first');  -- ينجح

  BEGIN
    PERFORM proc_approve_step(v_s1, 'second');  -- يجب أن يفشل
    RAISE NOTICE 'TEST 6: FAIL — كان يجب رفع STEP_NOT_PENDING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%STEP_NOT_PENDING%' THEN
      RAISE NOTICE 'TEST 6: PASS — تم رفض الاعتماد المكرر';
    ELSE
      RAISE NOTICE 'TEST 6: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t6;

-- ═══════════════════════════════════════════════════════════
-- TEST 7: concurrent approval — يدوي
-- ═══════════════════════════════════════════════════════════
-- لا يمكن محاكاة سباق داخل DO block واحد (المعاملة تسلسلية).
-- خطوات اختبار يدوي:
--   1) في psql session A:  BEGIN; SELECT _test_as(99003); SELECT proc_approve_step(<step_id>, 'A');
--   2) في psql session B (متوازيًا): BEGIN; SELECT _test_as(99003); SELECT proc_approve_step(<step_id>, 'B');
--   3) session A: COMMIT. النتيجة المتوقعة: session A تنجح، B تنتظر ثم تفشل بـSTEP_NOT_PENDING.
DO $$ BEGIN RAISE NOTICE 'TEST 7: SKIPPED — اختبار يدوي (concurrent). راجع التعليقات لخطوات psql'; END $$;

-- ═══════════════════════════════════════════════════════════
-- TEST 8: rejection with mandatory reason — رفض بدون سبب
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t8;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99003);
  BEGIN
    PERFORM proc_reject_step(v_s1, '');  -- سبب فارغ
    RAISE NOTICE 'TEST 8a: FAIL — كان يجب رفع REJECTION_REASON_REQUIRED (سبب فارغ)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REJECTION_REASON_REQUIRED%' THEN
      RAISE NOTICE 'TEST 8a: PASS — رفض السبب الفارغ';
    ELSE
      RAISE NOTICE 'TEST 8a: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  BEGIN
    PERFORM proc_reject_step(v_s1, NULL);  -- NULL
    RAISE NOTICE 'TEST 8b: FAIL — كان يجب رفع REJECTION_REASON_REQUIRED (NULL)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REJECTION_REASON_REQUIRED%' THEN
      RAISE NOTICE 'TEST 8b: PASS — رفض السبب NULL';
    ELSE
      RAISE NOTICE 'TEST 8b: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  -- سبب صحيح — يمر ويسجل
  PERFORM proc_reject_step(v_s1, 'not needed');
  IF EXISTS (SELECT 1 FROM proc_approval_activity
             WHERE requisition_id = v_req AND action = 'rejected' AND note = 'not needed') THEN
    RAISE NOTICE 'TEST 8c: PASS — الرفض بسبب صحيح مسجَّل';
  ELSE
    RAISE NOTICE 'TEST 8c: FAIL — لم يُسجَّل الرفض في activity';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t8;

-- ═══════════════════════════════════════════════════════════
-- TEST 9: resubmission after rejection — طلب مرفوض يحاول الرجوع
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t9;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99003); PERFORM proc_reject_step(v_s1, 'test rejection');

  -- الطلب الآن rejected. المحاولات المتوقعة:
  PERFORM _test_as(99001);
  BEGIN
    UPDATE proc_requisitions SET status = 'submitted' WHERE id = v_req;
    RAISE NOTICE 'TEST 9a: FAIL — كان يجب رفع REQ_TERMINAL_STATE (rejected → submitted)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_TERMINAL_STATE%' OR SQLERRM LIKE '%new row violates%' THEN
      RAISE NOTICE 'TEST 9a: PASS — منع تحويل rejected → submitted';
    ELSE
      RAISE NOTICE 'TEST 9a: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  BEGIN
    UPDATE proc_requisitions SET status = 'draft' WHERE id = v_req;
    RAISE NOTICE 'TEST 9b: FAIL — كان يجب رفع REQ_TERMINAL_STATE (rejected → draft)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_TERMINAL_STATE%' THEN
      RAISE NOTICE 'TEST 9b: PASS — منع الرجوع من rejected';
    ELSE
      RAISE NOTICE 'TEST 9b: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t9;

-- ═══════════════════════════════════════════════════════════
-- TEST 10: modification after submission
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t10;
DO $$
DECLARE
  v_req BIGINT;
  v_branch2 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  SELECT id INTO v_branch2 FROM branches WHERE is_active = TRUE LIMIT 1;

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);

  -- 10a: تعديل branch_id بعد التقديم
  BEGIN
    UPDATE proc_requisitions SET branch_id = v_branch2 WHERE id = v_req;
    RAISE NOTICE 'TEST 10a: FAIL — كان يجب رفع REQ_LOCKED_FIELDS';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_LOCKED_FIELDS%' THEN
      RAISE NOTICE 'TEST 10a: PASS — رفض تعديل branch_id بعد التقديم';
    ELSE
      RAISE NOTICE 'TEST 10a: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  -- 10b: تعديل بند من proc_requisition_items بعد التقديم
  BEGIN
    UPDATE proc_requisition_items SET quantity = 99 WHERE requisition_id = v_req;
    RAISE NOTICE 'TEST 10b: FAIL — كان يجب رفع REQ_ITEMS_LOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_ITEMS_LOCKED%' THEN
      RAISE NOTICE 'TEST 10b: PASS — رفض تعديل البنود بعد التقديم';
    ELSE
      RAISE NOTICE 'TEST 10b: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  -- 10c: حذف بند بعد التقديم
  BEGIN
    DELETE FROM proc_requisition_items WHERE requisition_id = v_req;
    RAISE NOTICE 'TEST 10c: FAIL — كان يجب رفع REQ_ITEMS_LOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_ITEMS_LOCKED%' THEN
      RAISE NOTICE 'TEST 10c: PASS — رفض حذف البنود بعد التقديم';
    ELSE
      RAISE NOTICE 'TEST 10c: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;

  -- 10d: إضافة بند بعد التقديم
  BEGIN
    INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
    VALUES (v_req, 'NEW after submit', 1, 'unit', 100);
    RAISE NOTICE 'TEST 10d: FAIL — كان يجب رفع REQ_ITEMS_LOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%REQ_ITEMS_LOCKED%' THEN
      RAISE NOTICE 'TEST 10d: PASS — رفض إضافة بند بعد التقديم';
    ELSE
      RAISE NOTICE 'TEST 10d: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t10;

-- ═══════════════════════════════════════════════════════════
-- TEST 11: conversion to PO BEFORE final approval
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t11;
DO $$
DECLARE
  v_req BIGINT;
  v_vendor BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  -- الطلب الآن status='submitted', فيه step pending

  SELECT id INTO v_vendor FROM acct_vendors LIMIT 1;
  IF v_vendor IS NULL THEN
    RAISE NOTICE 'TEST 11: SKIPPED — لا توجد موردون في acct_vendors';
    RETURN;
  END IF;

  BEGIN
    INSERT INTO proc_purchase_orders (vendor_id, requisition_id, created_by)
    VALUES (v_vendor, v_req, 99003);
    RAISE NOTICE 'TEST 11: FAIL — كان يجب رفع PO_BEFORE_APPROVAL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%PO_BEFORE_APPROVAL%' OR SQLERRM LIKE '%PO_STEPS_PENDING%' THEN
      RAISE NOTICE 'TEST 11: PASS — تم منع إنشاء PO قبل الاعتماد';
    ELSE
      RAISE NOTICE 'TEST 11: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT t11;

-- ═══════════════════════════════════════════════════════════
-- TEST 12: conversion to PO AFTER final approval → success
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t12;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
  v_vendor BIGINT;
  v_po BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99003);
  PERFORM proc_approve_step(v_s1, 'ok');

  SELECT id INTO v_vendor FROM acct_vendors LIMIT 1;
  IF v_vendor IS NULL THEN
    RAISE NOTICE 'TEST 12: SKIPPED — لا توجد موردون في acct_vendors';
    RETURN;
  END IF;

  BEGIN
    INSERT INTO proc_purchase_orders (vendor_id, requisition_id, created_by)
    VALUES (v_vendor, v_req, 99003) RETURNING id INTO v_po;
    IF v_po IS NOT NULL THEN
      RAISE NOTICE 'TEST 12: PASS — تم إنشاء PO رقم % بعد الاعتماد النهائي', v_po;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 12: FAIL — تعذّر إنشاء PO بعد الاعتماد: %', SQLERRM;
  END;
END $$;
ROLLBACK TO SAVEPOINT t12;

-- ═══════════════════════════════════════════════════════════
-- BONUS: TEST — inactive user
-- ═══════════════════════════════════════════════════════════
SAVEPOINT tb1;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  PERFORM _test_as(99005);  -- inactive user with procurement_manager role
  BEGIN
    PERFORM proc_approve_step(v_s1, 'inactive try');
    RAISE NOTICE 'BONUS TEST inactive: FAIL — كان يجب رفع USER_INACTIVE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%USER_INACTIVE%' THEN
      RAISE NOTICE 'BONUS TEST inactive: PASS — منع المستخدم غير النشط';
    ELSE
      RAISE NOTICE 'BONUS TEST inactive: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT tb1;

-- ═══════════════════════════════════════════════════════════
-- BONUS: TEST — self approval blocked
-- ═══════════════════════════════════════════════════════════
SAVEPOINT tb2;
DO $$
DECLARE
  v_req BIGINT;
  v_s1 BIGINT;
BEGIN
  -- سيناريو: مدير مشتريات (99003) يفتح طلبًا لنفسه ويحاول اعتماده
  UPDATE users SET role = 'procurement_manager' WHERE id = 99001;
  PERFORM _test_as(99001);

  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1);

  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (NULL, NULL, 99001, 'medium', CURRENT_DATE + 7, 'draft')
  RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'self test', 1, 'unit', 500);

  PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  BEGIN
    PERFORM proc_approve_step(v_s1, 'self');
    RAISE NOTICE 'BONUS TEST self-appr: FAIL — كان يجب رفع SELF_APPROVAL_BLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SELF_APPROVAL_BLOCKED%' THEN
      RAISE NOTICE 'BONUS TEST self-appr: PASS — منع الاعتماد الذاتي';
    ELSE
      RAISE NOTICE 'BONUS TEST self-appr: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT tb2;

-- ═══════════════════════════════════════════════════════════
-- BONUS: TEST — legacy flag ON enables legacy submit
-- ═══════════════════════════════════════════════════════════
SAVEPOINT tb3;
DO $$
DECLARE
  v_req BIGINT;
  v_result JSON;
  v_mode TEXT;
BEGIN
  -- تفعيل flag
  UPDATE proc_approval_settings SET allow_legacy_approval = TRUE WHERE id = TRUE;
  -- لا توجد قواعد
  v_req := _test_create_req(500);
  PERFORM _test_as(99001);
  v_result := proc_submit_requisition(v_req);
  v_mode := v_result ->> 'mode';
  IF v_mode = 'legacy' THEN
    RAISE NOTICE 'BONUS TEST legacy flag: PASS — تقديم بالنمط القديم اشتغل';
  ELSE
    RAISE NOTICE 'BONUS TEST legacy flag: FAIL — mode=%', v_mode;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT tb3;

-- ═══════════════════════════════════════════════════════════
-- TEST 16: disabled rule after workflow creation
--          → إذا عُطّلت قاعدة بعد إنشاء سلسلة، السلسلة القائمة تبقى سليمة
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t16;
DO $$
DECLARE
  v_req BIGINT;
  v_rule_id BIGINT;
  v_s1 BIGINT;
  v_status_before TEXT;
  v_status_after  TEXT;
BEGIN
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
  VALUES ('TEST_L1', 0, 'procurement_manager', 1)
  RETURNING id INTO v_rule_id;

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);
  SELECT id INTO v_s1 FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;
  SELECT status INTO v_status_before FROM proc_requisition_approvals WHERE id = v_s1;

  -- الآن نعطّل القاعدة
  UPDATE proc_approval_rules SET is_active = FALSE WHERE id = v_rule_id;

  -- الخطوة يجب أن تبقى pending وقابلة للاعتماد
  SELECT status INTO v_status_after FROM proc_requisition_approvals WHERE id = v_s1;

  PERFORM _test_as(99003);
  PERFORM proc_approve_step(v_s1, 'approve after rule disabled');

  IF v_status_before = 'pending' AND v_status_after = 'pending'
     AND (SELECT status FROM proc_requisitions WHERE id = v_req) = 'approved' THEN
    RAISE NOTICE 'TEST 16: PASS — تعطيل القاعدة لم يؤثر على السلسلة القائمة';
  ELSE
    RAISE NOTICE 'TEST 16: FAIL — before=%, after=%', v_status_before, v_status_after;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t16;

-- ═══════════════════════════════════════════════════════════
-- TEST 17: legacy fallback DISABLED — صريح
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t17;
DO $$
DECLARE
  v_req BIGINT;
  v_allow BOOLEAN;
BEGIN
  SELECT allow_legacy_approval INTO v_allow FROM proc_approval_settings WHERE id = TRUE;

  IF v_allow THEN
    RAISE NOTICE 'TEST 17: SKIPPED — flag ON (default should be FALSE, reset needed)';
  ELSE
    -- لا قواعد، flag OFF → يجب أن يرفض
    v_req := _test_create_req(1000);
    PERFORM _test_as(99001);
    BEGIN
      PERFORM proc_submit_requisition(v_req);
      RAISE NOTICE 'TEST 17: FAIL — كان يجب رفع APPROVAL_CONFIGURATION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE '%APPROVAL_CONFIGURATION_MISSING%' THEN
        RAISE NOTICE 'TEST 17: PASS — legacy disabled يرفض التقديم صراحة';
      ELSE
        RAISE NOTICE 'TEST 17: FAIL — خطأ غير متوقع: %', SQLERRM;
      END IF;
    END;
    -- تحقق أن الطلب لسه draft (ما تغيّرش)
    IF (SELECT status FROM proc_requisitions WHERE id = v_req) = 'draft' THEN
      RAISE NOTICE 'TEST 17b: PASS — الطلب باقٍ في draft بعد الرفض';
    ELSE
      RAISE NOTICE 'TEST 17b: FAIL — تغيّرت حالة الطلب رغم الرفض';
    END IF;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t17;

-- ═══════════════════════════════════════════════════════════
-- TEST 20: two matching rules — deterministic pick (branch+dept فوق global)
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t20;
DO $$
DECLARE
  v_req BIGINT;
  v_branch BIGINT;
  v_dept BIGINT;
  v_rule_global BIGINT;
  v_rule_specific BIGINT;
  v_selected_rule_id BIGINT;
  v_snapshot JSONB;
BEGIN
  SELECT id INTO v_branch FROM branches WHERE is_active = TRUE LIMIT 1;
  SELECT id INTO v_dept FROM departments LIMIT 1;
  IF v_branch IS NULL OR v_dept IS NULL THEN
    RAISE NOTICE 'TEST 20: SKIPPED — لا يوجد فرع أو قسم في القاعدة';
    RETURN;
  END IF;

  -- قاعدة عامة (global)
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order, priority)
  VALUES ('TEST_GLOBAL', 0, 'finance_manager', 1, 100)
  RETURNING id INTO v_rule_global;

  -- قاعدة أكثر تخصيصًا (branch + dept)
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order, priority, branch_id, department_id)
  VALUES ('TEST_SPECIFIC', 0, 'procurement_manager', 1, 100, v_branch, v_dept)
  RETURNING id INTO v_rule_specific;

  v_req := _test_create_req(500, v_branch, v_dept);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);

  SELECT (rule_snapshot->>'rule_id')::BIGINT INTO v_selected_rule_id
  FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  IF v_selected_rule_id = v_rule_specific THEN
    RAISE NOTICE 'TEST 20: PASS — القاعدة الأكثر تخصيصًا اُختيرت (rule_id=%)', v_selected_rule_id;
  ELSE
    RAISE NOTICE 'TEST 20: FAIL — تم اختيار rule_id=% بدل الأكثر تخصيصًا (%)', v_selected_rule_id, v_rule_specific;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t20;

-- ═══════════════════════════════════════════════════════════
-- TEST 20b: two matching rules with different priority — الأعلى priority يفوز
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t20b;
DO $$
DECLARE
  v_req BIGINT;
  v_rule_low BIGINT;
  v_rule_high BIGINT;
  v_selected BIGINT;
BEGIN
  -- قاعدتان عامتان بنفس النطاق، لكن priority مختلف
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order, priority)
  VALUES ('TEST_LOW_PRIO', 0, 'branch_manager', 1, 50)
  RETURNING id INTO v_rule_low;
  INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order, priority)
  VALUES ('TEST_HIGH_PRIO', 0, 'finance_manager', 1, 200)
  RETURNING id INTO v_rule_high;

  v_req := _test_create_req(500);
  PERFORM _test_as(99001); PERFORM proc_submit_requisition(v_req);

  SELECT (rule_snapshot->>'rule_id')::BIGINT INTO v_selected
  FROM proc_requisition_approvals WHERE requisition_id = v_req AND step_no = 1;

  IF v_selected = v_rule_high THEN
    RAISE NOTICE 'TEST 20b: PASS — الأعلى priority اُختير (rule_id=%)', v_selected;
  ELSE
    RAISE NOTICE 'TEST 20b: FAIL — priority لم يُطبَّق: v_selected=%, high=%', v_selected, v_rule_high;
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t20b;

-- ═══════════════════════════════════════════════════════════
-- TEST 21: AMBIGUOUS_APPROVAL_RULES — قاعدتان متطابقتان تمامًا
-- ═══════════════════════════════════════════════════════════
SAVEPOINT t21;
DO $$
DECLARE
  v_req BIGINT;
  v_r1 BIGINT; v_r2 BIGINT;
  v_now TIMESTAMPTZ := now();
BEGIN
  -- قاعدتان بنفس (specificity, range, priority, updated_at)
  INSERT INTO proc_approval_rules (rule_name, min_amount, max_amount, required_role, step_order, priority)
  VALUES ('TEST_A', 0, 1000, 'branch_manager', 1, 100)
  RETURNING id INTO v_r1;
  INSERT INTO proc_approval_rules (rule_name, min_amount, max_amount, required_role, step_order, priority)
  VALUES ('TEST_B', 0, 1000, 'finance_manager', 1, 100)
  RETURNING id INTO v_r2;
  -- توحيد updated_at لضمان التعادل التام
  UPDATE proc_approval_rules SET updated_at = v_now WHERE id IN (v_r1, v_r2);

  v_req := _test_create_req(500);
  PERFORM _test_as(99001);
  BEGIN
    PERFORM proc_submit_requisition(v_req);
    RAISE NOTICE 'TEST 21: FAIL — كان يجب رفع AMBIGUOUS_APPROVAL_RULES';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%AMBIGUOUS_APPROVAL_RULES%' THEN
      RAISE NOTICE 'TEST 21: PASS — التعادل التام اكتُشف ورُفع AMBIGUOUS_APPROVAL_RULES';
    ELSE
      RAISE NOTICE 'TEST 21: FAIL — خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
  -- تحقق أن الطلب لم يتقدم
  IF (SELECT status FROM proc_requisitions WHERE id = v_req) = 'draft' THEN
    RAISE NOTICE 'TEST 21b: PASS — الطلب باقٍ في draft بعد الرفض';
  ELSE
    RAISE NOTICE 'TEST 21b: FAIL — تغيّرت حالة الطلب رغم الرفض';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT t21;

-- ═══════════════════════════════════════════════════════════
-- تنظيف نهائي — ROLLBACK يلغي كل شيء (بما فيه المستخدمين التجريبيين)
-- ═══════════════════════════════════════════════════════════
ROLLBACK;

-- ═══════════════════════════════════════════════════════════
-- ملاحظة أخيرة:
-- بعد التنفيذ، راجع رسائل NOTICE في مخرجات psql/Supabase SQL Editor.
-- ابحث عن PASS/FAIL/SKIPPED.
-- الاختبارات: 12 core + 3 bonus + 5 (16, 17, 20, 20b, 21) = 20+
-- المتوقع: كل الاختبارات PASS (منها test 7 SKIPPED — يستخدم proc-concurrency-session-*.sql)
-- ═══════════════════════════════════════════════════════════
