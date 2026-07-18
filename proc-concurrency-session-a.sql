-- ═══════════════════════════════════════════════════════════
-- اختبار التزامن — الجلسة (A)
-- ═══════════════════════════════════════════════════════════
-- ⚠️ يشتغل بالتوازي مع proc-concurrency-session-b.sql في جلسة psql منفصلة
-- ═══════════════════════════════════════════════════════════
-- الطريقة:
--   1) افتح Terminal 1 → psql على staging → شغل هذا الملف
--      أو من Supabase Dashboard: SQL Editor tab 1
--   2) افتح Terminal 2 → psql على نفس staging → شغل session-b.sql
--      أو Supabase Dashboard tab 2
--   3) اتّبع التعليمات التي تُطبَع (RAISE NOTICE) في كلا الجلستين
--
-- النتيجة المتوقعة:
--   - الجلسة (A) تعتمد الخطوة بنجاح
--   - الجلسة (B) تنتظر (advisory lock) ثم تفشل بـSTEP_NOT_PENDING
--   - الطلب يصبح approved مرة واحدة فقط
--   - لا سجل نشاط مكرر
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- الإعداد: نفس المستخدمين والقاعدة كما في proc-approval-tests.sql
INSERT INTO users (id, full_name, role, auth_id, is_active)
VALUES
  (99001, 'TEST Requester',       'employee',            '99999999-0000-0000-0000-000000090001'::UUID, TRUE),
  (99003, 'TEST Proc Manager',    'procurement_manager', '99999999-0000-0000-0000-000000090003'::UUID, TRUE)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION _test_as(p_user_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_auth UUID;
BEGIN
  SELECT auth_id INTO v_auth FROM users WHERE id = p_user_id;
  PERFORM set_config('request.jwt.claim.sub', v_auth::TEXT, TRUE);
END;
$$;

-- (1) جهّز الطلب والقاعدة (session A تنشئها)
INSERT INTO proc_approval_rules (rule_name, min_amount, required_role, step_order)
VALUES ('CONCURRENCY_TEST_RULE', 0, 'procurement_manager', 1)
ON CONFLICT DO NOTHING;

-- (2) أنشئ طلبًا مقدّمًا (submitted)
DO $$
DECLARE
  v_req BIGINT;
  v_step BIGINT;
BEGIN
  PERFORM _test_as(99001);
  INSERT INTO proc_requisitions (branch_id, department_id, requested_by, priority, needed_by_date, status)
  VALUES (NULL, NULL, 99001, 'medium', CURRENT_DATE + 7, 'draft')
  RETURNING id INTO v_req;
  INSERT INTO proc_requisition_items (requisition_id, item_name, quantity, unit, estimated_price)
  VALUES (v_req, 'CONCURRENCY test', 1, 'unit', 500);

  PERFORM proc_submit_requisition(v_req);

  SELECT id INTO v_step FROM proc_requisition_approvals
    WHERE requisition_id = v_req AND step_no = 1 AND status = 'pending';

  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'SESSION A: أنشأت طلبًا وخطوة.';
  RAISE NOTICE 'REQUISITION_ID = %', v_req;
  RAISE NOTICE 'STEP_ID = %', v_step;
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'الآن افتح session-b.sql وعدّل السطر STEP_ID_HERE إلى %', v_step;
  RAISE NOTICE 'ثم شغّل session-b.sql في جلسة psql/SQL Editor أخرى.';
  RAISE NOTICE 'ثم عُد هنا واستمر في تنفيذ SQL أدناه.';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

  -- خزّن الـID في جدول مؤقت ليقرأه session B
  DROP TABLE IF EXISTS _concurrency_test_state;
  CREATE TEMP TABLE IF NOT EXISTS _concurrency_test_state (k TEXT PRIMARY KEY, v BIGINT) ON COMMIT DROP;
  INSERT INTO _concurrency_test_state VALUES ('req_id', v_req), ('step_id', v_step);
END $$;

-- ═══════════════════════════════════════════════════════════
-- ⏸ توقّف هنا. قبل تنفيذ الجزء التالي:
--    1) افتح session-b.sql في جلسة أخرى
--    2) استبدل STEP_ID_HERE بقيمة STEP_ID المطبوعة أعلاه
--    3) شغّل session-b.sql — ستنتظر عند استدعاء proc_approve_step
--    4) عُد هنا وشغّل باقي الملف — الاعتماد ينجح، ثم تجد B تفشل
-- ═══════════════════════════════════════════════════════════

-- (3) اعتماد الخطوة من session A
DO $$
DECLARE
  v_step BIGINT;
BEGIN
  -- ملاحظة: TEMP tables تُحذف على COMMIT، فلن تكون متاحة عبر ROLLBACK.
  -- لو انقطع الاتصال، عوّض بقيمة يدوية:
  -- v_step := <STEP_ID printed above>;
  BEGIN
    SELECT v INTO v_step FROM _concurrency_test_state WHERE k = 'step_id';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'استبدل هذا السطر بقيمة STEP_ID المطبوعة أعلاه';
  END;

  PERFORM _test_as(99003);  -- procurement_manager
  PERFORM proc_approve_step(v_step, 'session A approval');

  RAISE NOTICE 'SESSION A: تم الاعتماد. الآن راجع session-b — يجب أن تفشل بـSTEP_NOT_PENDING.';
END $$;

-- (4) COMMIT — يطلق القفل، فتفشل session B فورًا
-- ⚠️ استخدم COMMIT فقط في اختبار حقيقي على staging
--    (تسجيل الاعتماد يبقى — لكن ROLLBACK يوجد أيضًا لو أردت تنظيفًا)
COMMIT;
-- بديل: ROLLBACK; — يلغي كل شيء

\echo 'SESSION A: انتهيت. تحقق من session B الآن.'
