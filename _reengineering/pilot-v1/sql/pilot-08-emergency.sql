-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 08 — تصليب موديول الطوارئ
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING. يعتمد على pilot-01 + pilot-02 (core_*).
-- الأعمدة المؤكدة: emergency_alerts(id,title,message,emergency_type,severity,
--   location,department_id,sender_id,recipient_id,status[open/resolved],
--   processing_status[new/in_progress/closed],escalation_*,resolved_*,closed_*,
--   attachment_*,created_at) — لا updated_at، لا branch_id.
-- يعالج: عدم منع الحذف، تعارض الحالتين، غياب زمن الاستجابة/تقرير الإغلاق/الدروس.
-- افتراض مسجّل: processing_status هو مصدر الحالة الوحيد؛ status يبقى للتوافق.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS first_response_at TIMESTAMPTZ;
ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS closure_report TEXT;
ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS lessons_learned TEXT;
ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS updated_by BIGINT;

CREATE OR REPLACE FUNCTION core_is_company_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager'); $$;
CREATE OR REPLACE FUNCTION core_current_dept()
RETURNS BIGINT LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT department_id FROM users WHERE id = current_app_user_id(); $$;

-- SECURITY DEFINER: يتجاوز RLS على emergency_recipients لكسر التكرار المتبادل
-- بين سياسة emergency_alerts وسياسة emergency_recipients.
CREATE OR REPLACE FUNCTION emergency_is_recipient(p_alert BIGINT, p_user BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM emergency_recipients r WHERE r.alert_id = p_alert AND r.user_id = p_user);
$$;

-- ─── منع الحذف نهائيًا (حالات الطوارئ لا تُحذف) ────────────────────────
CREATE OR REPLACE FUNCTION em_block_delete()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'حالات الطوارئ لا تُحذف — أغلق الحالة بدل حذفها';
END $$;
DROP TRIGGER IF EXISTS trg_em_nodelete ON emergency_alerts;
CREATE TRIGGER trg_em_nodelete BEFORE DELETE ON emergency_alerts
  FOR EACH ROW EXECUTE FUNCTION em_block_delete();

-- ─── حارس حالة المعالجة + زمن الاستجابة + تقرير الإغلاق ────────────────
CREATE OR REPLACE FUNCTION em_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  IF NEW.processing_status IS NOT DISTINCT FROM OLD.processing_status THEN
    IF OLD.processing_status = 'closed' AND NOT core_is_company_admin() THEN
      RAISE EXCEPTION 'الحالة مغلقة — لا يمكن تعديلها إلا بصلاحية الإدارة';
    END IF;
    RETURN NEW;
  END IF;
  v_ok := CASE
    WHEN OLD.processing_status = 'new'         AND NEW.processing_status = 'in_progress' THEN TRUE
    WHEN OLD.processing_status = 'in_progress' AND NEW.processing_status = 'closed'      THEN TRUE
    WHEN OLD.processing_status = 'closed'      AND NEW.processing_status = 'in_progress' AND core_is_company_admin() THEN TRUE
    ELSE FALSE
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'انتقال غير مسموح لحالة الطوارئ: % ← %', OLD.processing_status, NEW.processing_status;
  END IF;

  -- زمن أول استجابة
  IF NEW.processing_status = 'in_progress' AND OLD.first_response_at IS NULL THEN
    NEW.first_response_at := NOW();
  END IF;
  -- الإغلاق يتطلب تقرير إغلاق
  IF NEW.processing_status = 'closed' THEN
    IF NEW.closure_report IS NULL OR btrim(NEW.closure_report) = '' THEN
      RAISE EXCEPTION 'يجب كتابة تقرير الإغلاق قبل إغلاق حالة الطوارئ';
    END IF;
    NEW.closed_at := NOW();
    NEW.closed_by := current_app_user_id();
    NEW.status := 'resolved';   -- توحيد الحقل القديم
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_em_guard ON emergency_alerts;
CREATE TRIGGER trg_em_guard BEFORE UPDATE ON emergency_alerts FOR EACH ROW EXECUTE FUNCTION em_guard_transition();
DROP TRIGGER IF EXISTS trg_em_touch ON emergency_alerts;
CREATE TRIGGER trg_em_touch BEFORE UPDATE ON emergency_alerts FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();
DROP TRIGGER IF EXISTS trg_em_audit ON emergency_alerts;
CREATE TRIGGER trg_em_audit AFTER INSERT OR UPDATE OR DELETE ON emergency_alerts FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══ RLS ═══
DROP POLICY IF EXISTS emergency_alerts_auth_select ON emergency_alerts;
DROP POLICY IF EXISTS emergency_alerts_auth_insert ON emergency_alerts;
DROP POLICY IF EXISTS emergency_alerts_auth_update ON emergency_alerts;
DROP POLICY IF EXISTS emergency_alerts_auth_delete ON emergency_alerts;
CREATE POLICY em_sel ON emergency_alerts FOR SELECT TO authenticated USING (
  core_is_company_admin() OR sender_id = current_app_user_id() OR recipient_id = current_app_user_id()
  OR (department_id IS NOT NULL AND department_id = core_current_dept())
  OR EXISTS (SELECT 1 FROM emergency_recipients r WHERE r.alert_id = emergency_alerts.id AND r.user_id = current_app_user_id())
);
CREATE POLICY em_ins ON emergency_alerts FOR INSERT TO authenticated WITH CHECK (
  sender_id = current_app_user_id()
);
CREATE POLICY em_upd ON emergency_alerts FOR UPDATE TO authenticated
  USING (core_is_company_admin() OR sender_id = current_app_user_id() OR recipient_id = current_app_user_id()
         OR EXISTS (SELECT 1 FROM emergency_recipients r WHERE r.alert_id = emergency_alerts.id AND r.user_id = current_app_user_id()))
  WITH CHECK (core_is_company_admin() OR sender_id = current_app_user_id() OR recipient_id = current_app_user_id()
         OR EXISTS (SELECT 1 FROM emergency_recipients r WHERE r.alert_id = emergency_alerts.id AND r.user_id = current_app_user_id()));
-- لا سياسة DELETE (والتريجر يمنع الحذف على أي حال)

-- ── emergency_recipients (يملك user_id) ──
DO $$
DECLARE child TEXT; children TEXT[] := ARRAY['emergency_recipients'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_auth_select', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_auth_insert', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_auth_update', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_auth_delete', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child||'_wr', child);
    EXECUTE format($f$
      CREATE POLICY %1$s_sel ON %1$I FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = %1$I.alert_id
          AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id()
               OR (e.department_id IS NOT NULL AND e.department_id = core_current_dept())))
        OR %1$I.user_id = current_app_user_id()
      )$f$, child);
    EXECUTE format($f$
      CREATE POLICY %1$s_wr ON %1$I FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = %1$I.alert_id
             AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id()))
             OR %1$I.user_id = current_app_user_id())
      WITH CHECK (EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = %1$I.alert_id
             AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id()))
             OR %1$I.user_id = current_app_user_id())
      $f$, child);
  END LOOP;
END $$;
-- ملاحظة: emergency_activity_log لا يملك user_id؛ الشرط OR %I.user_id يفشل
-- لعموده الغائب. نصحّح: activity_log يرث من التنبيه فقط.
DROP POLICY IF EXISTS emergency_activity_log_sel ON emergency_activity_log;
DROP POLICY IF EXISTS emergency_activity_log_wr ON emergency_activity_log;
CREATE POLICY emergency_activity_log_sel ON emergency_activity_log FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = emergency_activity_log.alert_id
    AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id()
         OR (e.department_id IS NOT NULL AND e.department_id = core_current_dept())))
);
CREATE POLICY emergency_activity_log_wr ON emergency_activity_log FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = emergency_activity_log.alert_id
         AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id())))
  WITH CHECK (EXISTS (SELECT 1 FROM emergency_alerts e WHERE e.id = emergency_activity_log.alert_id
         AND (core_is_company_admin() OR e.sender_id = current_app_user_id() OR e.recipient_id = current_app_user_id())));

SELECT 'emergency' AS object,
  (SELECT count(*)::text FROM pg_policies WHERE tablename='emergency_alerts') AS policies;
