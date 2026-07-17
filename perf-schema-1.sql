-- ═══════════════════════════════════════════════════════════
-- الأداء Performance — Phase 1 (Wave 2 Module 29)
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: تعريفات KPI + سكوركارد شهري + قيم البنود + تقييمات + أهداف SMART
-- + دالة perf_compute_scorecard_score() لحساب الدرجة الإجمالية
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير الأداء
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_perf_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'hr_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) perf_kpi_definitions — تعريفات مؤشرات الأداء
--    DECISION: نوع الهدف يحدد كيفية حساب الدرجة:
--    higher_better: النسبة = actual/target × 100
--    lower_better:  النسبة = target/actual × 100 (كل ما قلّت لأقل، درجة أعلى)
--    range:         100 لو داخل النطاق، أقل حسب الانحراف
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perf_kpi_definitions (
  id             BIGSERIAL PRIMARY KEY,
  code           TEXT UNIQUE NOT NULL,
  name           TEXT NOT NULL,
  category       TEXT NOT NULL CHECK (category IN ('sales', 'service', 'quality', 'operations', 'hr', 'finance', 'safety')),
  unit           TEXT NOT NULL DEFAULT 'number',
  target_type    TEXT NOT NULL DEFAULT 'higher_better'
                  CHECK (target_type IN ('higher_better', 'lower_better', 'range')),
  weight         NUMERIC(5,2) NOT NULL DEFAULT 1 CHECK (weight > 0),
  applies_to     TEXT NOT NULL DEFAULT 'branch' CHECK (applies_to IN ('branch', 'employee', 'both')),
  description    TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS perf_kpi_category_idx ON perf_kpi_definitions(category) WHERE is_active;

DROP TRIGGER IF EXISTS perf_kpi_updated_at ON perf_kpi_definitions;
CREATE TRIGGER perf_kpi_updated_at BEFORE UPDATE ON perf_kpi_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- بذر KPIs افتراضية شائعة في المطاعم
INSERT INTO perf_kpi_definitions (code, name, category, unit, target_type, weight, applies_to, description) VALUES
  ('SALES_MOM',      'نمو المبيعات شهر لشهر',      'sales',      '%',      'higher_better', 2.0, 'branch',   'نسبة نمو المبيعات مقارنة بالشهر السابق'),
  ('AVG_TICKET',     'متوسط قيمة الفاتورة',         'sales',      'ر.س',    'higher_better', 1.5, 'branch',   'متوسط ما ينفقه العميل في الفاتورة'),
  ('CUSTOMER_SAT',   'رضا العملاء',                'service',    '/5',     'higher_better', 2.0, 'both',     'متوسط تقييم رضا العملاء'),
  ('COMPLAINT_RATE', 'معدل الشكاوى',                'quality',    '/1000',  'lower_better',  1.5, 'branch',   'عدد الشكاوى لكل 1000 معاملة'),
  ('WASTE_RATIO',    'نسبة الهدر',                  'operations', '%',      'lower_better',  1.5, 'branch',   'قيمة الهدر ÷ قيمة المبيعات'),
  ('ATTENDANCE',     'الالتزام بالحضور',            'hr',         '%',      'higher_better', 1.0, 'employee', 'أيام الحضور ÷ أيام العمل'),
  ('LATE_RATIO',     'نسبة التأخر',                 'hr',         '%',      'lower_better',  1.0, 'employee', 'عدد مرات التأخر ÷ أيام العمل'),
  ('GROSS_MARGIN',   'هامش الربح الإجمالي',         'finance',    '%',      'higher_better', 2.0, 'branch',   'الربح الإجمالي ÷ الإيرادات'),
  ('HACCP_BREACHES', 'عدد مخالفات سلامة الغذاء',    'safety',     'عدد',    'lower_better',  1.5, 'branch',   'حوادث/خروقات مسجلة في الشهر')
ON CONFLICT (code) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- 2) perf_scorecards — سكوركارد شهري (فرع أو موظف)
--    DECISION: صف واحد لكل (branch_id | employee_id) لكل شهر.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perf_scorecards (
  id             BIGSERIAL PRIMARY KEY,
  scorecard_no   TEXT UNIQUE,
  entity_type    TEXT NOT NULL CHECK (entity_type IN ('branch', 'employee')),
  branch_id      BIGINT REFERENCES branches(id) ON DELETE CASCADE,
  employee_id    BIGINT REFERENCES users(id) ON DELETE CASCADE,
  period_year    INT NOT NULL,
  period_month   INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  status         TEXT NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'submitted', 'reviewed', 'locked')),
  total_score    NUMERIC(6,2),
  grade          TEXT CHECK (grade IN ('A+', 'A', 'B', 'C', 'D', 'F') OR grade IS NULL),
  reviewed_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at    TIMESTAMPTZ,
  notes          TEXT,
  created_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT perf_sc_entity CHECK (
    (entity_type = 'branch'   AND branch_id IS NOT NULL AND employee_id IS NULL) OR
    (entity_type = 'employee' AND employee_id IS NOT NULL)
  )
  -- ملاحظة: التفرد يُنفَّذ عبر partial unique indexes أدناه بدل constraint واحد
  -- (السلوك القديم CONSTRAINT perf_sc_unique_branch كان يعامل NULL كمتميز
  -- فيسمح بتكرار سكوركاردات الموظفين. الحل: index لكل entity_type منفصل)
);

CREATE INDEX IF NOT EXISTS perf_sc_branch_idx   ON perf_scorecards(branch_id, period_year DESC, period_month DESC);
CREATE INDEX IF NOT EXISTS perf_sc_employee_idx ON perf_scorecards(employee_id, period_year DESC, period_month DESC);
CREATE INDEX IF NOT EXISTS perf_sc_status_idx   ON perf_scorecards(status);

-- إزالة القيد القديم لو موجود من نسخة سابقة (كان يسمح بتكرار سكوركاردات الموظفين)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'perf_sc_unique_branch') THEN
    ALTER TABLE perf_scorecards DROP CONSTRAINT perf_sc_unique_branch;
  END IF;
END $$;

-- partial unique indexes للتفرد الصحيح: صف واحد لكل (فرع/موظف، سنة، شهر)
CREATE UNIQUE INDEX IF NOT EXISTS perf_sc_branch_period_uniq
  ON perf_scorecards (branch_id, period_year, period_month)
  WHERE entity_type = 'branch';
CREATE UNIQUE INDEX IF NOT EXISTS perf_sc_employee_period_uniq
  ON perf_scorecards (employee_id, period_year, period_month)
  WHERE entity_type = 'employee';

DROP TRIGGER IF EXISTS perf_sc_updated_at ON perf_scorecards;
CREATE TRIGGER perf_sc_updated_at BEFORE UPDATE ON perf_scorecards
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION perf_assign_scorecard_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_prefix TEXT;
  v_seq    INT;
BEGIN
  IF NEW.scorecard_no IS NULL THEN
    v_prefix := 'SC-' || NEW.period_year || LPAD(NEW.period_month::TEXT, 2, '0') || '-';
    IF NEW.entity_type = 'branch' THEN v_prefix := v_prefix || 'BR' || NEW.branch_id || '-';
    ELSE v_prefix := v_prefix || 'EMP' || NEW.employee_id || '-';
    END IF;
    SELECT COUNT(*) + 1 INTO v_seq FROM perf_scorecards WHERE scorecard_no LIKE v_prefix || '%';
    NEW.scorecard_no := v_prefix || LPAD(v_seq::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS perf_sc_assign_no ON perf_scorecards;
CREATE TRIGGER perf_sc_assign_no BEFORE INSERT ON perf_scorecards
  FOR EACH ROW EXECUTE FUNCTION perf_assign_scorecard_no();

-- ───────────────────────────────────────────────────────────
-- 3) perf_scorecard_entries — قيم KPI لكل سكوركارد
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perf_scorecard_entries (
  id                BIGSERIAL PRIMARY KEY,
  scorecard_id      BIGINT NOT NULL REFERENCES perf_scorecards(id) ON DELETE CASCADE,
  kpi_id            BIGINT NOT NULL REFERENCES perf_kpi_definitions(id) ON DELETE RESTRICT,
  target_value      NUMERIC(12,2) NOT NULL,
  target_min        NUMERIC(12,2),
  target_max        NUMERIC(12,2),
  actual_value      NUMERIC(12,2),
  weighted_score    NUMERIC(6,2),
  comment           TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT perf_sce_unique UNIQUE (scorecard_id, kpi_id)
);

CREATE INDEX IF NOT EXISTS perf_sce_scorecard_idx ON perf_scorecard_entries(scorecard_id);

DROP TRIGGER IF EXISTS perf_sce_updated_at ON perf_scorecard_entries;
CREATE TRIGGER perf_sce_updated_at BEFORE UPDATE ON perf_scorecard_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 4) perf_reviews — تقييمات دورية للموظفين
--    DECISION: تشمل تجربة عمل (probation) وسنوي/نصف سنوي/ربعي
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perf_reviews (
  id                    BIGSERIAL PRIMARY KEY,
  review_no             TEXT UNIQUE,
  employee_id           BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reviewer_id           BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  review_type           TEXT NOT NULL DEFAULT 'annual'
                         CHECK (review_type IN ('probation', 'quarterly', 'semi_annual', 'annual', 'ad_hoc')),
  period_from           DATE NOT NULL,
  period_to             DATE NOT NULL,
  overall_rating        INT CHECK (overall_rating BETWEEN 1 AND 5),
  strengths             TEXT,
  areas_for_improvement TEXT,
  development_plan      TEXT,
  employee_comments     TEXT,
  status                TEXT NOT NULL DEFAULT 'draft'
                         CHECK (status IN ('draft', 'submitted', 'acknowledged', 'closed')),
  submitted_at          TIMESTAMPTZ,
  acknowledged_at       TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT perf_review_period CHECK (period_to >= period_from)
);

CREATE INDEX IF NOT EXISTS perf_reviews_employee_idx ON perf_reviews(employee_id, period_to DESC);
CREATE INDEX IF NOT EXISTS perf_reviews_reviewer_idx ON perf_reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS perf_reviews_status_idx   ON perf_reviews(status);

DROP TRIGGER IF EXISTS perf_reviews_updated_at ON perf_reviews;
CREATE TRIGGER perf_reviews_updated_at BEFORE UPDATE ON perf_reviews
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION perf_assign_review_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.review_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM perf_reviews WHERE review_no LIKE 'RV-' || v_year || '-%';
    NEW.review_no := 'RV-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS perf_reviews_assign_no ON perf_reviews;
CREATE TRIGGER perf_reviews_assign_no BEFORE INSERT ON perf_reviews
  FOR EACH ROW EXECUTE FUNCTION perf_assign_review_no();

-- ───────────────────────────────────────────────────────────
-- 5) perf_goals — أهداف SMART فردية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perf_goals (
  id              BIGSERIAL PRIMARY KEY,
  goal_no         TEXT UNIQUE,
  employee_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  review_id       BIGINT REFERENCES perf_reviews(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  description     TEXT,
  category        TEXT DEFAULT 'general'
                   CHECK (category IN ('performance', 'skill_development', 'behavior', 'project', 'general')),
  target_date     DATE NOT NULL,
  progress_pct    INT NOT NULL DEFAULT 0 CHECK (progress_pct BETWEEN 0 AND 100),
  status          TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active', 'achieved', 'partially_met', 'not_met', 'cancelled')),
  achievement_notes TEXT,
  assigned_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS perf_goals_employee_idx ON perf_goals(employee_id, target_date);
CREATE INDEX IF NOT EXISTS perf_goals_status_idx   ON perf_goals(status) WHERE status = 'active';

DROP TRIGGER IF EXISTS perf_goals_updated_at ON perf_goals;
CREATE TRIGGER perf_goals_updated_at BEFORE UPDATE ON perf_goals
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION perf_assign_goal_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.goal_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM perf_goals WHERE goal_no LIKE 'GOAL-' || v_year || '-%';
    NEW.goal_no := 'GOAL-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS perf_goals_assign_no ON perf_goals;
CREATE TRIGGER perf_goals_assign_no BEFORE INSERT ON perf_goals
  FOR EACH ROW EXECUTE FUNCTION perf_assign_goal_no();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة حساب درجة السكوركارد
-- ═══════════════════════════════════════════════════════════
-- تحسب weighted_score لكل بند + total_score للسكوركارد + grade
-- المعادلات:
--   higher_better: pct = LEAST(actual/target × 100, 150)  -- سقف 150%
--   lower_better:  pct = LEAST(target/GREATEST(actual,0.0001) × 100, 150)
--   range:         100 لو target_min ≤ actual ≤ target_max، وإلا خصم
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION perf_compute_scorecard_score(p_scorecard_id BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry     RECORD;
  v_kpi       RECORD;
  v_pct       NUMERIC;
  v_weighted  NUMERIC;
  v_total_w   NUMERIC := 0;
  v_sum_ws    NUMERIC := 0;
  v_score     NUMERIC;
  v_grade     TEXT;
BEGIN
  FOR v_entry IN
    SELECT * FROM perf_scorecard_entries WHERE scorecard_id = p_scorecard_id AND actual_value IS NOT NULL
  LOOP
    SELECT * INTO v_kpi FROM perf_kpi_definitions WHERE id = v_entry.kpi_id;
    IF v_kpi.target_type = 'higher_better' THEN
      IF v_entry.target_value <= 0 THEN v_pct := 100;
      ELSE v_pct := LEAST(v_entry.actual_value / v_entry.target_value * 100, 150);
      END IF;
    ELSIF v_kpi.target_type = 'lower_better' THEN
      IF v_entry.actual_value <= 0 THEN v_pct := 150;
      ELSIF v_entry.target_value <= 0 THEN v_pct := GREATEST(100 - v_entry.actual_value, 0);
      ELSE v_pct := LEAST(v_entry.target_value / v_entry.actual_value * 100, 150);
      END IF;
    ELSIF v_kpi.target_type = 'range' THEN
      IF v_entry.target_min IS NOT NULL AND v_entry.target_max IS NOT NULL
         AND v_entry.actual_value >= v_entry.target_min AND v_entry.actual_value <= v_entry.target_max THEN
        v_pct := 100;
      ELSIF v_entry.target_min IS NOT NULL AND v_entry.actual_value < v_entry.target_min THEN
        v_pct := GREATEST(100 - (v_entry.target_min - v_entry.actual_value) / GREATEST(v_entry.target_min, 0.0001) * 100, 0);
      ELSIF v_entry.target_max IS NOT NULL AND v_entry.actual_value > v_entry.target_max THEN
        v_pct := GREATEST(100 - (v_entry.actual_value - v_entry.target_max) / GREATEST(v_entry.target_max, 0.0001) * 100, 0);
      ELSE v_pct := 100;
      END IF;
    ELSE v_pct := 0;
    END IF;

    v_weighted := v_pct * v_kpi.weight;
    v_sum_ws  := v_sum_ws + v_weighted;
    v_total_w := v_total_w + v_kpi.weight;

    UPDATE perf_scorecard_entries SET weighted_score = ROUND(v_pct, 2) WHERE id = v_entry.id;
  END LOOP;

  IF v_total_w > 0 THEN
    v_score := ROUND(v_sum_ws / v_total_w, 2);
  ELSE
    v_score := NULL;
  END IF;

  -- تحديد الدرجة
  v_grade := CASE
    WHEN v_score IS NULL THEN NULL
    WHEN v_score >= 110 THEN 'A+'
    WHEN v_score >= 95  THEN 'A'
    WHEN v_score >= 80  THEN 'B'
    WHEN v_score >= 65  THEN 'C'
    WHEN v_score >= 50  THEN 'D'
    ELSE 'F'
  END;

  UPDATE perf_scorecards SET total_score = v_score, grade = v_grade WHERE id = p_scorecard_id;
  RETURN v_score;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE perf_kpi_definitions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE perf_scorecards          ENABLE ROW LEVEL SECURITY;
ALTER TABLE perf_scorecard_entries   ENABLE ROW LEVEL SECURITY;
ALTER TABLE perf_reviews             ENABLE ROW LEVEL SECURITY;
ALTER TABLE perf_goals               ENABLE ROW LEVEL SECURITY;

-- تعريفات KPI: قراءة لكل مصادَق، كتابة لمدير الأداء
DROP POLICY IF EXISTS perf_kpi_sel ON perf_kpi_definitions;
CREATE POLICY perf_kpi_sel ON perf_kpi_definitions FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS perf_kpi_wr ON perf_kpi_definitions;
CREATE POLICY perf_kpi_wr ON perf_kpi_definitions FOR ALL TO authenticated
  USING (is_perf_manager()) WITH CHECK (is_perf_manager());

-- السكوركارد: الموظف يشوف الخاص به، مدير الفرع يشوف فرعه، مدير الأداء يشوف الكل
DROP POLICY IF EXISTS perf_sc_sel ON perf_scorecards;
CREATE POLICY perf_sc_sel ON perf_scorecards FOR SELECT TO authenticated USING (
  employee_id = current_app_user_id()
  OR is_perf_manager()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = perf_scorecards.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager'))
);
DROP POLICY IF EXISTS perf_sc_wr ON perf_scorecards;
CREATE POLICY perf_sc_wr ON perf_scorecards FOR ALL TO authenticated
  USING (is_perf_manager()) WITH CHECK (is_perf_manager());

-- قيم السكوركارد: تتبع صلاحية الأم
DROP POLICY IF EXISTS perf_sce_sel ON perf_scorecard_entries;
CREATE POLICY perf_sce_sel ON perf_scorecard_entries FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM perf_scorecards s WHERE s.id = perf_scorecard_entries.scorecard_id
          AND (s.employee_id = current_app_user_id()
               OR is_perf_manager()
               OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                          AND u.branch_id = s.branch_id AND u.role IN ('branch_manager', 'deputy_manager'))))
);
DROP POLICY IF EXISTS perf_sce_wr ON perf_scorecard_entries;
CREATE POLICY perf_sce_wr ON perf_scorecard_entries FOR ALL TO authenticated
  USING (is_perf_manager()) WITH CHECK (is_perf_manager());

-- تقييمات الأداء: الموظف يشوف تقييمه، المُقيِّم يشوف تقييماته، مدير الأداء يشوف الكل
DROP POLICY IF EXISTS perf_reviews_sel ON perf_reviews;
CREATE POLICY perf_reviews_sel ON perf_reviews FOR SELECT TO authenticated USING (
  employee_id = current_app_user_id()
  OR reviewer_id = current_app_user_id()
  OR is_perf_manager()
);
DROP POLICY IF EXISTS perf_reviews_ins ON perf_reviews;
CREATE POLICY perf_reviews_ins ON perf_reviews FOR INSERT TO authenticated
  WITH CHECK (reviewer_id = current_app_user_id() OR is_perf_manager());
DROP POLICY IF EXISTS perf_reviews_upd ON perf_reviews;
CREATE POLICY perf_reviews_upd ON perf_reviews FOR UPDATE TO authenticated USING (
  (reviewer_id = current_app_user_id() AND status IN ('draft', 'submitted'))
  OR (employee_id = current_app_user_id() AND status = 'submitted')  -- اقرار الموظف
  OR is_perf_manager()
);

-- الأهداف: الموظف يشوف أهدافه ويحدّث نسبة الإنجاز، المُعيِّن يحدّث كل شيء
DROP POLICY IF EXISTS perf_goals_sel ON perf_goals;
CREATE POLICY perf_goals_sel ON perf_goals FOR SELECT TO authenticated USING (
  employee_id = current_app_user_id()
  OR assigned_by = current_app_user_id()
  OR is_perf_manager()
);
DROP POLICY IF EXISTS perf_goals_ins ON perf_goals;
CREATE POLICY perf_goals_ins ON perf_goals FOR INSERT TO authenticated
  WITH CHECK (assigned_by = current_app_user_id() OR is_perf_manager());
DROP POLICY IF EXISTS perf_goals_upd ON perf_goals;
CREATE POLICY perf_goals_upd ON perf_goals FOR UPDATE TO authenticated USING (
  employee_id = current_app_user_id()  -- الموظف يحدّث التقدم
  OR assigned_by = current_app_user_id()
  OR is_perf_manager()
);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT count(*) FROM perf_kpi_definitions;  -- 9 مؤشرات افتراضية
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'perf_%';
-- 3) SELECT relname FROM pg_class WHERE relname LIKE 'perf_%';
-- ═══════════════════════════════════════════════════════════
