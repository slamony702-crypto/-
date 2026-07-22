-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 01 — الأساس المشترك (Audit + دوال التتبع)
-- ═══════════════════════════════════════════════════════════════════════
-- إضافي بحت: ينشئ جدول تدقيق موحّدًا ودوال تريجر عامة. لا يلمس أي جدول
-- قائم ولا يحذف أي بيانات. آمن لإعادة التشغيل (idempotent).
--
-- يوفّر للموديولات التسعة متطلبًا مشتركًا مطلوبًا: سجل «من فعل ماذا، القيمة
-- السابقة والجديدة، ومتى». التريجرز نفسها تُربَط بكل جدول داخل ملف الموديول
-- الخاص به (لا هنا) حتى يبقى كل موديول معزولًا.
--
-- يعتمد على: current_app_user_id(), current_app_role() (دوال RLS القائمة).
-- إن لم تكن موجودة، شغّل preflight أولًا وأبلغني.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── (1) جدول التدقيق الموحّد ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pilot_audit_log (
  id             BIGSERIAL PRIMARY KEY,
  table_name     TEXT        NOT NULL,
  record_id      TEXT,                          -- مفتاح السجل (نصّي ليشمل bigint/uuid)
  action         TEXT        NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  actor_user_id  BIGINT,                        -- من نفّذ (current_app_user_id وقت التغيير)
  actor_role     TEXT,                          -- دوره وقتها
  branch_id      BIGINT,                        -- الفرع (أفضل جهد من الصف)
  changed_fields TEXT[],                        -- الحقول المتغيّرة (للتحديث فقط)
  old_values     JSONB,                         -- القيمة السابقة
  new_values     JSONB,                         -- القيمة الجديدة
  note           TEXT,                          -- ملاحظة اختيارية (لأحداث منطق التطبيق)
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS pilot_audit_tbl_rec_idx  ON pilot_audit_log (table_name, record_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pilot_audit_actor_idx    ON pilot_audit_log (actor_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pilot_audit_branch_idx   ON pilot_audit_log (branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pilot_audit_created_idx  ON pilot_audit_log (created_at DESC);

-- ─── (2) تحويل آمن لنص→bigint (لا يرمي خطأ لو القيمة غير رقمية) ─────────
CREATE OR REPLACE FUNCTION pilot_safe_bigint(p TEXT)
RETURNS BIGINT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p ~ '^[0-9]+$' THEN p::BIGINT ELSE NULL END;
$$;

-- ─── (3) دالة تريجر تدقيق عامة تعمل مع أي جدول (تعتمد to_jsonb) ────────
CREATE OR REPLACE FUNCTION pilot_audit_trigger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_old JSONB; v_new JSONB; v_id TEXT; v_changed TEXT[]; v_branch BIGINT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_old := to_jsonb(OLD); v_id := v_old->>'id';
  ELSIF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW); v_id := v_new->>'id';
  ELSE
    v_old := to_jsonb(OLD); v_new := to_jsonb(NEW); v_id := v_new->>'id';
    SELECT array_agg(n.key) INTO v_changed
    FROM jsonb_each(v_new) n
    WHERE n.value IS DISTINCT FROM (v_old -> n.key);
    -- لا نسجّل تحديثًا لم يغيّر شيئًا فعليًا (أو غيّر updated_at فقط)
    IF v_changed IS NULL OR v_changed = ARRAY['updated_at']::text[] THEN
      RETURN NEW;
    END IF;
  END IF;

  v_branch := COALESCE(
    pilot_safe_bigint(v_new->>'branch_id'),
    pilot_safe_bigint(v_old->>'branch_id')
  );

  INSERT INTO pilot_audit_log(table_name, record_id, action, actor_user_id,
                              actor_role, branch_id, changed_fields, old_values, new_values)
  VALUES (TG_TABLE_NAME, v_id, TG_OP, current_app_user_id(),
          current_app_role(), v_branch, v_changed, v_old, v_new);

  RETURN COALESCE(NEW, OLD);
END $$;

-- ─── (4) دالة لضبط updated_at/updated_by تلقائيًا (للجداول التي تملك العمودين) ─
CREATE OR REPLACE FUNCTION pilot_touch_row()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at := NOW();
  BEGIN
    NEW.updated_by := current_app_user_id();
  EXCEPTION WHEN undefined_column THEN
    NULL; -- الجدول لا يملك updated_by — نتجاهل بهدوء
  END;
  RETURN NEW;
END $$;

-- ملاحظة: حارس انتقال الحالة يُعرَّف لكل موديول داخل ملفه بجدول انتقالات
-- صريح (أوضح وأسهل مراجعةً من دالة عامة)، لذلك لا يوجد حارس عام هنا.

-- ─── (6) RLS على سجل التدقيق: قراءة للإدارة فقط، ولا تعديل/حذف إطلاقًا ──
ALTER TABLE pilot_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pilot_audit_select ON pilot_audit_log;
CREATE POLICY pilot_audit_select ON pilot_audit_log
  FOR SELECT TO authenticated USING (
    current_app_role() IN ('admin','company_manager')
    OR (branch_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = current_app_user_id()
        AND u.branch_id = pilot_audit_log.branch_id
        AND u.role IN ('branch_manager','deputy_manager','department_manager')
    ))
  );

-- لا سياسات INSERT/UPDATE/DELETE للمستخدمين: الكتابة تتم فقط عبر التريجر
-- (SECURITY DEFINER) الذي يتجاوز RLS. أي محاولة كتابة مباشرة من المستخدم
-- تُرفض تلقائيًا (لا سياسة = ممنوع). السجل بذلك append-only فعليًا.

-- ═══════════════════════════════════════════════════════════════════════
-- تأكيد
-- ═══════════════════════════════════════════════════════════════════════
SELECT 'pilot_audit_log' AS object, 'ready' AS status,
       (SELECT count(*)::text FROM pilot_audit_log) AS rows
UNION ALL
SELECT 'helpers', 'ready',
       (SELECT count(*)::text FROM pg_proc
        WHERE proname IN ('pilot_audit_trigger','pilot_touch_row','pilot_safe_bigint'));
