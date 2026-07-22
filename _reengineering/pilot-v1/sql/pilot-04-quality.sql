-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 04 — تصليب موديول الجودة
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING (سياسات RLS تعتمد auth.uid()؛ تفعيلها مرهون
-- بترحيل Auth). يعتمد على pilot-01-foundation.sql.
--
-- يعالج فجوات الجودة من مصفوفة الفجوات:
--   • حالتان فقط draft/completed → إضافة verified/closed مع مسار قبول/إعادة.
--   • لا فصل مهام → المحقِّق ≠ المفتِّش ولا صاحب أي إجراء تصحيحي (بتريجر).
--   • إعادة الحفظ تمسح التاريخ → تدقيق يحفظ كل حذف/إدراج + منع الكتابة بعد التحقق.
--   • RLS using(true) → RLS مقيّدة بالفرع/الدور.
--
-- افتراض مسجّل: فصل المهام = verified_by ∉ {inspector_id, responsible_user_id
--   لأي عنصر في الزيارة}. الزيارة المغلقة غير قابلة للتعديل.
-- آمن لإعادة التشغيل. لا يحذف بيانات.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── (1) أعمدة التحقّق/الإغلاق + التتبّع ────────────────────────────────
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS verified_by BIGINT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS verification_result TEXT;   -- accepted | redo
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS closed_by BIGINT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
ALTER TABLE quality_visits ADD COLUMN IF NOT EXISTS updated_by BIGINT;

-- ─── (2) قيد الحالة (NOT VALID: يُطبَّق على الصفوف الجديدة فقط) ─────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='qv_status_chk') THEN
    ALTER TABLE quality_visits ADD CONSTRAINT qv_status_chk CHECK (
      status IN ('draft','completed','verified','closed')
    ) NOT VALID;
  END IF;
END $$;

-- ─── (3) حارس انتقالات + فصل المهام + حماية نهائية (SECURITY INVOKER) ──
CREATE OR REPLACE FUNCTION qv_guard_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  -- لا تغيير حالة: امنع أي تعديل على المغلق
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status = 'closed' THEN
      RAISE EXCEPTION 'الزيارة مغلقة ولا يمكن تعديلها';
    END IF;
    RETURN NEW;
  END IF;

  v_ok := CASE
    WHEN OLD.status = 'draft'     AND NEW.status = 'completed' THEN TRUE
    WHEN OLD.status = 'completed' AND NEW.status = 'verified'  THEN TRUE
    WHEN OLD.status = 'verified'  AND NEW.status IN ('closed','completed') THEN TRUE  -- closed=قبول، completed=إعادة
    ELSE FALSE
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'انتقال غير مسموح للزيارة: % ← %', OLD.status, NEW.status;
  END IF;

  -- عند التحقق: فصل المهام إلزامي
  IF NEW.status = 'verified' THEN
    IF NEW.verified_by IS NULL THEN
      RAISE EXCEPTION 'يجب تحديد المُحقِّق (verified_by) عند التحقق';
    END IF;
    IF NEW.verified_by = OLD.inspector_id THEN
      RAISE EXCEPTION 'فصل المهام: لا يجوز أن يعتمد المفتِّش زيارته بنفسه';
    END IF;
    IF EXISTS (SELECT 1 FROM quality_visit_items qi
               WHERE qi.visit_id = NEW.id AND qi.responsible_user_id = NEW.verified_by) THEN
      RAISE EXCEPTION 'فصل المهام: لا يجوز أن يعتمد صاحبُ إجراء تصحيحي التحققَ';
    END IF;
    NEW.verified_at := NOW();
  END IF;

  -- عند الإغلاق: يجب أن يكون التحقق قبولًا
  IF NEW.status = 'closed' THEN
    IF OLD.verification_result IS DISTINCT FROM 'accepted' THEN
      RAISE EXCEPTION 'لا يمكن الإغلاق قبل تحقق مقبول (accepted)';
    END IF;
    NEW.closed_at := NOW();
    NEW.closed_by := current_app_user_id();
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_qv_guard ON quality_visits;
CREATE TRIGGER trg_qv_guard BEFORE UPDATE ON quality_visits
  FOR EACH ROW EXECUTE FUNCTION qv_guard_transition();

DROP TRIGGER IF EXISTS trg_qv_touch ON quality_visits;
CREATE TRIGGER trg_qv_touch BEFORE UPDATE ON quality_visits
  FOR EACH ROW EXECUTE FUNCTION pilot_touch_row();

DROP TRIGGER IF EXISTS trg_qv_audit ON quality_visits;
CREATE TRIGGER trg_qv_audit AFTER INSERT OR UPDATE OR DELETE ON quality_visits
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ─── (4) حماية عناصر الزيارة بعد التحقق + تدقيق يحفظ التاريخ ────────────
-- يمنع مسح/تعديل عناصر زيارة تم التحقق منها أو إغلاقها (يوقف مسح التاريخ
-- التدميري في الواجهة بعد اكتمال المراجعة). التدقيق يلتقط أي حذف/إدراج.
CREATE OR REPLACE FUNCTION qvi_guard_after_verify()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_status TEXT; v_vid BIGINT;
BEGIN
  v_vid := COALESCE(NEW.visit_id, OLD.visit_id);
  SELECT status INTO v_status FROM quality_visits WHERE id = v_vid;
  IF v_status IN ('verified','closed') THEN
    RAISE EXCEPTION 'لا يمكن تعديل عناصر زيارة تم التحقق منها أو إغلاقها';
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS trg_qvi_guard ON quality_visit_items;
CREATE TRIGGER trg_qvi_guard BEFORE INSERT OR UPDATE OR DELETE ON quality_visit_items
  FOR EACH ROW EXECUTE FUNCTION qvi_guard_after_verify();

DROP TRIGGER IF EXISTS trg_qvi_audit ON quality_visit_items;
CREATE TRIGGER trg_qvi_audit AFTER INSERT OR UPDATE OR DELETE ON quality_visit_items
  FOR EACH ROW EXECUTE FUNCTION pilot_audit_trigger();

-- ═══════════════════════════════════════════════════════════════════════
-- (5) RLS الحقيقية — استبدال using(true)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION qv_is_quality_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT current_app_role() IN ('admin','company_manager','quality_manager','operations_manager');
$$;
CREATE OR REPLACE FUNCTION qv_user_in_branch(p_branch BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = p_branch);
$$;

-- ── القوالب (sections/items): قراءة للجميع، تعديل لإدارة الجودة ──
DROP POLICY IF EXISTS qs_all ON quality_sections;
DROP POLICY IF EXISTS qi_all ON quality_items;
DROP POLICY IF EXISTS qs_sel ON quality_sections; DROP POLICY IF EXISTS qs_wr ON quality_sections;
DROP POLICY IF EXISTS qi_sel ON quality_items;    DROP POLICY IF EXISTS qi_wr ON quality_items;
CREATE POLICY qs_sel ON quality_sections FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
CREATE POLICY qs_wr  ON quality_sections FOR ALL TO authenticated USING (qv_is_quality_admin()) WITH CHECK (qv_is_quality_admin());
CREATE POLICY qi_sel ON quality_items FOR SELECT TO authenticated USING (current_app_user_id() IS NOT NULL);
CREATE POLICY qi_wr  ON quality_items FOR ALL TO authenticated USING (qv_is_quality_admin()) WITH CHECK (qv_is_quality_admin());

-- ── الزيارات: بالفرع + المفتِّش نفسه ──
DROP POLICY IF EXISTS qv_all ON quality_visits;
DROP POLICY IF EXISTS qv_sel ON quality_visits; DROP POLICY IF EXISTS qv_ins ON quality_visits;
DROP POLICY IF EXISTS qv_upd ON quality_visits; DROP POLICY IF EXISTS qv_del ON quality_visits;
CREATE POLICY qv_sel ON quality_visits FOR SELECT TO authenticated USING (
  qv_is_quality_admin() OR qv_user_in_branch(branch_id) OR inspector_id = current_app_user_id()
);
CREATE POLICY qv_ins ON quality_visits FOR INSERT TO authenticated WITH CHECK (
  inspector_id = current_app_user_id()
  AND (qv_is_quality_admin() OR qv_user_in_branch(branch_id) OR branch_id IS NULL)
);
CREATE POLICY qv_upd ON quality_visits FOR UPDATE TO authenticated
  USING (qv_is_quality_admin() OR qv_user_in_branch(branch_id))
  WITH CHECK (qv_is_quality_admin() OR qv_user_in_branch(branch_id));
CREATE POLICY qv_del ON quality_visits FOR DELETE TO authenticated USING (
  current_app_role() IN ('admin','company_manager')
);

-- ── الجداول الفرعية للزيارة: ترث من الزيارة الأم ──
DO $$
DECLARE child TEXT; old_name TEXT;
  children TEXT[] := ARRAY['quality_visit_items','quality_visit_sections','quality_attachments'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    old_name := CASE child
      WHEN 'quality_visit_items' THEN 'qvi_all'
      WHEN 'quality_visit_sections' THEN 'qvs_all'
      WHEN 'quality_attachments' THEN 'qa_all' END;
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', old_name, child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
    EXECUTE format($f$
      CREATE POLICY %1$s_sel ON %1$I FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM quality_visits v WHERE v.id = %1$I.visit_id
          AND (qv_is_quality_admin() OR qv_user_in_branch(v.branch_id) OR v.inspector_id = current_app_user_id()))
      )$f$, child);
    EXECUTE format($f$
      CREATE POLICY %1$s_wr ON %1$I FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM quality_visits v WHERE v.id = %1$I.visit_id
             AND (qv_is_quality_admin() OR qv_user_in_branch(v.branch_id))))
      WITH CHECK (EXISTS (SELECT 1 FROM quality_visits v WHERE v.id = %1$I.visit_id
             AND (qv_is_quality_admin() OR qv_user_in_branch(v.branch_id))))
      $f$, child);
  END LOOP;
END $$;

SELECT 'quality policies' AS object,
       (SELECT count(*)::text FROM pg_policies WHERE tablename LIKE 'quality_%') AS all_policies;
