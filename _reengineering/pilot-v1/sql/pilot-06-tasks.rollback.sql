-- Rollback موديول المهام (pilot-06).
DROP TRIGGER IF EXISTS trg_ai_guard ON action_items; DROP TRIGGER IF EXISTS trg_ai_touch ON action_items; DROP TRIGGER IF EXISTS trg_ai_audit ON action_items;
DROP TRIGGER IF EXISTS trg_dt_guard ON department_tasks; DROP TRIGGER IF EXISTS trg_dt_touch ON department_tasks; DROP TRIGGER IF EXISTS trg_dt_audit ON department_tasks;
DROP FUNCTION IF EXISTS ai_guard_transition(); DROP FUNCTION IF EXISTS dt_guard_transition();
DROP POLICY IF EXISTS ai_sel ON action_items; DROP POLICY IF EXISTS ai_ins ON action_items; DROP POLICY IF EXISTS ai_upd ON action_items; DROP POLICY IF EXISTS ai_del ON action_items;
DROP POLICY IF EXISTS dt_sel ON department_tasks; DROP POLICY IF EXISTS dt_ins ON department_tasks; DROP POLICY IF EXISTS dt_upd ON department_tasks; DROP POLICY IF EXISTS dt_del ON department_tasks;
DO $$ DECLARE t TEXT; BEGIN FOREACH t IN ARRAY ARRAY['action_items','department_tasks'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname=t||'_auth_select') THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING(true)', t||'_auth_select', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK(true)', t||'_auth_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING(true) WITH CHECK(true)', t||'_auth_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING(true)', t||'_auth_delete', t);
  END IF; END LOOP; END $$;
SELECT 'tasks rollback done';
