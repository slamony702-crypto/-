-- ═══════════════════════════════════════════════════════════
-- وحدة التشغيل (Operations) — المرحلة 3.a
-- التشغيل اليومي والورديات
-- ═══════════════════════════════════════════════════════════
-- يفترض هذا الملف وجود: current_app_user_id(), current_app_role(),
-- set_updated_at()، وجدول users(branch_id) — كلها من hr-schema.sql
-- وقواعد النظام الأساسية. لا يُنشئ أي جدول موازٍ لموجود بالفعل.
-- التنفيذ آمن ومتكرر (idempotent) — يمكن تشغيله أكثر من مرة.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دوال مساعدة لصلاحيات وحدة التشغيل
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_ops_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager');
$$;

-- هل المستخدم الحالي منتمٍ لنفس فرع الصف المطلوب (أو مدير تشغيل/شركة/نظام)؟
CREATE OR REPLACE FUNCTION can_access_branch_ops(p_branch_id BIGINT)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT is_ops_manager()
    OR EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = current_app_user_id()
        AND u.branch_id = p_branch_id
        AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
    );
$$;

-- ───────────────────────────────────────────────────────────
-- 1) ops_shift_templates — قوالب الورديات (صباحي/مسائي/... لكل فرع)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_shift_templates (
  id           BIGSERIAL PRIMARY KEY,
  branch_id    BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  start_time   TIME NOT NULL,
  end_time     TIME NOT NULL,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_shift_templates_branch_idx ON ops_shift_templates(branch_id) WHERE is_active;

DROP TRIGGER IF EXISTS ops_shift_templates_updated_at ON ops_shift_templates;
CREATE TRIGGER ops_shift_templates_updated_at BEFORE UPDATE ON ops_shift_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) ops_shifts — الورديات الفعلية المجدولة/الجارية/المغلقة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_shifts (
  id                BIGSERIAL PRIMARY KEY,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  template_id       BIGINT REFERENCES ops_shift_templates(id) ON DELETE SET NULL,
  shift_date        DATE NOT NULL,
  shift_manager_id  BIGINT REFERENCES users(id) ON DELETE SET NULL,
  status            TEXT NOT NULL DEFAULT 'planned'
                     CHECK (status IN ('planned', 'in_progress', 'handed_over', 'closed')),
  opened_at         TIMESTAMPTZ,
  closed_at         TIMESTAMPTZ,
  notes             TEXT,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  CONSTRAINT ops_shifts_unique_slot UNIQUE (branch_id, shift_date, template_id)
);

CREATE INDEX IF NOT EXISTS ops_shifts_branch_date_idx ON ops_shifts(branch_id, shift_date DESC);
CREATE INDEX IF NOT EXISTS ops_shifts_status_idx      ON ops_shifts(status) WHERE status IN ('planned', 'in_progress');

DROP TRIGGER IF EXISTS ops_shifts_updated_at ON ops_shifts;
CREATE TRIGGER ops_shifts_updated_at BEFORE UPDATE ON ops_shifts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) ops_shift_handovers — تسليم/استلام الوردية بين المسؤولين
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_shift_handovers (
  id              BIGSERIAL PRIMARY KEY,
  shift_id        BIGINT NOT NULL REFERENCES ops_shifts(id) ON DELETE CASCADE,
  next_shift_id   BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  handed_over_by  BIGINT REFERENCES users(id) ON DELETE SET NULL,
  received_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  cash_amount     NUMERIC(14,2),
  pending_items   TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_shift_handovers_shift_idx ON ops_shift_handovers(shift_id);

-- ───────────────────────────────────────────────────────────
-- 4) ops_station_assignments — توزيع الموظفين على المحطات في الوردية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_station_assignments (
  id            BIGSERIAL PRIMARY KEY,
  shift_id      BIGINT NOT NULL REFERENCES ops_shifts(id) ON DELETE CASCADE,
  user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  station_name  TEXT NOT NULL,
  assigned_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT ops_station_assignments_unique UNIQUE (shift_id, user_id, station_name)
);

CREATE INDEX IF NOT EXISTS ops_station_assignments_shift_idx ON ops_station_assignments(shift_id);
CREATE INDEX IF NOT EXISTS ops_station_assignments_user_idx  ON ops_station_assignments(user_id);

-- ملاحظة: التحقق من عدم تعيين موظف غائب على محطة يتم في طبقة JS
-- (window.OPS) بمقارنة hr_attendance لنفس اليوم قبل الإدراج، وليس
-- بقيد قاعدة بيانات صارم، لتفادي تعقيد عبور-جداول غير ضروري.

-- ───────────────────────────────────────────────────────────
-- 5) ops_daily_checklists + ops_checklist_items — قوائم الفتح/الإغلاق
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_daily_checklists (
  id               BIGSERIAL PRIMARY KEY,
  branch_id        BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id         BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  checklist_type   TEXT NOT NULL CHECK (checklist_type IN ('opening', 'closing')),
  checklist_date   DATE NOT NULL,
  status           TEXT NOT NULL DEFAULT 'in_progress'
                    CHECK (status IN ('in_progress', 'completed')),
  completed_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  completed_at     TIMESTAMPTZ,
  created_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_daily_checklists_branch_date_idx ON ops_daily_checklists(branch_id, checklist_date DESC);
CREATE INDEX IF NOT EXISTS ops_daily_checklists_shift_idx       ON ops_daily_checklists(shift_id);

DROP TRIGGER IF EXISTS ops_daily_checklists_updated_at ON ops_daily_checklists;
CREATE TRIGGER ops_daily_checklists_updated_at BEFORE UPDATE ON ops_daily_checklists
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS ops_checklist_items (
  id            BIGSERIAL PRIMARY KEY,
  checklist_id  BIGINT NOT NULL REFERENCES ops_daily_checklists(id) ON DELETE CASCADE,
  item_text     TEXT NOT NULL,
  sort_order    INT NOT NULL DEFAULT 0,
  is_checked    BOOLEAN NOT NULL DEFAULT false,
  checked_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  checked_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_checklist_items_checklist_idx ON ops_checklist_items(checklist_id, sort_order);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE ops_shift_templates    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_shifts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_shift_handovers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_station_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_daily_checklists   ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_checklist_items    ENABLE ROW LEVEL SECURITY;

-- ops_shift_templates: قراءة لكل مستخدمي الفرع، كتابة لمدير التشغيل/الفرع
DROP POLICY IF EXISTS ops_shift_templates_select ON ops_shift_templates;
CREATE POLICY ops_shift_templates_select ON ops_shift_templates FOR SELECT
  USING (can_access_branch_ops(branch_id));

DROP POLICY IF EXISTS ops_shift_templates_write ON ops_shift_templates;
CREATE POLICY ops_shift_templates_write ON ops_shift_templates FOR ALL
  USING (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_shift_templates.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager')
         ))
  WITH CHECK (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_shift_templates.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager')
         ));

-- ops_shifts
DROP POLICY IF EXISTS ops_shifts_select ON ops_shifts;
CREATE POLICY ops_shifts_select ON ops_shifts FOR SELECT
  USING (can_access_branch_ops(branch_id));

DROP POLICY IF EXISTS ops_shifts_write ON ops_shifts;
CREATE POLICY ops_shifts_write ON ops_shifts FOR ALL
  USING (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_shifts.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager')
         ))
  WITH CHECK (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_shifts.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager')
         ));

-- ops_shift_handovers: يتبع فرع الوردية المرتبطة
DROP POLICY IF EXISTS ops_shift_handovers_select ON ops_shift_handovers;
CREATE POLICY ops_shift_handovers_select ON ops_shift_handovers FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_shift_handovers.shift_id
                   AND can_access_branch_ops(s.branch_id)));

DROP POLICY IF EXISTS ops_shift_handovers_write ON ops_shift_handovers;
CREATE POLICY ops_shift_handovers_write ON ops_shift_handovers FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_shift_handovers.shift_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = s.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
                        ))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_shift_handovers.shift_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = s.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
                        ))));

-- ops_station_assignments: يتبع فرع الوردية
DROP POLICY IF EXISTS ops_station_assignments_select ON ops_station_assignments;
CREATE POLICY ops_station_assignments_select ON ops_station_assignments FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_station_assignments.shift_id
                   AND can_access_branch_ops(s.branch_id)));

DROP POLICY IF EXISTS ops_station_assignments_write ON ops_station_assignments;
CREATE POLICY ops_station_assignments_write ON ops_station_assignments FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_station_assignments.shift_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = s.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager')
                        ))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_shifts s WHERE s.id = ops_station_assignments.shift_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = s.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager')
                        ))));

-- ops_daily_checklists
DROP POLICY IF EXISTS ops_daily_checklists_select ON ops_daily_checklists;
CREATE POLICY ops_daily_checklists_select ON ops_daily_checklists FOR SELECT
  USING (can_access_branch_ops(branch_id));

DROP POLICY IF EXISTS ops_daily_checklists_write ON ops_daily_checklists;
CREATE POLICY ops_daily_checklists_write ON ops_daily_checklists FOR ALL
  USING (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_daily_checklists.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
         ))
  WITH CHECK (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = ops_daily_checklists.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
         ));

-- ops_checklist_items: يتبع فرع القائمة الأصلية
DROP POLICY IF EXISTS ops_checklist_items_select ON ops_checklist_items;
CREATE POLICY ops_checklist_items_select ON ops_checklist_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_daily_checklists c WHERE c.id = ops_checklist_items.checklist_id
                   AND can_access_branch_ops(c.branch_id)));

DROP POLICY IF EXISTS ops_checklist_items_write ON ops_checklist_items;
CREATE POLICY ops_checklist_items_write ON ops_checklist_items FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_daily_checklists c WHERE c.id = ops_checklist_items.checklist_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = c.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
                        ))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_daily_checklists c WHERE c.id = ops_checklist_items.checklist_id
                   AND (is_ops_manager() OR EXISTS (
                          SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                            AND u.branch_id = c.branch_id
                            AND u.role IN ('branch_manager', 'deputy_manager', 'employee')
                        ))));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ (Post-migration checklist):
-- 1) SELECT * FROM ops_shift_templates LIMIT 1;   -- يجب أن ينجح بدون خطأ
-- 2) SELECT * FROM ops_shifts LIMIT 1;
-- 3) SELECT * FROM ops_shift_handovers LIMIT 1;
-- 4) SELECT * FROM ops_station_assignments LIMIT 1;
-- 5) SELECT * FROM ops_daily_checklists LIMIT 1;
-- 6) SELECT * FROM ops_checklist_items LIMIT 1;
-- 7) تأكد أن RLS مفعّلة: SELECT relname, relrowsecurity FROM pg_class
--    WHERE relname LIKE 'ops_%';
-- ═══════════════════════════════════════════════════════════
