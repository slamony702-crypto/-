-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.a — Foundation + Journal)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Settings + Chart of Accounts + Cost Centers + Fiscal Year + Periods
--        + Journal Entries with double-entry trigger + HR/Cafe integration
-- Prerequisites: users, departments, branches, hr_payroll, cafe_orders, cafe_order_items
--                already exist. hr-schema.sql must have been applied first
--                (we reuse set_updated_at, current_app_user_id, current_app_role).
-- Idempotent: safe to re-run (uses IF NOT EXISTS / ON CONFLICT / DROP POLICY IF EXISTS)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1) RLS helper functions — one per accounting role
-- ───────────────────────────────────────────────────────────────────────────

-- Finance manager: approves, posts, closes periods
CREATE OR REPLACE FUNCTION is_finance_manager()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'finance_manager');
$$;

-- GL accountant: creates and edits draft entries
CREATE OR REPLACE FUNCTION is_gl_accountant()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'finance_manager', 'gl_accountant');
$$;

-- AP officer: vendors, purchase orders, bills, payments
CREATE OR REPLACE FUNCTION is_ap_officer()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'finance_manager', 'ap_officer');
$$;

-- AR officer: customers, invoices, receipts
CREATE OR REPLACE FUNCTION is_ar_officer()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'finance_manager', 'ar_officer');
$$;

-- Union of all accounting roles — used for read access
CREATE OR REPLACE FUNCTION is_accounting_role()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'finance_manager', 'gl_accountant', 'ap_officer', 'ar_officer');
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2) acct_settings — singleton config row (id=1)
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_settings (
  id                              INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  company_name                    TEXT DEFAULT 'شركة شؤون الغذاء',
  company_name_en                 TEXT,
  vat_registration_number         TEXT,
  vat_rate                        NUMERIC(5,2) NOT NULL DEFAULT 15,
  currency                        TEXT NOT NULL DEFAULT 'SAR',
  fiscal_year_start_month         INT NOT NULL DEFAULT 1 CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  dual_approval_threshold         NUMERIC(12,2) NOT NULL DEFAULT 10000,
  cafe_generates_journal_entry    BOOLEAN NOT NULL DEFAULT TRUE,
  cafe_revenue_account_id         BIGINT,
  cafe_cash_account_id            BIGINT,
  external_auditor_name           TEXT,
  external_auditor_license        TEXT,
  zatca_seller_name               TEXT DEFAULT 'شركة شؤون الغذاء',
  zatca_environment               TEXT DEFAULT 'phase1' CHECK (zatca_environment IN ('phase1', 'phase2_sandbox', 'phase2_production')),
  created_at                      TIMESTAMPTZ DEFAULT now(),
  updated_at                      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO acct_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS acct_settings_updated_at ON acct_settings;
CREATE TRIGGER acct_settings_updated_at BEFORE UPDATE ON acct_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────────────────
-- 3) acct_chart_of_accounts — hierarchical COA
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_chart_of_accounts (
  id              BIGSERIAL PRIMARY KEY,
  code            TEXT NOT NULL UNIQUE,
  name            TEXT NOT NULL,
  name_en         TEXT,
  parent_id       BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE RESTRICT,
  account_type    TEXT NOT NULL CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
  account_subtype TEXT,
  normal_balance  TEXT NOT NULL CHECK (normal_balance IN ('debit', 'credit')),
  is_leaf         BOOLEAN NOT NULL DEFAULT TRUE,
  is_system       BOOLEAN NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  vat_applicable  BOOLEAN NOT NULL DEFAULT FALSE,
  description     TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_coa_parent_idx ON acct_chart_of_accounts(parent_id);
CREATE INDEX IF NOT EXISTS acct_coa_type_idx   ON acct_chart_of_accounts(account_type) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS acct_coa_leaf_idx   ON acct_chart_of_accounts(is_leaf) WHERE is_leaf = TRUE AND deleted_at IS NULL;

DROP TRIGGER IF EXISTS acct_coa_updated_at ON acct_chart_of_accounts;
CREATE TRIGGER acct_coa_updated_at BEFORE UPDATE ON acct_chart_of_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────────────────
-- 4) acct_cost_centers — hierarchical cost centers tied to branches
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_cost_centers (
  id           BIGSERIAL PRIMARY KEY,
  code         TEXT NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  parent_id    BIGINT REFERENCES acct_cost_centers(id) ON DELETE RESTRICT,
  branch_id    BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  is_leaf      BOOLEAN NOT NULL DEFAULT TRUE,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  description  TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_cc_parent_idx ON acct_cost_centers(parent_id);
CREATE INDEX IF NOT EXISTS acct_cc_branch_idx ON acct_cost_centers(branch_id);

DROP TRIGGER IF EXISTS acct_cc_updated_at ON acct_cost_centers;
CREATE TRIGGER acct_cc_updated_at BEFORE UPDATE ON acct_cost_centers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────────────────
-- 5) acct_fiscal_years + acct_periods — auto-generate 12 periods per FY
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_fiscal_years (
  id           BIGSERIAL PRIMARY KEY,
  year         INT NOT NULL UNIQUE CHECK (year BETWEEN 2000 AND 2100),
  start_date   DATE NOT NULL,
  end_date     DATE NOT NULL,
  status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  closed_at    TIMESTAMPTZ,
  closed_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT acct_fy_dates_check CHECK (end_date > start_date)
);

DROP TRIGGER IF EXISTS acct_fy_updated_at ON acct_fiscal_years;
CREATE TRIGGER acct_fy_updated_at BEFORE UPDATE ON acct_fiscal_years
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_periods (
  id                BIGSERIAL PRIMARY KEY,
  fiscal_year_id    BIGINT NOT NULL REFERENCES acct_fiscal_years(id) ON DELETE CASCADE,
  year              INT NOT NULL,
  month             INT NOT NULL CHECK (month BETWEEN 1 AND 12),
  start_date        DATE NOT NULL,
  end_date          DATE NOT NULL,
  status            TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'locked')),
  closed_at         TIMESTAMPTZ,
  closed_by         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT acct_periods_unique UNIQUE (year, month)
);

CREATE INDEX IF NOT EXISTS acct_periods_year_month_idx ON acct_periods(year, month);
CREATE INDEX IF NOT EXISTS acct_periods_status_idx     ON acct_periods(status);

DROP TRIGGER IF EXISTS acct_periods_updated_at ON acct_periods;
CREATE TRIGGER acct_periods_updated_at BEFORE UPDATE ON acct_periods
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-populate 12 monthly periods when a fiscal year is inserted
CREATE OR REPLACE FUNCTION acct_generate_periods_for_fy()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  m INT;
  ps DATE;
  pe DATE;
BEGIN
  FOR m IN 1..12 LOOP
    ps := make_date(NEW.year, m, 1);
    pe := (ps + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    INSERT INTO acct_periods (fiscal_year_id, year, month, start_date, end_date)
    VALUES (NEW.id, NEW.year, m, ps, pe)
    ON CONFLICT (year, month) DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_fy_gen_periods ON acct_fiscal_years;
CREATE TRIGGER acct_fy_gen_periods AFTER INSERT ON acct_fiscal_years
  FOR EACH ROW EXECUTE FUNCTION acct_generate_periods_for_fy();

-- ───────────────────────────────────────────────────────────────────────────
-- 6) acct_journal_entries — Journal entries (headers)
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_journal_entries (
  id              BIGSERIAL PRIMARY KEY,
  entry_no        TEXT NOT NULL UNIQUE,
  entry_date      DATE NOT NULL,
  period_id       BIGINT REFERENCES acct_periods(id) ON DELETE RESTRICT,
  description     TEXT NOT NULL,
  reference       TEXT,
  source_type     TEXT NOT NULL DEFAULT 'manual'
                    CHECK (source_type IN ('manual', 'hr_payroll', 'bill', 'invoice', 'payment', 'receipt', 'cafe_order', 'depreciation', 'closing', 'opening', 'reversal')),
  source_id       BIGINT,
  status          TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'posted', 'reversed', 'cancelled')),
  total_debit     NUMERIC(14,2) DEFAULT 0,
  total_credit    NUMERIC(14,2) DEFAULT 0,
  is_reversal_of  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  reversed_by     BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  posted_at       TIMESTAMPTZ,
  posted_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_je_period_idx ON acct_journal_entries(period_id);
CREATE INDEX IF NOT EXISTS acct_je_date_idx   ON acct_journal_entries(entry_date DESC);
CREATE INDEX IF NOT EXISTS acct_je_source_idx ON acct_journal_entries(source_type, source_id);
CREATE INDEX IF NOT EXISTS acct_je_status_idx ON acct_journal_entries(status);

DROP TRIGGER IF EXISTS acct_je_updated_at ON acct_journal_entries;
CREATE TRIGGER acct_je_updated_at BEFORE UPDATE ON acct_journal_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────────────────
-- 7) acct_journal_lines — Journal entry lines
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS acct_journal_lines (
  id                BIGSERIAL PRIMARY KEY,
  entry_id          BIGINT NOT NULL REFERENCES acct_journal_entries(id) ON DELETE CASCADE,
  line_no           INT NOT NULL,
  account_id        BIGINT NOT NULL REFERENCES acct_chart_of_accounts(id) ON DELETE RESTRICT,
  cost_center_id    BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  debit             NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  description       TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  -- Every line is either a debit XOR a credit — never both, never neither
  CONSTRAINT acct_jl_side_check CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)),
  CONSTRAINT acct_jl_line_unique UNIQUE (entry_id, line_no)
);

CREATE INDEX IF NOT EXISTS acct_jl_entry_idx   ON acct_journal_lines(entry_id);
CREATE INDEX IF NOT EXISTS acct_jl_account_idx ON acct_journal_lines(account_id);
CREATE INDEX IF NOT EXISTS acct_jl_cc_idx      ON acct_journal_lines(cost_center_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 8) CRITICAL: Double-entry trigger
--    On UPDATE that transitions to 'posted', the trigger:
--      • checks sum(debit) = sum(credit)
--      • checks the period is not closed/locked
--      • records total_debit, total_credit, posted_at
--    Also: journal lines cannot be inserted/updated/deleted once the parent
--    entry is posted, reversed, or cancelled (line-level trigger below).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION acct_validate_journal_posting()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_debit NUMERIC(14,2);
  v_credit NUMERIC(14,2);
  v_period_status TEXT;
BEGIN
  IF NEW.status = 'posted' AND (OLD.status IS DISTINCT FROM 'posted') THEN
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
      INTO v_debit, v_credit
      FROM acct_journal_lines
      WHERE entry_id = NEW.id;

    IF v_debit = 0 THEN
      RAISE EXCEPTION 'Journal entry % has no lines', NEW.entry_no;
    END IF;
    IF ABS(v_debit - v_credit) > 0.005 THEN
      RAISE EXCEPTION 'Journal entry % is unbalanced: debit=% credit=%', NEW.entry_no, v_debit, v_credit;
    END IF;

    IF NEW.period_id IS NOT NULL THEN
      SELECT status INTO v_period_status FROM acct_periods WHERE id = NEW.period_id;
      IF v_period_status IN ('closed', 'locked') THEN
        RAISE EXCEPTION 'Cannot post entry: period is % (entry_date=%)', v_period_status, NEW.entry_date;
      END IF;
    END IF;

    NEW.total_debit  := v_debit;
    NEW.total_credit := v_credit;
    IF NEW.posted_at IS NULL THEN NEW.posted_at := now(); END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_je_validate_post ON acct_journal_entries;
CREATE TRIGGER acct_je_validate_post BEFORE UPDATE ON acct_journal_entries
  FOR EACH ROW EXECUTE FUNCTION acct_validate_journal_posting();

-- Prevent editing lines of an already-posted / reversed / cancelled entry
CREATE OR REPLACE FUNCTION acct_validate_line_edit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_status TEXT;
  v_entry_ref BIGINT;
BEGIN
  v_entry_ref := COALESCE(NEW.entry_id, OLD.entry_id);
  SELECT status INTO v_status FROM acct_journal_entries WHERE id = v_entry_ref;
  IF v_status IN ('posted', 'reversed', 'cancelled') THEN
    RAISE EXCEPTION 'Cannot modify lines of a % journal entry', v_status;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS acct_jl_validate_edit ON acct_journal_lines;
CREATE TRIGGER acct_jl_validate_edit BEFORE INSERT OR UPDATE OR DELETE ON acct_journal_lines
  FOR EACH ROW EXECUTE FUNCTION acct_validate_line_edit();

-- ═══════════════════════════════════════════════════════════════════════════
-- 9) HR Integration: create draft journal entry from a payroll slip
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_journal_for_payroll(p_payroll_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payroll RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_entry_no TEXT;
  v_expense_account_id BIGINT;
  v_payable_account_id BIGINT;
BEGIN
  SELECT * INTO v_payroll FROM hr_payroll WHERE id = p_payroll_id;
  IF v_payroll IS NULL THEN
    RAISE EXCEPTION 'Payroll % not found', p_payroll_id;
  END IF;
  IF v_payroll.status NOT IN ('approved', 'paid') THEN
    RAISE EXCEPTION 'Payroll must be approved before generating a journal entry';
  END IF;

  -- Reuse the existing entry if one was already generated
  SELECT id INTO v_entry_id FROM acct_journal_entries
    WHERE source_type = 'hr_payroll' AND source_id = p_payroll_id
    LIMIT 1;
  IF v_entry_id IS NOT NULL THEN RETURN v_entry_id; END IF;

  SELECT id INTO v_expense_account_id FROM acct_chart_of_accounts WHERE code = '5203' LIMIT 1;
  SELECT id INTO v_payable_account_id FROM acct_chart_of_accounts WHERE code = '2102' LIMIT 1;
  IF v_expense_account_id IS NULL OR v_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts (5203 salary expense or 2102 salaries payable) not found. Seed the chart of accounts.';
  END IF;

  SELECT id INTO v_period_id FROM acct_periods
    WHERE year = v_payroll.period_year AND month = v_payroll.period_month
    LIMIT 1;
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'Accounting period %/% not found. Create the fiscal year first.', v_payroll.period_year, v_payroll.period_month;
  END IF;

  v_entry_no := 'JE-PR-' || v_payroll.period_year || '-' || LPAD(v_payroll.period_month::TEXT, 2, '0') || '-' || v_payroll.id;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES (
    v_entry_no,
    (make_date(v_payroll.period_year, v_payroll.period_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE,
    v_period_id,
    'قيد راتب: ' || v_payroll.period_month || '/' || v_payroll.period_year,
    'hr_payroll',
    p_payroll_id,
    'draft',
    current_app_user_id()
  )
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_expense_account_id, v_payroll.gross_salary, 0, 'مصروف رواتب — إجمالي');
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_payable_account_id, 0, v_payroll.gross_salary, 'مستحقات موظفين');

  RETURN v_entry_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10) Cafe Integration: create draft entry from a delivered cafe order
--     Only fires when acct_settings.cafe_generates_journal_entry = TRUE.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_journal_for_cafe_order(p_order_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_settings RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_entry_no TEXT;
  v_total NUMERIC(14,2);
BEGIN
  SELECT * INTO v_order FROM cafe_orders WHERE id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Cafe order % not found', p_order_id; END IF;

  SELECT * INTO v_settings FROM acct_settings WHERE id = 1;
  IF NOT v_settings.cafe_generates_journal_entry THEN RETURN NULL; END IF;
  IF v_settings.cafe_revenue_account_id IS NULL OR v_settings.cafe_cash_account_id IS NULL THEN
    RAISE EXCEPTION 'Cafe revenue/cash accounts are not configured in acct_settings';
  END IF;

  -- Idempotent
  SELECT id INTO v_entry_id FROM acct_journal_entries
    WHERE source_type = 'cafe_order' AND source_id = p_order_id LIMIT 1;
  IF v_entry_id IS NOT NULL THEN RETURN v_entry_id; END IF;

  -- Total from order items
  SELECT COALESCE(SUM(quantity * unit_price), 0) INTO v_total
    FROM cafe_order_items WHERE order_id = p_order_id;
  IF v_total <= 0 THEN RETURN NULL; END IF;

  SELECT id INTO v_period_id FROM acct_periods
    WHERE start_date <= v_order.created_at::DATE AND end_date >= v_order.created_at::DATE
    LIMIT 1;
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'No open accounting period for date %', v_order.created_at::DATE;
  END IF;

  v_entry_no := 'JE-CAFE-' || p_order_id;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES (v_entry_no, v_order.created_at::DATE, v_period_id,
          'قيد طلب كافيه رقم ' || COALESCE(v_order.order_number, p_order_id::TEXT),
          'cafe_order', p_order_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_settings.cafe_cash_account_id, v_total, 0, 'نقدية — بيع كافيه');
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_settings.cafe_revenue_account_id, 0, v_total, 'إيرادات مبيعات الكافيه');

  RETURN v_entry_id;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11) SEED: Standard restaurant chart of accounts (~65 accounts)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Assets (1xxx)
INSERT INTO acct_chart_of_accounts (code, name, name_en, account_type, normal_balance, is_leaf, is_system, vat_applicable) VALUES
  ('1000', 'الأصول', 'Assets', 'asset', 'debit', FALSE, TRUE, FALSE),
  ('1100', 'الأصول المتداولة', 'Current Assets', 'asset', 'debit', FALSE, TRUE, FALSE),
  ('1101', 'النقدية في الصندوق', 'Cash on Hand', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1102', 'نقدية العهد', 'Petty Cash', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1110', 'البنوك', 'Banks', 'asset', 'debit', FALSE, TRUE, FALSE),
  ('1120', 'العملاء', 'Trade Receivables', 'asset', 'debit', TRUE, TRUE, FALSE),
  ('1130', 'المخزون', 'Inventory', 'asset', 'debit', FALSE, TRUE, FALSE),
  ('1131', 'مخزون مواد غذائية', 'Food Inventory', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1132', 'مخزون مشروبات', 'Beverage Inventory', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1133', 'مخزون مواد استهلاكية', 'Consumables Inventory', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1140', 'دفعات مقدمة', 'Prepayments', 'asset', 'debit', FALSE, FALSE, FALSE),
  ('1141', 'إيجارات مدفوعة مقدماً', 'Prepaid Rent', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1142', 'تأمينات مدفوعة مقدماً', 'Prepaid Insurance', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1150', 'ضريبة القيمة المضافة - مدين', 'Input VAT', 'asset', 'debit', TRUE, TRUE, FALSE),
  ('1200', 'الأصول الثابتة', 'Fixed Assets', 'asset', 'debit', FALSE, TRUE, FALSE),
  ('1210', 'مبانٍ وتشطيبات', 'Buildings & Fit-out', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1211', 'مبانٍ - إهلاك متراكم', 'Buildings — Acc. Depreciation', 'asset', 'credit', TRUE, FALSE, FALSE),
  ('1220', 'سيارات', 'Vehicles', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1221', 'سيارات - إهلاك متراكم', 'Vehicles — Acc. Depreciation', 'asset', 'credit', TRUE, FALSE, FALSE),
  ('1230', 'معدات المطبخ', 'Kitchen Equipment', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1231', 'معدات المطبخ - إهلاك متراكم', 'Kitchen Equip. — Acc. Depr.', 'asset', 'credit', TRUE, FALSE, FALSE),
  ('1240', 'أثاث وتجهيزات', 'Furniture & Fittings', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1241', 'أثاث - إهلاك متراكم', 'Furniture — Acc. Depreciation', 'asset', 'credit', TRUE, FALSE, FALSE),
  ('1250', 'أجهزة كمبيوتر و IT', 'IT Equipment', 'asset', 'debit', TRUE, FALSE, FALSE),
  ('1251', 'كمبيوتر - إهلاك متراكم', 'IT — Acc. Depreciation', 'asset', 'credit', TRUE, FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Liabilities (2xxx)
INSERT INTO acct_chart_of_accounts (code, name, name_en, account_type, normal_balance, is_leaf, is_system, vat_applicable) VALUES
  ('2000', 'الالتزامات', 'Liabilities', 'liability', 'credit', FALSE, TRUE, FALSE),
  ('2100', 'الالتزامات المتداولة', 'Current Liabilities', 'liability', 'credit', FALSE, TRUE, FALSE),
  ('2101', 'الموردون', 'Trade Payables', 'liability', 'credit', TRUE, TRUE, FALSE),
  ('2102', 'مستحقات موظفين', 'Salaries Payable', 'liability', 'credit', TRUE, TRUE, FALSE),
  ('2103', 'مستحقات التأمينات الاجتماعية', 'GOSI Payable', 'liability', 'credit', TRUE, FALSE, FALSE),
  ('2104', 'ضريبة القيمة المضافة - دائن', 'Output VAT', 'liability', 'credit', TRUE, TRUE, FALSE),
  ('2105', 'مصروفات مستحقة', 'Accrued Expenses', 'liability', 'credit', TRUE, FALSE, FALSE),
  ('2106', 'عربونات عملاء', 'Customer Advances', 'liability', 'credit', TRUE, FALSE, FALSE),
  ('2110', 'قروض قصيرة الأجل', 'Short-term Loans', 'liability', 'credit', TRUE, FALSE, FALSE),
  ('2200', 'الالتزامات طويلة الأجل', 'Long-term Liabilities', 'liability', 'credit', FALSE, FALSE, FALSE),
  ('2210', 'قروض طويلة الأجل', 'Long-term Loans', 'liability', 'credit', TRUE, FALSE, FALSE),
  ('2220', 'مخصص مكافأة نهاية الخدمة', 'End of Service Provision', 'liability', 'credit', TRUE, FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Equity (3xxx)
INSERT INTO acct_chart_of_accounts (code, name, name_en, account_type, normal_balance, is_leaf, is_system, vat_applicable) VALUES
  ('3000', 'حقوق الملكية', 'Equity', 'equity', 'credit', FALSE, TRUE, FALSE),
  ('3101', 'رأس المال', 'Capital', 'equity', 'credit', TRUE, TRUE, FALSE),
  ('3102', 'أرباح محتجزة', 'Retained Earnings', 'equity', 'credit', TRUE, TRUE, FALSE),
  ('3103', 'أرباح السنة الحالية', 'Current Year Earnings', 'equity', 'credit', TRUE, TRUE, FALSE),
  ('3104', 'سحوبات الشركاء', 'Owner Withdrawals', 'equity', 'debit', TRUE, FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Revenue (4xxx)
INSERT INTO acct_chart_of_accounts (code, name, name_en, account_type, normal_balance, is_leaf, is_system, vat_applicable) VALUES
  ('4000', 'الإيرادات', 'Revenue', 'revenue', 'credit', FALSE, TRUE, FALSE),
  ('4100', 'إيرادات المبيعات', 'Sales Revenue', 'revenue', 'credit', FALSE, TRUE, FALSE),
  ('4101', 'مبيعات الطعام', 'Food Sales', 'revenue', 'credit', TRUE, FALSE, TRUE),
  ('4102', 'مبيعات المشروبات', 'Beverage Sales', 'revenue', 'credit', TRUE, FALSE, TRUE),
  ('4103', 'مبيعات التوصيل', 'Delivery Sales', 'revenue', 'credit', TRUE, FALSE, TRUE),
  ('4104', 'مبيعات الكافيه', 'Cafe Sales', 'revenue', 'credit', TRUE, TRUE, TRUE),
  ('4105', 'إيرادات مبيعات أخرى', 'Other Sales', 'revenue', 'credit', TRUE, FALSE, TRUE),
  ('4210', 'مسموحات ومردودات مبيعات', 'Sales Returns & Allowances', 'revenue', 'debit', TRUE, FALSE, FALSE),
  ('4900', 'إيرادات غير تشغيلية', 'Non-operating Revenue', 'revenue', 'credit', FALSE, FALSE, FALSE),
  ('4901', 'أرباح استثمارات', 'Investment Income', 'revenue', 'credit', TRUE, FALSE, FALSE),
  ('4902', 'إيرادات متنوعة', 'Miscellaneous Income', 'revenue', 'credit', TRUE, FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Expenses (5xxx)
INSERT INTO acct_chart_of_accounts (code, name, name_en, account_type, normal_balance, is_leaf, is_system, vat_applicable) VALUES
  ('5000', 'المصروفات', 'Expenses', 'expense', 'debit', FALSE, TRUE, FALSE),
  ('5100', 'تكلفة المبيعات', 'Cost of Sales', 'expense', 'debit', FALSE, TRUE, FALSE),
  ('5101', 'تكلفة المواد الغذائية', 'Food Cost', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5102', 'تكلفة المشروبات', 'Beverage Cost', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5103', 'رسوم منصات التوصيل', 'Delivery Platform Fees', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5104', 'هدر ومخزون تالف', 'Waste & Spoilage', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5200', 'رواتب وأجور', 'Salaries & Wages', 'expense', 'debit', FALSE, TRUE, FALSE),
  ('5201', 'رواتب موظفي المطبخ', 'Kitchen Staff Salaries', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5202', 'رواتب موظفي الصالة', 'Hall Staff Salaries', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5203', 'رواتب الإدارة', 'Admin Salaries', 'expense', 'debit', TRUE, TRUE, FALSE),
  ('5204', 'التأمينات الاجتماعية GOSI', 'GOSI Employer Contribution', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5205', 'مكافآت وحوافز', 'Bonuses & Incentives', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5206', 'مخصص نهاية الخدمة', 'End of Service Provision', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5300', 'إيجارات وخدمات', 'Rent & Utilities', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5301', 'إيجارات الفروع', 'Branch Rent', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5302', 'كهرباء', 'Electricity', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5303', 'ماء', 'Water', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5304', 'إنترنت واتصالات', 'Internet & Telecom', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5305', 'غاز', 'Gas', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5400', 'تسويق وترويج', 'Marketing', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5401', 'إعلانات ومنصات', 'Advertising', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5402', 'تصميم وطباعة', 'Design & Printing', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5403', 'عمولات منصات التوصيل', 'Delivery Platform Commissions', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5500', 'صيانة وإصلاحات', 'Maintenance & Repairs', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5501', 'صيانة معدات المطبخ', 'Kitchen Equipment Maintenance', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5502', 'صيانة عامة للفروع', 'Branch General Maintenance', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5503', 'قطع غيار', 'Spare Parts', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5600', 'نظافة ومستهلكات', 'Cleaning & Consumables', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5601', 'مواد نظافة', 'Cleaning Supplies', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5602', 'مستهلكات المطعم', 'Restaurant Consumables', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5603', 'زي الموظفين', 'Employee Uniforms', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5700', 'نقل ومواصلات', 'Transportation', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5701', 'وقود سيارات', 'Vehicle Fuel', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5702', 'تأمين سيارات', 'Vehicle Insurance', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5703', 'رخص ورسوم حكومية', 'Government Fees & Licenses', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5800', 'مصروفات إدارية', 'Administrative Expenses', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5801', 'قرطاسية', 'Stationery', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5802', 'رسوم بنكية', 'Bank Charges', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5803', 'رسوم قانونية ومحاسبية', 'Legal & Accounting Fees', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5804', 'سفريات ومهمات رسمية', 'Business Travel', 'expense', 'debit', TRUE, FALSE, TRUE),
  ('5805', 'إهلاكات', 'Depreciation Expense', 'expense', 'debit', TRUE, TRUE, FALSE),
  ('5900', 'مصروفات مالية', 'Financial Expenses', 'expense', 'debit', FALSE, FALSE, FALSE),
  ('5901', 'فوائد قروض', 'Loan Interest', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5911', 'غرامات ومخالفات', 'Penalties & Fines', 'expense', 'debit', TRUE, FALSE, FALSE),
  ('5912', 'مصروفات متنوعة', 'Miscellaneous Expenses', 'expense', 'debit', TRUE, FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- Wire up parent_id relationships (idempotent — only fills NULLs)
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '1000') WHERE code IN ('1100', '1200') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '1100') WHERE code IN ('1101', '1102', '1110', '1120', '1130', '1140', '1150') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '1130') WHERE code IN ('1131', '1132', '1133') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '1140') WHERE code IN ('1141', '1142') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '1200') WHERE code IN ('1210', '1211', '1220', '1221', '1230', '1231', '1240', '1241', '1250', '1251') AND parent_id IS NULL;

UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '2000') WHERE code IN ('2100', '2200') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '2100') WHERE code IN ('2101', '2102', '2103', '2104', '2105', '2106', '2110') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '2200') WHERE code IN ('2210', '2220') AND parent_id IS NULL;

UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '3000') WHERE code IN ('3101', '3102', '3103', '3104') AND parent_id IS NULL;

UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '4000') WHERE code IN ('4100', '4210', '4900') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '4100') WHERE code IN ('4101', '4102', '4103', '4104', '4105') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '4900') WHERE code IN ('4901', '4902') AND parent_id IS NULL;

UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5000') WHERE code IN ('5100', '5200', '5300', '5400', '5500', '5600', '5700', '5800', '5900') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5100') WHERE code IN ('5101', '5102', '5103', '5104') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5200') WHERE code IN ('5201', '5202', '5203', '5204', '5205', '5206') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5300') WHERE code IN ('5301', '5302', '5303', '5304', '5305') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5400') WHERE code IN ('5401', '5402', '5403') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5500') WHERE code IN ('5501', '5502', '5503') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5600') WHERE code IN ('5601', '5602', '5603') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5700') WHERE code IN ('5701', '5702', '5703') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5800') WHERE code IN ('5801', '5802', '5803', '5804', '5805') AND parent_id IS NULL;
UPDATE acct_chart_of_accounts SET parent_id = (SELECT id FROM acct_chart_of_accounts WHERE code = '5900') WHERE code IN ('5901', '5911', '5912') AND parent_id IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12) SEED: Cost centers — one parent per active branch + 4 children each
-- ═══════════════════════════════════════════════════════════════════════════

-- Top-level HQ cost center (branch-independent)
INSERT INTO acct_cost_centers (code, name, is_leaf, description) VALUES
  ('CC-HQ', 'الإدارة العامة', TRUE, 'مركز تكلفة الإدارة العامة للشركة')
ON CONFLICT (code) DO NOTHING;

-- Parent cost center per branch
INSERT INTO acct_cost_centers (code, name, branch_id, is_leaf)
  SELECT 'CC-B' || id::TEXT, 'فرع: ' || name, id, FALSE
  FROM branches WHERE COALESCE(is_active, TRUE) = TRUE
  ON CONFLICT (code) DO NOTHING;

-- 4 sub-centers per branch: kitchen, hall, delivery, admin
INSERT INTO acct_cost_centers (code, name, parent_id, branch_id, is_leaf)
  SELECT 'CC-B' || b.id::TEXT || '-K', 'مطبخ ' || b.name, cc.id, b.id, TRUE
  FROM branches b JOIN acct_cost_centers cc ON cc.code = 'CC-B' || b.id::TEXT
  WHERE COALESCE(b.is_active, TRUE) = TRUE
  ON CONFLICT (code) DO NOTHING;

INSERT INTO acct_cost_centers (code, name, parent_id, branch_id, is_leaf)
  SELECT 'CC-B' || b.id::TEXT || '-H', 'صالة ' || b.name, cc.id, b.id, TRUE
  FROM branches b JOIN acct_cost_centers cc ON cc.code = 'CC-B' || b.id::TEXT
  WHERE COALESCE(b.is_active, TRUE) = TRUE
  ON CONFLICT (code) DO NOTHING;

INSERT INTO acct_cost_centers (code, name, parent_id, branch_id, is_leaf)
  SELECT 'CC-B' || b.id::TEXT || '-D', 'توصيل ' || b.name, cc.id, b.id, TRUE
  FROM branches b JOIN acct_cost_centers cc ON cc.code = 'CC-B' || b.id::TEXT
  WHERE COALESCE(b.is_active, TRUE) = TRUE
  ON CONFLICT (code) DO NOTHING;

INSERT INTO acct_cost_centers (code, name, parent_id, branch_id, is_leaf)
  SELECT 'CC-B' || b.id::TEXT || '-A', 'إدارة ' || b.name, cc.id, b.id, TRUE
  FROM branches b JOIN acct_cost_centers cc ON cc.code = 'CC-B' || b.id::TEXT
  WHERE COALESCE(b.is_active, TRUE) = TRUE
  ON CONFLICT (code) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 13) SEED: Current fiscal year — triggers 12-period auto-creation
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO acct_fiscal_years (year, start_date, end_date)
  VALUES (
    EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    make_date(EXTRACT(YEAR FROM CURRENT_DATE)::INT, 1, 1),
    make_date(EXTRACT(YEAR FROM CURRENT_DATE)::INT, 12, 31)
  )
  ON CONFLICT (year) DO NOTHING;

-- Wire the cafe integration accounts into settings (only if empty)
UPDATE acct_settings SET
  cafe_revenue_account_id = COALESCE(cafe_revenue_account_id, (SELECT id FROM acct_chart_of_accounts WHERE code = '4104')),
  cafe_cash_account_id    = COALESCE(cafe_cash_account_id,    (SELECT id FROM acct_chart_of_accounts WHERE code = '1101'))
  WHERE id = 1;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 14) Row-Level Security
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE acct_settings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_chart_of_accounts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_cost_centers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_fiscal_years       ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_periods            ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_journal_entries    ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_journal_lines      ENABLE ROW LEVEL SECURITY;

-- acct_settings — read for all authenticated, write for finance_manager
DROP POLICY IF EXISTS acct_settings_sel ON acct_settings;
DROP POLICY IF EXISTS acct_settings_upd ON acct_settings;
CREATE POLICY acct_settings_sel ON acct_settings FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY acct_settings_upd ON acct_settings FOR UPDATE TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- acct_chart_of_accounts
DROP POLICY IF EXISTS acct_coa_sel ON acct_chart_of_accounts;
DROP POLICY IF EXISTS acct_coa_wr  ON acct_chart_of_accounts;
CREATE POLICY acct_coa_sel ON acct_chart_of_accounts FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_coa_wr  ON acct_chart_of_accounts FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- acct_cost_centers
DROP POLICY IF EXISTS acct_cc_sel ON acct_cost_centers;
DROP POLICY IF EXISTS acct_cc_wr  ON acct_cost_centers;
CREATE POLICY acct_cc_sel ON acct_cost_centers FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_cc_wr  ON acct_cost_centers FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- Fiscal years + periods
DROP POLICY IF EXISTS acct_fy_sel ON acct_fiscal_years;
DROP POLICY IF EXISTS acct_fy_wr  ON acct_fiscal_years;
CREATE POLICY acct_fy_sel ON acct_fiscal_years FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_fy_wr  ON acct_fiscal_years FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_p_sel ON acct_periods;
DROP POLICY IF EXISTS acct_p_wr  ON acct_periods;
CREATE POLICY acct_p_sel ON acct_periods FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_p_wr  ON acct_periods FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- Journal entries: read for accounting roles, draft creation by gl_accountant,
-- posting restricted to finance_manager
DROP POLICY IF EXISTS acct_je_sel ON acct_journal_entries;
DROP POLICY IF EXISTS acct_je_ins ON acct_journal_entries;
DROP POLICY IF EXISTS acct_je_upd ON acct_journal_entries;
DROP POLICY IF EXISTS acct_je_del ON acct_journal_entries;

CREATE POLICY acct_je_sel ON acct_journal_entries FOR SELECT TO authenticated
  USING (is_accounting_role());
CREATE POLICY acct_je_ins ON acct_journal_entries FOR INSERT TO authenticated
  WITH CHECK (is_gl_accountant());
CREATE POLICY acct_je_upd ON acct_journal_entries FOR UPDATE TO authenticated
  USING (is_gl_accountant())
  WITH CHECK (
    is_finance_manager()
    OR (is_gl_accountant() AND status = 'draft')
  );
CREATE POLICY acct_je_del ON acct_journal_entries FOR DELETE TO authenticated
  USING (is_finance_manager());

-- Journal lines
DROP POLICY IF EXISTS acct_jl_sel ON acct_journal_lines;
DROP POLICY IF EXISTS acct_jl_wr  ON acct_journal_lines;
CREATE POLICY acct_jl_sel ON acct_journal_lines FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_jl_wr  ON acct_journal_lines FOR ALL   TO authenticated USING (is_gl_accountant()) WITH CHECK (is_gl_accountant());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist (run these AFTER the script above completes):
--
--   1. Confirm all 7 tables exist:
--      SELECT tablename FROM pg_tables WHERE tablename LIKE 'acct\_%' ORDER BY tablename;
--
--   2. Confirm RLS is on:
--      SELECT tablename, rowsecurity FROM pg_tables WHERE tablename LIKE 'acct\_%';
--      Every row should show rowsecurity = true.
--
--   3. Confirm the seeded chart of accounts:
--      SELECT COUNT(*) FROM acct_chart_of_accounts;     -- expect 65
--      SELECT COUNT(*) FROM acct_chart_of_accounts WHERE account_type = 'asset';     -- expect 25
--      SELECT COUNT(*) FROM acct_chart_of_accounts WHERE account_type = 'expense';   -- expect ~40
--
--   4. Confirm the cost centers were seeded per branch:
--      SELECT COUNT(*) FROM acct_cost_centers;          -- expect 1 + (5 * #active_branches)
--
--   5. Confirm the current fiscal year + its 12 periods:
--      SELECT * FROM acct_fiscal_years ORDER BY year DESC;
--      SELECT year, month, status FROM acct_periods ORDER BY year DESC, month;
--
--   6. Register the four new roles in the app code (not SQL):
--        finance_manager   — approves entries, closes periods, signs statements
--        gl_accountant     — creates draft journal entries
--        ap_officer        — vendors, purchase orders, bills, payments
--        ar_officer        — customers, invoices, receipts
--      Add to LABELS.role, PERMISSION_ROLES, and NEW_ROLE_DEFAULT_PERMS
--      inside index.html.html (Step 2.3).
-- ═══════════════════════════════════════════════════════════════════════════
