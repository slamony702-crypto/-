-- ═══════════════════════════════════════════════════════════
-- نقاط البيع POS — Phase 1a (Wave 1 Module 23)
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: أجهزة + جلسات + معاملات + بنودها + طرق الدفع
-- + دالة pos_complete_transaction() تُتمّ كل شيء في transaction واحد:
--   (فحص الدفعات = الإجمالي) → قيد محاسبي مسودة → تحديث بيانات العميل
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- السماح بمصدر قيود جديد: pos_sale
ALTER TABLE acct_journal_entries DROP CONSTRAINT IF EXISTS acct_journal_entries_source_type_check;
ALTER TABLE acct_journal_entries ADD CONSTRAINT acct_journal_entries_source_type_check
  CHECK (source_type IN (
    'manual', 'hr_payroll', 'bill', 'invoice', 'payment', 'receipt',
    'cafe_order', 'depreciation', 'closing', 'opening', 'reversal',
    'ops_order', 'pay_settlement', 'pos_sale'
  ));

-- ───────────────────────────────────────────────────────────
-- 1) pos_terminals — أجهزة نقاط البيع في كل فرع
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_terminals (
  id           BIGSERIAL PRIMARY KEY,
  branch_id    BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  code         TEXT UNIQUE,
  name         TEXT NOT NULL,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_terminals_branch_idx ON pos_terminals(branch_id) WHERE is_active;

DROP TRIGGER IF EXISTS pos_terminals_updated_at ON pos_terminals;
CREATE TRIGGER pos_terminals_updated_at BEFORE UPDATE ON pos_terminals
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION pos_assign_terminal_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'POS-' || LPAD(NEW.id::TEXT, 4, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pos_terminals_assign_code ON pos_terminals;
CREATE TRIGGER pos_terminals_assign_code BEFORE INSERT ON pos_terminals
  FOR EACH ROW EXECUTE FUNCTION pos_assign_terminal_code();

-- ───────────────────────────────────────────────────────────
-- 2) pos_sessions — جلسة الكاشير (فتح/إغلاق صندوق)
--    DECISION: الرصيد الافتتاحي والختامي بالنقد فقط. طرق الدفع
--    الإلكترونية تُحسب من مجاميع pos_payment_splits تلقائيًا.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_sessions (
  id                BIGSERIAL PRIMARY KEY,
  session_no        TEXT UNIQUE,
  terminal_id       BIGINT REFERENCES pos_terminals(id) ON DELETE SET NULL,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  cashier_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  opened_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  opening_float     NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (opening_float >= 0),
  closed_at         TIMESTAMPTZ,
  expected_cash     NUMERIC(10,2),
  actual_cash       NUMERIC(10,2),
  cash_variance     NUMERIC(10,2) GENERATED ALWAYS AS (COALESCE(actual_cash, 0) - COALESCE(expected_cash, 0)) STORED,
  variance_reason   TEXT,
  status            TEXT NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'closed', 'approved')),
  approved_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at       TIMESTAMPTZ,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_sessions_branch_idx  ON pos_sessions(branch_id, opened_at DESC);
CREATE INDEX IF NOT EXISTS pos_sessions_cashier_idx ON pos_sessions(cashier_id, opened_at DESC);
CREATE INDEX IF NOT EXISTS pos_sessions_open_idx    ON pos_sessions(status) WHERE status = 'open';

DROP TRIGGER IF EXISTS pos_sessions_updated_at ON pos_sessions;
CREATE TRIGGER pos_sessions_updated_at BEFORE UPDATE ON pos_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- رقم جلسة تلقائي POS-2026-BR1-00001
CREATE OR REPLACE FUNCTION pos_assign_session_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.session_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM pos_sessions
      WHERE branch_id = NEW.branch_id AND session_no LIKE 'POS-' || v_year || '-BR' || NEW.branch_id || '-%';
    NEW.session_no := 'POS-' || v_year || '-BR' || NEW.branch_id || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pos_sessions_assign_no ON pos_sessions;
CREATE TRIGGER pos_sessions_assign_no BEFORE INSERT ON pos_sessions
  FOR EACH ROW EXECUTE FUNCTION pos_assign_session_no();

-- ───────────────────────────────────────────────────────────
-- 3) pos_transactions — المعاملات (بيع/مرتجع/إلغاء)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_transactions (
  id                 BIGSERIAL PRIMARY KEY,
  transaction_no     TEXT UNIQUE,
  session_id         BIGINT NOT NULL REFERENCES pos_sessions(id) ON DELETE RESTRICT,
  branch_id          BIGINT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  cashier_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  customer_id        BIGINT REFERENCES crm_customers(id) ON DELETE SET NULL,
  type               TEXT NOT NULL DEFAULT 'sale' CHECK (type IN ('sale', 'refund', 'void')),
  channel            TEXT NOT NULL DEFAULT 'dine_in' CHECK (channel IN ('dine_in', 'takeaway', 'delivery')),
  subtotal           NUMERIC(10,2) NOT NULL DEFAULT 0,
  discount_amount    NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  discount_reason    TEXT,
  vat_amount         NUMERIC(10,2) NOT NULL DEFAULT 0,
  total_amount       NUMERIC(10,2) NOT NULL DEFAULT 0,
  refund_of_id       BIGINT REFERENCES pos_transactions(id) ON DELETE SET NULL,
  journal_entry_id   BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  loyalty_txn_id     BIGINT REFERENCES loyalty_transactions(id) ON DELETE SET NULL,
  zatca_qr           TEXT,
  status             TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'completed', 'voided')),
  completed_at       TIMESTAMPTZ,
  voided_at          TIMESTAMPTZ,
  voided_by          BIGINT REFERENCES users(id) ON DELETE SET NULL,
  void_reason        TEXT,
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_txn_session_idx    ON pos_transactions(session_id);
CREATE INDEX IF NOT EXISTS pos_txn_branch_date_idx ON pos_transactions(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pos_txn_customer_idx   ON pos_transactions(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS pos_txn_status_idx     ON pos_transactions(status);

DROP TRIGGER IF EXISTS pos_txn_updated_at ON pos_transactions;
CREATE TRIGGER pos_txn_updated_at BEFORE UPDATE ON pos_transactions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- رقم معاملة تلقائي TXN-2026-00000001
CREATE OR REPLACE FUNCTION pos_assign_transaction_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  BIGINT;
BEGIN
  IF NEW.transaction_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM pos_transactions
      WHERE transaction_no LIKE 'TXN-' || v_year || '-%';
    NEW.transaction_no := 'TXN-' || v_year || '-' || LPAD(v_seq::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pos_txn_assign_no ON pos_transactions;
CREATE TRIGGER pos_txn_assign_no BEFORE INSERT ON pos_transactions
  FOR EACH ROW EXECUTE FUNCTION pos_assign_transaction_no();

-- ───────────────────────────────────────────────────────────
-- 4) pos_transaction_items — بنود المعاملة
--    DECISION: نحفظ snapshot للاسم والسعر (لا نعتمد على menu_items
--    اللي ممكن تتغير أسعارها بعد البيع)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_transaction_items (
  id                  BIGSERIAL PRIMARY KEY,
  transaction_id      BIGINT NOT NULL REFERENCES pos_transactions(id) ON DELETE CASCADE,
  menu_item_id        BIGINT REFERENCES menu_items(id) ON DELETE SET NULL,
  item_name           TEXT NOT NULL,
  item_sku            TEXT,
  quantity            NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price          NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  discount_amount     NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  line_total          NUMERIC(10,2) NOT NULL,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_txn_items_txn_idx ON pos_transaction_items(transaction_id);

-- ───────────────────────────────────────────────────────────
-- 5) pos_payment_splits — طرق الدفع (يدعم الدفع المختلط)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_payment_splits (
  id                BIGSERIAL PRIMARY KEY,
  transaction_id    BIGINT NOT NULL REFERENCES pos_transactions(id) ON DELETE CASCADE,
  method            TEXT NOT NULL CHECK (method IN ('cash', 'card', 'wallet', 'bank_transfer', 'loyalty_points', 'other')),
  amount            NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  reference         TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_payments_txn_idx ON pos_payment_splits(transaction_id);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة إتمام المعاملة (atomic)
-- تفحص الدفعات + تنشئ قيد محاسبي مسودة + تحدّث بيانات العميل
-- (خصم المخزون عبر الوصفة يتم في طبقة JS بعد نجاح هذه الدالة)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION pos_complete_transaction(p_txn_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_txn        RECORD;
  v_paid       NUMERIC;
  v_settings   RECORD;
  v_period_id  BIGINT;
  v_cash_acc   BIGINT;
  v_rev_acc    BIGINT;
  v_vat_acc    BIGINT;
  v_je_id      BIGINT;
  v_net        NUMERIC;
BEGIN
  SELECT * INTO v_txn FROM pos_transactions WHERE id = p_txn_id;
  IF v_txn IS NULL THEN RAISE EXCEPTION 'المعاملة غير موجودة'; END IF;
  IF v_txn.status <> 'draft' THEN RAISE EXCEPTION 'المعاملة أُتمّت بالفعل'; END IF;
  IF v_txn.total_amount <= 0 THEN RAISE EXCEPTION 'الإجمالي صفر — أضف بندًا على الأقل'; END IF;

  -- التحقق من أن مجموع الدفعات >= الإجمالي (الفرق = فكة)
  SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM pos_payment_splits WHERE transaction_id = p_txn_id;
  IF v_paid < v_txn.total_amount THEN
    RAISE EXCEPTION 'مجموع الدفعات (%.2f) أقل من الإجمالي (%.2f)', v_paid, v_txn.total_amount;
  END IF;

  -- توليد QR ZATCA يتم في طبقة JS ثم تحديث الحقل
  -- (لا يمكن استخدام buildZatcaQrBase64 من داخل SQL)

  -- بناء القيد المحاسبي المسودة
  SELECT * INTO v_settings FROM acct_settings WHERE id = 1;
  SELECT id INTO v_cash_acc FROM acct_chart_of_accounts WHERE code = '1101' LIMIT 1;
  SELECT id INTO v_rev_acc  FROM acct_chart_of_accounts WHERE code = '4101' LIMIT 1;
  SELECT id INTO v_vat_acc  FROM acct_chart_of_accounts WHERE code = '2104' LIMIT 1;

  IF v_cash_acc IS NULL OR v_rev_acc IS NULL THEN
    RAISE EXCEPTION 'حسابات القيود المحاسبية غير مُعرَّفة (1101 أو 4101)';
  END IF;

  SELECT id INTO v_period_id FROM acct_periods
    WHERE start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
    LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'لا توجد فترة محاسبية مفتوحة لتاريخ اليوم'; END IF;

  v_net := v_txn.total_amount - v_txn.vat_amount;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-POS-' || v_txn.transaction_no, CURRENT_DATE, v_period_id,
          'قيد بيع POS رقم ' || v_txn.transaction_no,
          'pos_sale', p_txn_id, 'draft', current_app_user_id())
  RETURNING id INTO v_je_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_je_id, 1, v_cash_acc, v_txn.total_amount, 0, 'نقدية — بيع POS');

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_je_id, 2, v_rev_acc, 0, v_net, 'إيرادات مبيعات POS');

  IF v_txn.vat_amount > 0 AND v_vat_acc IS NOT NULL THEN
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_je_id, 3, v_vat_acc, 0, v_txn.vat_amount, 'ضريبة القيمة المضافة - دائن');
  END IF;

  -- تحديث المعاملة
  UPDATE pos_transactions
  SET status = 'completed', completed_at = now(), journal_entry_id = v_je_id
  WHERE id = p_txn_id;

  -- تحديث بيانات العميل لو مربوط
  IF v_txn.customer_id IS NOT NULL THEN
    UPDATE crm_customers
    SET total_orders   = total_orders + 1,
        total_spent    = total_spent + v_txn.total_amount,
        last_order_at  = now(),
        first_order_at = COALESCE(first_order_at, now())
    WHERE id = v_txn.customer_id;
  END IF;

  RETURN v_je_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE pos_terminals            ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sessions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_transactions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_transaction_items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_payment_splits       ENABLE ROW LEVEL SECURITY;

-- الأجهزة: قراءة لكل مصادَق، كتابة للمدير/الأدمن
DROP POLICY IF EXISTS pos_terminals_sel ON pos_terminals;
CREATE POLICY pos_terminals_sel ON pos_terminals FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pos_terminals_wr ON pos_terminals;
CREATE POLICY pos_terminals_wr ON pos_terminals FOR ALL TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager', 'operations_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager', 'operations_manager'));

-- الجلسات: الكاشير يشوف جلساته، المدراء يشوفون كل الجلسات في فروعهم
DROP POLICY IF EXISTS pos_sessions_sel ON pos_sessions;
CREATE POLICY pos_sessions_sel ON pos_sessions FOR SELECT TO authenticated USING (
  cashier_id = current_app_user_id()
  OR current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager')
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = pos_sessions.branch_id AND u.role IN ('branch_manager', 'deputy_manager'))
);
DROP POLICY IF EXISTS pos_sessions_ins ON pos_sessions;
CREATE POLICY pos_sessions_ins ON pos_sessions FOR INSERT TO authenticated
  WITH CHECK (cashier_id = current_app_user_id());
DROP POLICY IF EXISTS pos_sessions_upd ON pos_sessions;
CREATE POLICY pos_sessions_upd ON pos_sessions FOR UPDATE TO authenticated USING (
  cashier_id = current_app_user_id()
  OR current_app_role() IN ('admin', 'company_manager', 'operations_manager')
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = pos_sessions.branch_id AND u.role IN ('branch_manager', 'deputy_manager'))
);

-- المعاملات: نفس نمط الجلسات
DROP POLICY IF EXISTS pos_txn_sel ON pos_transactions;
CREATE POLICY pos_txn_sel ON pos_transactions FOR SELECT TO authenticated USING (
  cashier_id = current_app_user_id()
  OR current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager', 'gl_accountant')
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = pos_transactions.branch_id AND u.role IN ('branch_manager', 'deputy_manager'))
);
DROP POLICY IF EXISTS pos_txn_ins ON pos_transactions;
CREATE POLICY pos_txn_ins ON pos_transactions FOR INSERT TO authenticated
  WITH CHECK (cashier_id = current_app_user_id());
DROP POLICY IF EXISTS pos_txn_upd ON pos_transactions;
CREATE POLICY pos_txn_upd ON pos_transactions FOR UPDATE TO authenticated USING (
  cashier_id = current_app_user_id()
  OR current_app_role() IN ('admin', 'company_manager', 'operations_manager')
);

-- بنود المعاملة والدفعات: يتبعن صلاحية المعاملة الأم
DROP POLICY IF EXISTS pos_txn_items_sel ON pos_transaction_items;
CREATE POLICY pos_txn_items_sel ON pos_transaction_items FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_transaction_items.transaction_id
          AND (t.cashier_id = current_app_user_id()
               OR current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager', 'gl_accountant')))
);
DROP POLICY IF EXISTS pos_txn_items_wr ON pos_transaction_items;
CREATE POLICY pos_txn_items_wr ON pos_transaction_items FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_transaction_items.transaction_id
          AND t.cashier_id = current_app_user_id() AND t.status = 'draft')
) WITH CHECK (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_transaction_items.transaction_id
          AND t.cashier_id = current_app_user_id() AND t.status = 'draft')
);

DROP POLICY IF EXISTS pos_payments_sel ON pos_payment_splits;
CREATE POLICY pos_payments_sel ON pos_payment_splits FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_payment_splits.transaction_id
          AND (t.cashier_id = current_app_user_id()
               OR current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager', 'gl_accountant')))
);
DROP POLICY IF EXISTS pos_payments_wr ON pos_payment_splits;
CREATE POLICY pos_payments_wr ON pos_payment_splits FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_payment_splits.transaction_id
          AND t.cashier_id = current_app_user_id() AND t.status = 'draft')
) WITH CHECK (
  EXISTS (SELECT 1 FROM pos_transactions t WHERE t.id = pos_payment_splits.transaction_id
          AND t.cashier_id = current_app_user_id() AND t.status = 'draft')
);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM pos_terminals LIMIT 1;
-- 2) SELECT * FROM pos_sessions LIMIT 1;
-- 3) SELECT * FROM pos_transactions LIMIT 1;
-- 4) SELECT proname FROM pg_proc WHERE proname = 'pos_complete_transaction';
-- 5) SELECT conname FROM pg_constraint WHERE conname = 'acct_journal_entries_source_type_check';
-- ═══════════════════════════════════════════════════════════
