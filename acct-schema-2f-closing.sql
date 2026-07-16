-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.f — VAT, Closing, Financial Statements, Budgets)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: VAT return records, a proper year-end closing function that nets
--        revenue/expense into Retained Earnings via a balanced journal entry,
--        SQL functions for Trial Balance / Income Statement / Balance Sheet,
--        and simple annual budgets.
-- Prerequisites: acct-schema.sql through acct-schema-2e-assets.sql must
--                already be applied.
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) acct_vat_returns — one row per reporting period (quarterly is typical in KSA)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_vat_returns (
  id              BIGSERIAL PRIMARY KEY,
  period_start    DATE NOT NULL,
  period_end      DATE NOT NULL,
  total_sales     NUMERIC(14,2) NOT NULL DEFAULT 0,
  output_vat      NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_purchases NUMERIC(14,2) NOT NULL DEFAULT 0,
  input_vat       NUMERIC(14,2) NOT NULL DEFAULT 0,
  net_vat         NUMERIC(14,2) GENERATED ALWAYS AS (output_vat - input_vat) STORED,
  status          TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted')),
  submitted_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  submitted_at     TIMESTAMPTZ,
  notes           TEXT,
  created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT acct_vat_period_check CHECK (period_end >= period_start),
  CONSTRAINT acct_vat_unique_period UNIQUE (period_start, period_end)
);

CREATE INDEX IF NOT EXISTS acct_vat_period_idx ON acct_vat_returns(period_start, period_end);

DROP TRIGGER IF EXISTS acct_vat_updated_at ON acct_vat_returns;
CREATE TRIGGER acct_vat_updated_at BEFORE UPDATE ON acct_vat_returns
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE acct_vat_returns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS acct_vat_sel ON acct_vat_returns;
DROP POLICY IF EXISTS acct_vat_wr  ON acct_vat_returns;
CREATE POLICY acct_vat_sel ON acct_vat_returns FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_vat_wr  ON acct_vat_returns FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- Computes sales/purchases/VAT totals for a date range from issued invoices and approved bills
CREATE OR REPLACE FUNCTION compute_vat_totals(p_start DATE, p_end DATE)
RETURNS TABLE(total_sales NUMERIC, output_vat NUMERIC, total_purchases NUMERIC, input_vat NUMERIC)
LANGUAGE sql STABLE
AS $$
  SELECT
    COALESCE((SELECT SUM(subtotal) FROM acct_invoices WHERE status IN ('issued','partially_paid','paid') AND invoice_date BETWEEN p_start AND p_end), 0),
    COALESCE((SELECT SUM(vat_amount) FROM acct_invoices WHERE status IN ('issued','partially_paid','paid') AND invoice_date BETWEEN p_start AND p_end), 0),
    COALESCE((SELECT SUM(subtotal) FROM acct_bills WHERE status IN ('approved','paid') AND bill_date BETWEEN p_start AND p_end), 0),
    COALESCE((SELECT SUM(vat_amount) FROM acct_bills WHERE status IN ('approved','paid') AND bill_date BETWEEN p_start AND p_end), 0);
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) Financial statement functions — read-only aggregates over posted journal lines
-- ═══════════════════════════════════════════════════════════════════════════

-- Trial balance as of a given date: every leaf account's net balance shown on
-- its normal side (debit column for debit-normal accounts, credit column for
-- credit-normal accounts). Only accounts with nonzero activity are returned.
CREATE OR REPLACE FUNCTION get_trial_balance(p_as_of DATE)
RETURNS TABLE(account_code TEXT, account_name TEXT, account_type TEXT, debit NUMERIC, credit NUMERIC)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.code, a.name, a.account_type,
    CASE WHEN a.normal_balance = 'debit'  AND (raw.d - raw.c) > 0 THEN raw.d - raw.c
         WHEN a.normal_balance = 'credit' AND (raw.c - raw.d) < 0 THEN raw.d - raw.c
         ELSE 0 END AS debit,
    CASE WHEN a.normal_balance = 'credit' AND (raw.c - raw.d) > 0 THEN raw.c - raw.d
         WHEN a.normal_balance = 'debit'  AND (raw.d - raw.c) < 0 THEN raw.c - raw.d
         ELSE 0 END AS credit
  FROM acct_chart_of_accounts a
  JOIN LATERAL (
    SELECT COALESCE(SUM(jl.debit), 0) AS d, COALESCE(SUM(jl.credit), 0) AS c
    FROM acct_journal_lines jl
    JOIN acct_journal_entries je ON je.id = jl.entry_id
    WHERE jl.account_id = a.id AND je.status = 'posted' AND je.entry_date <= p_as_of AND je.deleted_at IS NULL
  ) raw ON TRUE
  WHERE a.is_leaf AND a.deleted_at IS NULL AND (raw.d <> 0 OR raw.c <> 0)
  ORDER BY a.code;
END;
$$;

-- Income statement for a date range: revenue and expense account movements only.
CREATE OR REPLACE FUNCTION get_income_statement(p_start DATE, p_end DATE)
RETURNS TABLE(account_code TEXT, account_name TEXT, account_type TEXT, amount NUMERIC)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT a.code, a.name, a.account_type,
    CASE WHEN a.account_type = 'revenue' THEN raw.c - raw.d ELSE raw.d - raw.c END AS amount
  FROM acct_chart_of_accounts a
  JOIN LATERAL (
    SELECT COALESCE(SUM(jl.debit), 0) AS d, COALESCE(SUM(jl.credit), 0) AS c
    FROM acct_journal_lines jl
    JOIN acct_journal_entries je ON je.id = jl.entry_id
    WHERE jl.account_id = a.id AND je.status = 'posted' AND je.entry_date BETWEEN p_start AND p_end AND je.deleted_at IS NULL
  ) raw ON TRUE
  WHERE a.is_leaf AND a.deleted_at IS NULL AND a.account_type IN ('revenue', 'expense') AND (raw.d <> 0 OR raw.c <> 0)
  ORDER BY a.account_type, a.code;
END;
$$;

-- Balance sheet as of a date. Adds one synthetic "current period earnings" row
-- under equity so the sheet balances even before the fiscal year is closed —
-- once closed, that amount lives in Retained Earnings (3102) instead and this
-- synthetic row for the (now-past) year naturally reads as zero going forward.
CREATE OR REPLACE FUNCTION get_balance_sheet(p_as_of DATE)
RETURNS TABLE(account_code TEXT, account_name TEXT, account_type TEXT, balance NUMERIC)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_year_start DATE := make_date(EXTRACT(YEAR FROM p_as_of)::INT, 1, 1);
  v_current_earnings NUMERIC(14,2);
BEGIN
  RETURN QUERY
  SELECT a.code, a.name, a.account_type,
    CASE WHEN a.account_type = 'asset' THEN raw.d - raw.c ELSE raw.c - raw.d END AS balance
  FROM acct_chart_of_accounts a
  JOIN LATERAL (
    SELECT COALESCE(SUM(jl.debit), 0) AS d, COALESCE(SUM(jl.credit), 0) AS c
    FROM acct_journal_lines jl
    JOIN acct_journal_entries je ON je.id = jl.entry_id
    WHERE jl.account_id = a.id AND je.status = 'posted' AND je.entry_date <= p_as_of AND je.deleted_at IS NULL
  ) raw ON TRUE
  WHERE a.is_leaf AND a.deleted_at IS NULL AND a.account_type IN ('asset', 'liability', 'equity') AND (raw.d <> 0 OR raw.c <> 0)
  ORDER BY a.account_type, a.code;

  SELECT COALESCE(SUM(amount), 0) INTO v_current_earnings FROM get_income_statement(v_year_start, p_as_of);
  IF v_current_earnings <> 0 THEN
    RETURN QUERY SELECT 'CUR-EARN'::TEXT, ('أرباح الفترة الحالية (' || EXTRACT(YEAR FROM p_as_of)::TEXT || ')')::TEXT, 'equity'::TEXT, v_current_earnings;
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) close_fiscal_year — nets all revenue/expense accounts to Retained Earnings
--    via ONE balanced closing journal entry, then locks the fiscal year and
--    all twelve of its periods so no further entries can post into it.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION close_fiscal_year(p_year INT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fy RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_line_no INT := 1;
  v_acc RECORD;
  v_total_rev NUMERIC(14,2) := 0;
  v_total_exp NUMERIC(14,2) := 0;
  v_net NUMERIC(14,2);
  v_retained_id BIGINT;
BEGIN
  SELECT * INTO v_fy FROM acct_fiscal_years WHERE year = p_year;
  IF v_fy IS NULL THEN RAISE EXCEPTION 'Fiscal year % not found', p_year; END IF;
  IF v_fy.status = 'closed' THEN RAISE EXCEPTION 'Fiscal year % is already closed', p_year; END IF;

  SELECT id INTO v_retained_id FROM acct_chart_of_accounts WHERE code = '3102';
  IF v_retained_id IS NULL THEN RAISE EXCEPTION 'Account 3102 (Retained Earnings) not found'; END IF;

  -- December's period holds the closing entry
  SELECT id INTO v_period_id FROM acct_periods WHERE year = p_year AND month = 12;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'December period for % not found', p_year; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-CLOSE-' || p_year, make_date(p_year, 12, 31), v_period_id, 'قيد إقفال السنة المالية ' || p_year, 'closing', NULL, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  -- Zero out every revenue account with a nonzero balance for the year
  FOR v_acc IN
    SELECT account_code, account_name, amount FROM get_income_statement(make_date(p_year,1,1), make_date(p_year,12,31))
    WHERE account_type = 'revenue' AND amount <> 0
  LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    SELECT v_entry_id, v_line_no, id, v_acc.amount, 0, 'إقفال: ' || v_acc.account_name FROM acct_chart_of_accounts WHERE code = v_acc.account_code;
    v_line_no := v_line_no + 1;
    v_total_rev := v_total_rev + v_acc.amount;
  END LOOP;

  -- Zero out every expense account with a nonzero balance for the year
  FOR v_acc IN
    SELECT account_code, account_name, amount FROM get_income_statement(make_date(p_year,1,1), make_date(p_year,12,31))
    WHERE account_type = 'expense' AND amount <> 0
  LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    SELECT v_entry_id, v_line_no, id, 0, v_acc.amount, 'إقفال: ' || v_acc.account_name FROM acct_chart_of_accounts WHERE code = v_acc.account_code;
    v_line_no := v_line_no + 1;
    v_total_exp := v_total_exp + v_acc.amount;
  END LOOP;

  IF v_total_rev = 0 AND v_total_exp = 0 THEN
    -- Nothing to close — remove the empty entry and just lock the year
    DELETE FROM acct_journal_entries WHERE id = v_entry_id;
    v_entry_id := NULL;
  ELSE
    v_net := v_total_rev - v_total_exp;
    IF v_net > 0 THEN
      INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
      VALUES (v_entry_id, v_line_no, v_retained_id, 0, v_net, 'صافي ربح العام ' || p_year || ' إلى الأرباح المحتجزة');
    ELSIF v_net < 0 THEN
      INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
      VALUES (v_entry_id, v_line_no, v_retained_id, -v_net, 0, 'صافي خسارة العام ' || p_year || ' من الأرباح المحتجزة');
    END IF;

    UPDATE acct_journal_entries SET status = 'posted' WHERE id = v_entry_id;
  END IF;

  UPDATE acct_fiscal_years SET status = 'closed', closed_at = now(), closed_by = current_app_user_id() WHERE id = v_fy.id;
  UPDATE acct_periods SET status = 'closed', closed_at = now(), closed_by = current_app_user_id() WHERE fiscal_year_id = v_fy.id AND status = 'open';

  RETURN v_entry_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) acct_budgets + acct_budget_lines — one row per (budget, account, month)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_budgets (
  id          BIGSERIAL PRIMARY KEY,
  year        INT NOT NULL,
  name        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved')),
  created_by  BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT acct_budgets_unique UNIQUE (year, name)
);

DROP TRIGGER IF EXISTS acct_budgets_updated_at ON acct_budgets;
CREATE TRIGGER acct_budgets_updated_at BEFORE UPDATE ON acct_budgets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_budget_lines (
  id             BIGSERIAL PRIMARY KEY,
  budget_id      BIGINT NOT NULL REFERENCES acct_budgets(id) ON DELETE CASCADE,
  account_id     BIGINT NOT NULL REFERENCES acct_chart_of_accounts(id) ON DELETE CASCADE,
  cost_center_id BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  month          INT NOT NULL CHECK (month BETWEEN 1 AND 12),
  amount         NUMERIC(14,2) NOT NULL DEFAULT 0,
  CONSTRAINT acct_bl2_unique UNIQUE (budget_id, account_id, cost_center_id, month)
);

CREATE INDEX IF NOT EXISTS acct_budget_lines_budget_idx ON acct_budget_lines(budget_id);

-- Plan vs actual for one budget's year, aggregated per account across all 12 months
CREATE OR REPLACE FUNCTION get_budget_vs_actual(p_budget_id BIGINT)
RETURNS TABLE(account_code TEXT, account_name TEXT, budgeted NUMERIC, actual NUMERIC)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_year INT;
BEGIN
  SELECT year INTO v_year FROM acct_budgets WHERE id = p_budget_id;
  RETURN QUERY
  SELECT a.code, a.name,
    COALESCE(bl.total, 0) AS budgeted,
    COALESCE(act.amount, 0) AS actual
  FROM acct_chart_of_accounts a
  LEFT JOIN (
    SELECT account_id, SUM(amount) AS total FROM acct_budget_lines WHERE budget_id = p_budget_id GROUP BY account_id
  ) bl ON bl.account_id = a.id
  LEFT JOIN (
    SELECT account_code, amount FROM get_income_statement(make_date(v_year,1,1), make_date(v_year,12,31))
  ) act ON act.account_code = a.code
  WHERE bl.account_id IS NOT NULL
  ORDER BY a.code;
END;
$$;

ALTER TABLE acct_budgets      ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_budget_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS acct_budgets_sel ON acct_budgets;
DROP POLICY IF EXISTS acct_budgets_wr  ON acct_budgets;
CREATE POLICY acct_budgets_sel ON acct_budgets FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_budgets_wr  ON acct_budgets FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_bl2_sel ON acct_budget_lines;
DROP POLICY IF EXISTS acct_bl2_wr  ON acct_budget_lines;
CREATE POLICY acct_bl2_sel ON acct_budget_lines FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_bl2_wr  ON acct_budget_lines FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist:
--   1. SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN
--        ('acct_vat_returns','acct_budgets','acct_budget_lines');  -- all true
--   2. Try the read-only reports once you have a few posted entries:
--      SELECT * FROM get_trial_balance(CURRENT_DATE);
--      SELECT * FROM get_income_statement('2026-01-01', CURRENT_DATE);
--      SELECT * FROM get_balance_sheet(CURRENT_DATE);
--   3. Year-end closing (only run once you're actually ready to close a year):
--      SELECT close_fiscal_year(2026);
-- ═══════════════════════════════════════════════════════════════════════════
