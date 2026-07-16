-- ═══════════════════════════════════════════════════════════
-- المدفوعات والمقاصات — المرحلة P1: الشركاء الماليون والعقود
-- ═══════════════════════════════════════════════════════════
-- النطاق: pay_partners + pay_partner_contracts + حقول "من استلم
-- المبلغ" على ops_orders. محرك العمولات في P1 يُحسب في طبقة JS
-- على الطاير (قابل للتفسير)، والتخزين الدائم لنتائج العمولات يبدأ
-- في P3 مع المقاصة.
-- يعتمد على: is_accounting_role()، is_finance_manager()،
-- current_app_user_id()، set_updated_at() — كلها موجودة من موديول
-- الحسابات. التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) pay_partners — الأطراف المالية (منصات توصيل، بوابات دفع...)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_partners (
  id             BIGSERIAL PRIMARY KEY,
  code           TEXT UNIQUE,
  name           TEXT NOT NULL,
  partner_type   TEXT NOT NULL CHECK (partner_type IN
                   ('delivery_platform',   -- منصة طلبات وتوصيل (تحصّل من العميل)
                    'delivery_company',    -- شركة توصيل لوجستية فقط
                    'payment_gateway',     -- بوابة دفع إلكتروني
                    'restaurant_owner',    -- مالك مطعم مُدار للغير
                    'other')),
  legal_name     TEXT,
  tax_number     TEXT,
  contact_name   TEXT,
  phone          TEXT,
  email          TEXT,
  bank_name      TEXT,
  iban           TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  notes          TEXT,
  created_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS pay_partners_type_idx   ON pay_partners(partner_type) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS pay_partners_active_idx ON pay_partners(is_active) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS pay_partners_updated_at ON pay_partners;
CREATE TRIGGER pay_partners_updated_at BEFORE UPDATE ON pay_partners
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- كود تلقائي PRT-00001
CREATE OR REPLACE FUNCTION pay_assign_partner_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'PRT-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pay_partners_assign_code ON pay_partners;
CREATE TRIGGER pay_partners_assign_code BEFORE INSERT ON pay_partners
  FOR EACH ROW EXECUTE FUNCTION pay_assign_partner_code();

-- ───────────────────────────────────────────────────────────
-- 2) pay_partner_contracts — عقود الشركاء (كل صف "إصدار" بتاريخ سريان)
--    DECISION: لا يُعدَّل عقد ساري ماليًا — يُنشأ إصدار جديد بتاريخ
--    سريان لاحق، ومحرك العمولات يختار الإصدار الساري في تاريخ الطلب.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pay_partner_contracts (
  id                 BIGSERIAL PRIMARY KEY,
  partner_id         BIGINT NOT NULL REFERENCES pay_partners(id) ON DELETE CASCADE,
  contract_no        TEXT,
  -- أساس العمولة: صافي المنتجات (الافتراضي المؤسسي) أو إجمالي الطلب
  commission_basis   TEXT NOT NULL DEFAULT 'net_products'
                       CHECK (commission_basis IN ('net_products', 'gross_order')),
  commission_type    TEXT NOT NULL DEFAULT 'percentage'
                       CHECK (commission_type IN ('percentage', 'fixed_per_order', 'percentage_plus_fixed')),
  commission_rate    NUMERIC(6,3) NOT NULL DEFAULT 0 CHECK (commission_rate >= 0 AND commission_rate <= 100),
  fixed_fee          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (fixed_fee >= 0),
  min_fee            NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (min_fee >= 0),
  -- من يتحمل رسوم التوصيل التي دفعها العميل
  delivery_fee_owner TEXT NOT NULL DEFAULT 'partner'
                       CHECK (delivery_fee_owner IN ('partner', 'restaurant', 'customer')),
  settlement_cycle   TEXT NOT NULL DEFAULT 'weekly'
                       CHECK (settlement_cycle IN ('weekly', 'biweekly', 'monthly')),
  effective_from     DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to       DATE,
  status             TEXT NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft', 'active', 'expired', 'cancelled')),
  notes              TEXT,
  created_by         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT pay_contract_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE INDEX IF NOT EXISTS pay_contracts_partner_idx ON pay_partner_contracts(partner_id, effective_from DESC);
CREATE INDEX IF NOT EXISTS pay_contracts_active_idx  ON pay_partner_contracts(status) WHERE status = 'active';

DROP TRIGGER IF EXISTS pay_contracts_updated_at ON pay_partner_contracts;
CREATE TRIGGER pay_contracts_updated_at BEFORE UPDATE ON pay_partner_contracts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) ops_orders — السؤال الحاسم لكل طلب: من استلم المبلغ؟
--    إضافة غير كاسرة: أعمدة جديدة بقيم افتراضية، بلا تعديل لأي
--    منطق قائم. funds_holder الافتراضي 'branch' (الفرع حصّل بنفسه).
-- ───────────────────────────────────────────────────────────
ALTER TABLE ops_orders
  ADD COLUMN IF NOT EXISTS funds_holder TEXT NOT NULL DEFAULT 'branch'
    CHECK (funds_holder IN ('branch', 'delivery_platform', 'delivery_company', 'payment_gateway', 'driver')),
  ADD COLUMN IF NOT EXISTS pay_partner_id BIGINT REFERENCES pay_partners(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ops_orders_pay_partner_idx ON ops_orders(pay_partner_id) WHERE pay_partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ops_orders_funds_holder_idx ON ops_orders(funds_holder) WHERE funds_holder != 'branch';

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE pay_partners          ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_partner_contracts ENABLE ROW LEVEL SECURITY;

-- قراءة لكل أدوار المحاسبة، كتابة للمدير المالي فقط (نفس نمط acct_vendors)
DROP POLICY IF EXISTS pay_partners_sel ON pay_partners;
CREATE POLICY pay_partners_sel ON pay_partners FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_partners_wr ON pay_partners;
CREATE POLICY pay_partners_wr ON pay_partners FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS pay_contracts_sel ON pay_partner_contracts;
CREATE POLICY pay_contracts_sel ON pay_partner_contracts FOR SELECT TO authenticated USING (is_accounting_role());
DROP POLICY IF EXISTS pay_contracts_wr ON pay_partner_contracts;
CREATE POLICY pay_contracts_wr ON pay_partner_contracts FOR ALL TO authenticated
  USING (is_finance_manager()) WITH CHECK (is_finance_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ (Post-migration checklist):
-- 1) SELECT * FROM pay_partners LIMIT 1;
-- 2) SELECT * FROM pay_partner_contracts LIMIT 1;
-- 3) SELECT funds_holder, pay_partner_id FROM ops_orders LIMIT 1;
-- 4) SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'pay_%' AND relkind='r';
-- ═══════════════════════════════════════════════════════════
