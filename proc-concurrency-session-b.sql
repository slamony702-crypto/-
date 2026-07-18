-- ═══════════════════════════════════════════════════════════
-- اختبار التزامن — الجلسة (B)
-- ═══════════════════════════════════════════════════════════
-- ⚠️ يشتغل بالتوازي مع proc-concurrency-session-a.sql
-- ═══════════════════════════════════════════════════════════
-- قبل التشغيل:
--   1) شغّل session-a.sql أولًا حتى تُطبَع STEP_ID
--   2) استبدل STEP_ID_HERE في الأسفل بالقيمة الفعلية
--   3) شغّل هذا الملف — سينتظر عند pg_advisory_xact_lock حتى COMMIT من A
--
-- النتيجة المتوقعة:
--   - أنت تنتظر ما يقارب ثوانٍ حتى تُحرَّر session A
--   - ثم تفشل بـERROR: STEP_NOT_PENDING (لأن A اعتمدها قبلك)
-- ═══════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION _test_as(p_user_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_auth UUID;
BEGIN
  SELECT auth_id INTO v_auth FROM users WHERE id = p_user_id;
  PERFORM set_config('request.jwt.claim.sub', v_auth::TEXT, TRUE);
END;
$$;

-- ⚠️ استبدل STEP_ID_HERE بقيمة STEP_ID التي طبعتها session-a.sql
-- مثال: v_step := 42;
DO $$
DECLARE
  v_step BIGINT := STEP_ID_HERE;  -- ⚠️ عدّل هذا
BEGIN
  IF v_step IS NULL THEN
    RAISE EXCEPTION 'عدّل السطر أعلاه ليحمل STEP_ID الحقيقي';
  END IF;

  PERFORM _test_as(99003);  -- procurement_manager (same as session A)
  RAISE NOTICE 'SESSION B: يحاول الاعتماد على step_id = %', v_step;
  RAISE NOTICE 'SESSION B: سينتظر advisory lock إذا كانت session A لم تُطلقه بعد...';

  BEGIN
    PERFORM proc_approve_step(v_step, 'session B approval');
    RAISE NOTICE 'SESSION B: FAIL — تم الاعتماد! المفروض يفشل بـSTEP_NOT_PENDING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%STEP_NOT_PENDING%' THEN
      RAISE NOTICE 'SESSION B: PASS — تم رفض الاعتماد الثاني (%)', SQLERRM;
    ELSE
      RAISE NOTICE 'SESSION B: خطأ غير متوقع: %', SQLERRM;
    END IF;
  END;
END $$;

ROLLBACK;

\echo 'SESSION B: انتهيت. النتيجة المتوقعة أعلاه: PASS.'
