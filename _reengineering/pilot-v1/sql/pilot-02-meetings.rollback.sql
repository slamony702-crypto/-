-- Rollback موديول الاجتماعات (pilot-02): يزيل الحرّاس/السياسات ويعيد المفتوحة.
DROP TRIGGER IF EXISTS trg_meetings_guard ON meetings;
DROP TRIGGER IF EXISTS trg_meetings_touch ON meetings;
DROP TRIGGER IF EXISTS trg_meetings_audit ON meetings;
DROP FUNCTION IF EXISTS meetings_guard_transition();
DROP POLICY IF EXISTS meetings_sel ON meetings; DROP POLICY IF EXISTS meetings_ins ON meetings;
DROP POLICY IF EXISTS meetings_upd ON meetings; DROP POLICY IF EXISTS meetings_del ON meetings;
DO $$ DECLARE child TEXT; children TEXT[] := ARRAY['meeting_attendees','meeting_minutes','meeting_requests'];
BEGIN FOREACH child IN ARRAY children LOOP
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_sel', child);
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_wr', child);
END LOOP; END $$;
-- إعادة السياسات المفتوحة
DO $$ DECLARE t TEXT; BEGIN FOREACH t IN ARRAY ARRAY['meetings','meeting_attendees','meeting_minutes','meeting_requests'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname=t||'_auth_select') THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING(true)', t||'_auth_select', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK(true)', t||'_auth_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING(true) WITH CHECK(true)', t||'_auth_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING(true)', t||'_auth_delete', t);
  END IF; END LOOP; END $$;
SELECT 'meetings rollback done';
