-- ═══════════════════════════════════════════════════════════
-- التكاملات Integrations — Phase 1 (Wave 4 Module 34)
-- ═══════════════════════════════════════════════════════════
-- 4 جداول: مزوّدين + اتصالات مفعّلة + Webhook endpoints + سجل أحداث
-- + مزوّدين مبذورين (WhatsApp, Slack, Jahez, HungerStation, ...)
-- + دالة int_log_event() لتسجيل ذرّي
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير التكاملات
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_integrations_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'integrations_admin');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) int_providers — كتالوج مزوّدي الخدمات
--    DECISION: config_schema يخزّن JSON schema لحقول الإعدادات المطلوبة
--    لكل مزوّد — الطبقة الأمامية تولّد نموذجًا تلقائيًا منه.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS int_providers (
  id                BIGSERIAL PRIMARY KEY,
  code              TEXT UNIQUE NOT NULL,
  name              TEXT NOT NULL,
  category          TEXT NOT NULL CHECK (category IN ('messaging', 'payment', 'delivery_aggregator', 'accounting', 'crm', 'analytics', 'workflow', 'sms', 'other')),
  provider_type     TEXT NOT NULL DEFAULT 'api' CHECK (provider_type IN ('api', 'webhook', 'oauth', 'sdk', 'file')),
  icon              TEXT DEFAULT 'plug',
  description       TEXT,
  homepage_url      TEXT,
  docs_url          TEXT,
  logo_url          TEXT,
  supports_inbound  BOOLEAN NOT NULL DEFAULT FALSE,
  supports_outbound BOOLEAN NOT NULL DEFAULT TRUE,
  config_schema     JSONB,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS int_providers_updated_at ON int_providers;
CREATE TRIGGER int_providers_updated_at BEFORE UPDATE ON int_providers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS int_providers_category_idx ON int_providers(category) WHERE is_active;

-- بذر المزوّدين الشائعين
INSERT INTO int_providers (code, name, category, provider_type, icon, description, supports_inbound, supports_outbound, config_schema) VALUES
  ('WHATSAPP_CLOUD',    'واتساب Cloud API',     'messaging',            'api',     'message-circle',      'إرسال رسائل واتساب عبر Meta Cloud API',                TRUE,  TRUE,
    '{"required":["phone_number_id","access_token"],"fields":[{"name":"phone_number_id","label":"Phone Number ID","type":"text"},{"name":"access_token","label":"Access Token","type":"password"},{"name":"verify_token","label":"Verify Token","type":"password"}]}'),
  ('TWILIO_SMS',        'Twilio SMS',            'sms',                  'api',     'send',                'إرسال رسائل SMS عبر Twilio',                           FALSE, TRUE,
    '{"required":["account_sid","auth_token","from_number"],"fields":[{"name":"account_sid","label":"Account SID","type":"text"},{"name":"auth_token","label":"Auth Token","type":"password"},{"name":"from_number","label":"From","type":"text"}]}'),
  ('SLACK_INCOMING',    'Slack Webhooks',        'messaging',            'webhook', 'hash',                'إرسال تنبيهات لقنوات Slack',                            FALSE, TRUE,
    '{"required":["webhook_url"],"fields":[{"name":"webhook_url","label":"Webhook URL","type":"url"},{"name":"default_channel","label":"القناة الافتراضية","type":"text"}]}'),
  ('JAHEZ',             'جاهز (Jahez)',          'delivery_aggregator',  'api',     'bike',                'استقبال طلبات من تطبيق جاهز',                          TRUE,  TRUE,
    '{"required":["merchant_id","api_key"],"fields":[{"name":"merchant_id","label":"Merchant ID","type":"text"},{"name":"api_key","label":"API Key","type":"password"},{"name":"branch_ref","label":"مرجع الفرع","type":"text"}]}'),
  ('HUNGERSTATION',     'HungerStation',         'delivery_aggregator',  'api',     'bike',                'ربط طلبات هنقرستيشن',                                   TRUE,  TRUE,
    '{"required":["client_id","client_secret"],"fields":[{"name":"client_id","label":"Client ID","type":"text"},{"name":"client_secret","label":"Client Secret","type":"password"}]}'),
  ('MRSOOL',            'مرسول (Mrsool)',        'delivery_aggregator',  'api',     'bike',                'ربط طلبات مرسول',                                       TRUE,  TRUE,
    '{"required":["api_key"],"fields":[{"name":"api_key","label":"API Key","type":"password"},{"name":"webhook_secret","label":"Webhook Secret","type":"password"}]}'),
  ('MADA_PAY',          'مدى Pay',               'payment',              'api',     'credit-card',         'تكامل مع بوابة مدى للدفع',                              FALSE, TRUE,
    '{"required":["merchant_key"],"fields":[{"name":"merchant_key","label":"Merchant Key","type":"password"},{"name":"terminal_id","label":"Terminal ID","type":"text"}]}'),
  ('STC_PAY',           'STC Pay',               'payment',              'api',     'wallet',              'استقبال مدفوعات STC Pay',                                FALSE, TRUE,
    '{"required":["merchant_id","secret"],"fields":[{"name":"merchant_id","label":"Merchant ID","type":"text"},{"name":"secret","label":"Secret","type":"password"}]}'),
  ('ZATCA_EINVOICE',    'زاتكا (فوترة إلكترونية)','accounting',           'api',     'file-check',          'إرسال الفواتير الإلكترونية لزاتكا',                    FALSE, TRUE,
    '{"required":["seller_id","private_key"],"fields":[{"name":"seller_id","label":"Seller ID","type":"text"},{"name":"private_key","label":"Private Key","type":"password"}]}'),
  ('ZAPIER',            'Zapier',                'workflow',             'webhook', 'zap',                 'إرسال أحداث لـ Zapier لتشغيل workflows',                FALSE, TRUE,
    '{"required":["webhook_url"],"fields":[{"name":"webhook_url","label":"Webhook URL","type":"url"}]}'),
  ('GOOGLE_ANALYTICS',  'Google Analytics 4',    'analytics',            'api',     'bar-chart',           'إرسال أحداث لـ GA4',                                    FALSE, TRUE,
    '{"required":["measurement_id","api_secret"],"fields":[{"name":"measurement_id","label":"Measurement ID","type":"text"},{"name":"api_secret","label":"API Secret","type":"password"}]}'),
  ('WEBHOOK_GENERIC',   'Webhook مخصص',          'workflow',             'webhook', 'link',                'إرسال HTTP POST لأي رابط',                              FALSE, TRUE,
    '{"required":["target_url"],"fields":[{"name":"target_url","label":"Target URL","type":"url"},{"name":"auth_header","label":"Authorization Header","type":"password"}]}')
ON CONFLICT (code) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- 2) int_connections — اتصالات مفعّلة لكل مزوّد
--    DECISION: config JSONB لتخزين البيانات الحساسة مشفَّرة عبر
--    Supabase Vault (يُوصى بتفعيله يدويًا للبيانات الحساسة).
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS int_connections (
  id                    BIGSERIAL PRIMARY KEY,
  provider_id           BIGINT NOT NULL REFERENCES int_providers(id) ON DELETE RESTRICT,
  name                  TEXT NOT NULL,
  branch_id             BIGINT REFERENCES branches(id) ON DELETE CASCADE,
  config                JSONB NOT NULL DEFAULT '{}'::JSONB,
  status                TEXT NOT NULL DEFAULT 'inactive'
                         CHECK (status IN ('inactive', 'active', 'error', 'testing', 'suspended')),
  last_error            TEXT,
  last_success_at       TIMESTAMPTZ,
  last_error_at         TIMESTAMPTZ,
  total_events_success  BIGINT NOT NULL DEFAULT 0,
  total_events_failed   BIGINT NOT NULL DEFAULT 0,
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT int_conn_unique_name UNIQUE (provider_id, name)
);

CREATE INDEX IF NOT EXISTS int_conn_provider_idx ON int_connections(provider_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS int_conn_branch_idx   ON int_connections(branch_id) WHERE branch_id IS NOT NULL;

DROP TRIGGER IF EXISTS int_conn_updated_at ON int_connections;
CREATE TRIGGER int_conn_updated_at BEFORE UPDATE ON int_connections
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) int_webhook_endpoints — نقاط استقبال للـ Webhooks الواردة
--    كل endpoint له slug فريد يُستخدم في URL: /api/webhooks/<slug>
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS int_webhook_endpoints (
  id              BIGSERIAL PRIMARY KEY,
  connection_id   BIGINT NOT NULL REFERENCES int_connections(id) ON DELETE CASCADE,
  slug            TEXT UNIQUE NOT NULL,
  secret_token    TEXT NOT NULL,
  event_types     TEXT[],
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  total_received  BIGINT NOT NULL DEFAULT 0,
  last_received_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS int_webhooks_conn_idx ON int_webhook_endpoints(connection_id) WHERE is_active;

DROP TRIGGER IF EXISTS int_webhooks_updated_at ON int_webhook_endpoints;
CREATE TRIGGER int_webhooks_updated_at BEFORE UPDATE ON int_webhook_endpoints
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 4) int_events — سجل كل الأحداث inbound/outbound
--    DECISION: نسجل كل حدث لتتبع كامل ومحاولات إعادة إرسال.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS int_events (
  id                BIGSERIAL PRIMARY KEY,
  event_no          TEXT UNIQUE,
  connection_id     BIGINT REFERENCES int_connections(id) ON DELETE SET NULL,
  provider_code     TEXT,
  direction         TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  event_type        TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'processing', 'success', 'failed', 'retrying', 'skipped')),
  payload           JSONB NOT NULL DEFAULT '{}'::JSONB,
  response          JSONB,
  http_status       INT,
  error_message     TEXT,
  attempt_count     INT NOT NULL DEFAULT 0,
  max_attempts      INT NOT NULL DEFAULT 3,
  next_retry_at     TIMESTAMPTZ,
  related_entity_type TEXT,
  related_entity_id BIGINT,
  triggered_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  processed_at      TIMESTAMPTZ,
  duration_ms       INT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS int_events_conn_idx     ON int_events(connection_id, created_at DESC) WHERE connection_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS int_events_status_idx   ON int_events(status) WHERE status IN ('pending', 'retrying');
CREATE INDEX IF NOT EXISTS int_events_retry_idx    ON int_events(next_retry_at) WHERE status = 'retrying';
CREATE INDEX IF NOT EXISTS int_events_type_idx     ON int_events(event_type, direction, created_at DESC);
CREATE INDEX IF NOT EXISTS int_events_related_idx  ON int_events(related_entity_type, related_entity_id) WHERE related_entity_type IS NOT NULL;

DROP TRIGGER IF EXISTS int_events_updated_at ON int_events;
CREATE TRIGGER int_events_updated_at BEFORE UPDATE ON int_events
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION int_assign_event_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  BIGINT;
BEGIN
  IF NEW.event_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM int_events WHERE event_no LIKE 'INT-' || v_year || '-%';
    NEW.event_no := 'INT-' || v_year || '-' || LPAD(v_seq::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS int_events_assign_no ON int_events;
CREATE TRIGGER int_events_assign_no BEFORE INSERT ON int_events
  FOR EACH ROW EXECUTE FUNCTION int_assign_event_no();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دوال العمليات
-- ═══════════════════════════════════════════════════════════

-- تسجيل حدث جديد + تحديث إحصائيات الاتصال
CREATE OR REPLACE FUNCTION int_log_event(
  p_connection_id BIGINT,
  p_direction TEXT,
  p_event_type TEXT,
  p_payload JSONB,
  p_status TEXT DEFAULT 'pending',
  p_related_type TEXT DEFAULT NULL,
  p_related_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO int_events (connection_id, direction, event_type, payload, status,
                          related_entity_type, related_entity_id, triggered_by)
  VALUES (p_connection_id, p_direction, p_event_type, COALESCE(p_payload, '{}'::JSONB),
          p_status, p_related_type, p_related_id, current_app_user_id())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- تحديث نتيجة حدث + تحديث إحصائيات الاتصال
CREATE OR REPLACE FUNCTION int_complete_event(
  p_event_id BIGINT,
  p_status TEXT,
  p_response JSONB DEFAULT NULL,
  p_http_status INT DEFAULT NULL,
  p_error TEXT DEFAULT NULL,
  p_duration_ms INT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event RECORD;
BEGIN
  UPDATE int_events SET
    status = p_status,
    response = COALESCE(p_response, response),
    http_status = COALESCE(p_http_status, http_status),
    error_message = COALESCE(p_error, error_message),
    duration_ms = COALESCE(p_duration_ms, duration_ms),
    processed_at = now(),
    attempt_count = attempt_count + 1
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  IF v_event.connection_id IS NOT NULL THEN
    UPDATE int_connections SET
      total_events_success = total_events_success + CASE WHEN p_status = 'success' THEN 1 ELSE 0 END,
      total_events_failed  = total_events_failed  + CASE WHEN p_status = 'failed'  THEN 1 ELSE 0 END,
      last_success_at      = CASE WHEN p_status = 'success' THEN now() ELSE last_success_at END,
      last_error_at        = CASE WHEN p_status = 'failed'  THEN now() ELSE last_error_at   END,
      last_error           = CASE WHEN p_status = 'failed'  THEN p_error ELSE last_error    END,
      status               = CASE WHEN p_status = 'failed' AND status = 'active' THEN 'error' ELSE status END
    WHERE id = v_event.connection_id;
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE int_providers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE int_connections        ENABLE ROW LEVEL SECURITY;
ALTER TABLE int_webhook_endpoints  ENABLE ROW LEVEL SECURITY;
ALTER TABLE int_events             ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS int_prov_sel ON int_providers;
CREATE POLICY int_prov_sel ON int_providers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS int_prov_wr ON int_providers;
CREATE POLICY int_prov_wr ON int_providers FOR ALL TO authenticated
  USING (current_app_role() = 'admin') WITH CHECK (current_app_role() = 'admin');

DROP POLICY IF EXISTS int_conn_sel ON int_connections;
CREATE POLICY int_conn_sel ON int_connections FOR SELECT TO authenticated
  USING (is_integrations_manager());
DROP POLICY IF EXISTS int_conn_wr ON int_connections;
CREATE POLICY int_conn_wr ON int_connections FOR ALL TO authenticated
  USING (is_integrations_manager()) WITH CHECK (is_integrations_manager());

DROP POLICY IF EXISTS int_wh_sel ON int_webhook_endpoints;
CREATE POLICY int_wh_sel ON int_webhook_endpoints FOR SELECT TO authenticated
  USING (is_integrations_manager());
DROP POLICY IF EXISTS int_wh_wr ON int_webhook_endpoints;
CREATE POLICY int_wh_wr ON int_webhook_endpoints FOR ALL TO authenticated
  USING (is_integrations_manager()) WITH CHECK (is_integrations_manager());

DROP POLICY IF EXISTS int_ev_sel ON int_events;
CREATE POLICY int_ev_sel ON int_events FOR SELECT TO authenticated
  USING (is_integrations_manager());
DROP POLICY IF EXISTS int_ev_ins ON int_events;
CREATE POLICY int_ev_ins ON int_events FOR INSERT TO authenticated
  WITH CHECK (is_integrations_manager());
DROP POLICY IF EXISTS int_ev_upd ON int_events;
CREATE POLICY int_ev_upd ON int_events FOR UPDATE TO authenticated
  USING (is_integrations_manager()) WITH CHECK (is_integrations_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT count(*) FROM int_providers;  -- 12 مزوّدًا مبذورًا
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'int_%';
-- 3) SELECT relname FROM pg_class WHERE relname LIKE 'int_%';
-- ═══════════════════════════════════════════════════════════
