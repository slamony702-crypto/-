-- Rollback موديول الطوارئ (pilot-08). ملاحظة: يُبقي منع الحذف كخيار — إن أردت
-- استعادة السماح بالحذف، أسقط trg_em_nodelete صراحةً (غير مستحسن).
DROP TRIGGER IF EXISTS trg_em_guard ON emergency_alerts;
DROP TRIGGER IF EXISTS trg_em_touch ON emergency_alerts;
DROP TRIGGER IF EXISTS trg_em_audit ON emergency_alerts;
DROP TRIGGER IF EXISTS trg_em_nodelete ON emergency_alerts;
DROP FUNCTION IF EXISTS em_guard_transition();
DROP FUNCTION IF EXISTS em_block_delete();
DROP POLICY IF EXISTS em_sel ON emergency_alerts; DROP POLICY IF EXISTS em_ins ON emergency_alerts; DROP POLICY IF EXISTS em_upd ON emergency_alerts;
DROP POLICY IF EXISTS emergency_recipients_sel ON emergency_recipients; DROP POLICY IF EXISTS emergency_recipients_wr ON emergency_recipients;
DROP POLICY IF EXISTS emergency_activity_log_sel ON emergency_activity_log; DROP POLICY IF EXISTS emergency_activity_log_wr ON emergency_activity_log;
DO $$ DECLARE t TEXT; BEGIN FOREACH t IN ARRAY ARRAY['emergency_alerts','emergency_recipients','emergency_activity_log'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname=t||'_auth_select') THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING(true)', t||'_auth_select', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK(true)', t||'_auth_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING(true) WITH CHECK(true)', t||'_auth_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING(true)', t||'_auth_delete', t);
  END IF; END LOOP; END $$;
SELECT 'emergency rollback done';
