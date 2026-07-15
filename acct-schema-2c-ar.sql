-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.c — Accounts Receivable + ZATCA Phase 1)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Customers, Sales Invoices (with ZATCA Phase 1 QR fields), Invoice Lines,
--        Receipts. RLS via is_ar_officer. No dual-approval gate on the AR side —
--        the 10,000 SAR dual-approval threshold protects money going OUT
--        (bills/payments, Phase 2.b), not money coming in.
-- Prerequisites: acct-schema.sql (Phase 2.a) and acct-schema-2b-ap.sql (Phase 2.b)
--                must already be applied.
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) acct_customers
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_customers (
  id            BIGSERIAL PRIMARY KEY,
  code          TEXT UNIQUE,
  name          TEXT NOT NULL,
  phone         TEXT,
  email         TEXT,
  tax_number    TEXT,
  address       TEXT,
  credit_limit  NUMERIC(14,2) DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_customers_active_idx ON acct_customers(is_active) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS acct_customers_updated_at ON acct_customers;
CREATE TRIGGER acct_customers_updated_at BEFORE UPDATE ON acct_customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_assign_customer_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'CUST-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_customers_assign_code ON acct_customers;
CREATE TRIGGER acct_customers_assign_code BEFORE INSERT ON acct_customers
  FOR EACH ROW EXECUTE FUNCTION acct_assign_customer_code();

-- Seed a generic "Walk-in / Cash Customer" so quick sales don't need a real customer record
INSERT INTO acct_customers (name, notes) VALUES ('عميل نقدي (بدون تسجيل)', 'عميل افتراضي للمبيعات النقدية السريعة')
  ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) acct_invoices — sales invoices with ZATCA Phase 1 fields
--    zatca_qr_base64 holds a base64 TLV string (seller name, VAT no, timestamp,
--    total, VAT amount) generated client-side at issue time — Phase 1 needs no
--    cryptographic stamp or government API call.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_invoices (
  id                BIGSERIAL PRIMARY KEY,
  invoice_no        TEXT NOT NULL UNIQUE,
  customer_id       BIGINT NOT NULL REFERENCES acct_customers(id) ON DELETE RESTRICT,
  invoice_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date          DATE,
  subtotal          NUMERIC(14,2) NOT NULL DEFAULT 0,
  vat_amount        NUMERIC(14,2) NOT NULL DEFAULT 0,
  total             NUMERIC(14,2) GENERATED ALWAYS AS (subtotal + vat_amount) STORED,
  status            TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'issued', 'paid', 'partially_paid', 'cancelled')),
  amount_paid       NUMERIC(14,2) NOT NULL DEFAULT 0,
  zatca_uuid        UUID NOT NULL DEFAULT gen_random_uuid(),
  zatca_qr_base64   TEXT,
  zatca_status      TEXT NOT NULL DEFAULT 'phase1_qr' CHECK (zatca_status IN ('phase1_qr', 'phase2_signed', 'reported', 'cleared')),
  source_type       TEXT NOT NULL DEFAULT 'manual' CHECK (source_type IN ('manual', 'cafe_order')),
  source_id         BIGINT,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes             TEXT,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  issued_by         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  issued_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_invoices_customer_idx ON acct_invoices(customer_id);
CREATE INDEX IF NOT EXISTS acct_invoices_status_idx   ON acct_invoices(status);
CREATE INDEX IF NOT EXISTS acct_invoices_source_idx   ON acct_invoices(source_type, source_id);
CREATE UNIQUE INDEX IF NOT EXISTS acct_invoices_zatca_uuid_idx ON acct_invoices(zatca_uuid);

DROP TRIGGER IF EXISTS acct_invoices_updated_at ON acct_invoices;
CREATE TRIGGER acct_invoices_updated_at BEFORE UPDATE ON acct_invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_invoice_lines (
  id              BIGSERIAL PRIMARY KEY,
  invoice_id      BIGINT NOT NULL REFERENCES acct_invoices(id) ON DELETE CASCADE,
  line_no         INT NOT NULL,
  description     TEXT NOT NULL,
  quantity        NUMERIC(12,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  line_total      NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  account_id      BIGINT NOT NULL REFERENCES acct_chart_of_accounts(id) ON DELETE RESTRICT,
  vat_applicable  BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT acct_il_unique UNIQUE (invoice_id, line_no)
);

CREATE INDEX IF NOT EXISTS acct_il_invoice_idx ON acct_invoice_lines(invoice_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) acct_receipts — customer payments received
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_receipts (
  id                BIGSERIAL PRIMARY KEY,
  receipt_no        TEXT NOT NULL UNIQUE,
  customer_id       BIGINT NOT NULL REFERENCES acct_customers(id) ON DELETE RESTRICT,
  invoice_id        BIGINT REFERENCES acct_invoices(id) ON DELETE SET NULL,
  bank_account_id   BIGINT, -- FK added in Phase 2.d once acct_bank_accounts exists
  receipt_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  method            TEXT NOT NULL DEFAULT 'cash' CHECK (method IN ('bank', 'cash', 'check')),
  reference         TEXT,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes             TEXT,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_receipts_customer_idx ON acct_receipts(customer_id);
CREATE INDEX IF NOT EXISTS acct_receipts_invoice_idx  ON acct_receipts(invoice_id);

DROP TRIGGER IF EXISTS acct_receipts_updated_at ON acct_receipts;
CREATE TRIGGER acct_receipts_updated_at BEFORE UPDATE ON acct_receipts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) Journal integration functions
-- ═══════════════════════════════════════════════════════════════════════════

-- Issuing an invoice: Debit 1120 Trade Receivables / Credit revenue account(s) + 2104 Output VAT
CREATE OR REPLACE FUNCTION create_journal_for_invoice(p_invoice_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_receivable_account_id BIGINT;
  v_vat_account_id BIGINT;
  v_line RECORD;
  v_line_no INT := 1;
BEGIN
  SELECT * INTO v_inv FROM acct_invoices WHERE id = p_invoice_id;
  IF v_inv IS NULL THEN RAISE EXCEPTION 'Invoice % not found', p_invoice_id; END IF;
  IF v_inv.status NOT IN ('issued', 'paid', 'partially_paid') THEN
    RAISE EXCEPTION 'Invoice must be issued before generating a journal entry';
  END IF;
  IF v_inv.journal_entry_id IS NOT NULL THEN RETURN v_inv.journal_entry_id; END IF;

  SELECT id INTO v_receivable_account_id FROM acct_chart_of_accounts WHERE code = '1120';
  SELECT id INTO v_vat_account_id FROM acct_chart_of_accounts WHERE code = '2104';
  IF v_receivable_account_id IS NULL THEN RAISE EXCEPTION 'Account 1120 (Trade Receivables) not found'; END IF;

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_inv.invoice_date AND end_date >= v_inv.invoice_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_inv.invoice_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-INV-' || p_invoice_id, v_inv.invoice_date, v_period_id, 'قيد فاتورة مبيعات رقم ' || v_inv.invoice_no, 'invoice', p_invoice_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, v_line_no, v_receivable_account_id, v_inv.total, 0, 'مستحق على العميل');
  v_line_no := v_line_no + 1;

  FOR v_line IN SELECT * FROM acct_invoice_lines WHERE invoice_id = p_invoice_id ORDER BY line_no LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_line.account_id, 0, v_line.line_total, v_line.description);
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_inv.vat_amount > 0 AND v_vat_account_id IS NOT NULL THEN
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_vat_account_id, 0, v_inv.vat_amount, 'ضريبة القيمة المضافة - دائن');
  END IF;

  UPDATE acct_invoices SET journal_entry_id = v_entry_id WHERE id = p_invoice_id;
  RETURN v_entry_id;
END;
$$;

-- Receiving a payment: Debit 1101 Cash / Credit 1120 Trade Receivables, and
-- marks the linked invoice paid/partially_paid based on cumulative receipts.
CREATE OR REPLACE FUNCTION create_journal_for_receipt(p_receipt_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rcpt RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_cash_account_id BIGINT;
  v_receivable_account_id BIGINT;
  v_invoice_total NUMERIC(14,2);
  v_paid_total NUMERIC(14,2);
BEGIN
  SELECT * INTO v_rcpt FROM acct_receipts WHERE id = p_receipt_id;
  IF v_rcpt IS NULL THEN RAISE EXCEPTION 'Receipt % not found', p_receipt_id; END IF;
  IF v_rcpt.journal_entry_id IS NOT NULL THEN RETURN v_rcpt.journal_entry_id; END IF;

  SELECT id INTO v_cash_account_id FROM acct_chart_of_accounts WHERE code = '1101';
  SELECT id INTO v_receivable_account_id FROM acct_chart_of_accounts WHERE code = '1120';

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_rcpt.receipt_date AND end_date >= v_rcpt.receipt_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_rcpt.receipt_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-RCPT-' || p_receipt_id, v_rcpt.receipt_date, v_period_id, 'قيد تحصيل من عميل رقم ' || v_rcpt.receipt_no, 'receipt', p_receipt_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_cash_account_id, v_rcpt.amount, 0, 'تحصيل نقدي/بنكي من عميل');
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_receivable_account_id, 0, v_rcpt.amount, 'سداد مستحقات عميل');

  UPDATE acct_receipts SET journal_entry_id = v_entry_id WHERE id = p_receipt_id;

  IF v_rcpt.invoice_id IS NOT NULL THEN
    SELECT total INTO v_invoice_total FROM acct_invoices WHERE id = v_rcpt.invoice_id;
    SELECT COALESCE(SUM(amount), 0) INTO v_paid_total FROM acct_receipts WHERE invoice_id = v_rcpt.invoice_id AND deleted_at IS NULL;
    UPDATE acct_invoices SET
      amount_paid = v_paid_total,
      status = CASE WHEN v_paid_total >= v_invoice_total THEN 'paid' ELSE 'partially_paid' END
    WHERE id = v_rcpt.invoice_id;
  END IF;

  RETURN v_entry_id;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Row-Level Security
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE acct_customers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_invoices       ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_invoice_lines  ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_receipts       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS acct_cust_sel ON acct_customers;
DROP POLICY IF EXISTS acct_cust_wr  ON acct_customers;
CREATE POLICY acct_cust_sel ON acct_customers FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_cust_wr  ON acct_customers FOR ALL   TO authenticated USING (is_ar_officer()) WITH CHECK (is_ar_officer());

DROP POLICY IF EXISTS acct_inv_sel ON acct_invoices;
DROP POLICY IF EXISTS acct_inv_ins ON acct_invoices;
DROP POLICY IF EXISTS acct_inv_upd ON acct_invoices;
CREATE POLICY acct_inv_sel ON acct_invoices FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_inv_ins ON acct_invoices FOR INSERT TO authenticated WITH CHECK (is_ar_officer());
CREATE POLICY acct_inv_upd ON acct_invoices FOR UPDATE TO authenticated USING (is_ar_officer()) WITH CHECK (is_ar_officer() OR is_finance_manager());

DROP POLICY IF EXISTS acct_il_sel ON acct_invoice_lines;
DROP POLICY IF EXISTS acct_il_wr  ON acct_invoice_lines;
CREATE POLICY acct_il_sel ON acct_invoice_lines FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_il_wr  ON acct_invoice_lines FOR ALL   TO authenticated USING (is_ar_officer()) WITH CHECK (is_ar_officer());

DROP POLICY IF EXISTS acct_rcpt_sel ON acct_receipts;
DROP POLICY IF EXISTS acct_rcpt_wr  ON acct_receipts;
CREATE POLICY acct_rcpt_sel ON acct_receipts FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_rcpt_wr  ON acct_receipts FOR ALL   TO authenticated USING (is_ar_officer()) WITH CHECK (is_ar_officer());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist:
--   1. SELECT * FROM acct_customers;  -- expect the seeded "عميل نقدي" row
--   2. SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN
--        ('acct_customers','acct_invoices','acct_invoice_lines','acct_receipts');
--      All should show rowsecurity = true.
--   3. The ZATCA QR string (zatca_qr_base64) is generated client-side in
--      index.html.html when an invoice is issued — it is NOT computed by SQL.
-- ═══════════════════════════════════════════════════════════════════════════
