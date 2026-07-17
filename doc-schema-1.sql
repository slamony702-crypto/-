-- ═══════════════════════════════════════════════════════════
-- إدارة المستندات Documents — Phase 1 (Wave 3 Module 31)
-- ═══════════════════════════════════════════════════════════
-- 3 جداول: تصنيفات + مستندات + سجل وصول
-- + دالة doc_log_access() لتسجيل ذرّي
-- + تصنيفات مبذورة (تراخيص، عقود، فواتير، ضمانات، إلخ)
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير المستندات
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_doc_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'hr_manager', 'finance_manager', 'legal_officer');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) doc_categories — تصنيفات المستندات
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS doc_categories (
  id                  BIGSERIAL PRIMARY KEY,
  code                TEXT UNIQUE NOT NULL,
  name                TEXT NOT NULL,
  icon                TEXT DEFAULT 'file-text',
  description         TEXT,
  requires_expiry     BOOLEAN NOT NULL DEFAULT FALSE,
  default_alert_days  INT NOT NULL DEFAULT 30 CHECK (default_alert_days >= 0),
  is_confidential     BOOLEAN NOT NULL DEFAULT FALSE,
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS doc_cat_updated_at ON doc_categories;
CREATE TRIGGER doc_cat_updated_at BEFORE UPDATE ON doc_categories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- بذر التصنيفات الشائعة
INSERT INTO doc_categories (code, name, icon, requires_expiry, default_alert_days, is_confidential, description) VALUES
  ('COMMERCIAL_LICENSE', 'السجل التجاري', 'shield', TRUE, 30, FALSE, 'السجل التجاري وتراخيص وزارة التجارة'),
  ('MUNICIPAL_LICENSE',  'رخصة البلدية', 'landmark', TRUE, 30, FALSE, 'تراخيص البلدية والمحلات'),
  ('CIVIL_DEFENSE',      'شهادة الدفاع المدني', 'flame', TRUE, 30, FALSE, 'شهادات السلامة من الدفاع المدني'),
  ('MUNICIPAL_HEALTH',   'الشهادات الصحية', 'heart-pulse', TRUE, 30, FALSE, 'شهادات الصحة العامة والغذاء'),
  ('LEASE_CONTRACT',     'عقد الإيجار', 'file-signature', TRUE, 60, FALSE, 'عقود إيجار المقرات والفروع'),
  ('EMPLOYMENT_CONTRACT', 'عقد عمل', 'file-signature', TRUE, 60, TRUE, 'عقود عمل الموظفين'),
  ('VENDOR_CONTRACT',    'عقود الموردين', 'file-check', TRUE, 60, FALSE, 'اتفاقيات مع الموردين'),
  ('INSURANCE',          'وثائق التأمين', 'shield-check', TRUE, 30, FALSE, 'التأمين على المنشآت والمركبات'),
  ('INVOICE',            'الفواتير', 'receipt', FALSE, 0, FALSE, 'فواتير مستلمة وصادرة'),
  ('WARRANTY',           'الضمانات', 'badge-check', TRUE, 90, FALSE, 'ضمانات المعدات والأجهزة'),
  ('VAT_CERTIFICATE',    'شهادة الضريبة', 'file-badge', TRUE, 30, FALSE, 'شهادة التسجيل الضريبي'),
  ('POLICY',             'السياسات والأدلة', 'book-open', FALSE, 0, FALSE, 'دلائل العمل والسياسات الداخلية'),
  ('LEGAL',              'قانوني', 'gavel', FALSE, 0, TRUE, 'مذكرات قانونية وقضايا'),
  ('OTHER',              'أخرى', 'file', FALSE, 0, FALSE, 'مستندات متنوعة')
ON CONFLICT (code) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- 2) doc_documents — المستندات الفعلية
--    DECISION: file_url يشير لملف في Supabase Storage أو رابط خارجي.
--    related_entity_type + related_entity_id لربط اختياري مع أي جدول
--    (branch, user, vendor, contract, إلخ) — تصميم polymorphic بسيط.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS doc_documents (
  id                    BIGSERIAL PRIMARY KEY,
  document_no           TEXT UNIQUE,
  category_id           BIGINT NOT NULL REFERENCES doc_categories(id) ON DELETE RESTRICT,
  title                 TEXT NOT NULL,
  description           TEXT,
  file_url              TEXT,
  file_name             TEXT,
  file_size_bytes       BIGINT,
  file_mime_type        TEXT,
  reference_no          TEXT,
  issue_date            DATE,
  expiry_date           DATE,
  alert_days_before     INT,
  status                TEXT NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'expired', 'archived', 'cancelled')),
  branch_id             BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  related_entity_type   TEXT CHECK (related_entity_type IS NULL OR related_entity_type IN
                          ('branch', 'user', 'vendor', 'customer', 'contract', 'equipment', 'other')),
  related_entity_id     BIGINT,
  is_confidential       BOOLEAN NOT NULL DEFAULT FALSE,
  tags                  TEXT[],
  metadata              JSONB,
  version               INT NOT NULL DEFAULT 1,
  supersedes_id         BIGINT REFERENCES doc_documents(id) ON DELETE SET NULL,
  uploaded_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  archived_at           TIMESTAMPTZ,
  archived_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS doc_documents_category_idx   ON doc_documents(category_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS doc_documents_branch_idx     ON doc_documents(branch_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS doc_documents_expiry_idx     ON doc_documents(expiry_date) WHERE status = 'active' AND expiry_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS doc_documents_related_idx    ON doc_documents(related_entity_type, related_entity_id) WHERE related_entity_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS doc_documents_tags_idx       ON doc_documents USING GIN (tags);
CREATE INDEX IF NOT EXISTS doc_documents_status_idx     ON doc_documents(status);

DROP TRIGGER IF EXISTS doc_documents_updated_at ON doc_documents;
CREATE TRIGGER doc_documents_updated_at BEFORE UPDATE ON doc_documents
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION doc_assign_document_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.document_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM doc_documents WHERE document_no LIKE 'DOC-' || v_year || '-%';
    NEW.document_no := 'DOC-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS doc_documents_assign_no ON doc_documents;
CREATE TRIGGER doc_documents_assign_no BEFORE INSERT ON doc_documents
  FOR EACH ROW EXECUTE FUNCTION doc_assign_document_no();

-- ترحيل تلقائي للحالة عند انتهاء الصلاحية (لو التاريخ فات)
-- ملحوظة: يستخدم للفحص عند القراءة؛ للتوثيق التلقائي احتاج cron أو تشغيل يدوي دوري.
CREATE OR REPLACE FUNCTION doc_expire_overdue()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INT;
BEGIN
  UPDATE doc_documents SET status = 'expired'
  WHERE status = 'active' AND expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ───────────────────────────────────────────────────────────
-- 3) doc_access_log — سجل وصول المستندات
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS doc_access_log (
  id            BIGSERIAL PRIMARY KEY,
  document_id   BIGINT NOT NULL REFERENCES doc_documents(id) ON DELETE CASCADE,
  user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action        TEXT NOT NULL CHECK (action IN ('view', 'download', 'update', 'archive', 'restore', 'delete')),
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS doc_access_log_doc_idx  ON doc_access_log(document_id, created_at DESC);
CREATE INDEX IF NOT EXISTS doc_access_log_user_idx ON doc_access_log(user_id, created_at DESC);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة تسجيل الوصول
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION doc_log_access(
  p_document_id BIGINT,
  p_action TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO doc_access_log (document_id, user_id, action, notes)
  VALUES (p_document_id, current_app_user_id(), p_action, p_notes);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE doc_categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc_documents    ENABLE ROW LEVEL SECURITY;
ALTER TABLE doc_access_log   ENABLE ROW LEVEL SECURITY;

-- التصنيفات: قراءة للجميع، كتابة لمدير المستندات
DROP POLICY IF EXISTS doc_cat_sel ON doc_categories;
CREATE POLICY doc_cat_sel ON doc_categories FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS doc_cat_wr ON doc_categories;
CREATE POLICY doc_cat_wr ON doc_categories FOR ALL TO authenticated
  USING (is_doc_manager()) WITH CHECK (is_doc_manager());

-- المستندات: قراءة عامة إلا السرية (مدير المستندات، من رفعها، أو المسؤول عن الجهة)
DROP POLICY IF EXISTS doc_documents_sel ON doc_documents;
CREATE POLICY doc_documents_sel ON doc_documents FOR SELECT TO authenticated USING (
  NOT is_confidential
  OR is_doc_manager()
  OR uploaded_by = current_app_user_id()
  OR (related_entity_type = 'user' AND related_entity_id = current_app_user_id())
);
DROP POLICY IF EXISTS doc_documents_ins ON doc_documents;
CREATE POLICY doc_documents_ins ON doc_documents FOR INSERT TO authenticated
  WITH CHECK (uploaded_by = current_app_user_id() OR is_doc_manager());
DROP POLICY IF EXISTS doc_documents_upd ON doc_documents;
CREATE POLICY doc_documents_upd ON doc_documents FOR UPDATE TO authenticated USING (
  is_doc_manager() OR (uploaded_by = current_app_user_id() AND status = 'active')
);

-- سجل الوصول: قراءة لمدير المستندات ورافع الملف، إدراج لأي مستخدم مصادَق
DROP POLICY IF EXISTS doc_log_sel ON doc_access_log;
CREATE POLICY doc_log_sel ON doc_access_log FOR SELECT TO authenticated USING (
  is_doc_manager()
  OR EXISTS (SELECT 1 FROM doc_documents d WHERE d.id = doc_access_log.document_id AND d.uploaded_by = current_app_user_id())
);
DROP POLICY IF EXISTS doc_log_ins ON doc_access_log;
CREATE POLICY doc_log_ins ON doc_access_log FOR INSERT TO authenticated
  WITH CHECK (user_id = current_app_user_id());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT count(*) FROM doc_categories;  -- 14 تصنيفًا افتراضيًا
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'doc_%';
-- 3) SELECT relname FROM pg_class WHERE relname LIKE 'doc_%';
-- ═══════════════════════════════════════════════════════════
