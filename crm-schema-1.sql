-- ═══════════════════════════════════════════════════════════
-- إدارة العملاء والولاء (CRM & Loyalty) — Wave 1 Module 25
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: العملاء + عناوينهم + حسابات النقاط + حركات النقاط + الشكاوى
-- + Trigger لتحديث رصيد النقاط تلقائيًا من الحركات
-- + Trigger لتوليد أكواد تلقائية (CUS-00001, CMP-2026-00001)
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير CRM (admin أو company_manager أو operations)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_crm_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) crm_customers — قاعدة العملاء الأساسية
--    DECISION: العلاقة بين العميل والطلب (ops_orders) هتُضاف عند
--    بناء POS في المرحلة القادمة — الآن نبني القاعدة نظيفة.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_customers (
  id                BIGSERIAL PRIMARY KEY,
  code              TEXT UNIQUE,
  full_name         TEXT NOT NULL,
  phone             TEXT,
  email             TEXT,
  birth_date        DATE,
  gender            TEXT CHECK (gender IN ('male', 'female') OR gender IS NULL),
  preferences       TEXT,
  allergies         TEXT,
  notes             TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  segment           TEXT NOT NULL DEFAULT 'new'
                     CHECK (segment IN ('vip', 'regular', 'inactive', 'new')),
  first_order_at    TIMESTAMPTZ,
  last_order_at     TIMESTAMPTZ,
  total_orders      INT NOT NULL DEFAULT 0,
  total_spent       NUMERIC(12,2) NOT NULL DEFAULT 0,
  source            TEXT,
  marketing_consent BOOLEAN NOT NULL DEFAULT FALSE,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS crm_customers_phone_idx    ON crm_customers(phone) WHERE deleted_at IS NULL AND phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS crm_customers_segment_idx  ON crm_customers(segment) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS crm_customers_active_idx   ON crm_customers(is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS crm_customers_last_order_idx ON crm_customers(last_order_at DESC NULLS LAST) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS crm_customers_updated_at ON crm_customers;
CREATE TRIGGER crm_customers_updated_at BEFORE UPDATE ON crm_customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- كود تلقائي CUS-00001
CREATE OR REPLACE FUNCTION crm_assign_customer_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'CUS-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_customers_assign_code ON crm_customers;
CREATE TRIGGER crm_customers_assign_code BEFORE INSERT ON crm_customers
  FOR EACH ROW EXECUTE FUNCTION crm_assign_customer_code();

-- ───────────────────────────────────────────────────────────
-- 2) crm_customer_addresses — عناوين متعددة لكل عميل
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_customer_addresses (
  id               BIGSERIAL PRIMARY KEY,
  customer_id      BIGINT NOT NULL REFERENCES crm_customers(id) ON DELETE CASCADE,
  label            TEXT NOT NULL DEFAULT 'المنزل',
  city             TEXT,
  district         TEXT,
  street           TEXT,
  building         TEXT,
  additional_info  TEXT,
  latitude         NUMERIC(10,7),
  longitude        NUMERIC(10,7),
  is_default       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS crm_addresses_customer_idx ON crm_customer_addresses(customer_id);

-- إضافة updated_at لجداول قديمة تركّبت قبل هذا التحديث (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'crm_customer_addresses' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE crm_customer_addresses ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
  END IF;
END $$;

DROP TRIGGER IF EXISTS crm_addresses_updated_at ON crm_customer_addresses;
CREATE TRIGGER crm_addresses_updated_at BEFORE UPDATE ON crm_customer_addresses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- partial unique: عنوان افتراضي واحد لكل عميل
CREATE UNIQUE INDEX IF NOT EXISTS crm_addresses_default_uniq
  ON crm_customer_addresses (customer_id)
  WHERE is_default = TRUE;

-- ───────────────────────────────────────────────────────────
-- 3) loyalty_accounts — حساب نقاط لكل عميل (1:1)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_accounts (
  id               BIGSERIAL PRIMARY KEY,
  customer_id      BIGINT UNIQUE NOT NULL REFERENCES crm_customers(id) ON DELETE CASCADE,
  tier             TEXT NOT NULL DEFAULT 'bronze'
                    CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum')),
  points_balance   NUMERIC(10,2) NOT NULL DEFAULT 0,
  lifetime_points  NUMERIC(10,2) NOT NULL DEFAULT 0,
  tier_since       DATE NOT NULL DEFAULT CURRENT_DATE,
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS loyalty_accounts_tier_idx ON loyalty_accounts(tier);

DROP TRIGGER IF EXISTS loyalty_accounts_updated_at ON loyalty_accounts;
CREATE TRIGGER loyalty_accounts_updated_at BEFORE UPDATE ON loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 4) loyalty_transactions — كل حركة نقاط (اكتساب/استبدال)
--    DECISION: points مُوقَّع — earn موجب، redeem سالب.
--    trigger يحدّث الرصيد تلقائيًا من الحركات (مصدر الحقيقة الوحيد).
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_transactions (
  id           BIGSERIAL PRIMARY KEY,
  account_id   BIGINT NOT NULL REFERENCES loyalty_accounts(id) ON DELETE CASCADE,
  type         TEXT NOT NULL CHECK (type IN ('earn', 'redeem', 'adjustment', 'expiry')),
  points       NUMERIC(10,2) NOT NULL,
  description  TEXT,
  reference    TEXT,
  created_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS loyalty_txn_account_idx ON loyalty_transactions(account_id, created_at DESC);

-- تحديث رصيد النقاط تلقائيًا من كل حركة
CREATE OR REPLACE FUNCTION loyalty_apply_transaction()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE loyalty_accounts
  SET points_balance  = points_balance + NEW.points,
      lifetime_points = lifetime_points + GREATEST(NEW.points, 0),
      updated_at      = now()
  WHERE id = NEW.account_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS loyalty_txn_applies ON loyalty_transactions;
CREATE TRIGGER loyalty_txn_applies AFTER INSERT ON loyalty_transactions
  FOR EACH ROW EXECUTE FUNCTION loyalty_apply_transaction();

-- ───────────────────────────────────────────────────────────
-- 5) crm_complaints — شكاوى العملاء
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_complaints (
  id                  BIGSERIAL PRIMARY KEY,
  complaint_no        TEXT UNIQUE,
  customer_id         BIGINT REFERENCES crm_customers(id) ON DELETE SET NULL,
  channel             TEXT NOT NULL
                       CHECK (channel IN ('phone', 'whatsapp', 'website', 'app', 'social', 'in_person', 'other')),
  category            TEXT NOT NULL
                       CHECK (category IN ('food_quality', 'service', 'delivery', 'pricing', 'cleanliness', 'staff', 'other')),
  severity            TEXT NOT NULL DEFAULT 'medium'
                       CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  title               TEXT NOT NULL,
  description         TEXT,
  status              TEXT NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open', 'in_progress', 'resolved', 'closed', 'escalated')),
  assigned_to         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  resolution          TEXT,
  compensation        TEXT,
  resolved_at         TIMESTAMPTZ,
  satisfaction_rating INT CHECK (satisfaction_rating BETWEEN 1 AND 5),
  branch_id           BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  created_by          BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS crm_complaints_status_idx    ON crm_complaints(status) WHERE status IN ('open', 'in_progress', 'escalated');
CREATE INDEX IF NOT EXISTS crm_complaints_severity_idx  ON crm_complaints(severity);
CREATE INDEX IF NOT EXISTS crm_complaints_customer_idx  ON crm_complaints(customer_id);
CREATE INDEX IF NOT EXISTS crm_complaints_assigned_idx  ON crm_complaints(assigned_to);

DROP TRIGGER IF EXISTS crm_complaints_updated_at ON crm_complaints;
CREATE TRIGGER crm_complaints_updated_at BEFORE UPDATE ON crm_complaints
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- رقم شكوى تلقائي CMP-2026-00001
CREATE OR REPLACE FUNCTION crm_assign_complaint_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.complaint_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM crm_complaints WHERE complaint_no LIKE 'CMP-' || v_year || '-%';
    NEW.complaint_no := 'CMP-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_complaints_assign_no ON crm_complaints;
CREATE TRIGGER crm_complaints_assign_no BEFORE INSERT ON crm_complaints
  FOR EACH ROW EXECUTE FUNCTION crm_assign_complaint_no();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE crm_customers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_customer_addresses   ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_accounts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_complaints           ENABLE ROW LEVEL SECURITY;

-- العملاء والعناوين: قراءة لكل مصادَق (POS يقرأ)، كتابة لمدير CRM
DROP POLICY IF EXISTS crm_customers_sel ON crm_customers;
CREATE POLICY crm_customers_sel ON crm_customers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS crm_customers_wr ON crm_customers;
CREATE POLICY crm_customers_wr ON crm_customers FOR ALL TO authenticated
  USING (is_crm_manager()) WITH CHECK (is_crm_manager());

DROP POLICY IF EXISTS crm_addresses_sel ON crm_customer_addresses;
CREATE POLICY crm_addresses_sel ON crm_customer_addresses FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS crm_addresses_wr ON crm_customer_addresses;
CREATE POLICY crm_addresses_wr ON crm_customer_addresses FOR ALL TO authenticated
  USING (is_crm_manager()) WITH CHECK (is_crm_manager());

-- حسابات النقاط: قراءة عامة (POS يعرض الرصيد)، إنشاء عبر إدارة CRM
DROP POLICY IF EXISTS loyalty_accounts_sel ON loyalty_accounts;
CREATE POLICY loyalty_accounts_sel ON loyalty_accounts FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS loyalty_accounts_wr ON loyalty_accounts;
CREATE POLICY loyalty_accounts_wr ON loyalty_accounts FOR ALL TO authenticated
  USING (is_crm_manager()) WITH CHECK (is_crm_manager());

-- حركات النقاط: قراءة لكل مصادَق، إنشاء عبر إدارة CRM
-- DECISION: لا UPDATE ولا DELETE — سجل النقاط ثابت (مصدر الحقيقة)
DROP POLICY IF EXISTS loyalty_txn_sel ON loyalty_transactions;
CREATE POLICY loyalty_txn_sel ON loyalty_transactions FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS loyalty_txn_ins ON loyalty_transactions;
CREATE POLICY loyalty_txn_ins ON loyalty_transactions FOR INSERT TO authenticated
  WITH CHECK (is_crm_manager());

-- الشكاوى: قراءة عامة (كل موظف يشوف شكاوى فرعه/قسمه)، كتابة عبر CRM
DROP POLICY IF EXISTS crm_complaints_sel ON crm_complaints;
CREATE POLICY crm_complaints_sel ON crm_complaints FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS crm_complaints_wr ON crm_complaints;
CREATE POLICY crm_complaints_wr ON crm_complaints FOR ALL TO authenticated
  USING (is_crm_manager() OR
         (assigned_to = current_app_user_id()))  -- المسؤول عن الشكوى يقدر يحدثها
  WITH CHECK (is_crm_manager() OR
              (assigned_to = current_app_user_id()));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM crm_customers LIMIT 1;
-- 2) SELECT * FROM loyalty_accounts LIMIT 1;
-- 3) SELECT * FROM loyalty_transactions LIMIT 1;
-- 4) SELECT * FROM crm_complaints LIMIT 1;
-- 5) SELECT relname, relrowsecurity FROM pg_class
--    WHERE relname LIKE 'crm_%' OR relname LIKE 'loyalty_%';
-- ═══════════════════════════════════════════════════════════
