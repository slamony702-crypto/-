-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 09 — تصليب المستخدمين والصلاحيات (IAM)
-- ═══════════════════════════════════════════════════════════════════════
-- الحكم: INTERNALLY READY — AUTH STAGING APPLICATION REQUIRED.
-- REQUIRES SUPABASE STAGING. يعتمد على pilot-01 + pilot-02 (core_*).
--
-- يعالج أخطر الفجوات:
--   • role_permissions/user_permission_overrides مفتوحة للكتابة → أي مستخدم
--     يرفع صلاحياته بنفسه. نقصر الكتابة على الإدارة العليا فقط.
--   • users مفتوحة للكتابة → أي مستخدم يغيّر دور/حالة أي مستخدم. نقصر التعديل
--     ونمنع تصعيد الدور/الحالة/الفرع/القسم بتريجر (حتى على صفّه نفسه).
--   • قراءة password_plain عبر API → نلغي صلاحية قراءة العمود عن authenticated.
--   • تدقيق كل تغيير صلاحية/دور.
--
-- ملاحظة: لا يحذف password_plain (ممنوع) ولا يكسر verify_login (SECURITY DEFINER
--   يتجاوز صلاحيات الأعمدة). users.SELECT يبقى واسعًا (التطبيق يحتاج أسماء
--   المستخدمين للقوائم) لكن عمود كلمة المرور يُحجب عبر صلاحية العمود.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION core_is_company_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager'); $$;

-- ─── (1) منع تصعيد الحقول الحسّاسة على users (لغير الإدارة) ────────────
CREATE OR REPLACE FUNCTION users_guard_privileged()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
  IF core_is_company_admin() THEN RETURN NEW; END IF;
  IF NEW.role         IS DISTINCT FROM OLD.role
     OR NEW.status    IS DISTINCT FROM OLD.status
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
     OR NEW.department_id IS DISTINCT FROM OLD.department_id THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الدور أو الحالة أو الفرع أو القسم';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_users_guard ON users;
CREATE TRIGGER trg_users_guard BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION users_guard_privileged();

-- ─── (2) تدقيق users + جداول الصلاحيات ─────────────────────────────────
DROP TRIGGER IF EXISTS trg_users_audit ON users;
CREATE TRIGGER trg_users_audit AFTER INSERT OR UPDATE OR DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();
DROP TRIGGER IF EXISTS trg_rp_audit ON role_permissions;
CREATE TRIGGER trg_rp_audit AFTER INSERT OR UPDATE OR DELETE ON role_permissions
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();
DROP TRIGGER IF EXISTS trg_upo_audit ON user_permission_overrides;
CREATE TRIGGER trg_upo_audit AFTER INSERT OR UPDATE OR DELETE ON user_permission_overrides
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ─── (3) RLS: role_permissions (قراءة للكل، كتابة للإدارة فقط) ─────────
DROP POLICY IF EXISTS role_permissions_auth_select ON role_permissions;
DROP POLICY IF EXISTS role_permissions_auth_insert ON role_permissions;
DROP POLICY IF EXISTS role_permissions_auth_update ON role_permissions;
DROP POLICY IF EXISTS role_permissions_auth_delete ON role_permissions;
CREATE POLICY rp_sel ON role_permissions FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
CREATE POLICY rp_wr  ON role_permissions FOR ALL TO authenticated
  USING (core_is_company_admin()) WITH CHECK (core_is_company_admin());

-- ─── (4) RLS: user_permission_overrides (يرى المستخدم تجاوزاته، الكتابة للإدارة) ─
DROP POLICY IF EXISTS user_permission_overrides_auth_select ON user_permission_overrides;
DROP POLICY IF EXISTS user_permission_overrides_auth_insert ON user_permission_overrides;
DROP POLICY IF EXISTS user_permission_overrides_auth_update ON user_permission_overrides;
DROP POLICY IF EXISTS user_permission_overrides_auth_delete ON user_permission_overrides;
CREATE POLICY upo_sel ON user_permission_overrides FOR SELECT TO authenticated USING (
  core_is_company_admin() OR user_id = current_app_user_id()
);
CREATE POLICY upo_wr ON user_permission_overrides FOR ALL TO authenticated
  USING (core_is_company_admin()) WITH CHECK (core_is_company_admin());

-- ─── (5) RLS: users (قراءة واسعة، إنشاء/حذف للإدارة، تعديل للإدارة أو الذات) ─
DROP POLICY IF EXISTS users_auth_select ON users;
DROP POLICY IF EXISTS users_auth_insert ON users;
DROP POLICY IF EXISTS users_auth_update ON users;
DROP POLICY IF EXISTS users_auth_delete ON users;
CREATE POLICY users_sel ON users FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
CREATE POLICY users_ins ON users FOR INSERT TO authenticated WITH CHECK (core_is_company_admin());
CREATE POLICY users_upd ON users FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR id = current_app_user_id())
  WITH CHECK (core_is_company_admin() OR id = current_app_user_id());
CREATE POLICY users_del ON users FOR DELETE TO authenticated USING (core_is_company_admin());

-- ─── (6) حجب قراءة password_plain عبر API (صلاحية العمود) ───────────────
-- verify_login (SECURITY DEFINER) يبقى يعمل لأنه يتجاوز صلاحيات الأعمدة.
-- التطبيق لم يعد يعرض/ينسخ كلمة المرور (تصليب الواجهة)، وبهذا لا يقرأها أحد
-- عبر PostgREST مباشرة.
REVOKE SELECT (password_plain) ON users FROM authenticated;
REVOKE SELECT (password_plain) ON users FROM anon;

SELECT 'iam' AS object,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='users') AS user_policies,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='role_permissions') AS rp_policies;
