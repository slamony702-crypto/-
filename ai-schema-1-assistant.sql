-- ═══════════════════════════════════════════════════════════
-- المساعد الذكي (AI Assistant) — المرحلة 1: قراءة فقط
-- ═══════════════════════════════════════════════════════════
-- 4 جداول فقط: الجلسات، الرسائل، سجل التدقيق، الإعدادات.
-- القاعدة الذهبية: الوكيل لا يتجاوز RLS أبدًا — البيانات تُجلب من
-- المتصفح بصلاحيات المستخدم نفسه، والجداول هنا للجلسات والتدقيق فقط.
-- لا يوجد أي جدول تنفيذ إجراءات — المرحلة الأولى قراءة وتحليل فقط.
-- يعتمد على: current_app_user_id()، current_app_role()، set_updated_at()
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 1) ai_settings — إعدادات المساعد (صف واحد id=1)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_settings (
  id                       INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  is_enabled               BOOLEAN NOT NULL DEFAULT TRUE,
  assistant_name           TEXT NOT NULL DEFAULT 'المساعد الذكي',
  -- حد يومي لعدد أسئلة المستخدم الواحد (حماية للتكلفة)
  daily_message_limit      INT NOT NULL DEFAULT 50 CHECK (daily_message_limit > 0),
  -- تعليمات إضافية تُلحق بشخصية المساعد من غير تعديل كود
  extra_instructions       TEXT,
  created_at               TIMESTAMPTZ DEFAULT now(),
  updated_at               TIMESTAMPTZ DEFAULT now()
);

INSERT INTO ai_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS ai_settings_updated_at ON ai_settings;
CREATE TRIGGER ai_settings_updated_at BEFORE UPDATE ON ai_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) ai_sessions — جلسات المحادثة مع المساعد
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_sessions (
  id           BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title        TEXT,                        -- يُشتق من أول سؤال
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ai_sessions_user_idx ON ai_sessions(user_id, updated_at DESC) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS ai_sessions_updated_at ON ai_sessions;
CREATE TRIGGER ai_sessions_updated_at BEFORE UPDATE ON ai_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) ai_session_messages — رسائل الجلسة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_session_messages (
  id           BIGSERIAL PRIMARY KEY,
  session_id   BIGINT NOT NULL REFERENCES ai_sessions(id) ON DELETE CASCADE,
  role         TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content      TEXT NOT NULL,
  -- الأدوات المستخدمة في توليد هذا الرد (أسماء فقط + ملخص عددي، بلا بيانات خام)
  tools_used   JSONB,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_session_messages_session_idx ON ai_session_messages(session_id, created_at);

-- ───────────────────────────────────────────────────────────
-- 4) ai_audit_log — سجل تدقيق كامل (لا يُحذف ولا يُعدَّل)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_audit_log (
  id           BIGSERIAL PRIMARY KEY,
  session_id   BIGINT REFERENCES ai_sessions(id) ON DELETE SET NULL,
  user_id      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  action       TEXT NOT NULL CHECK (action IN ('question', 'tool_call', 'answer', 'error', 'blocked')),
  tool_name    TEXT,          -- عند action = tool_call
  detail       JSONB,         -- ملخص مختصر (عدد سجلات، رسالة خطأ...) — بلا بيانات حساسة
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_audit_log_user_idx    ON ai_audit_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_audit_log_session_idx ON ai_audit_log(session_id);
CREATE INDEX IF NOT EXISTS ai_audit_log_action_idx  ON ai_audit_log(action) WHERE action IN ('error', 'blocked');

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE ai_settings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_session_messages  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_audit_log         ENABLE ROW LEVEL SECURITY;

-- ai_settings: قراءة للجميع، تعديل لمدير النظام/الشركة فقط
DROP POLICY IF EXISTS ai_settings_select ON ai_settings;
CREATE POLICY ai_settings_select ON ai_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ai_settings_write ON ai_settings;
CREATE POLICY ai_settings_write ON ai_settings FOR UPDATE TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager'));

-- ai_sessions: كل مستخدم يرى جلساته فقط؛ الإدارة العليا ترى الكل للرقابة
DROP POLICY IF EXISTS ai_sessions_select ON ai_sessions;
CREATE POLICY ai_sessions_select ON ai_sessions FOR SELECT TO authenticated
  USING (user_id = current_app_user_id() OR current_app_role() IN ('admin', 'company_manager'));
DROP POLICY IF EXISTS ai_sessions_insert ON ai_sessions;
CREATE POLICY ai_sessions_insert ON ai_sessions FOR INSERT TO authenticated
  WITH CHECK (user_id = current_app_user_id());
DROP POLICY IF EXISTS ai_sessions_update ON ai_sessions;
CREATE POLICY ai_sessions_update ON ai_sessions FOR UPDATE TO authenticated
  USING (user_id = current_app_user_id())
  WITH CHECK (user_id = current_app_user_id());

-- ai_session_messages: تتبع صلاحية الجلسة الأم؛ إدراج فقط في جلسة المستخدم نفسه
DROP POLICY IF EXISTS ai_session_messages_select ON ai_session_messages;
CREATE POLICY ai_session_messages_select ON ai_session_messages FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM ai_sessions s WHERE s.id = ai_session_messages.session_id
                   AND (s.user_id = current_app_user_id() OR current_app_role() IN ('admin', 'company_manager'))));
DROP POLICY IF EXISTS ai_session_messages_insert ON ai_session_messages;
CREATE POLICY ai_session_messages_insert ON ai_session_messages FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM ai_sessions s WHERE s.id = ai_session_messages.session_id
                   AND s.user_id = current_app_user_id()));
-- لا UPDATE ولا DELETE على الرسائل — سجل المحادثة ثابت

-- ai_audit_log: إدراج فقط لصاحب الحدث؛ قراءة للإدارة العليا فقط؛ لا تعديل ولا حذف
DROP POLICY IF EXISTS ai_audit_log_insert ON ai_audit_log;
CREATE POLICY ai_audit_log_insert ON ai_audit_log FOR INSERT TO authenticated
  WITH CHECK (user_id = current_app_user_id());
DROP POLICY IF EXISTS ai_audit_log_select ON ai_audit_log;
CREATE POLICY ai_audit_log_select ON ai_audit_log FOR SELECT TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager'));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ (Post-migration checklist):
-- 1) SELECT * FROM ai_settings;            -- صف واحد id=1
-- 2) SELECT * FROM ai_sessions LIMIT 1;
-- 3) SELECT * FROM ai_session_messages LIMIT 1;
-- 4) SELECT * FROM ai_audit_log LIMIT 1;
-- 5) SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'ai_%';
--    -- كل الجداول الأربعة يجب أن تكون relrowsecurity = true
-- ═══════════════════════════════════════════════════════════
