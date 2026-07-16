-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.d — Treasury)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Bank Accounts (each auto-gets its own GL sub-account under 1110),
--        Bank Transactions (manual entries + reconciliation flag),
--        Petty Cash funds + their transactions,
--        Employee Expense Claims + line items with an approval workflow.
-- Prerequisites: acct-schema.sql, acct-schema-2b-ap.sql, acct-schema-2c-ar.sql
--                must already be applied.
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) acct_bank_accounts — each one gets an auto-created child ledger account
--    under 1110 (Banks) so its balance can be tracked and reported separately.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_bank_accounts (
  id                BIGSERIAL PRIMARY KEY,
  code              TEXT UNIQUE,
  bank_name         TEXT NOT NULL,
  account_name      TEXT NOT NULL,
  account_no        TEXT,
  iban              TEXT,
  currency          TEXT NOT NULL DEFAULT 'SAR',
  opening_balance   NUMERIC(14,2) NOT NULL DEFAULT 0,
  coa_account_id    BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE SET NULL,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_bank_accounts_active_idx ON acct_bank_accounts(is_active) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS acct_bank_accounts_updated_at ON acct_bank_accounts;
CREATE TRIGGER acct_bank_accounts_updated_at BEFORE UPDATE ON acct_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_setup_bank_account()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_parent_id BIGINT;
  v_sub_code TEXT;
  v_sub_id BIGINT;
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'BANK-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;

  IF NEW.coa_account_id IS NULL THEN
    SELECT id INTO v_parent_id FROM acct_chart_of_accounts WHERE code = '1110';
    IF v_parent_id IS NOT NULL THEN
      v_sub_code := '1110-' || NEW.id;
      INSERT INTO acct_chart_of_accounts (code, name, parent_id, account_type, normal_balance, is_leaf, is_system)
      VALUES (v_sub_code, NEW.bank_name || ' — ' || NEW.account_name, v_parent_id, 'asset', 'debit', TRUE, TRUE)
      ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
      RETURNING id INTO v_sub_id;
      NEW.coa_account_id := v_sub_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_bank_accounts_setup ON acct_bank_accounts;
CREATE TRIGGER acct_bank_accounts_setup BEFORE INSERT ON acct_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION acct_setup_bank_account();

-- Now that acct_bank_accounts exists, wire the FK left dangling since Phase 2.b/2.c
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'acct_payments_bank_account_fk'
  ) THEN
    ALTER TABLE acct_payments
      ADD CONSTRAINT acct_payments_bank_account_fk
      FOREIGN KEY (bank_account_id) REFERENCES acct_bank_accounts(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'acct_receipts_bank_account_fk'
  ) THEN
    ALTER TABLE acct_receipts
      ADD CONSTRAINT acct_receipts_bank_account_fk
      FOREIGN KEY (bank_account_id) REFERENCES acct_bank_accounts(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) acct_bank_transactions — manual bank-side entries + reconciliation flag
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_bank_transactions (
  id                BIGSERIAL PRIMARY KEY,
  bank_account_id   BIGINT NOT NULL REFERENCES acct_bank_accounts(id) ON DELETE CASCADE,
  transaction_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  type              TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  reference         TEXT,
  description       TEXT,
  reconciled        BOOLEAN NOT NULL DEFAULT FALSE,
  reconciled_at     TIMESTAMPTZ,
  reconciled_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_bank_tx_account_idx ON acct_bank_transactions(bank_account_id);
CREATE INDEX IF NOT EXISTS acct_bank_tx_recon_idx   ON acct_bank_transactions(reconciled);

DROP TRIGGER IF EXISTS acct_bank_tx_updated_at ON acct_bank_transactions;
CREATE TRIGGER acct_bank_tx_updated_at BEFORE UPDATE ON acct_bank_transactions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION create_journal_for_bank_transaction(p_tx_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx RECORD;
  v_bank RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_contra_account_id BIGINT;
BEGIN
  SELECT * INTO v_tx FROM acct_bank_transactions WHERE id = p_tx_id;
  IF v_tx IS NULL THEN RAISE EXCEPTION 'Bank transaction % not found', p_tx_id; END IF;
  IF v_tx.journal_entry_id IS NOT NULL THEN RETURN v_tx.journal_entry_id; END IF;

  SELECT * INTO v_bank FROM acct_bank_accounts WHERE id = v_tx.bank_account_id;
  SELECT id INTO v_contra_account_id FROM acct_chart_of_accounts WHERE code = '5912'; -- misc expense/income placeholder

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_tx.transaction_date AND end_date >= v_tx.transaction_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_tx.transaction_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-BANKTX-' || p_tx_id, v_tx.transaction_date, v_period_id,
          COALESCE(v_tx.description, 'حركة بنكية') || ' — ' || v_bank.bank_name, 'manual', p_tx_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  IF v_tx.type = 'deposit' THEN
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, 1, v_bank.coa_account_id, v_tx.amount, 0, 'إيداع بنكي');
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, 2, v_contra_account_id, 0, v_tx.amount, COALESCE(v_tx.description, 'مقابل الإيداع'));
  ELSE
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, 1, v_contra_account_id, v_tx.amount, 0, COALESCE(v_tx.description, 'مقابل السحب'));
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, 2, v_bank.coa_account_id, 0, v_tx.amount, 'سحب بنكي');
  END IF;

  UPDATE acct_bank_transactions SET journal_entry_id = v_entry_id WHERE id = p_tx_id;
  RETURN v_entry_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) acct_petty_cash — cash funds held by a custodian (all post to 1102)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_petty_cash (
  id                BIGSERIAL PRIMARY KEY,
  code              TEXT UNIQUE,
  custodian_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  branch_id         BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  opening_balance   NUMERIC(14,2) NOT NULL DEFAULT 0,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_petty_cash_custodian_idx ON acct_petty_cash(custodian_id);

DROP TRIGGER IF EXISTS acct_petty_cash_updated_at ON acct_petty_cash;
CREATE TRIGGER acct_petty_cash_updated_at BEFORE UPDATE ON acct_petty_cash
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_assign_petty_cash_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'PC-' || LPAD(NEW.id::TEXT, 4, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_petty_cash_assign_code ON acct_petty_cash;
CREATE TRIGGER acct_petty_cash_assign_code BEFORE INSERT ON acct_petty_cash
  FOR EACH ROW EXECUTE FUNCTION acct_assign_petty_cash_code();

CREATE TABLE IF NOT EXISTS acct_petty_cash_transactions (
  id                BIGSERIAL PRIMARY KEY,
  petty_cash_id     BIGINT NOT NULL REFERENCES acct_petty_cash(id) ON DELETE CASCADE,
  transaction_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  type              TEXT NOT NULL CHECK (type IN ('replenishment', 'expense', 'return')),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  description       TEXT,
  expense_claim_id  BIGINT, -- FK added below, after acct_expense_claims is created
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS acct_pct_fund_idx ON acct_petty_cash_transactions(petty_cash_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) acct_expense_claims + lines — employee expense reimbursement workflow
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_expense_claims (
  id                    BIGSERIAL PRIMARY KEY,
  claim_no              TEXT NOT NULL UNIQUE,
  employee_id           BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claim_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  status                TEXT NOT NULL DEFAULT 'draft'
                          CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'paid', 'cancelled')),
  total                 NUMERIC(14,2) NOT NULL DEFAULT 0,
  reimbursement_method  TEXT CHECK (reimbursement_method IN ('petty_cash', 'bank', 'payroll_deduction')),
  petty_cash_id         BIGINT REFERENCES acct_petty_cash(id) ON DELETE SET NULL,
  bank_account_id       BIGINT REFERENCES acct_bank_accounts(id) ON DELETE SET NULL,
  requires_second_approval BOOLEAN NOT NULL DEFAULT FALSE,
  second_approved_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  second_approved_at    TIMESTAMPTZ,
  journal_entry_id      BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes                 TEXT,
  rejection_reason      TEXT,
  submitted_at          TIMESTAMPTZ,
  approved_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at           TIMESTAMPTZ,
  paid_at               TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  deleted_at            TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_ec_employee_idx ON acct_expense_claims(employee_id);
CREATE INDEX IF NOT EXISTS acct_ec_status_idx   ON acct_expense_claims(status);

DROP TRIGGER IF EXISTS acct_ec_updated_at ON acct_expense_claims;
CREATE TRIGGER acct_ec_updated_at BEFORE UPDATE ON acct_expense_claims
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_expense_claim_lines (
  id            BIGSERIAL PRIMARY KEY,
  claim_id      BIGINT NOT NULL REFERENCES acct_expense_claims(id) ON DELETE CASCADE,
  line_no       INT NOT NULL,
  expense_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  description   TEXT NOT NULL,
  amount        NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  account_id    BIGINT NOT NULL REFERENCES acct_chart_of_accounts(id) ON DELETE RESTRICT,
  receipt_url   TEXT,
  CONSTRAINT acct_ecl_unique UNIQUE (claim_id, line_no)
);

CREATE INDEX IF NOT EXISTS acct_ecl_claim_idx ON acct_expense_claim_lines(claim_id);

-- Now that acct_expense_claims exists, link petty cash transactions to it
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'acct_pct_expense_claim_fk'
  ) THEN
    ALTER TABLE acct_petty_cash_transactions
      ADD CONSTRAINT acct_pct_expense_claim_fk
      FOREIGN KEY (expense_claim_id) REFERENCES acct_expense_claims(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Dual-approval gate mirrors bills/payments (Phase 2.b)
CREATE OR REPLACE FUNCTION acct_validate_expense_claim_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_threshold NUMERIC(12,2);
BEGIN
  SELECT dual_approval_threshold INTO v_threshold FROM acct_settings WHERE id = 1;
  NEW.requires_second_approval := (NEW.total > v_threshold);
  IF NEW.status = 'approved' AND (OLD.status IS DISTINCT FROM 'approved') THEN
    IF NEW.requires_second_approval AND NEW.second_approved_by IS NULL THEN
      RAISE EXCEPTION 'مصروفات هذا الطلب (% ر.س) تتجاوز حد الاعتماد المزدوج (% ر.س) وتحتاج موافقة ثانية', NEW.total, v_threshold;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_ec_validate_approval ON acct_expense_claims;
CREATE TRIGGER acct_ec_validate_approval BEFORE INSERT OR UPDATE ON acct_expense_claims
  FOR EACH ROW EXECUTE FUNCTION acct_validate_expense_claim_approval();

-- Marking a claim 'paid': Debit expense accounts from lines / Credit petty cash (1102) or bank
CREATE OR REPLACE FUNCTION create_journal_for_expense_claim(p_claim_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claim RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_credit_account_id BIGINT;
  v_line RECORD;
  v_line_no INT := 1;
BEGIN
  SELECT * INTO v_claim FROM acct_expense_claims WHERE id = p_claim_id;
  IF v_claim IS NULL THEN RAISE EXCEPTION 'Expense claim % not found', p_claim_id; END IF;
  IF v_claim.status != 'paid' THEN RAISE EXCEPTION 'Claim must be marked paid first'; END IF;
  IF v_claim.journal_entry_id IS NOT NULL THEN RETURN v_claim.journal_entry_id; END IF;

  IF v_claim.reimbursement_method = 'bank' AND v_claim.bank_account_id IS NOT NULL THEN
    SELECT coa_account_id INTO v_credit_account_id FROM acct_bank_accounts WHERE id = v_claim.bank_account_id;
  ELSE
    SELECT id INTO v_credit_account_id FROM acct_chart_of_accounts WHERE code = '1102'; -- Petty Cash
  END IF;

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_claim.claim_date AND end_date >= v_claim.claim_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_claim.claim_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-EXP-' || p_claim_id, v_claim.claim_date, v_period_id, 'قيد سداد مصروفات رقم ' || v_claim.claim_no, 'manual', p_claim_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  FOR v_line IN SELECT * FROM acct_expense_claim_lines WHERE claim_id = p_claim_id ORDER BY line_no LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_line.account_id, v_line.amount, 0, v_line.description);
    v_line_no := v_line_no + 1;
  END LOOP;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, v_line_no, v_credit_account_id, 0, v_claim.total, 'سداد مصروفات موظف');

  UPDATE acct_expense_claims SET journal_entry_id = v_entry_id WHERE id = p_claim_id;
  RETURN v_entry_id;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Row-Level Security
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE acct_bank_accounts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_bank_transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_petty_cash              ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_petty_cash_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_expense_claims          ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_expense_claim_lines     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS acct_bank_sel ON acct_bank_accounts;
DROP POLICY IF EXISTS acct_bank_wr  ON acct_bank_accounts;
CREATE POLICY acct_bank_sel ON acct_bank_accounts FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_bank_wr  ON acct_bank_accounts FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_banktx_sel ON acct_bank_transactions;
DROP POLICY IF EXISTS acct_banktx_wr  ON acct_bank_transactions;
CREATE POLICY acct_banktx_sel ON acct_bank_transactions FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_banktx_wr  ON acct_bank_transactions FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_pc_sel ON acct_petty_cash;
DROP POLICY IF EXISTS acct_pc_wr  ON acct_petty_cash;
CREATE POLICY acct_pc_sel ON acct_petty_cash FOR SELECT TO authenticated USING (is_accounting_role() OR custodian_id = current_app_user_id());
CREATE POLICY acct_pc_wr  ON acct_petty_cash FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_pct_sel ON acct_petty_cash_transactions;
DROP POLICY IF EXISTS acct_pct_wr  ON acct_petty_cash_transactions;
CREATE POLICY acct_pct_sel ON acct_petty_cash_transactions FOR SELECT TO authenticated USING (
  is_accounting_role()
  OR EXISTS (SELECT 1 FROM acct_petty_cash p WHERE p.id = petty_cash_id AND p.custodian_id = current_app_user_id())
);
CREATE POLICY acct_pct_wr ON acct_petty_cash_transactions FOR ALL TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

-- Expense claims: employee sees/creates their own; finance roles see & approve all
DROP POLICY IF EXISTS acct_ec_sel     ON acct_expense_claims;
DROP POLICY IF EXISTS acct_ec_ins     ON acct_expense_claims;
DROP POLICY IF EXISTS acct_ec_upd     ON acct_expense_claims;
CREATE POLICY acct_ec_sel ON acct_expense_claims FOR SELECT TO authenticated
  USING (employee_id = current_app_user_id() OR is_accounting_role());
CREATE POLICY acct_ec_ins ON acct_expense_claims FOR INSERT TO authenticated
  WITH CHECK (employee_id = current_app_user_id() OR is_gl_accountant());
CREATE POLICY acct_ec_upd ON acct_expense_claims FOR UPDATE TO authenticated
  USING (
    (employee_id = current_app_user_id() AND status IN ('draft', 'submitted'))
    OR is_gl_accountant()
  )
  WITH CHECK (
    (employee_id = current_app_user_id() AND status IN ('draft', 'submitted', 'cancelled'))
    OR is_gl_accountant()
    OR is_finance_manager()
  );

DROP POLICY IF EXISTS acct_ecl_sel ON acct_expense_claim_lines;
DROP POLICY IF EXISTS acct_ecl_wr  ON acct_expense_claim_lines;
CREATE POLICY acct_ecl_sel ON acct_expense_claim_lines FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM acct_expense_claims c WHERE c.id = claim_id AND (c.employee_id = current_app_user_id() OR is_accounting_role()))
);
CREATE POLICY acct_ecl_wr ON acct_expense_claim_lines FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM acct_expense_claims c WHERE c.id = claim_id AND (c.employee_id = current_app_user_id() OR is_gl_accountant()) AND c.status IN ('draft', 'submitted'))
) WITH CHECK (
  EXISTS (SELECT 1 FROM acct_expense_claims c WHERE c.id = claim_id AND (c.employee_id = current_app_user_id() OR is_gl_accountant()))
);

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist:
--   1. SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN
--        ('acct_bank_accounts','acct_bank_transactions','acct_petty_cash',
--         'acct_petty_cash_transactions','acct_expense_claims','acct_expense_claim_lines');
--      All should show rowsecurity = true.
--   2. Confirm the dangling FKs from Phase 2.b/2.c got wired:
--      SELECT constraint_name FROM information_schema.table_constraints
--        WHERE constraint_name IN ('acct_payments_bank_account_fk','acct_receipts_bank_account_fk');
--   3. After adding your first bank account, confirm its sub-account was created:
--      SELECT code, name FROM acct_chart_of_accounts WHERE code LIKE '1110-%';
-- ═══════════════════════════════════════════════════════════════════════════
