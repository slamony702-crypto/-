-- ═══════════════════════════════════════════════════════════
-- المدفوعات والمقاصات — المرحلة P2: كشوف الشركاء والمطابقة
-- ═══════════════════════════════════════════════════════════
-- كشوف تسوية الشركاء (استيراد CSV أو إدخال يدوي) + بنودها + مطابقتها
-- مع طلبات المطعم (ops_orders). محرك المطابقة يعمل في طبقة JS
-- (تطابق بالمرجع أولًا ثم بالمبلغ والتاريخ)، والنتائج تُخزَّن هنا.
-- يعتمد على: pay-schema-p1-partners.sql. التنفيذ آمن ومتكرر.
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) pay_statements — كشف تسوية من شريك عن فترة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_statements (
  id             BIGSERIAL PRIMARY KEY,
  partner_id     BIGINT NOT NULL REFERENCES pay_partners(id) ON DELETE CASCADE,
  statement_no   TEXT,
  period_start   DATE NOT NULL,
  period_end     DATE NOT NULL,
  source         TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'csv')),
  gross_total    NUMERIC(14,2) NOT NULL DEFAULT 0,
  fees_total     NUMERIC(14,2) NOT NULL DEFAULT 0,
  net_total      NUMERIC(14,2) NOT NULL DEFAULT 0,
  status         TEXT NOT NULL DEFAULT 'imported'
                   CHECK (status IN ('imported', 'reconciling', 'reconciled', 'approved', 'cancelled')),
  -- يُملأ في P3 عند دخول الكشف في دفعة مقاصة (يمنع استخدامه مرتين)
  cleared_batch_id BIGINT,
  notes          TEXT,
  created_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT pay_statement_period CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS pay_statements_partner_idx ON pay_statements(partner_id, period_start DESC);
CREATE INDEX IF NOT EXISTS pay_statements_status_idx  ON pay_statements(status);

DROP TRIGGER IF EXISTS pay_statements_updated_at ON pay_statements;
CREATE TRIGGER pay_statements_updated_at BEFORE UPDATE ON pay_statements
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) pay_statement_lines — بنود الكشف (طلب بطلب)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_statement_lines (
  id                  BIGSERIAL PRIMARY KEY,
  statement_id        BIGINT NOT NULL REFERENCES pay_statements(id) ON DELETE CASCADE,
  external_order_ref  TEXT,                          -- مرجع الطلب لدى الشريك
  order_date          DATE,
  gross_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  commission_fee      NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_fee        NUMERIC(12,2) NOT NULL DEFAULT 0,
  other_fee           NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  matched_order_id    BIGINT REFERENCES ops_orders(id) ON DELETE SET NULL,
  match_status        TEXT NOT NULL DEFAULT 'unmatched'
                        CHECK (match_status IN ('unmatched', 'matched', 'exception')),
  exception_reason    TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pay_stmt_lines_stmt_idx  ON pay_statement_lines(statement_id);
CREATE INDEX IF NOT EXISTS pay_stmt_lines_match_idx ON pay_statement_lines(match_status) WHERE match_status != 'matched';

-- ───────────────────────────────────────────────────────────
-- 3) سياسة قراءة إضافية على ops_orders لأدوار المحاسبة
--    المطابقة تحتاج قراءة الطلبات، وأدوار المحاسبة ليست ضمن سياسات
--    التشغيل الحالية. سياسة إضافية (OR) — لا تعدل أي سياسة قائمة.
-- ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS ops_orders_acct_read ON ops_orders;
CREATE POLICY ops_orders_acct_read ON ops_orders FOR SELECT TO authenticated
  USING (is_accounting_role());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE pay_statements      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_statement_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pay_statements_sel ON pay_statements;
CREATE POLICY pay_statements_sel ON pay_statements FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_statements_wr ON pay_statements;
CREATE POLICY pay_statements_wr ON pay_statements FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS pay_stmt_lines_sel ON pay_statement_lines;
CREATE POLICY pay_stmt_lines_sel ON pay_statement_lines FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_stmt_lines_wr ON pay_statement_lines;
CREATE POLICY pay_stmt_lines_wr ON pay_statement_lines FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM pay_statements LIMIT 1;
-- 2) SELECT * FROM pay_statement_lines LIMIT 1;
-- 3) SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'pay_%' AND relkind='r';
-- ═══════════════════════════════════════════════════════════
