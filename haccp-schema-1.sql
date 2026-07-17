-- ═══════════════════════════════════════════════════════════
-- سلامة الغذاء HACCP — Phase 1 (Wave 2 Module 27)
-- ═══════════════════════════════════════════════════════════
-- 6 جداول: إعدادات + معدات + سجلات حرارة + دفعات غذائية +
-- شهادات صحية + حوادث سلامة غذاء
-- + Triggers لحساب is_within_range تلقائيًا + ترقيم الحوادث
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير HACCP (Quality/Ops managers أو أعلى)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_haccp_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'quality_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) haccp_settings — إعدادات مركزية (صف واحد id=1)
--    DECISION: الحدود من مواصفة SASO 2233 لحفظ الأغذية:
--    ثلاجة 0-4°م • مجمّد -25 إلى -18°م • حفظ ساخن 63°م+
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_settings (
  id                                INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  fridge_min_temp                   NUMERIC(5,2) NOT NULL DEFAULT 0,
  fridge_max_temp                   NUMERIC(5,2) NOT NULL DEFAULT 4,
  freezer_min_temp                  NUMERIC(5,2) NOT NULL DEFAULT -25,
  freezer_max_temp                  NUMERIC(5,2) NOT NULL DEFAULT -18,
  hot_holding_min_temp              NUMERIC(5,2) NOT NULL DEFAULT 63,
  temperature_log_frequency_hours   INT NOT NULL DEFAULT 4 CHECK (temperature_log_frequency_hours > 0),
  health_cert_alert_days            INT NOT NULL DEFAULT 30 CHECK (health_cert_alert_days > 0),
  batch_expiry_alert_days           INT NOT NULL DEFAULT 3 CHECK (batch_expiry_alert_days > 0),
  auto_close_incidents_days         INT NOT NULL DEFAULT 30,
  created_at                        TIMESTAMPTZ DEFAULT now(),
  updated_at                        TIMESTAMPTZ DEFAULT now()
);

INSERT INTO haccp_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS haccp_settings_updated_at ON haccp_settings;
CREATE TRIGGER haccp_settings_updated_at BEFORE UPDATE ON haccp_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) haccp_equipment — المعدات الخاضعة للمراقبة الحرارية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_equipment (
  id               BIGSERIAL PRIMARY KEY,
  branch_id        BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  code             TEXT UNIQUE,
  name             TEXT NOT NULL,
  equipment_type   TEXT NOT NULL CHECK (equipment_type IN ('fridge', 'freezer', 'hot_holding', 'other')),
  location         TEXT,
  target_min_temp  NUMERIC(5,2),
  target_max_temp  NUMERIC(5,2),
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  notes            TEXT,
  created_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS haccp_equipment_branch_idx ON haccp_equipment(branch_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS haccp_equipment_type_idx   ON haccp_equipment(equipment_type) WHERE is_active;

DROP TRIGGER IF EXISTS haccp_equipment_updated_at ON haccp_equipment;
CREATE TRIGGER haccp_equipment_updated_at BEFORE UPDATE ON haccp_equipment
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION haccp_assign_equipment_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.code IS NULL THEN NEW.code := 'EQP-' || LPAD(NEW.id::TEXT, 4, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS haccp_equipment_assign_code ON haccp_equipment;
CREATE TRIGGER haccp_equipment_assign_code BEFORE INSERT ON haccp_equipment
  FOR EACH ROW EXECUTE FUNCTION haccp_assign_equipment_code();

-- ───────────────────────────────────────────────────────────
-- 3) haccp_temperature_logs — سجلات قراءات الحرارة اليومية
--    is_within_range يُحسب تلقائيًا من الحدود المستهدفة أو الإعدادات
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_temperature_logs (
  id                BIGSERIAL PRIMARY KEY,
  equipment_id      BIGINT NOT NULL REFERENCES haccp_equipment(id) ON DELETE CASCADE,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  temperature       NUMERIC(5,2) NOT NULL,
  is_within_range   BOOLEAN NOT NULL DEFAULT TRUE,
  action_taken      TEXT,
  recorded_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS haccp_temp_equipment_idx ON haccp_temperature_logs(equipment_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS haccp_temp_branch_idx    ON haccp_temperature_logs(branch_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS haccp_temp_breach_idx    ON haccp_temperature_logs(equipment_id, recorded_at DESC) WHERE is_within_range = FALSE;

-- حساب is_within_range تلقائيًا: يستخدم الحدود المستهدفة للمعدة،
-- ولو فارغة يعتمد على إعدادات النوع من haccp_settings
CREATE OR REPLACE FUNCTION haccp_compute_within_range()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_eq       RECORD;
  v_settings RECORD;
  v_min      NUMERIC(5,2);
  v_max      NUMERIC(5,2);
BEGIN
  SELECT * INTO v_eq FROM haccp_equipment WHERE id = NEW.equipment_id;
  SELECT * INTO v_settings FROM haccp_settings WHERE id = 1;

  v_min := COALESCE(v_eq.target_min_temp,
    CASE v_eq.equipment_type
      WHEN 'fridge'      THEN v_settings.fridge_min_temp
      WHEN 'freezer'     THEN v_settings.freezer_min_temp
      WHEN 'hot_holding' THEN v_settings.hot_holding_min_temp
      ELSE NULL
    END);
  v_max := COALESCE(v_eq.target_max_temp,
    CASE v_eq.equipment_type
      WHEN 'fridge'  THEN v_settings.fridge_max_temp
      WHEN 'freezer' THEN v_settings.freezer_max_temp
      WHEN 'hot_holding' THEN NULL
      ELSE NULL
    END);

  NEW.is_within_range := (
    (v_min IS NULL OR NEW.temperature >= v_min) AND
    (v_max IS NULL OR NEW.temperature <= v_max)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS haccp_temp_compute_range ON haccp_temperature_logs;
CREATE TRIGGER haccp_temp_compute_range BEFORE INSERT OR UPDATE OF temperature ON haccp_temperature_logs
  FOR EACH ROW EXECUTE FUNCTION haccp_compute_within_range();

-- ───────────────────────────────────────────────────────────
-- 4) haccp_food_batches — دفعات غذائية بتاريخ صلاحية
--    ترقيم آلي BATCH-YYYYMMDD-00001
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_food_batches (
  id                    BIGSERIAL PRIMARY KEY,
  batch_no              TEXT UNIQUE,
  branch_id             BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  item_name             TEXT NOT NULL,
  inventory_item_id     BIGINT REFERENCES acct_inventory_items(id) ON DELETE SET NULL,
  quantity              NUMERIC(10,2) NOT NULL DEFAULT 0,
  unit                  TEXT NOT NULL DEFAULT 'unit',
  production_date       DATE,
  expiry_date           DATE NOT NULL,
  storage_location      TEXT,
  storage_temperature   TEXT,
  status                TEXT NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'consumed', 'discarded', 'expired')),
  discarded_reason      TEXT,
  supplier              TEXT,
  received_at           TIMESTAMPTZ DEFAULT now(),
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS haccp_batch_branch_idx    ON haccp_food_batches(branch_id, expiry_date);
CREATE INDEX IF NOT EXISTS haccp_batch_expiry_idx    ON haccp_food_batches(expiry_date) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS haccp_batch_status_idx    ON haccp_food_batches(status) WHERE status = 'active';

DROP TRIGGER IF EXISTS haccp_batches_updated_at ON haccp_food_batches;
CREATE TRIGGER haccp_batches_updated_at BEFORE UPDATE ON haccp_food_batches
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION haccp_assign_batch_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_date TEXT := to_char(now(), 'YYYYMMDD');
  v_seq  INT;
BEGIN
  IF NEW.batch_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM haccp_food_batches WHERE batch_no LIKE 'BATCH-' || v_date || '-%';
    NEW.batch_no := 'BATCH-' || v_date || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS haccp_batches_assign_no ON haccp_food_batches;
CREATE TRIGGER haccp_batches_assign_no BEFORE INSERT ON haccp_food_batches
  FOR EACH ROW EXECUTE FUNCTION haccp_assign_batch_no();

-- ───────────────────────────────────────────────────────────
-- 5) haccp_health_certificates — شهادات صحية للموظفين
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_health_certificates (
  id                 BIGSERIAL PRIMARY KEY,
  employee_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  certificate_no     TEXT,
  issue_date         DATE NOT NULL,
  expiry_date        DATE NOT NULL,
  issuing_authority  TEXT,
  document_url       TEXT,
  status             TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'expired', 'renewed', 'suspended')),
  notes              TEXT,
  created_by         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT haccp_cert_dates CHECK (expiry_date >= issue_date)
);

CREATE INDEX IF NOT EXISTS haccp_cert_employee_idx ON haccp_health_certificates(employee_id, expiry_date DESC);
CREATE INDEX IF NOT EXISTS haccp_cert_expiry_idx   ON haccp_health_certificates(expiry_date) WHERE status = 'active';

DROP TRIGGER IF EXISTS haccp_certs_updated_at ON haccp_health_certificates;
CREATE TRIGGER haccp_certs_updated_at BEFORE UPDATE ON haccp_health_certificates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 6) haccp_incidents — حوادث سلامة الغذاء
--    ترقيم آلي HACCP-YYYY-00001
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS haccp_incidents (
  id                    BIGSERIAL PRIMARY KEY,
  incident_no           TEXT UNIQUE,
  branch_id             BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  incident_type         TEXT NOT NULL
                         CHECK (incident_type IN ('contamination', 'food_poisoning', 'temperature_breach', 'pest', 'cross_contamination', 'foreign_object', 'other')),
  severity              TEXT NOT NULL DEFAULT 'medium'
                         CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  title                 TEXT NOT NULL,
  description           TEXT,
  affected_products     TEXT,
  affected_batch_id     BIGINT REFERENCES haccp_food_batches(id) ON DELETE SET NULL,
  incident_at           TIMESTAMPTZ DEFAULT now(),
  status                TEXT NOT NULL DEFAULT 'open'
                         CHECK (status IN ('open', 'investigating', 'resolved', 'closed')),
  root_cause            TEXT,
  corrective_actions    TEXT,
  preventive_actions    TEXT,
  reported_to_authority BOOLEAN NOT NULL DEFAULT FALSE,
  authority_report_ref  TEXT,
  reported_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  resolved_by           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  resolved_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS haccp_incidents_branch_idx   ON haccp_incidents(branch_id, incident_at DESC);
CREATE INDEX IF NOT EXISTS haccp_incidents_severity_idx ON haccp_incidents(severity, status);
CREATE INDEX IF NOT EXISTS haccp_incidents_open_idx     ON haccp_incidents(status) WHERE status IN ('open', 'investigating');

DROP TRIGGER IF EXISTS haccp_incidents_updated_at ON haccp_incidents;
CREATE TRIGGER haccp_incidents_updated_at BEFORE UPDATE ON haccp_incidents
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION haccp_assign_incident_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.incident_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM haccp_incidents WHERE incident_no LIKE 'HACCP-' || v_year || '-%';
    NEW.incident_no := 'HACCP-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS haccp_incidents_assign_no ON haccp_incidents;
CREATE TRIGGER haccp_incidents_assign_no BEFORE INSERT ON haccp_incidents
  FOR EACH ROW EXECUTE FUNCTION haccp_assign_incident_no();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE haccp_settings                ENABLE ROW LEVEL SECURITY;
ALTER TABLE haccp_equipment               ENABLE ROW LEVEL SECURITY;
ALTER TABLE haccp_temperature_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE haccp_food_batches            ENABLE ROW LEVEL SECURITY;
ALTER TABLE haccp_health_certificates     ENABLE ROW LEVEL SECURITY;
ALTER TABLE haccp_incidents               ENABLE ROW LEVEL SECURITY;

-- الإعدادات: قراءة للجميع، تعديل لمدير HACCP فقط
DROP POLICY IF EXISTS haccp_settings_sel ON haccp_settings;
CREATE POLICY haccp_settings_sel ON haccp_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS haccp_settings_wr ON haccp_settings;
CREATE POLICY haccp_settings_wr ON haccp_settings FOR UPDATE TO authenticated
  USING (is_haccp_manager()) WITH CHECK (is_haccp_manager());

-- المعدات: قراءة لكل مصادَق، كتابة لمدير HACCP أو مدير الفرع
DROP POLICY IF EXISTS haccp_equipment_sel ON haccp_equipment;
CREATE POLICY haccp_equipment_sel ON haccp_equipment FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS haccp_equipment_wr ON haccp_equipment;
CREATE POLICY haccp_equipment_wr ON haccp_equipment FOR ALL TO authenticated
  USING (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = haccp_equipment.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')))
  WITH CHECK (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = haccp_equipment.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')));

-- سجلات الحرارة: قراءة لكل مصادَق، إدراج لموظفي الفرع أو مديري HACCP
DROP POLICY IF EXISTS haccp_temp_sel ON haccp_temperature_logs;
CREATE POLICY haccp_temp_sel ON haccp_temperature_logs FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS haccp_temp_ins ON haccp_temperature_logs;
CREATE POLICY haccp_temp_ins ON haccp_temperature_logs FOR INSERT TO authenticated
  WITH CHECK (is_haccp_manager()
              OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = haccp_temperature_logs.branch_id));
DROP POLICY IF EXISTS haccp_temp_upd ON haccp_temperature_logs;
CREATE POLICY haccp_temp_upd ON haccp_temperature_logs FOR UPDATE TO authenticated
  USING (is_haccp_manager()) WITH CHECK (is_haccp_manager());

-- الدفعات الغذائية: قراءة لكل مصادَق، كتابة لموظفي الفرع أو مديري HACCP
DROP POLICY IF EXISTS haccp_batches_sel ON haccp_food_batches;
CREATE POLICY haccp_batches_sel ON haccp_food_batches FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS haccp_batches_wr ON haccp_food_batches;
CREATE POLICY haccp_batches_wr ON haccp_food_batches FOR ALL TO authenticated
  USING (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = haccp_food_batches.branch_id))
  WITH CHECK (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = haccp_food_batches.branch_id));

-- الشهادات الصحية: قراءة لمدير HACCP و HR + الموظف يشوف شهاداته
DROP POLICY IF EXISTS haccp_certs_sel ON haccp_health_certificates;
CREATE POLICY haccp_certs_sel ON haccp_health_certificates FOR SELECT TO authenticated
  USING (employee_id = current_app_user_id()
         OR is_haccp_manager()
         OR current_app_role() IN ('hr_manager'));
DROP POLICY IF EXISTS haccp_certs_wr ON haccp_health_certificates;
CREATE POLICY haccp_certs_wr ON haccp_health_certificates FOR ALL TO authenticated
  USING (is_haccp_manager() OR current_app_role() IN ('hr_manager'))
  WITH CHECK (is_haccp_manager() OR current_app_role() IN ('hr_manager'));

-- الحوادث: قراءة لمدير HACCP وموظفي الفرع، كتابة نفس النطاق
DROP POLICY IF EXISTS haccp_incidents_sel ON haccp_incidents;
CREATE POLICY haccp_incidents_sel ON haccp_incidents FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS haccp_incidents_wr ON haccp_incidents;
CREATE POLICY haccp_incidents_wr ON haccp_incidents FOR ALL TO authenticated
  USING (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = haccp_incidents.branch_id))
  WITH CHECK (is_haccp_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = haccp_incidents.branch_id));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM haccp_settings;              -- صف id=1
-- 2) SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'haccp_%';
-- 3) SELECT proname FROM pg_proc WHERE proname LIKE 'haccp_%';
-- ═══════════════════════════════════════════════════════════
