-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 07 — تصليب موديول القرارات
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING. يعتمد على pilot-01 + pilot-02 (core_*).
-- الأعمدة المؤكدة: decisions(id,decision_text,meeting_id,department_id,
--   responsible_user_id,due_date,priority,status[new/in_progress/executed/
--   delayed/cancelled/pending_approval],notes,created_by,created_at) — لا updated_at.
-- يعالج: حرية الانتقال، تعديل/حذف المعتمد (executed)، هوية العميل.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE decisions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE decisions ADD COLUMN IF NOT EXISTS updated_by BIGINT;

CREATE OR REPLACE FUNCTION core_is_company_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager'); $$;
CREATE OR REPLACE FUNCTION core_current_dept()
RETURNS BIGINT LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT department_id FROM users WHERE id = current_app_user_id(); $$;

-- SECURITY DEFINER: يتجاوز RLS على الجداول الفرعية لكسر التكرار المتبادل
-- بين سياسة decisions وسياسات decision_viewers/decision_sub_responsibles.
CREATE OR REPLACE FUNCTION decision_user_linked(p_dec BIGINT, p_user BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM decision_viewers v WHERE v.decision_id = p_dec AND v.user_id = p_user)
      OR EXISTS (SELECT 1 FROM decision_sub_responsibles s WHERE s.decision_id = p_dec AND s.user_id = p_user);
$$;

-- ─── حارس حالة + حماية المعتمد/الملغى ──────────────────────────────────
CREATE OR REPLACE FUNCTION dec_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status IN ('executed','cancelled') AND NOT core_is_company_admin() THEN
      RAISE EXCEPTION 'القرار % — لا يمكن تعديله إلا بصلاحية الإدارة', OLD.status;
    END IF;
    RETURN NEW;
  END IF;
  v_ok := CASE
    WHEN OLD.status = 'new'              AND NEW.status IN ('in_progress','pending_approval','cancelled') THEN TRUE
    WHEN OLD.status = 'pending_approval' AND NEW.status IN ('in_progress','executed','cancelled','new')   THEN TRUE
    WHEN OLD.status = 'in_progress'      AND NEW.status IN ('executed','delayed','cancelled')             THEN TRUE
    WHEN OLD.status = 'delayed'          AND NEW.status IN ('in_progress','executed','cancelled')         THEN TRUE
    WHEN OLD.status IN ('executed','cancelled') AND NEW.status = 'in_progress' AND core_is_company_admin() THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'انتقال غير مسموح للقرار: % ← %', OLD.status, NEW.status; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_dec_guard ON decisions;
CREATE TRIGGER trg_dec_guard BEFORE UPDATE ON decisions FOR EACH ROW EXECUTE FUNCTION dec_guard_transition();
DROP TRIGGER IF EXISTS trg_dec_touch ON decisions;
CREATE TRIGGER trg_dec_touch BEFORE UPDATE ON decisions FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();
DROP TRIGGER IF EXISTS trg_dec_audit ON decisions;
CREATE TRIGGER trg_dec_audit AFTER INSERT OR UPDATE OR DELETE ON decisions FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══ RLS: decisions ═══
DROP POLICY IF EXISTS decisions_auth_select ON decisions;
DROP POLICY IF EXISTS decisions_auth_insert ON decisions;
DROP POLICY IF EXISTS decisions_auth_update ON decisions;
DROP POLICY IF EXISTS decisions_auth_delete ON decisions;
CREATE POLICY dec_sel ON decisions FOR SELECT TO authenticated USING (
  core_is_company_admin() OR created_by = current_app_user_id() OR responsible_user_id = current_app_user_id()
  OR (department_id IS NOT NULL AND department_id = core_current_dept())
  OR decision_user_linked(decisions.id, current_app_user_id())
);
CREATE POLICY dec_ins ON decisions FOR INSERT TO authenticated WITH CHECK (
  created_by = current_app_user_id()
  AND (core_is_company_admin() OR current_app_role() IN ('department_manager','meeting_organizer','projects_manager'))
);
CREATE POLICY dec_upd ON decisions FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR created_by = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()))
  WITH CHECK (core_is_company_admin() OR created_by = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()));
-- الحذف: لا يجوز حذف قرار معتمد (executed) — الإدارة فقط ولغير المعتمد
CREATE POLICY dec_del ON decisions FOR DELETE TO authenticated USING (
  core_is_company_admin() AND status <> 'executed'
);

-- ── الجداول الفرعية التي تملك user_id: ترث الرؤية + صف المستخدم نفسه ──
-- (decision_activity_log مستثنى — عموده created_by لا user_id، يُعالَج تحت)
DO $$
DECLARE child TEXT;
  children TEXT[] := ARRAY['decision_sub_responsibles','decision_viewers','decision_acknowledgments'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_select', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_insert', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_update', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_delete', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
    EXECUTE format($f$
      CREATE POLICY %1$s_sel ON %1$I FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM decisions d WHERE d.id = %1$I.decision_id
          AND (core_is_company_admin() OR d.created_by = current_app_user_id()
               OR d.responsible_user_id = current_app_user_id()
               OR (d.department_id IS NOT NULL AND d.department_id = core_current_dept())))
        OR %1$I.user_id = current_app_user_id()
      )$f$, child);
    EXECUTE format($f$
      CREATE POLICY %1$s_wr ON %1$I FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM decisions d WHERE d.id = %1$I.decision_id
             AND (core_is_company_admin() OR d.created_by = current_app_user_id()
                  OR (current_app_role()='department_manager' AND d.department_id = core_current_dept())))
             OR %1$I.user_id = current_app_user_id())
      WITH CHECK (EXISTS (SELECT 1 FROM decisions d WHERE d.id = %1$I.decision_id
             AND (core_is_company_admin() OR d.created_by = current_app_user_id()
                  OR (current_app_role()='department_manager' AND d.department_id = core_current_dept())))
             OR %1$I.user_id = current_app_user_id())
      $f$, child);
  END LOOP;
END $$;

-- ── decision_activity_log: يرث من القرار الأم (عموده created_by لا user_id) ──
DROP POLICY IF EXISTS decision_activity_log_auth_select ON decision_activity_log;
DROP POLICY IF EXISTS decision_activity_log_auth_insert ON decision_activity_log;
DROP POLICY IF EXISTS decision_activity_log_auth_update ON decision_activity_log;
DROP POLICY IF EXISTS decision_activity_log_auth_delete ON decision_activity_log;
DROP POLICY IF EXISTS decision_activity_log_sel ON decision_activity_log;
DROP POLICY IF EXISTS decision_activity_log_wr ON decision_activity_log;
CREATE POLICY decision_activity_log_sel ON decision_activity_log FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM decisions d WHERE d.id = decision_activity_log.decision_id
    AND (core_is_company_admin() OR d.created_by = current_app_user_id()
         OR d.responsible_user_id = current_app_user_id()
         OR (d.department_id IS NOT NULL AND d.department_id = core_current_dept())))
  OR created_by = current_app_user_id()
);
CREATE POLICY decision_activity_log_wr ON decision_activity_log FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM decisions d WHERE d.id = decision_activity_log.decision_id
         AND (core_is_company_admin() OR d.created_by = current_app_user_id()
              OR (current_app_role()='department_manager' AND d.department_id = core_current_dept())))
         OR created_by = current_app_user_id())
  WITH CHECK (EXISTS (SELECT 1 FROM decisions d WHERE d.id = decision_activity_log.decision_id
         AND (core_is_company_admin() OR d.created_by = current_app_user_id()
              OR (current_app_role()='department_manager' AND d.department_id = core_current_dept())))
         OR created_by = current_app_user_id());

SELECT 'decisions' AS object,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='decisions') AS policies;
