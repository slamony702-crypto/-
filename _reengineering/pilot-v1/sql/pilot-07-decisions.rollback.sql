-- Rollback موديول القرارات (pilot-07).
DROP TRIGGER IF EXISTS trg_dec_guard ON decisions; DROP TRIGGER IF EXISTS trg_dec_touch ON decisions; DROP TRIGGER IF EXISTS trg_dec_audit ON decisions;
DROP FUNCTION IF EXISTS dec_guard_transition();
DROP POLICY IF EXISTS dec_sel ON decisions; DROP POLICY IF EXISTS dec_ins ON decisions; DROP POLICY IF EXISTS dec_upd ON decisions; DROP POLICY IF EXISTS dec_del ON decisions;
DO $$ DECLARE child TEXT; children TEXT[] := ARRAY['decision_sub_responsibles','decision_viewers','decision_activity_log','decision_acknowledgments'];
BEGIN FOREACH child IN ARRAY children LOOP
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_sel', child);
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_wr', child);
END LOOP; END $$;
DO $$ DECLARE t TEXT; BEGIN FOREACH t IN ARRAY ARRAY['decisions','decision_sub_responsibles','decision_viewers','decision_activity_log','decision_acknowledgments'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname=t||'_auth_select') THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING(true)', t||'_auth_select', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK(true)', t||'_auth_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING(true) WITH CHECK(true)', t||'_auth_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING(true)', t||'_auth_delete', t);
  END IF; END LOOP; END $$;
SELECT 'decisions rollback done';
