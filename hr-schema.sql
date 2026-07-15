-- ═══════════════════════════════════════════════════════════════════════════
-- HR MODULE — Schema v1.0
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Core HR (Employee Profile, Positions, Attendance, Leaves, Payroll)
-- Prerequisites: users, departments, branches tables must already exist
-- Idempotent: safe to re-run (uses IF NOT EXISTS / ON CONFLICT / DROP POLICY IF EXISTS)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 0) Extend users with branch_id (nullable) if not present.
--    HR sees each employee's branch. Existing rows keep NULL — no breakage.
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES branches(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS users_branch_id_idx ON users(branch_id) WHERE branch_id IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────
-- 1) Shared helpers used by every HR RLS policy
--    All are SECURITY DEFINER + STABLE so RLS can call them without recursion.
-- ───────────────────────────────────────────────────────────────────────────

-- Map Supabase auth.uid() → app users.id
CREATE OR REPLACE FUNCTION current_app_user_id()
RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM users WHERE auth_id = auth.uid() LIMIT 1;
$$;

-- Role of the current app user (or NULL if not signed in)
CREATE OR REPLACE FUNCTION current_app_role()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM users WHERE auth_id = auth.uid() LIMIT 1;
$$;

-- HR-privileged roles (edit employee profiles, positions, attendance, leaves)
CREATE OR REPLACE FUNCTION is_hr_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'hr_manager');
$$;

-- Payroll-privileged roles (see + edit anyone's salary)
CREATE OR REPLACE FUNCTION is_payroll_authorized()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'hr_manager', 'payroll_officer');
$$;

-- Is current user the direct manager of target_user_id
CREATE OR REPLACE FUNCTION is_manager_of(target_user_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM users
    WHERE id = target_user_id
      AND direct_manager_id = current_app_user_id()
  );
$$;

-- Generic updated_at bumper
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) hr_positions — Positions inside departments (with salary range)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_positions (
  id             BIGSERIAL PRIMARY KEY,
  department_id  BIGINT NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  description    TEXT,
  min_salary     NUMERIC(12,2),
  max_salary     NUMERIC(12,2),
  is_active      BOOLEAN DEFAULT TRUE,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  deleted_at     TIMESTAMPTZ,
  CONSTRAINT hr_positions_salary_range_check
    CHECK (min_salary IS NULL OR max_salary IS NULL OR min_salary <= max_salary)
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_positions_unique_name_per_dept
  ON hr_positions(department_id, name) WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS hr_positions_department_idx
  ON hr_positions(department_id) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS hr_positions_updated_at ON hr_positions;
CREATE TRIGGER hr_positions_updated_at BEFORE UPDATE ON hr_positions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) hr_employee_profile — 1:1 extension of users with HR-only fields.
--    user_id is BOTH primary key AND foreign key — one profile per user max.
--    Every HR field is optional so it never blocks user creation from other flows.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_employee_profile (
  user_id                    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  employee_number            TEXT UNIQUE,
  national_id                TEXT,
  iqama_number               TEXT,
  iqama_expiry               DATE,
  passport_number            TEXT,
  passport_expiry            DATE,
  birth_date                 DATE,
  gender                     TEXT CHECK (gender IN ('male','female') OR gender IS NULL),
  marital_status             TEXT CHECK (marital_status IN ('single','married','divorced','widowed') OR marital_status IS NULL),
  blood_type                 TEXT,
  home_address               TEXT,
  emergency_contact_name     TEXT,
  emergency_contact_phone    TEXT,
  emergency_contact_relation TEXT,
  bank_name                  TEXT,
  iban                       TEXT,
  position_id                BIGINT REFERENCES hr_positions(id) ON DELETE SET NULL,
  contract_type              TEXT CHECK (contract_type IN ('full_time','part_time','temporary','seasonal') OR contract_type IS NULL),
  contract_start_date        DATE,
  contract_end_date          DATE,
  probation_end_date         DATE,
  working_hours_per_week     NUMERIC(5,2) DEFAULT 48,
  base_salary                NUMERIC(12,2) DEFAULT 0,
  housing_allowance          NUMERIC(12,2) DEFAULT 0,
  transport_allowance        NUMERIC(12,2) DEFAULT 0,
  other_allowances           NUMERIC(12,2) DEFAULT 0,
  notes                      TEXT,
  created_at                 TIMESTAMPTZ DEFAULT now(),
  updated_at                 TIMESTAMPTZ DEFAULT now(),
  deleted_at                 TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS hr_profile_position_idx    ON hr_employee_profile(position_id);
CREATE INDEX IF NOT EXISTS hr_profile_iqama_expiry_idx ON hr_employee_profile(iqama_expiry) WHERE iqama_expiry IS NOT NULL;

DROP TRIGGER IF EXISTS hr_profile_updated_at ON hr_employee_profile;
CREATE TRIGGER hr_profile_updated_at BEFORE UPDATE ON hr_employee_profile
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) hr_attendance — Daily attendance record, one row per (employee, day)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_attendance (
  id               BIGSERIAL PRIMARY KEY,
  user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date  DATE NOT NULL,
  check_in         TIMESTAMPTZ,
  check_out        TIMESTAMPTZ,
  status           TEXT NOT NULL CHECK (status IN ('present','absent','late','leave','holiday','sick','remote')),
  notes            TEXT,
  recorded_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  deleted_at       TIMESTAMPTZ,
  CONSTRAINT hr_attendance_unique_day UNIQUE (user_id, attendance_date),
  CONSTRAINT hr_attendance_time_order CHECK (check_out IS NULL OR check_in IS NULL OR check_out >= check_in)
);

CREATE INDEX IF NOT EXISTS hr_attendance_user_date_idx ON hr_attendance(user_id, attendance_date DESC);
CREATE INDEX IF NOT EXISTS hr_attendance_date_idx      ON hr_attendance(attendance_date DESC);
CREATE INDEX IF NOT EXISTS hr_attendance_status_idx    ON hr_attendance(status) WHERE status IN ('absent','late');

DROP TRIGGER IF EXISTS hr_attendance_updated_at ON hr_attendance;
CREATE TRIGGER hr_attendance_updated_at BEFORE UPDATE ON hr_attendance
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) hr_leave_types — Configurable leave categories (seed 8 defaults below)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_leave_types (
  id                    BIGSERIAL PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  code                  TEXT UNIQUE,
  annual_balance_days   NUMERIC(5,1) DEFAULT 0,   -- 0 = untracked (e.g. unpaid)
  is_paid               BOOLEAN DEFAULT TRUE,
  requires_attachment   BOOLEAN DEFAULT FALSE,
  description           TEXT,
  is_active             BOOLEAN DEFAULT TRUE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS hr_leave_types_updated_at ON hr_leave_types;
CREATE TRIGGER hr_leave_types_updated_at BEFORE UPDATE ON hr_leave_types
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO hr_leave_types (name, code, annual_balance_days, is_paid, requires_attachment, description) VALUES
  ('سنوية',        'annual',      30, TRUE,  FALSE, 'الإجازة السنوية المدفوعة'),
  ('مرضية',        'sick',        30, TRUE,  TRUE,  'إجازة مرضية بشهادة طبية'),
  ('طارئة',        'emergency',    5, TRUE,  FALSE, 'إجازة عارضة'),
  ('بدون راتب',    'unpaid',       0, FALSE, FALSE, 'إجازة بدون راتب'),
  ('أمومة',        'maternity',   70, TRUE,  TRUE,  'إجازة وضع للأمهات'),
  ('حج',           'hajj',        15, TRUE,  FALSE, 'إجازة أداء فريضة الحج'),
  ('زواج',         'marriage',     5, TRUE,  TRUE,  'إجازة زواج'),
  ('وفاة قريب',    'bereavement',  5, TRUE,  FALSE, 'إجازة وفاة أحد الأقارب')
ON CONFLICT (name) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6) hr_leaves — Leave requests with an approval workflow
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_leaves (
  id                BIGSERIAL PRIMARY KEY,
  user_id           BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type_id     BIGINT NOT NULL REFERENCES hr_leave_types(id),
  start_date        DATE NOT NULL,
  end_date          DATE NOT NULL,
  days_count        NUMERIC(5,1) NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','cancelled')),
  reason            TEXT,
  attachment_url    TEXT,
  approved_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  CONSTRAINT hr_leaves_date_order    CHECK (end_date >= start_date),
  CONSTRAINT hr_leaves_days_positive CHECK (days_count > 0)
);

CREATE INDEX IF NOT EXISTS hr_leaves_user_idx    ON hr_leaves(user_id, start_date DESC);
CREATE INDEX IF NOT EXISTS hr_leaves_pending_idx ON hr_leaves(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS hr_leaves_type_idx    ON hr_leaves(leave_type_id);

DROP TRIGGER IF EXISTS hr_leaves_updated_at ON hr_leaves;
CREATE TRIGGER hr_leaves_updated_at BEFORE UPDATE ON hr_leaves
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 7) hr_payroll — Monthly payroll slip, one row per (employee, year, month)
--    gross_salary and net_salary are GENERATED so they can never drift.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_payroll (
  id                    BIGSERIAL PRIMARY KEY,
  user_id               BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period_year           INT NOT NULL CHECK (period_year BETWEEN 2000 AND 2100),
  period_month          INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  currency              TEXT NOT NULL DEFAULT 'SAR',
  basic_salary          NUMERIC(12,2) NOT NULL DEFAULT 0,
  housing_allowance     NUMERIC(12,2) DEFAULT 0,
  transport_allowance   NUMERIC(12,2) DEFAULT 0,
  other_allowances      NUMERIC(12,2) DEFAULT 0,
  overtime_amount       NUMERIC(12,2) DEFAULT 0,
  bonus                 NUMERIC(12,2) DEFAULT 0,
  gross_salary          NUMERIC(12,2) GENERATED ALWAYS AS
                          (basic_salary + COALESCE(housing_allowance,0)
                           + COALESCE(transport_allowance,0)
                           + COALESCE(other_allowances,0)
                           + COALESCE(overtime_amount,0)
                           + COALESCE(bonus,0)) STORED,
  deductions            NUMERIC(12,2) DEFAULT 0,
  net_salary            NUMERIC(12,2) GENERATED ALWAYS AS
                          (basic_salary + COALESCE(housing_allowance,0)
                           + COALESCE(transport_allowance,0)
                           + COALESCE(other_allowances,0)
                           + COALESCE(overtime_amount,0)
                           + COALESCE(bonus,0)
                           - COALESCE(deductions,0)) STORED,
  status                TEXT NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','approved','paid','cancelled')),
  notes                 TEXT,
  approved_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at           TIMESTAMPTZ,
  paid_at               TIMESTAMPTZ,
  paid_by               BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  deleted_at            TIMESTAMPTZ,
  CONSTRAINT hr_payroll_unique_period UNIQUE (user_id, period_year, period_month)
);

CREATE INDEX IF NOT EXISTS hr_payroll_user_period_idx
  ON hr_payroll(user_id, period_year DESC, period_month DESC);
CREATE INDEX IF NOT EXISTS hr_payroll_period_idx
  ON hr_payroll(period_year, period_month);
CREATE INDEX IF NOT EXISTS hr_payroll_status_idx
  ON hr_payroll(status);

DROP TRIGGER IF EXISTS hr_payroll_updated_at ON hr_payroll;
CREATE TRIGGER hr_payroll_updated_at BEFORE UPDATE ON hr_payroll
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 8) hr_payroll_items — Line items for allowances / deductions / bonuses
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hr_payroll_items (
  id            BIGSERIAL PRIMARY KEY,
  payroll_id    BIGINT NOT NULL REFERENCES hr_payroll(id) ON DELETE CASCADE,
  item_type     TEXT NOT NULL CHECK (item_type IN ('allowance','deduction','bonus','overtime')),
  item_name     TEXT NOT NULL,
  amount        NUMERIC(12,2) NOT NULL,
  is_recurring  BOOLEAN DEFAULT FALSE,
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS hr_payroll_items_payroll_idx ON hr_payroll_items(payroll_id);
CREATE INDEX IF NOT EXISTS hr_payroll_items_type_idx    ON hr_payroll_items(item_type);

-- ═══════════════════════════════════════════════════════════════════════════
-- 9) Row-Level Security — enable + policies
--    Rule of thumb enforced below:
--    • Employee sees their own row.
--    • Direct manager sees their team's rows (EXCEPT payroll).
--    • HR admin (admin / company_manager / hr_manager) sees & writes everything.
--    • Payroll access is a strict subset: admin / company_manager / hr_manager / payroll_officer.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE hr_positions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_employee_profile  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_attendance        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_leave_types       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_leaves            ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_payroll           ENABLE ROW LEVEL SECURITY;
ALTER TABLE hr_payroll_items     ENABLE ROW LEVEL SECURITY;

-- ─── hr_positions ────────────────────────────────────────────────────
DROP POLICY IF EXISTS hr_positions_sel ON hr_positions;
DROP POLICY IF EXISTS hr_positions_ins ON hr_positions;
DROP POLICY IF EXISTS hr_positions_upd ON hr_positions;
DROP POLICY IF EXISTS hr_positions_del ON hr_positions;

CREATE POLICY hr_positions_sel ON hr_positions FOR SELECT TO authenticated
  USING (deleted_at IS NULL OR is_hr_admin());
CREATE POLICY hr_positions_ins ON hr_positions FOR INSERT TO authenticated
  WITH CHECK (is_hr_admin());
CREATE POLICY hr_positions_upd ON hr_positions FOR UPDATE TO authenticated
  USING (is_hr_admin()) WITH CHECK (is_hr_admin());
CREATE POLICY hr_positions_del ON hr_positions FOR DELETE TO authenticated
  USING (is_hr_admin());

-- ─── hr_leave_types ──────────────────────────────────────────────────
DROP POLICY IF EXISTS hr_leave_types_sel ON hr_leave_types;
DROP POLICY IF EXISTS hr_leave_types_wr  ON hr_leave_types;

CREATE POLICY hr_leave_types_sel ON hr_leave_types FOR SELECT TO authenticated
  USING (TRUE);
CREATE POLICY hr_leave_types_wr ON hr_leave_types FOR ALL TO authenticated
  USING (is_hr_admin()) WITH CHECK (is_hr_admin());

-- ─── hr_employee_profile ─────────────────────────────────────────────
DROP POLICY IF EXISTS hr_profile_sel ON hr_employee_profile;
DROP POLICY IF EXISTS hr_profile_ins ON hr_employee_profile;
DROP POLICY IF EXISTS hr_profile_upd ON hr_employee_profile;
DROP POLICY IF EXISTS hr_profile_del ON hr_employee_profile;

CREATE POLICY hr_profile_sel ON hr_employee_profile FOR SELECT TO authenticated
  USING (
    user_id = current_app_user_id()
    OR is_hr_admin()
    OR is_manager_of(user_id)
  );
CREATE POLICY hr_profile_ins ON hr_employee_profile FOR INSERT TO authenticated
  WITH CHECK (is_hr_admin());
CREATE POLICY hr_profile_upd ON hr_employee_profile FOR UPDATE TO authenticated
  USING (is_hr_admin() OR user_id = current_app_user_id())
  WITH CHECK (is_hr_admin() OR user_id = current_app_user_id());
CREATE POLICY hr_profile_del ON hr_employee_profile FOR DELETE TO authenticated
  USING (is_hr_admin());

-- ─── hr_attendance ───────────────────────────────────────────────────
DROP POLICY IF EXISTS hr_attendance_sel ON hr_attendance;
DROP POLICY IF EXISTS hr_attendance_wr  ON hr_attendance;

CREATE POLICY hr_attendance_sel ON hr_attendance FOR SELECT TO authenticated
  USING (
    user_id = current_app_user_id()
    OR is_hr_admin()
    OR is_manager_of(user_id)
  );
CREATE POLICY hr_attendance_wr ON hr_attendance FOR ALL TO authenticated
  USING (is_hr_admin()) WITH CHECK (is_hr_admin());

-- ─── hr_leaves ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS hr_leaves_sel        ON hr_leaves;
DROP POLICY IF EXISTS hr_leaves_ins_self   ON hr_leaves;
DROP POLICY IF EXISTS hr_leaves_ins_admin  ON hr_leaves;
DROP POLICY IF EXISTS hr_leaves_upd        ON hr_leaves;
DROP POLICY IF EXISTS hr_leaves_del        ON hr_leaves;

CREATE POLICY hr_leaves_sel ON hr_leaves FOR SELECT TO authenticated
  USING (
    user_id = current_app_user_id()
    OR is_hr_admin()
    OR is_manager_of(user_id)
  );

-- Employees request their OWN leave, and only in pending state
CREATE POLICY hr_leaves_ins_self ON hr_leaves FOR INSERT TO authenticated
  WITH CHECK (
    user_id = current_app_user_id()
    AND status = 'pending'
  );

-- HR admin can create in any state (e.g. HR entering a pre-approved leave)
CREATE POLICY hr_leaves_ins_admin ON hr_leaves FOR INSERT TO authenticated
  WITH CHECK (is_hr_admin());

-- HR admin OR the direct manager can approve/reject.
-- Employee can only mutate their own pending request (edit/cancel before decision).
CREATE POLICY hr_leaves_upd ON hr_leaves FOR UPDATE TO authenticated
  USING (
    is_hr_admin()
    OR is_manager_of(user_id)
    OR (user_id = current_app_user_id() AND status = 'pending')
  )
  WITH CHECK (
    is_hr_admin()
    OR is_manager_of(user_id)
    OR (user_id = current_app_user_id() AND status IN ('pending','cancelled'))
  );

CREATE POLICY hr_leaves_del ON hr_leaves FOR DELETE TO authenticated
  USING (is_hr_admin());

-- ─── hr_payroll (SENSITIVE — no direct-manager access) ───────────────
DROP POLICY IF EXISTS hr_payroll_sel ON hr_payroll;
DROP POLICY IF EXISTS hr_payroll_wr  ON hr_payroll;

CREATE POLICY hr_payroll_sel ON hr_payroll FOR SELECT TO authenticated
  USING (
    user_id = current_app_user_id()
    OR is_payroll_authorized()
  );

CREATE POLICY hr_payroll_wr ON hr_payroll FOR ALL TO authenticated
  USING (is_payroll_authorized()) WITH CHECK (is_payroll_authorized());

-- ─── hr_payroll_items (inherits parent's visibility) ────────────────
DROP POLICY IF EXISTS hr_payroll_items_sel ON hr_payroll_items;
DROP POLICY IF EXISTS hr_payroll_items_wr  ON hr_payroll_items;

CREATE POLICY hr_payroll_items_sel ON hr_payroll_items FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM hr_payroll p
      WHERE p.id = payroll_id
        AND (p.user_id = current_app_user_id() OR is_payroll_authorized())
    )
  );

CREATE POLICY hr_payroll_items_wr ON hr_payroll_items FOR ALL TO authenticated
  USING (is_payroll_authorized()) WITH CHECK (is_payroll_authorized());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist (do these AFTER the script runs cleanly):
--   1. Verify all 7 tables exist:
--      SELECT tablename FROM pg_tables WHERE tablename LIKE 'hr\_%' ORDER BY tablename;
--   2. Verify RLS is enforced:
--      SELECT tablename, rowsecurity FROM pg_tables WHERE tablename LIKE 'hr\_%';
--      Every row should show rowsecurity = true.
--   3. Verify seed leave types loaded:
--      SELECT name, code, annual_balance_days FROM hr_leave_types ORDER BY id;
--   4. Register the two new roles in the app code (not SQL):
--        hr_manager        — full HR access
--        payroll_officer   — payroll + read-only employee list
--      Add to LABELS.role, PERMISSION_ROLES, and NEW_ROLE_DEFAULT_PERMS
--      inside index.html.html.
-- ═══════════════════════════════════════════════════════════════════════════
