-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 06 — تصليب موديول المهام (action_items + department_tasks)
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING. يعتمد على pilot-01 + pilot-02 (دوال core_*).
-- الأعمدة المؤكدة من preflight:
--   action_items(id,title,assigned_to,meeting_id,decision_id,department_id,
--     due_date,priority,status[not_started/in_progress/completed/delayed],
--     progress_percent,follow_up_notes,delay_reason,created_at,updated_at) — لا branch_id
--   department_tasks(id,title,assigned_by,assigned_to,department_id,due_datetime,
--     priority,status,progress_percent,attachment_*,created_at,updated_at)
-- يعالج: تحديث الحالة بلا صلاحية/ملكية، تعديل المكتمل، إسناد بلا حارس.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE action_items    ADD COLUMN IF NOT EXISTS updated_by BIGINT;
ALTER TABLE department_tasks ADD COLUMN IF NOT EXISTS updated_by BIGINT;

-- دوال core_* معرّفة في pilot-02؛ نعيد تعريفها idempotent تحسبًا للتشغيل المنفرد
CREATE OR REPLACE FUNCTION core_is_company_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager'); $$;
CREATE OR REPLACE FUNCTION core_current_dept()
RETURNS BIGINT LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT department_id FROM users WHERE id = current_app_user_id(); $$;

-- ─── حارس حالة action_items + حماية المكتمل ────────────────────────────
CREATE OR REPLACE FUNCTION ai_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status = 'completed' AND NOT (core_is_company_admin()
        OR current_app_role() IN ('department_manager','meeting_organizer')) THEN
      RAISE EXCEPTION 'المهمة مكتملة — لا يمكن تعديلها إلا بصلاحية إدارية';
    END IF;
    RETURN NEW;
  END IF;
  v_ok := CASE
    WHEN OLD.status IN ('not_started','in_progress','delayed') AND NEW.status IN ('not_started','in_progress','delayed','completed') THEN TRUE
    WHEN OLD.status = 'completed' AND NEW.status = 'in_progress'
         AND (core_is_company_admin() OR current_app_role() IN ('department_manager','meeting_organizer')) THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'انتقال غير مسموح للمهمة: % ← %', OLD.status, NEW.status; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_ai_guard ON action_items;
CREATE TRIGGER trg_ai_guard BEFORE UPDATE ON action_items FOR EACH ROW EXECUTE FUNCTION ai_guard_transition();
DROP TRIGGER IF EXISTS trg_ai_touch ON action_items;
CREATE TRIGGER trg_ai_touch BEFORE UPDATE ON action_items FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();
DROP TRIGGER IF EXISTS trg_ai_audit ON action_items;
CREATE TRIGGER trg_ai_audit AFTER INSERT OR UPDATE OR DELETE ON action_items FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ─── حارس حالة department_tasks + حماية المكتمل ────────────────────────
CREATE OR REPLACE FUNCTION dt_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status = 'completed' AND NOT (core_is_company_admin()
        OR (current_app_role()='department_manager' AND OLD.department_id = core_current_dept())
        OR OLD.assigned_by = current_app_user_id()) THEN
      RAISE EXCEPTION 'التكليف مكتمل — لا يمكن تعديله إلا من مُسنِده أو الإدارة';
    END IF;
    RETURN NEW;
  END IF;
  v_ok := CASE
    WHEN OLD.status IN ('not_started','in_progress','delayed') AND NEW.status IN ('not_started','in_progress','delayed','completed') THEN TRUE
    WHEN OLD.status = 'completed' AND NEW.status = 'in_progress'
         AND (core_is_company_admin() OR OLD.assigned_by = current_app_user_id()) THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'انتقال غير مسموح للتكليف: % ← %', OLD.status, NEW.status; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_dt_guard ON department_tasks;
CREATE TRIGGER trg_dt_guard BEFORE UPDATE ON department_tasks FOR EACH ROW EXECUTE FUNCTION dt_guard_transition();
DROP TRIGGER IF EXISTS trg_dt_touch ON department_tasks;
CREATE TRIGGER trg_dt_touch BEFORE UPDATE ON department_tasks FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();
DROP TRIGGER IF EXISTS trg_dt_audit ON department_tasks;
CREATE TRIGGER trg_dt_audit AFTER INSERT OR UPDATE OR DELETE ON department_tasks FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══ RLS: action_items ═══
DROP POLICY IF EXISTS action_items_auth_select ON action_items;
DROP POLICY IF EXISTS action_items_auth_insert ON action_items;
DROP POLICY IF EXISTS action_items_auth_update ON action_items;
DROP POLICY IF EXISTS action_items_auth_delete ON action_items;
CREATE POLICY ai_sel ON action_items FOR SELECT TO authenticated USING (
  core_is_company_admin() OR assigned_to = current_app_user_id()
  OR (department_id IS NOT NULL AND department_id = core_current_dept())
);
CREATE POLICY ai_ins ON action_items FOR INSERT TO authenticated WITH CHECK (
  core_is_company_admin() OR current_app_role() IN ('department_manager','meeting_organizer','projects_manager')
);
-- التحديث: المكلَّف نفسه (حالته/تقدمه) أو الإدارة/مدير القسم
CREATE POLICY ai_upd ON action_items FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR assigned_to = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()))
  WITH CHECK (core_is_company_admin() OR assigned_to = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()));
CREATE POLICY ai_del ON action_items FOR DELETE TO authenticated USING (
  core_is_company_admin() OR current_app_role() IN ('department_manager','meeting_organizer')
);

-- ═══ RLS: department_tasks ═══
DROP POLICY IF EXISTS department_tasks_auth_select ON department_tasks;
DROP POLICY IF EXISTS department_tasks_auth_insert ON department_tasks;
DROP POLICY IF EXISTS department_tasks_auth_update ON department_tasks;
DROP POLICY IF EXISTS department_tasks_auth_delete ON department_tasks;
CREATE POLICY dt_sel ON department_tasks FOR SELECT TO authenticated USING (
  core_is_company_admin() OR assigned_to = current_app_user_id() OR assigned_by = current_app_user_id()
  OR (department_id IS NOT NULL AND department_id = core_current_dept())
);
CREATE POLICY dt_ins ON department_tasks FOR INSERT TO authenticated WITH CHECK (
  assigned_by = current_app_user_id()   -- لا يُسنِد باسم غيره
);
CREATE POLICY dt_upd ON department_tasks FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR assigned_to = current_app_user_id() OR assigned_by = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()))
  WITH CHECK (core_is_company_admin() OR assigned_to = current_app_user_id() OR assigned_by = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()));
CREATE POLICY dt_del ON department_tasks FOR DELETE TO authenticated USING (
  core_is_company_admin() OR assigned_by = current_app_user_id()
);

SELECT 'tasks' AS object,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='action_items') AS ai_policies,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='department_tasks') AS dt_policies;
