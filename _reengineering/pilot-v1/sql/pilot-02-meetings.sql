-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 02 — تصليب موديول الاجتماعات
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING (RLS تعتمد auth.uid()؛ تفعيلها مرهون بترحيل Auth).
-- يعتمد على pilot-01-foundation.sql. مبني على الأعمدة الحقيقية من preflight.
--
-- الأعمدة المؤكدة: meetings(id,title,meeting_type,meeting_datetime,location_type,
--   location_detail,department_id,organizer_id,status,summary,minutes_*,created_at,updated_at)
-- لا يوجد branch_id → النطاق بالقسم (department_id) + المنظِّم + الحضور.
-- قيد الحالة الحالي: scheduled/done/in_follow_up/closed/postponed/cancelled.
--
-- يعالج فجوات الاجتماعات: حذف جماعي بلا حارس، تعديل المغلق/الملغى، حرية الانتقال.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE meetings ADD COLUMN IF NOT EXISTS updated_by BIGINT;

-- ─── دوال مساعدة مشتركة للعنقود (idempotent) ───────────────────────────
CREATE OR REPLACE FUNCTION core_is_company_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager');
$$;
CREATE OR REPLACE FUNCTION core_current_dept()
RETURNS BIGINT LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT department_id FROM users WHERE id = current_app_user_id();
$$;

-- SECURITY DEFINER: يتجاوز RLS على meeting_attendees لكسر التكرار المتبادل
-- بين سياسة meetings وسياسة meeting_attendees (كلٌّ يشير للآخر).
CREATE OR REPLACE FUNCTION meeting_is_attendee(p_meeting BIGINT, p_user BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM meeting_attendees a WHERE a.meeting_id = p_meeting AND a.user_id = p_user);
$$;

-- ─── حارس انتقالات + حماية نهائية ──────────────────────────────────────
CREATE OR REPLACE FUNCTION meetings_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status IN ('closed','cancelled') AND NOT core_is_company_admin() THEN
      RAISE EXCEPTION 'الاجتماع % — لا يمكن تعديله إلا بصلاحية الإدارة', OLD.status;
    END IF;
    RETURN NEW;
  END IF;

  v_ok := CASE
    WHEN OLD.status = 'scheduled'    AND NEW.status IN ('in_follow_up','done','postponed','cancelled') THEN TRUE
    WHEN OLD.status = 'in_follow_up' AND NEW.status IN ('done','closed','postponed','cancelled')       THEN TRUE
    WHEN OLD.status = 'done'         AND NEW.status IN ('closed','in_follow_up')                        THEN TRUE
    WHEN OLD.status = 'postponed'    AND NEW.status IN ('scheduled','cancelled')                        THEN TRUE
    -- إعادة فتح المغلق/الملغى للإدارة فقط
    WHEN OLD.status IN ('closed','cancelled') AND NEW.status = 'in_follow_up' AND core_is_company_admin() THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'انتقال غير مسموح للاجتماع: % ← %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_meetings_guard ON meetings;
CREATE TRIGGER trg_meetings_guard BEFORE UPDATE ON meetings
  FOR EACH ROW EXECUTE FUNCTION meetings_guard_transition();
DROP TRIGGER IF EXISTS trg_meetings_touch ON meetings;
CREATE TRIGGER trg_meetings_touch BEFORE UPDATE ON meetings
  FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();
DROP TRIGGER IF EXISTS trg_meetings_audit ON meetings;
CREATE TRIGGER trg_meetings_audit AFTER INSERT OR UPDATE OR DELETE ON meetings
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══ RLS: استبدال السياسات المفتوحة (meetings_auth_*) ═══
DROP POLICY IF EXISTS meetings_auth_select ON meetings;
DROP POLICY IF EXISTS meetings_auth_insert ON meetings;
DROP POLICY IF EXISTS meetings_auth_update ON meetings;
DROP POLICY IF EXISTS meetings_auth_delete ON meetings;

CREATE POLICY meetings_sel ON meetings FOR SELECT TO authenticated USING (
  core_is_company_admin()
  OR organizer_id = current_app_user_id()
  OR (department_id IS NOT NULL AND department_id = core_current_dept())
  OR meeting_is_attendee(meetings.id, current_app_user_id())
);
CREATE POLICY meetings_ins ON meetings FOR INSERT TO authenticated WITH CHECK (
  organizer_id = current_app_user_id()   -- لا يُنشئ باسم منظِّم آخر
);
CREATE POLICY meetings_upd ON meetings FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR organizer_id = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()))
  WITH CHECK (core_is_company_admin() OR organizer_id = current_app_user_id()
         OR (current_app_role()='department_manager' AND department_id = core_current_dept()));
-- الحذف للإدارة العليا فقط (يوقف الحذف الجماعي غير المصرّح)
CREATE POLICY meetings_del ON meetings FOR DELETE TO authenticated USING (core_is_company_admin());

-- ── الجداول الفرعية: ترث رؤية الاجتماع الأم ──
DO $$
DECLARE child TEXT; fk TEXT;
  pairs TEXT[][] := ARRAY[['meeting_attendees','meeting_id'],['meeting_minutes','meeting_id'],['meeting_requests','meeting_id']];
BEGIN
  FOR i IN 1..array_length(pairs,1) LOOP
    child := pairs[i][1]; fk := pairs[i][2];
    -- إسقاط السياسات المفتوحة المعروفة
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_select', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_insert', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_update', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_auth_delete', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'allow all - minutes', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
    EXECUTE format($f$
      CREATE POLICY %1$s_sel ON %1$I FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM meetings m WHERE m.id = %1$I.%2$I
          AND (core_is_company_admin() OR m.organizer_id = current_app_user_id()
               OR (m.department_id IS NOT NULL AND m.department_id = core_current_dept())
               OR meeting_is_attendee(m.id, current_app_user_id())))
      )$f$, child, fk);
    EXECUTE format($f$
      CREATE POLICY %1$s_wr ON %1$I FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM meetings m WHERE m.id = %1$I.%2$I
             AND (core_is_company_admin() OR m.organizer_id = current_app_user_id()
                  OR (current_app_role()='department_manager' AND m.department_id = core_current_dept()))))
      WITH CHECK (EXISTS (SELECT 1 FROM meetings m WHERE m.id = %1$I.%2$I
             AND (core_is_company_admin() OR m.organizer_id = current_app_user_id()
                  OR (current_app_role()='department_manager' AND m.department_id = core_current_dept()))))
      $f$, child, fk);
  END LOOP;
END $$;

SELECT 'meetings' AS object,
       (SELECT count(*)::text FROM pg_policies WHERE tablename='meetings') AS policies;
