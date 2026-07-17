-- ═══════════════════════════════════════════════════════════
-- الامتياز التجاري Franchise — Phase 1 (Wave 4 Module 35)
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: شركاء + عقود + فروع الفرنشايز + تقارير مبيعات + فواتير روياليتي
-- + دالة franchise_compute_royalty() لحساب ذرّي:
--   استلام تقرير المبيعات → توليد فاتورة روياليتي في AR تلقائيًا
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير الفرنشايز
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_franchise_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'franchise_manager', 'finance_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) franchise_partners — الشركاء (external companies/persons)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_partners (
  id                    BIGSERIAL PRIMARY KEY,
  partner_no            TEXT UNIQUE,
  company_name          TEXT NOT NULL,
  legal_representative  TEXT,
  commercial_reg_no     TEXT,
  vat_number            TEXT,
  phone                 TEXT,
  email                 TEXT,
  address               TEXT,
  city                  TEXT,
  region                TEXT,
  country               TEXT DEFAULT 'SA',
  status                TEXT NOT NULL DEFAULT 'prospect'
                         CHECK (status IN ('prospect', 'onboarding', 'active', 'suspended', 'terminated')),
  onboarded_at          DATE,
  ar_customer_id        BIGINT REFERENCES acct_customers(id) ON DELETE SET NULL,
  notes                 TEXT,
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS franchise_partners_status_idx ON franchise_partners(status) WHERE status IN ('active', 'onboarding');

DROP TRIGGER IF EXISTS franchise_partners_updated_at ON franchise_partners;
CREATE TRIGGER franchise_partners_updated_at BEFORE UPDATE ON franchise_partners
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION franchise_assign_partner_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_seq INT;
BEGIN
  IF NEW.partner_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM franchise_partners WHERE partner_no LIKE 'FR-%';
    NEW.partner_no := 'FR-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS franchise_partners_assign_no ON franchise_partners;
CREATE TRIGGER franchise_partners_assign_no BEFORE INSERT ON franchise_partners
  FOR EACH ROW EXECUTE FUNCTION franchise_assign_partner_no();

-- ───────────────────────────────────────────────────────────
-- 2) franchise_agreements — عقود الامتياز
--    DECISION: royalty_pct نسبة مئوية من المبيعات الشهرية،
--    marketing_pct نسبة إضافية لصندوق التسويق المشترك.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_agreements (
  id                        BIGSERIAL PRIMARY KEY,
  agreement_no              TEXT UNIQUE,
  partner_id                BIGINT NOT NULL REFERENCES franchise_partners(id) ON DELETE RESTRICT,
  agreement_type            TEXT NOT NULL DEFAULT 'single_unit'
                             CHECK (agreement_type IN ('single_unit', 'multi_unit', 'area_development', 'master')),
  start_date                DATE NOT NULL,
  end_date                  DATE NOT NULL,
  initial_franchise_fee     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (initial_franchise_fee >= 0),
  royalty_pct               NUMERIC(5,2) NOT NULL DEFAULT 5 CHECK (royalty_pct >= 0 AND royalty_pct <= 100),
  marketing_pct             NUMERIC(5,2) NOT NULL DEFAULT 2 CHECK (marketing_pct >= 0 AND marketing_pct <= 100),
  min_monthly_royalty       NUMERIC(12,2) DEFAULT 0,
  territory                 TEXT,
  units_allowed             INT DEFAULT 1 CHECK (units_allowed >= 1),
  status                    TEXT NOT NULL DEFAULT 'draft'
                             CHECK (status IN ('draft', 'active', 'expired', 'terminated', 'renewed')),
  signed_at                 TIMESTAMPTZ,
  signed_by                 BIGINT REFERENCES users(id) ON DELETE SET NULL,
  contract_url              TEXT,
  notes                     TEXT,
  created_at                TIMESTAMPTZ DEFAULT now(),
  updated_at                TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT franchise_agr_dates CHECK (end_date > start_date)
);

CREATE INDEX IF NOT EXISTS franchise_agr_partner_idx ON franchise_agreements(partner_id);
CREATE INDEX IF NOT EXISTS franchise_agr_status_idx  ON franchise_agreements(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS franchise_agr_expiry_idx  ON franchise_agreements(end_date) WHERE status = 'active';

DROP TRIGGER IF EXISTS franchise_agr_updated_at ON franchise_agreements;
CREATE TRIGGER franchise_agr_updated_at BEFORE UPDATE ON franchise_agreements
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION franchise_assign_agr_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.agreement_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM franchise_agreements WHERE agreement_no LIKE 'FRA-' || v_year || '-%';
    NEW.agreement_no := 'FRA-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS franchise_agr_assign_no ON franchise_agreements;
CREATE TRIGGER franchise_agr_assign_no BEFORE INSERT ON franchise_agreements
  FOR EACH ROW EXECUTE FUNCTION franchise_assign_agr_no();

-- ───────────────────────────────────────────────────────────
-- 3) franchise_branches — فروع تابعة للفرنشايز
--    DECISION: ممكن ربطه بـ branches (فرع نظامي داخلي) أو مستقل
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_branches (
  id              BIGSERIAL PRIMARY KEY,
  agreement_id    BIGINT NOT NULL REFERENCES franchise_agreements(id) ON DELETE CASCADE,
  branch_id       BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  name            TEXT NOT NULL,
  city            TEXT,
  address         TEXT,
  opened_at       DATE,
  status          TEXT NOT NULL DEFAULT 'planning'
                   CHECK (status IN ('planning', 'construction', 'opened', 'closed', 'suspended')),
  monthly_target  NUMERIC(12,2),
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS franchise_br_agr_idx ON franchise_branches(agreement_id);
CREATE INDEX IF NOT EXISTS franchise_br_status_idx ON franchise_branches(status) WHERE status = 'opened';

DROP TRIGGER IF EXISTS franchise_br_updated_at ON franchise_branches;
CREATE TRIGGER franchise_br_updated_at BEFORE UPDATE ON franchise_branches
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 4) franchise_sales_reports — تقارير مبيعات شهرية من الفرنشايزي
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_sales_reports (
  id                    BIGSERIAL PRIMARY KEY,
  report_no             TEXT UNIQUE,
  agreement_id          BIGINT NOT NULL REFERENCES franchise_agreements(id) ON DELETE RESTRICT,
  franchise_branch_id   BIGINT REFERENCES franchise_branches(id) ON DELETE SET NULL,
  period_year           INT NOT NULL,
  period_month          INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  gross_sales           NUMERIC(14,2) NOT NULL CHECK (gross_sales >= 0),
  net_sales             NUMERIC(14,2) NOT NULL CHECK (net_sales >= 0),
  transactions_count    INT NOT NULL DEFAULT 0,
  royalty_invoice_id    BIGINT,
  status                TEXT NOT NULL DEFAULT 'submitted'
                         CHECK (status IN ('draft', 'submitted', 'audited', 'invoiced', 'disputed')),
  submitted_at          TIMESTAMPTZ DEFAULT now(),
  audited_at            TIMESTAMPTZ,
  audited_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  audit_notes           TEXT,
  supporting_docs       TEXT[],
  submitted_by          BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
  -- ملاحظة: التفرد يُنفَّذ عبر partial unique indexes أدناه بدل constraint واحد
  -- (السلوك القديم CONSTRAINT franchise_sr_unique كان يعامل NULL branch_id كمتميز
  -- فيسمح بتقارير مكررة لعقد بلا فرع محدد)
);

CREATE INDEX IF NOT EXISTS franchise_sr_agr_idx    ON franchise_sales_reports(agreement_id, period_year DESC, period_month DESC);
CREATE INDEX IF NOT EXISTS franchise_sr_status_idx ON franchise_sales_reports(status) WHERE status IN ('submitted', 'disputed');

-- إزالة القيد القديم لو موجود من نسخة سابقة
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'franchise_sr_unique') THEN
    ALTER TABLE franchise_sales_reports DROP CONSTRAINT franchise_sr_unique;
  END IF;
END $$;

-- partial unique indexes للتفرد الصحيح
CREATE UNIQUE INDEX IF NOT EXISTS franchise_sr_branch_uniq
  ON franchise_sales_reports (agreement_id, franchise_branch_id, period_year, period_month)
  WHERE franchise_branch_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS franchise_sr_no_branch_uniq
  ON franchise_sales_reports (agreement_id, period_year, period_month)
  WHERE franchise_branch_id IS NULL;

DROP TRIGGER IF EXISTS franchise_sr_updated_at ON franchise_sales_reports;
CREATE TRIGGER franchise_sr_updated_at BEFORE UPDATE ON franchise_sales_reports
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION franchise_assign_sr_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_prefix TEXT;
  v_seq    INT;
BEGIN
  IF NEW.report_no IS NULL THEN
    v_prefix := 'FSR-' || NEW.period_year || LPAD(NEW.period_month::TEXT, 2, '0') || '-';
    SELECT COUNT(*) + 1 INTO v_seq FROM franchise_sales_reports WHERE report_no LIKE v_prefix || '%';
    NEW.report_no := v_prefix || LPAD(v_seq::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS franchise_sr_assign_no ON franchise_sales_reports;
CREATE TRIGGER franchise_sr_assign_no BEFORE INSERT ON franchise_sales_reports
  FOR EACH ROW EXECUTE FUNCTION franchise_assign_sr_no();

-- ───────────────────────────────────────────────────────────
-- 5) franchise_royalty_invoices — فواتير الروياليتي
--    DECISION: تُنشأ آليًا من تقارير المبيعات، ومربوطة بـ AR في acct_invoices
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_royalty_invoices (
  id                    BIGSERIAL PRIMARY KEY,
  royalty_no            TEXT UNIQUE,
  agreement_id          BIGINT NOT NULL REFERENCES franchise_agreements(id) ON DELETE RESTRICT,
  sales_report_id       BIGINT REFERENCES franchise_sales_reports(id) ON DELETE SET NULL,
  period_year           INT NOT NULL,
  period_month          INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  gross_sales_base      NUMERIC(14,2) NOT NULL CHECK (gross_sales_base >= 0),
  royalty_pct           NUMERIC(5,2) NOT NULL,
  royalty_amount        NUMERIC(14,2) NOT NULL CHECK (royalty_amount >= 0),
  marketing_pct         NUMERIC(5,2) NOT NULL DEFAULT 0,
  marketing_amount      NUMERIC(14,2) NOT NULL DEFAULT 0,
  min_royalty_applied   BOOLEAN NOT NULL DEFAULT FALSE,
  vat_amount            NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_amount          NUMERIC(14,2) NOT NULL,
  status                TEXT NOT NULL DEFAULT 'draft'
                         CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'cancelled', 'disputed')),
  due_date              DATE NOT NULL,
  paid_at               TIMESTAMPTZ,
  ar_invoice_id         BIGINT REFERENCES acct_invoices(id) ON DELETE SET NULL,
  notes                 TEXT,
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS franchise_roy_agr_idx    ON franchise_royalty_invoices(agreement_id, period_year DESC, period_month DESC);
CREATE INDEX IF NOT EXISTS franchise_roy_status_idx ON franchise_royalty_invoices(status) WHERE status IN ('issued', 'overdue');
CREATE INDEX IF NOT EXISTS franchise_roy_due_idx    ON franchise_royalty_invoices(due_date) WHERE status = 'issued';

DROP TRIGGER IF EXISTS franchise_roy_updated_at ON franchise_royalty_invoices;
CREATE TRIGGER franchise_roy_updated_at BEFORE UPDATE ON franchise_royalty_invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION franchise_assign_roy_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_prefix TEXT;
  v_seq    INT;
BEGIN
  IF NEW.royalty_no IS NULL THEN
    v_prefix := 'ROY-' || NEW.period_year || LPAD(NEW.period_month::TEXT, 2, '0') || '-';
    SELECT COUNT(*) + 1 INTO v_seq FROM franchise_royalty_invoices WHERE royalty_no LIKE v_prefix || '%';
    NEW.royalty_no := v_prefix || LPAD(v_seq::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS franchise_roy_assign_no ON franchise_royalty_invoices;
CREATE TRIGGER franchise_roy_assign_no BEFORE INSERT ON franchise_royalty_invoices
  FOR EACH ROW EXECUTE FUNCTION franchise_assign_roy_no();

-- إضافة FK لـ royalty_invoice_id على franchise_sales_reports (بعد إنشاء الجدولين)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'franchise_sr_roy_fk') THEN
    ALTER TABLE franchise_sales_reports
      ADD CONSTRAINT franchise_sr_roy_fk
      FOREIGN KEY (royalty_invoice_id)
      REFERENCES franchise_royalty_invoices(id) ON DELETE SET NULL;
  END IF;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة حساب الروياليتي وإنشاء الفاتورة
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION franchise_compute_royalty(p_sales_report_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report    RECORD;
  v_agr       RECORD;
  v_royalty   NUMERIC;
  v_marketing NUMERIC;
  v_min_used  BOOLEAN := FALSE;
  v_subtotal  NUMERIC;
  v_vat       NUMERIC;
  v_total     NUMERIC;
  v_id        BIGINT;
BEGIN
  SELECT * INTO v_report FROM franchise_sales_reports WHERE id = p_sales_report_id;
  IF v_report IS NULL THEN RAISE EXCEPTION 'تقرير المبيعات غير موجود'; END IF;
  IF v_report.status NOT IN ('submitted', 'audited') THEN
    RAISE EXCEPTION 'التقرير غير جاهز للفوترة — الحالة: %', v_report.status;
  END IF;

  SELECT * INTO v_agr FROM franchise_agreements WHERE id = v_report.agreement_id;
  IF v_agr IS NULL OR v_agr.status <> 'active' THEN
    RAISE EXCEPTION 'الاتفاقية غير نشطة';
  END IF;

  -- احسب الروياليتي والتسويق
  v_royalty   := ROUND(v_report.gross_sales * v_agr.royalty_pct / 100, 2);
  v_marketing := ROUND(v_report.gross_sales * v_agr.marketing_pct / 100, 2);

  -- تطبيق الحد الأدنى للروياليتي
  IF v_agr.min_monthly_royalty > 0 AND v_royalty < v_agr.min_monthly_royalty THEN
    v_royalty := v_agr.min_monthly_royalty;
    v_min_used := TRUE;
  END IF;

  v_subtotal := v_royalty + v_marketing;
  v_vat      := ROUND(v_subtotal * 0.15, 2);
  v_total    := v_subtotal + v_vat;

  INSERT INTO franchise_royalty_invoices (
    agreement_id, sales_report_id, period_year, period_month,
    gross_sales_base, royalty_pct, royalty_amount,
    marketing_pct, marketing_amount, min_royalty_applied,
    vat_amount, total_amount, status, due_date, created_by
  ) VALUES (
    v_report.agreement_id, p_sales_report_id, v_report.period_year, v_report.period_month,
    v_report.gross_sales, v_agr.royalty_pct, v_royalty,
    v_agr.marketing_pct, v_marketing, v_min_used,
    v_vat, v_total, 'draft',
    CURRENT_DATE + INTERVAL '30 days',
    current_app_user_id()
  ) RETURNING id INTO v_id;

  UPDATE franchise_sales_reports
    SET status = 'invoiced', royalty_invoice_id = v_id
    WHERE id = p_sales_report_id;

  RETURN v_id;
END;
$$;

-- إصدار فاتورة الروياليتي (draft → issued)
CREATE OR REPLACE FUNCTION franchise_issue_royalty(p_royalty_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE franchise_royalty_invoices SET status = 'issued'
  WHERE id = p_royalty_id AND status = 'draft';
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE franchise_partners           ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_agreements         ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_branches           ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_sales_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_royalty_invoices   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS franchise_partners_sel ON franchise_partners;
CREATE POLICY franchise_partners_sel ON franchise_partners FOR SELECT TO authenticated USING (is_franchise_manager());
DROP POLICY IF EXISTS franchise_partners_wr ON franchise_partners;
CREATE POLICY franchise_partners_wr ON franchise_partners FOR ALL TO authenticated
  USING (is_franchise_manager()) WITH CHECK (is_franchise_manager());

DROP POLICY IF EXISTS franchise_agr_sel ON franchise_agreements;
CREATE POLICY franchise_agr_sel ON franchise_agreements FOR SELECT TO authenticated USING (is_franchise_manager());
DROP POLICY IF EXISTS franchise_agr_wr ON franchise_agreements;
CREATE POLICY franchise_agr_wr ON franchise_agreements FOR ALL TO authenticated
  USING (is_franchise_manager()) WITH CHECK (is_franchise_manager());

DROP POLICY IF EXISTS franchise_br_sel ON franchise_branches;
CREATE POLICY franchise_br_sel ON franchise_branches FOR SELECT TO authenticated USING (is_franchise_manager());
DROP POLICY IF EXISTS franchise_br_wr ON franchise_branches;
CREATE POLICY franchise_br_wr ON franchise_branches FOR ALL TO authenticated
  USING (is_franchise_manager()) WITH CHECK (is_franchise_manager());

DROP POLICY IF EXISTS franchise_sr_sel ON franchise_sales_reports;
CREATE POLICY franchise_sr_sel ON franchise_sales_reports FOR SELECT TO authenticated USING (is_franchise_manager());
DROP POLICY IF EXISTS franchise_sr_wr ON franchise_sales_reports;
CREATE POLICY franchise_sr_wr ON franchise_sales_reports FOR ALL TO authenticated
  USING (is_franchise_manager()) WITH CHECK (is_franchise_manager());

DROP POLICY IF EXISTS franchise_roy_sel ON franchise_royalty_invoices;
CREATE POLICY franchise_roy_sel ON franchise_royalty_invoices FOR SELECT TO authenticated USING (is_franchise_manager());
DROP POLICY IF EXISTS franchise_roy_wr ON franchise_royalty_invoices;
CREATE POLICY franchise_roy_wr ON franchise_royalty_invoices FOR ALL TO authenticated
  USING (is_franchise_manager()) WITH CHECK (is_franchise_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT proname FROM pg_proc WHERE proname LIKE 'franchise_%';
-- 2) SELECT relname FROM pg_class WHERE relname LIKE 'franchise_%';
-- ═══════════════════════════════════════════════════════════
