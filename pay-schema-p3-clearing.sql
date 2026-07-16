-- ═══════════════════════════════════════════════════════════
-- المدفوعات والمقاصات — المرحلة P3: المقاصة والتسويات والتحويلات
-- ═══════════════════════════════════════════════════════════
-- دفعات مقاصة دورية لكل شريك: تجميع الكشوف المعتمدة → صافي واحد →
-- اعتماد → تسجيل التحويل البنكي (بإثبات) → قيد محاسبي مسودة اختياري.
-- DECISION (اتجاه الصافي): net_receivable موجب = مستحق لنا على
-- الشريك (هو حصّل من العملاء ويحوّل لنا). سالب = مستحق للشريك علينا.
-- يعتمد على: pay-schema-p2-statements.sql. التنفيذ آمن ومتكرر.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) pay_clearing_batches — دفعة مقاصة لشريك عن فترة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_clearing_batches (
  id                BIGSERIAL PRIMARY KEY,
  batch_no          TEXT UNIQUE,
  partner_id        BIGINT NOT NULL REFERENCES pay_partners(id) ON DELETE CASCADE,
  period_start      DATE NOT NULL,
  period_end        DATE NOT NULL,
  status            TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'calculated', 'approved', 'settled', 'cancelled')),
  gross_total       NUMERIC(14,2) NOT NULL DEFAULT 0,
  fees_total        NUMERIC(14,2) NOT NULL DEFAULT 0,
  adjustments_total NUMERIC(14,2) NOT NULL DEFAULT 0,
  net_receivable    NUMERIC(14,2) NOT NULL DEFAULT 0,
  calculated_at     TIMESTAMPTZ,
  approved_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at       TIMESTAMPTZ,
  notes             TEXT,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT pay_clearing_period CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS pay_clearing_partner_idx ON pay_clearing_batches(partner_id, period_start DESC);
CREATE INDEX IF NOT EXISTS pay_clearing_status_idx  ON pay_clearing_batches(status);

DROP TRIGGER IF EXISTS pay_clearing_updated_at ON pay_clearing_batches;
CREATE TRIGGER pay_clearing_updated_at BEFORE UPDATE ON pay_clearing_batches
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION pay_assign_batch_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.batch_no IS NULL THEN NEW.batch_no := 'CLR-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pay_clearing_assign_no ON pay_clearing_batches;
CREATE TRIGGER pay_clearing_assign_no BEFORE INSERT ON pay_clearing_batches
  FOR EACH ROW EXECUTE FUNCTION pay_assign_batch_no();

-- ربط الكشف بدفعة المقاصة (تم تعريف العمود في P2 — هنا القيد المرجعي)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pay_statements_cleared_fkey') THEN
    ALTER TABLE pay_statements
      ADD CONSTRAINT pay_statements_cleared_fkey
      FOREIGN KEY (cleared_batch_id) REFERENCES pay_clearing_batches(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────
-- 2) pay_clearing_items — بنود الدفعة (كل بند بمرجعه)
--    المبلغ مُوقَّع: موجب = لنا على الشريك، سالب = علينا للشريك
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_clearing_items (
  id            BIGSERIAL PRIMARY KEY,
  batch_id      BIGINT NOT NULL REFERENCES pay_clearing_batches(id) ON DELETE CASCADE,
  source_type   TEXT NOT NULL CHECK (source_type IN ('statement', 'adjustment')),
  statement_id  BIGINT REFERENCES pay_statements(id) ON DELETE SET NULL,
  description   TEXT NOT NULL,
  amount        NUMERIC(14,2) NOT NULL,
  created_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pay_clearing_items_batch_idx ON pay_clearing_items(batch_id);

-- ───────────────────────────────────────────────────────────
-- 3) pay_payouts — التحويلات المرتبطة بالتسوية (بإثبات بنكي)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_payouts (
  id               BIGSERIAL PRIMARY KEY,
  batch_id         BIGINT NOT NULL REFERENCES pay_clearing_batches(id) ON DELETE CASCADE,
  partner_id       BIGINT NOT NULL REFERENCES pay_partners(id) ON DELETE CASCADE,
  direction        TEXT NOT NULL CHECK (direction IN ('incoming', 'outgoing')),
  amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  bank_account_id  BIGINT REFERENCES acct_bank_accounts(id) ON DELETE SET NULL,
  bank_ref         TEXT,
  payout_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  status           TEXT NOT NULL DEFAULT 'confirmed'
                     CHECK (status IN ('pending', 'confirmed', 'failed')),
  journal_entry_id BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes            TEXT,
  created_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pay_payouts_batch_idx ON pay_payouts(batch_id);

-- السماح بمصدر قيود جديد: pay_settlement
ALTER TABLE acct_journal_entries DROP CONSTRAINT IF EXISTS acct_journal_entries_source_type_check;
ALTER TABLE acct_journal_entries ADD CONSTRAINT acct_journal_entries_source_type_check
  CHECK (source_type IN ('manual', 'hr_payroll', 'bill', 'invoice', 'payment', 'receipt', 'cafe_order', 'depreciation', 'closing', 'opening', 'reversal', 'ops_order', 'pay_settlement'));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE pay_clearing_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_clearing_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_payouts          ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pay_clearing_sel ON pay_clearing_batches;
CREATE POLICY pay_clearing_sel ON pay_clearing_batches FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_clearing_wr ON pay_clearing_batches;
CREATE POLICY pay_clearing_wr ON pay_clearing_batches FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS pay_clr_items_sel ON pay_clearing_items;
CREATE POLICY pay_clr_items_sel ON pay_clearing_items FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_clr_items_wr ON pay_clearing_items;
CREATE POLICY pay_clr_items_wr ON pay_clearing_items FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS pay_payouts_sel ON pay_payouts;
CREATE POLICY pay_payouts_sel ON pay_payouts FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_payouts_wr ON pay_payouts;
CREATE POLICY pay_payouts_wr ON pay_payouts FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM pay_clearing_batches LIMIT 1;
-- 2) SELECT * FROM pay_clearing_items LIMIT 1;
-- 3) SELECT * FROM pay_payouts LIMIT 1;
-- 4) SELECT conname FROM pg_constraint WHERE conname = 'pay_statements_cleared_fkey';
-- ═══════════════════════════════════════════════════════════
