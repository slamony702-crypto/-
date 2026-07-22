-- Rollback IAM (pilot-09). يعيد الصلاحيات المفتوحة وقراءة password_plain.
DROP TRIGGER IF EXISTS trg_users_guard ON users;
DROP TRIGGER IF EXISTS trg_users_audit ON users;
DROP TRIGGER IF EXISTS trg_rp_audit ON role_permissions;
DROP TRIGGER IF EXISTS trg_upo_audit ON user_permission_overrides;
DROP FUNCTION IF EXISTS users_guard_privileged();
DROP POLICY IF EXISTS rp_sel ON role_permissions; DROP POLICY IF EXISTS rp_wr ON role_permissions;
DROP POLICY IF EXISTS upo_sel ON user_permission_overrides; DROP POLICY IF EXISTS upo_wr ON user_permission_overrides;
DROP POLICY IF EXISTS users_sel ON users; DROP POLICY IF EXISTS users_ins ON users; DROP POLICY IF EXISTS users_upd ON users; DROP POLICY IF EXISTS users_del ON users;
GRANT SELECT (password_plain) ON users TO authenticated;
DO $$ DECLARE t TEXT; BEGIN FOREACH t IN ARRAY ARRAY['users','role_permissions','user_permission_overrides'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname=t||'_auth_select') THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING(true)', t||'_auth_select', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT WITH CHECK(true)', t||'_auth_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE USING(true) WITH CHECK(true)', t||'_auth_update', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING(true)', t||'_auth_delete', t);
  END IF; END LOOP; END $$;
SELECT 'iam rollback done';
