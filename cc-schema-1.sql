-- ═══════════════════════════════════════════════════════════
-- مركز الاتصال Call Center — Phase 1 (Wave 3 Module 32)
-- ═══════════════════════════════════════════════════════════
-- 4 جداول: موظفي الكول سنتر + المكالمات + التصنيفات + السكريبتات
-- + دالة cc_end_call() لإنهاء المكالمة وتحديث إحصائيات الموظف
-- + تصنيفات وسكريبتات مبذورة
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير مركز الاتصال
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_cc_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'cc_manager', 'customer_service_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) cc_agents — موظفي الكول سنتر
--    DECISION: مربوطين بحسابات users؛ رقم الامتداد اختياري.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cc_agents (
  id                    BIGSERIAL PRIMARY KEY,
  user_id               BIGINT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  extension             TEXT UNIQUE,
  status                TEXT NOT NULL DEFAULT 'offline'
                         CHECK (status IN ('offline', 'available', 'on_call', 'break', 'training', 'unavailable')),
  skills                TEXT[],
  languages             TEXT[] DEFAULT ARRAY['ar'],
  max_concurrent_calls  INT NOT NULL DEFAULT 1 CHECK (max_concurrent_calls > 0),
  total_calls_handled   INT NOT NULL DEFAULT 0,
  total_talk_seconds    BIGINT NOT NULL DEFAULT 0,
  average_call_rating   NUMERIC(3,2),
  is_active             BOOLEAN NOT NULL DEFAULT TRUE,
  hired_at              DATE,
  notes                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cc_agents_status_idx ON cc_agents(status) WHERE is_active;

DROP TRIGGER IF EXISTS cc_agents_updated_at ON cc_agents;
CREATE TRIGGER cc_agents_updated_at BEFORE UPDATE ON cc_agents
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) cc_dispositions — نتائج المكالمات (Dispositions)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cc_dispositions (
  id              BIGSERIAL PRIMARY KEY,
  code            TEXT UNIQUE NOT NULL,
  name            TEXT NOT NULL,
  category        TEXT NOT NULL CHECK (category IN ('resolved', 'callback', 'transferred', 'escalated', 'no_answer', 'wrong_number', 'complaint', 'sale', 'inquiry', 'other')),
  is_success      BOOLEAN NOT NULL DEFAULT FALSE,
  requires_followup BOOLEAN NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO cc_dispositions (code, name, category, is_success, requires_followup) VALUES
  ('RESOLVED',       'تم حل الاستفسار',           'resolved',    TRUE,  FALSE),
  ('CALLBACK',       'مطلوب اتصال لاحق',           'callback',    FALSE, TRUE),
  ('TRANSFERRED',    'حُوِّلت لقسم آخر',            'transferred', FALSE, FALSE),
  ('ESCALATED',      'تصعيد للمدير',                'escalated',   FALSE, TRUE),
  ('NO_ANSWER',      'لم يُرد',                     'no_answer',   FALSE, TRUE),
  ('WRONG_NUMBER',   'رقم خاطئ',                    'wrong_number', FALSE, FALSE),
  ('COMPLAINT',      'تسجيل شكوى',                  'complaint',   FALSE, TRUE),
  ('ORDER_PLACED',   'تم أخذ طلب',                  'sale',        TRUE,  FALSE),
  ('INQUIRY',        'استفسار عام',                 'inquiry',     TRUE,  FALSE),
  ('FEEDBACK',       'استلام ملاحظة/اقتراح',       'inquiry',     TRUE,  FALSE),
  ('OTHER',          'أخرى',                        'other',       FALSE, FALSE)
ON CONFLICT (code) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- 3) cc_calls — سجل المكالمات
--    DECISION: نتتبع inbound/outbound + الربط بعميل CRM والشكاوى.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cc_calls (
  id                  BIGSERIAL PRIMARY KEY,
  call_no             TEXT UNIQUE,
  direction           TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  agent_id            BIGINT REFERENCES cc_agents(id) ON DELETE SET NULL,
  customer_id         BIGINT REFERENCES crm_customers(id) ON DELETE SET NULL,
  phone_number        TEXT NOT NULL,
  caller_name         TEXT,
  branch_id           BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  purpose             TEXT NOT NULL DEFAULT 'inquiry'
                       CHECK (purpose IN ('inquiry', 'complaint', 'order', 'reservation', 'follow_up', 'delivery', 'other')),
  disposition_id      BIGINT REFERENCES cc_dispositions(id) ON DELETE SET NULL,
  status              TEXT NOT NULL DEFAULT 'in_progress'
                       CHECK (status IN ('ringing', 'in_progress', 'completed', 'missed', 'abandoned')),
  started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  answered_at         TIMESTAMPTZ,
  ended_at            TIMESTAMPTZ,
  duration_seconds    INT,
  wait_seconds        INT,
  summary             TEXT,
  notes               TEXT,
  followup_required   BOOLEAN NOT NULL DEFAULT FALSE,
  followup_date       DATE,
  followup_notes      TEXT,
  followup_done       BOOLEAN NOT NULL DEFAULT FALSE,
  related_complaint_id BIGINT REFERENCES crm_complaints(id) ON DELETE SET NULL,
  related_pos_txn_id  BIGINT REFERENCES pos_transactions(id) ON DELETE SET NULL,
  related_delivery_id BIGINT REFERENCES delivery_orders(id) ON DELETE SET NULL,
  recording_url       TEXT,
  customer_rating     INT CHECK (customer_rating IS NULL OR customer_rating BETWEEN 1 AND 5),
  customer_feedback   TEXT,
  tags                TEXT[],
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cc_calls_agent_idx     ON cc_calls(agent_id, started_at DESC);
CREATE INDEX IF NOT EXISTS cc_calls_customer_idx  ON cc_calls(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS cc_calls_phone_idx     ON cc_calls(phone_number);
CREATE INDEX IF NOT EXISTS cc_calls_status_idx    ON cc_calls(status) WHERE status IN ('ringing', 'in_progress');
CREATE INDEX IF NOT EXISTS cc_calls_followup_idx  ON cc_calls(followup_date) WHERE followup_required AND NOT followup_done;
CREATE INDEX IF NOT EXISTS cc_calls_date_idx      ON cc_calls(started_at DESC);

DROP TRIGGER IF EXISTS cc_calls_updated_at ON cc_calls;
CREATE TRIGGER cc_calls_updated_at BEFORE UPDATE ON cc_calls
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION cc_assign_call_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  BIGINT;
BEGIN
  IF NEW.call_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM cc_calls WHERE call_no LIKE 'CALL-' || v_year || '-%';
    NEW.call_no := 'CALL-' || v_year || '-' || LPAD(v_seq::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cc_calls_assign_no ON cc_calls;
CREATE TRIGGER cc_calls_assign_no BEFORE INSERT ON cc_calls
  FOR EACH ROW EXECUTE FUNCTION cc_assign_call_no();

-- ───────────────────────────────────────────────────────────
-- 4) cc_scripts — سكريبتات جاهزة للموظفين
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cc_scripts (
  id              BIGSERIAL PRIMARY KEY,
  title           TEXT NOT NULL,
  category        TEXT NOT NULL CHECK (category IN ('greeting', 'complaint', 'order', 'inquiry', 'closing', 'objection', 'other')),
  content         TEXT NOT NULL,
  language        TEXT NOT NULL DEFAULT 'ar',
  usage_count     INT NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_by      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cc_scripts_category_idx ON cc_scripts(category) WHERE is_active;

DROP TRIGGER IF EXISTS cc_scripts_updated_at ON cc_scripts;
CREATE TRIGGER cc_scripts_updated_at BEFORE UPDATE ON cc_scripts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- بذر سكريبتات افتراضية
-- ضمان idempotency: UNIQUE على title حتى يعمل ON CONFLICT فعليًا
-- (بدون هذا القيد كل rerun يضيف السكريبتات الست مرة أخرى)

-- الخطوة 1: تنظيف أي تكرار من runs سابقة قبل الإصلاح.
-- (لا يوجد FK على cc_scripts، حذف مباشر آمن — نحتفظ بأصغر id لكل title)
DELETE FROM cc_scripts
WHERE id NOT IN (
  SELECT MIN(id) FROM cc_scripts GROUP BY title
);

-- الخطوة 2: إضافة القيد UNIQUE (آمن الآن بعد التنظيف)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cc_scripts_title_unique'
  ) THEN
    ALTER TABLE cc_scripts
      ADD CONSTRAINT cc_scripts_title_unique UNIQUE (title);
  END IF;
END $$;

INSERT INTO cc_scripts (title, category, content) VALUES
  ('الترحيب الرسمي', 'greeting', 'أهلًا وسهلًا بك في شؤون الغذاء، معك [اسم الموظف]، كيف أقدر أساعدك؟'),
  ('استلام شكوى', 'complaint', 'اسمح لي أفهم موضوعك بالتفصيل. ممكن تخبرني بالتاريخ والفرع اللي حدث فيه الموقف؟ سنعتذر لك ونحل الموضوع في أسرع وقت.'),
  ('استقبال طلب توصيل', 'order', 'ممكن أعرف اسمك الكريم ورقم جوالك؟ والعنوان بالتفصيل من فضلك، ثم نراجع الطلب معًا قبل التأكيد.'),
  ('استفسار عن المنيو', 'inquiry', 'بكل سرور. تحب أطلعك على قائمة اليوم أم فئة معينة (وجبات رئيسية، مشروبات، حلا)؟'),
  ('إغلاق مكالمة إيجابية', 'closing', 'شكرًا لك على تواصلك معنا. لو احتجت أي شيء آخر لا تتردد في الاتصال. يومك سعيد.'),
  ('التعامل مع اعتراض السعر', 'objection', 'أتفهم شعورك، وأود أخبرك أن جودتنا ومكوناتنا الطازجة تُبرِّر السعر. لدينا أيضًا عروض قد تعجبك، تحب أطلعك عليها؟')
ON CONFLICT (title) DO NOTHING;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة إنهاء المكالمة (atomic)
-- تحسب المدة + تحدّث إحصائيات الموظف + تسجّل النتيجة
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION cc_end_call(
  p_call_id BIGINT,
  p_disposition_id BIGINT DEFAULT NULL,
  p_summary TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_call     RECORD;
  v_duration INT;
BEGIN
  SELECT * INTO v_call FROM cc_calls WHERE id = p_call_id;
  IF v_call IS NULL THEN RAISE EXCEPTION 'المكالمة غير موجودة'; END IF;
  IF v_call.status = 'completed' THEN RAISE EXCEPTION 'المكالمة منتهية بالفعل'; END IF;

  v_duration := EXTRACT(EPOCH FROM (now() - v_call.started_at))::INT;

  UPDATE cc_calls SET
    status = 'completed',
    ended_at = now(),
    duration_seconds = v_duration,
    disposition_id = COALESCE(p_disposition_id, disposition_id),
    summary = COALESCE(p_summary, summary),
    notes = COALESCE(p_notes, notes)
  WHERE id = p_call_id;

  -- تحديث إحصائيات الموظف
  IF v_call.agent_id IS NOT NULL THEN
    UPDATE cc_agents
    SET total_calls_handled = total_calls_handled + 1,
        total_talk_seconds = total_talk_seconds + v_duration,
        status = CASE WHEN status = 'on_call' THEN 'available' ELSE status END
    WHERE id = v_call.agent_id;
  END IF;

  RETURN v_duration;
END;
$$;

-- بدء مكالمة (يحدّث حالة الموظف)
CREATE OR REPLACE FUNCTION cc_start_call(p_call_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_agent_id BIGINT;
BEGIN
  UPDATE cc_calls SET status = 'in_progress', answered_at = COALESCE(answered_at, now())
    WHERE id = p_call_id RETURNING agent_id INTO v_agent_id;
  IF v_agent_id IS NOT NULL THEN
    UPDATE cc_agents SET status = 'on_call' WHERE id = v_agent_id;
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE cc_agents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE cc_dispositions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE cc_calls         ENABLE ROW LEVEL SECURITY;
ALTER TABLE cc_scripts       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cc_agents_sel ON cc_agents;
CREATE POLICY cc_agents_sel ON cc_agents FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS cc_agents_wr ON cc_agents;
CREATE POLICY cc_agents_wr ON cc_agents FOR ALL TO authenticated
  USING (is_cc_manager()
         OR (user_id = current_app_user_id()))  -- الموظف يقدر يغير حالته الشخصية
  WITH CHECK (is_cc_manager()
         OR (user_id = current_app_user_id()));

DROP POLICY IF EXISTS cc_disp_sel ON cc_dispositions;
CREATE POLICY cc_disp_sel ON cc_dispositions FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS cc_disp_wr ON cc_dispositions;
CREATE POLICY cc_disp_wr ON cc_dispositions FOR ALL TO authenticated
  USING (is_cc_manager()) WITH CHECK (is_cc_manager());

DROP POLICY IF EXISTS cc_calls_sel ON cc_calls;
CREATE POLICY cc_calls_sel ON cc_calls FOR SELECT TO authenticated USING (
  is_cc_manager()
  OR EXISTS (SELECT 1 FROM cc_agents a WHERE a.id = cc_calls.agent_id AND a.user_id = current_app_user_id())
  OR current_app_role() IN ('customer_service_manager', 'branch_manager', 'deputy_manager')
);
DROP POLICY IF EXISTS cc_calls_ins ON cc_calls;
CREATE POLICY cc_calls_ins ON cc_calls FOR INSERT TO authenticated
  WITH CHECK (
    is_cc_manager()
    OR EXISTS (SELECT 1 FROM cc_agents a WHERE a.id = cc_calls.agent_id AND a.user_id = current_app_user_id())
  );
DROP POLICY IF EXISTS cc_calls_upd ON cc_calls;
CREATE POLICY cc_calls_upd ON cc_calls FOR UPDATE TO authenticated USING (
  is_cc_manager()
  OR EXISTS (SELECT 1 FROM cc_agents a WHERE a.id = cc_calls.agent_id AND a.user_id = current_app_user_id())
);

DROP POLICY IF EXISTS cc_scripts_sel ON cc_scripts;
CREATE POLICY cc_scripts_sel ON cc_scripts FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS cc_scripts_wr ON cc_scripts;
CREATE POLICY cc_scripts_wr ON cc_scripts FOR ALL TO authenticated
  USING (is_cc_manager()) WITH CHECK (is_cc_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT count(*) FROM cc_dispositions;  -- 11 مبذور
-- 2) SELECT count(*) FROM cc_scripts;       -- 6 سكريبتات
-- 3) SELECT proname FROM pg_proc WHERE proname LIKE 'cc_%';
-- 4) SELECT relname FROM pg_class WHERE relname LIKE 'cc_%';
-- ═══════════════════════════════════════════════════════════
