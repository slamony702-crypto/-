-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Rollback لموديول الجودة (pilot-04)
-- ═══════════════════════════════════════════════════════════════════════
-- يزيل الحرّاس/التدقيق/السياسات الجديدة ويعيد using(true) المؤقتة.
-- لا يحذف بيانات ولا الأعمدة المضافة (verified_by/…/updated_by تبقى بلا ضرر).
-- ═══════════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_qv_guard ON quality_visits;
DROP TRIGGER IF EXISTS trg_qv_touch ON quality_visits;
DROP TRIGGER IF EXISTS trg_qv_audit ON quality_visits;
DROP TRIGGER IF EXISTS trg_qvi_guard ON quality_visit_items;
DROP TRIGGER IF EXISTS trg_qvi_audit ON quality_visit_items;
DROP FUNCTION IF EXISTS qv_guard_transition();
DROP FUNCTION IF EXISTS qvi_guard_after_verify();

ALTER TABLE quality_visits DROP CONSTRAINT IF EXISTS qv_status_chk;

DROP POLICY IF EXISTS qs_sel ON quality_sections; DROP POLICY IF EXISTS qs_wr ON quality_sections;
DROP POLICY IF EXISTS qi_sel ON quality_items;    DROP POLICY IF EXISTS qi_wr ON quality_items;
DROP POLICY IF EXISTS qv_sel ON quality_visits;   DROP POLICY IF EXISTS qv_ins ON quality_visits;
DROP POLICY IF EXISTS qv_upd ON quality_visits;   DROP POLICY IF EXISTS qv_del ON quality_visits;
DO $$
DECLARE child TEXT;
  children TEXT[] := ARRAY['quality_visit_items','quality_visit_sections','quality_attachments'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS qv_is_quality_admin();
DROP FUNCTION IF EXISTS qv_user_in_branch(BIGINT);

-- إعادة السياسات المؤقتة المفتوحة
DO $$
DECLARE t TEXT; pol TEXT;
  pairs TEXT[][] := ARRAY[
    ['quality_sections','qs_all'],['quality_items','qi_all'],['quality_visits','qv_all'],
    ['quality_visit_items','qvi_all'],['quality_visit_sections','qvs_all'],['quality_attachments','qa_all']];
BEGIN
  FOR i IN 1..array_length(pairs,1) LOOP
    t := pairs[i][1]; pol := pairs[i][2];
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname=pol) THEN
      EXECUTE format('CREATE POLICY %I ON %I FOR ALL USING (true) WITH CHECK (true)', pol, t);
    END IF;
  END LOOP;
END $$;
SELECT 'quality rollback done' AS status;
