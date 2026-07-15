-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.b — Accounts Payable)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Vendors (migrated from maintenance_suppliers, no data loss),
--        Purchase Orders, Bills, Payments — with dual-approval enforcement
--        above acct_settings.dual_approval_threshold (10,000 SAR by default).
-- Prerequisites: acct-schema.sql (Phase 2.a) must already be applied.
--                maintenance_suppliers must already exist.
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) acct_vendors — migrated from maintenance_suppliers, no data lost.
--    legacy_maintenance_supplier_id keeps the link back to the original row.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_vendors (
  id                          BIGSERIAL PRIMARY KEY,
  code                        TEXT UNIQUE,
  name                        TEXT NOT NULL,
  activity                    TEXT,
  phone                       TEXT,
  email                       TEXT,
  tax_number                  TEXT,
  bank_name                   TEXT,
  iban                        TEXT,
  address                     TEXT,
  rating                      NUMERIC(2,1) DEFAULT 0,
  is_active                   BOOLEAN NOT NULL DEFAULT TRUE,
  notes                       TEXT,
  legacy_maintenance_supplier_id BIGINT UNIQUE REFERENCES maintenance_suppliers(id) ON DELETE SET NULL,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now(),
  deleted_at                  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_vendors_active_idx ON acct_vendors(is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS acct_vendors_legacy_idx ON acct_vendors(legacy_maintenance_supplier_id);

DROP TRIGGER IF EXISTS acct_vendors_updated_at ON acct_vendors;
CREATE TRIGGER acct_vendors_updated_at BEFORE UPDATE ON acct_vendors
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-assign a vendor code on insert if none given (VEN-00001, VEN-00002, ...)
CREATE OR REPLACE FUNCTION acct_assign_vendor_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.code IS NULL THEN
    NEW.code := 'VEN-' || LPAD(NEW.id::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_vendors_assign_code ON acct_vendors;
CREATE TRIGGER acct_vendors_assign_code BEFORE INSERT ON acct_vendors
  FOR EACH ROW EXECUTE FUNCTION acct_assign_vendor_code();

-- One-time migration: every existing maintenance supplier becomes a vendor.
-- Idempotent via the UNIQUE constraint on legacy_maintenance_supplier_id.
INSERT INTO acct_vendors (name, activity, phone, notes, rating, is_active, legacy_maintenance_supplier_id)
  SELECT name, activity, phone,
         CASE WHEN email IS NOT NULL THEN COALESCE(notes, '') || ' | البريد: ' || email ELSE notes END,
         rating, COALESCE(is_active, TRUE), id
  FROM maintenance_suppliers
  ON CONFLICT (legacy_maintenance_supplier_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) acct_purchase_orders + lines
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_purchase_orders (
  id             BIGSERIAL PRIMARY KEY,
  po_no          TEXT NOT NULL UNIQUE,
  vendor_id      BIGINT NOT NULL REFERENCES acct_vendors(id) ON DELETE RESTRICT,
  order_date     DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_date  DATE,
  cost_center_id BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  status         TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'received', 'closed', 'cancelled')),
  notes          TEXT,
  created_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_po_vendor_idx ON acct_purchase_orders(vendor_id);
CREATE INDEX IF NOT EXISTS acct_po_status_idx ON acct_purchase_orders(status);

DROP TRIGGER IF EXISTS acct_po_updated_at ON acct_purchase_orders;
CREATE TRIGGER acct_po_updated_at BEFORE UPDATE ON acct_purchase_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_purchase_order_lines (
  id                BIGSERIAL PRIMARY KEY,
  po_id             BIGINT NOT NULL REFERENCES acct_purchase_orders(id) ON DELETE CASCADE,
  line_no           INT NOT NULL,
  item_description  TEXT NOT NULL,
  quantity          NUMERIC(12,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  line_total        NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  account_id        BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE SET NULL,
  cost_center_id    BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  CONSTRAINT acct_pol_unique UNIQUE (po_id, line_no)
);

CREATE INDEX IF NOT EXISTS acct_pol_po_idx ON acct_purchase_order_lines(po_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) acct_bills + lines — vendor invoices, with dual-approval enforcement
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_bills (
  id                    BIGSERIAL PRIMARY KEY,
  bill_no               TEXT NOT NULL UNIQUE,
  vendor_id             BIGINT NOT NULL REFERENCES acct_vendors(id) ON DELETE RESTRICT,
  po_id                 BIGINT REFERENCES acct_purchase_orders(id) ON DELETE SET NULL,
  bill_date             DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date              DATE,
  vendor_invoice_no     TEXT,
  subtotal              NUMERIC(14,2) NOT NULL DEFAULT 0,
  vat_amount            NUMERIC(14,2) NOT NULL DEFAULT 0,
  total                 NUMERIC(14,2) GENERATED ALWAYS AS (subtotal + vat_amount) STORED,
  status                TEXT NOT NULL DEFAULT 'draft'
                          CHECK (status IN ('draft', 'pending_approval', 'approved', 'paid', 'cancelled')),
  requires_second_approval BOOLEAN NOT NULL DEFAULT FALSE,
  second_approved_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  second_approved_at    TIMESTAMPTZ,
  journal_entry_id      BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes                 TEXT,
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at           TIMESTAMPTZ,
  paid_at               TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  deleted_at            TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_bills_vendor_idx ON acct_bills(vendor_id);
CREATE INDEX IF NOT EXISTS acct_bills_status_idx ON acct_bills(status);
CREATE INDEX IF NOT EXISTS acct_bills_due_idx    ON acct_bills(due_date) WHERE status NOT IN ('paid', 'cancelled');

DROP TRIGGER IF EXISTS acct_bills_updated_at ON acct_bills;
CREATE TRIGGER acct_bills_updated_at BEFORE UPDATE ON acct_bills
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS acct_bill_lines (
  id              BIGSERIAL PRIMARY KEY,
  bill_id         BIGINT NOT NULL REFERENCES acct_bills(id) ON DELETE CASCADE,
  line_no         INT NOT NULL,
  description     TEXT NOT NULL,
  quantity        NUMERIC(12,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  line_total      NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  account_id      BIGINT NOT NULL REFERENCES acct_chart_of_accounts(id) ON DELETE RESTRICT,
  cost_center_id  BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  vat_applicable  BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT acct_bl_unique UNIQUE (bill_id, line_no)
);

CREATE INDEX IF NOT EXISTS acct_bl_bill_idx ON acct_bill_lines(bill_id);

-- Dual-approval gate: block moving a bill to 'approved' if its total exceeds
-- acct_settings.dual_approval_threshold and no second approver is set.
CREATE OR REPLACE FUNCTION acct_validate_bill_approval()
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
      RAISE EXCEPTION 'هذه الفاتورة (% ر.س) تتجاوز حد الاعتماد المزدوج (% ر.س) وتحتاج موافقة ثانية قبل الاعتماد', NEW.total, v_threshold;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_bills_validate_approval ON acct_bills;
CREATE TRIGGER acct_bills_validate_approval BEFORE INSERT OR UPDATE ON acct_bills
  FOR EACH ROW EXECUTE FUNCTION acct_validate_bill_approval();

-- Auto-create the journal entry for an approved bill:
--   Debit: expense/asset account(s) from bill lines
--   Credit: 2101 Trade Payables
CREATE OR REPLACE FUNCTION create_journal_for_bill(p_bill_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bill RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_entry_no TEXT;
  v_payable_account_id BIGINT;
  v_line RECORD;
  v_line_no INT := 1;
BEGIN
  SELECT * INTO v_bill FROM acct_bills WHERE id = p_bill_id;
  IF v_bill IS NULL THEN RAISE EXCEPTION 'Bill % not found', p_bill_id; END IF;
  IF v_bill.status NOT IN ('approved', 'paid') THEN RAISE EXCEPTION 'Bill must be approved first'; END IF;
  IF v_bill.journal_entry_id IS NOT NULL THEN RETURN v_bill.journal_entry_id; END IF;

  SELECT id INTO v_payable_account_id FROM acct_chart_of_accounts WHERE code = '2101';
  IF v_payable_account_id IS NULL THEN RAISE EXCEPTION 'Account 2101 (Trade Payables) not found'; END IF;

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_bill.bill_date AND end_date >= v_bill.bill_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_bill.bill_date; END IF;

  v_entry_no := 'JE-BILL-' || p_bill_id;
  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES (v_entry_no, v_bill.bill_date, v_period_id, 'قيد فاتورة مورد رقم ' || v_bill.bill_no, 'bill', p_bill_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  FOR v_line IN SELECT * FROM acct_bill_lines WHERE bill_id = p_bill_id ORDER BY line_no LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, cost_center_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_line.account_id, v_line.cost_center_id, v_line.line_total, 0, v_line.description);
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_bill.vat_amount > 0 THEN
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    SELECT v_entry_id, v_line_no, id, v_bill.vat_amount, 0, 'ضريبة القيمة المضافة - مدين'
    FROM acct_chart_of_accounts WHERE code = '1150';
    v_line_no := v_line_no + 1;
  END IF;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, v_line_no, v_payable_account_id, 0, v_bill.total, 'مستحق للمورد');

  UPDATE acct_bills SET journal_entry_id = v_entry_id WHERE id = p_bill_id;
  RETURN v_entry_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) acct_payments — payments to vendors, same dual-approval gate
--    bank_account_id is a plain nullable column (no FK yet) — Phase 2.d will
--    add the FK once acct_bank_accounts exists, via ALTER TABLE.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_payments (
  id                        BIGSERIAL PRIMARY KEY,
  payment_no                TEXT NOT NULL UNIQUE,
  vendor_id                 BIGINT NOT NULL REFERENCES acct_vendors(id) ON DELETE RESTRICT,
  bill_id                   BIGINT REFERENCES acct_bills(id) ON DELETE SET NULL,
  bank_account_id           BIGINT,
  payment_date              DATE NOT NULL DEFAULT CURRENT_DATE,
  amount                    NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  method                    TEXT NOT NULL DEFAULT 'bank' CHECK (method IN ('bank', 'cash', 'check')),
  reference                 TEXT,
  status                    TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'paid', 'cancelled')),
  requires_second_approval  BOOLEAN NOT NULL DEFAULT FALSE,
  second_approved_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  second_approved_at        TIMESTAMPTZ,
  journal_entry_id          BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes                     TEXT,
  created_by                BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_by               BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at               TIMESTAMPTZ,
  created_at                TIMESTAMPTZ DEFAULT now(),
  updated_at                TIMESTAMPTZ DEFAULT now(),
  deleted_at                TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_payments_vendor_idx ON acct_payments(vendor_id);
CREATE INDEX IF NOT EXISTS acct_payments_bill_idx   ON acct_payments(bill_id);
CREATE INDEX IF NOT EXISTS acct_payments_status_idx ON acct_payments(status);

DROP TRIGGER IF EXISTS acct_payments_updated_at ON acct_payments;
CREATE TRIGGER acct_payments_updated_at BEFORE UPDATE ON acct_payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_validate_payment_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_threshold NUMERIC(12,2);
BEGIN
  SELECT dual_approval_threshold INTO v_threshold FROM acct_settings WHERE id = 1;
  NEW.requires_second_approval := (NEW.amount > v_threshold);

  IF NEW.status = 'approved' AND (OLD.status IS DISTINCT FROM 'approved') THEN
    IF NEW.requires_second_approval AND NEW.second_approved_by IS NULL THEN
      RAISE EXCEPTION 'هذه الدفعة (% ر.س) تتجاوز حد الاعتماد المزدوج (% ر.س) وتحتاج موافقة ثانية قبل الاعتماد', NEW.amount, v_threshold;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_payments_validate_approval ON acct_payments;
CREATE TRIGGER acct_payments_validate_approval BEFORE INSERT OR UPDATE ON acct_payments
  FOR EACH ROW EXECUTE FUNCTION acct_validate_payment_approval();

-- Auto-create journal entry when a payment is marked 'paid':
--   Debit: 2101 Trade Payables / Credit: 1101 Cash on Hand (bank wiring comes in 2.d)
CREATE OR REPLACE FUNCTION create_journal_for_payment(p_payment_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pay RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_payable_account_id BIGINT;
  v_cash_account_id BIGINT;
BEGIN
  SELECT * INTO v_pay FROM acct_payments WHERE id = p_payment_id;
  IF v_pay IS NULL THEN RAISE EXCEPTION 'Payment % not found', p_payment_id; END IF;
  IF v_pay.status != 'paid' THEN RAISE EXCEPTION 'Payment must be marked paid first'; END IF;
  IF v_pay.journal_entry_id IS NOT NULL THEN RETURN v_pay.journal_entry_id; END IF;

  SELECT id INTO v_payable_account_id FROM acct_chart_of_accounts WHERE code = '2101';
  SELECT id INTO v_cash_account_id FROM acct_chart_of_accounts WHERE code = '1101';

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_pay.payment_date AND end_date >= v_pay.payment_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_pay.payment_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-PAY-' || p_payment_id, v_pay.payment_date, v_period_id, 'قيد سداد دفعة رقم ' || v_pay.payment_no, 'payment', p_payment_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_payable_account_id, v_pay.amount, 0, 'سداد مستحقات مورد');
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_cash_account_id, 0, v_pay.amount, 'صرف نقدية/بنك');

  UPDATE acct_payments SET journal_entry_id = v_entry_id WHERE id = p_payment_id;
  RETURN v_entry_id;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Row-Level Security
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE acct_vendors               ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_purchase_orders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_purchase_order_lines  ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_bills                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_bill_lines            ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_payments              ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS acct_vendors_sel ON acct_vendors;
DROP POLICY IF EXISTS acct_vendors_wr  ON acct_vendors;
CREATE POLICY acct_vendors_sel ON acct_vendors FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_vendors_wr  ON acct_vendors FOR ALL   TO authenticated USING (is_ap_officer()) WITH CHECK (is_ap_officer());

DROP POLICY IF EXISTS acct_po_sel ON acct_purchase_orders;
DROP POLICY IF EXISTS acct_po_wr  ON acct_purchase_orders;
CREATE POLICY acct_po_sel ON acct_purchase_orders FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_po_wr  ON acct_purchase_orders FOR ALL   TO authenticated USING (is_ap_officer()) WITH CHECK (is_ap_officer());

DROP POLICY IF EXISTS acct_pol_sel ON acct_purchase_order_lines;
DROP POLICY IF EXISTS acct_pol_wr  ON acct_purchase_order_lines;
CREATE POLICY acct_pol_sel ON acct_purchase_order_lines FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_pol_wr  ON acct_purchase_order_lines FOR ALL   TO authenticated USING (is_ap_officer()) WITH CHECK (is_ap_officer());

DROP POLICY IF EXISTS acct_bills_sel ON acct_bills;
DROP POLICY IF EXISTS acct_bills_ins ON acct_bills;
DROP POLICY IF EXISTS acct_bills_upd ON acct_bills;
CREATE POLICY acct_bills_sel ON acct_bills FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_bills_ins ON acct_bills FOR INSERT TO authenticated WITH CHECK (is_ap_officer());
CREATE POLICY acct_bills_upd ON acct_bills FOR UPDATE TO authenticated USING (is_ap_officer())
  WITH CHECK (is_ap_officer() OR is_finance_manager());

DROP POLICY IF EXISTS acct_bl_sel ON acct_bill_lines;
DROP POLICY IF EXISTS acct_bl_wr  ON acct_bill_lines;
CREATE POLICY acct_bl_sel ON acct_bill_lines FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_bl_wr  ON acct_bill_lines FOR ALL   TO authenticated USING (is_ap_officer()) WITH CHECK (is_ap_officer());

DROP POLICY IF EXISTS acct_pay_sel ON acct_payments;
DROP POLICY IF EXISTS acct_pay_ins ON acct_payments;
DROP POLICY IF EXISTS acct_pay_upd ON acct_payments;
CREATE POLICY acct_pay_sel ON acct_payments FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_pay_ins ON acct_payments FOR INSERT TO authenticated WITH CHECK (is_ap_officer());
CREATE POLICY acct_pay_upd ON acct_payments FOR UPDATE TO authenticated USING (is_ap_officer())
  WITH CHECK (is_ap_officer() OR is_finance_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist:
--   1. SELECT COUNT(*) FROM acct_vendors;  -- should be >= COUNT(*) FROM maintenance_suppliers
--   2. SELECT code, name, legacy_maintenance_supplier_id FROM acct_vendors ORDER BY id LIMIT 10;
--   3. SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN
--        ('acct_vendors','acct_purchase_orders','acct_purchase_order_lines','acct_bills','acct_bill_lines','acct_payments');
--      All should show rowsecurity = true.
-- ═══════════════════════════════════════════════════════════════════════════
