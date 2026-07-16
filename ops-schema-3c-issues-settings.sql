-- ═══════════════════════════════════════════════════════════
-- وحدة التشغيل (Operations) — المرحلة 3.c (الأخيرة)
-- المشكلات والتصعيد + إعدادات الوحدة
-- ═══════════════════════════════════════════════════════════
-- يعتمد على: ops-schema-3a-shifts.sql (is_ops_manager،
-- can_access_branch_ops)، وعلى جدول department_tasks الموجود
-- بالفعل في النظام الأساسي (التصعيد يُنشئ مهمة فيه بدلًا من
-- تكرار منطق مهام جديد). لا تُضاف لوحة متابعة فروع كجدول —
-- تُبنى من طبقة JS مباشرة فوق بيانات المراحل 3.a/3.b الموجودة.
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) ops_settings — إعدادات الوحدة (صف واحد id=1)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_settings (
  id                              INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  auto_escalate_critical_issues   BOOLEAN NOT NULL DEFAULT TRUE,
  default_escalation_assignee_id  BIGINT REFERENCES users(id) ON DELETE SET NULL,
  low_stock_alerts_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  issue_escalation_task_priority  TEXT NOT NULL DEFAULT 'high',
  created_at                      TIMESTAMPTZ DEFAULT now(),
  updated_at                      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO ops_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS ops_settings_updated_at ON ops_settings;
CREATE TRIGGER ops_settings_updated_at BEFORE UPDATE ON ops_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) ops_issues — المشكلات التشغيلية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_issues (
  id                BIGSERIAL PRIMARY KEY,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id          BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  category          TEXT NOT NULL CHECK (category IN ('service', 'food_quality', 'equipment', 'safety', 'staff', 'other')),
  title             TEXT NOT NULL,
  description       TEXT,
  severity          TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status            TEXT NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'in_progress', 'escalated', 'resolved', 'closed')),
  escalated_task_id BIGINT REFERENCES department_tasks(id) ON DELETE SET NULL,
  reported_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  resolved_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_issues_branch_idx ON ops_issues(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ops_issues_status_idx ON ops_issues(status) WHERE status IN ('open', 'in_progress', 'escalated');

DROP TRIGGER IF EXISTS ops_issues_updated_at ON ops_issues;
CREATE TRIGGER ops_issues_updated_at BEFORE UPDATE ON ops_issues
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) ops_issue_escalations — سجل كل عملية تصعيد لمشكلة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_issue_escalations (
  id             BIGSERIAL PRIMARY KEY,
  issue_id       BIGINT NOT NULL REFERENCES ops_issues(id) ON DELETE CASCADE,
  task_id        BIGINT REFERENCES department_tasks(id) ON DELETE SET NULL,
  escalated_to   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  escalated_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  reason         TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_issue_escalations_issue_idx ON ops_issue_escalations(issue_id);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE ops_settings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_issues            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_issue_escalations ENABLE ROW LEVEL SECURITY;

-- ops_settings: قراءة لكل مستخدمي التشغيل، تعديل لمدير التشغيل فقط
DROP POLICY IF EXISTS ops_settings_select ON ops_settings;
CREATE POLICY ops_settings_select ON ops_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ops_settings_write ON ops_settings;
CREATE POLICY ops_settings_write ON ops_settings FOR ALL
  USING (is_ops_manager()) WITH CHECK (is_ops_manager());

-- ops_issues
DROP POLICY IF EXISTS ops_issues_select ON ops_issues;
CREATE POLICY ops_issues_select ON ops_issues FOR SELECT
  USING (can_access_branch_ops(branch_id));
DROP POLICY IF EXISTS ops_issues_write ON ops_issues;
CREATE POLICY ops_issues_write ON ops_issues FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_issues.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_issues.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')));

-- ops_issue_escalations: يتبع صلاحية المشكلة الأصلية، والتصعيد نفسه لمدير التشغيل/مدير الفرع فقط
DROP POLICY IF EXISTS ops_issue_escalations_select ON ops_issue_escalations;
CREATE POLICY ops_issue_escalations_select ON ops_issue_escalations FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_issues i WHERE i.id = ops_issue_escalations.issue_id AND can_access_branch_ops(i.branch_id)));
DROP POLICY IF EXISTS ops_issue_escalations_write ON ops_issue_escalations;
CREATE POLICY ops_issue_escalations_write ON ops_issue_escalations FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_issues i WHERE i.id = ops_issue_escalations.issue_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = i.branch_id AND u.role IN ('branch_manager', 'deputy_manager')))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_issues i WHERE i.id = ops_issue_escalations.issue_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = i.branch_id AND u.role IN ('branch_manager', 'deputy_manager')))));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ (Post-migration checklist):
-- 1) SELECT * FROM ops_settings; -- يجب أن يظهر صف واحد id=1
-- 2) SELECT * FROM ops_issues LIMIT 1;
-- 3) SELECT * FROM ops_issue_escalations LIMIT 1;
-- ═══════════════════════════════════════════════════════════
