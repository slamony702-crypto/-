-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 00 — دوال هوية RLS (شرط مسبق)
-- ═══════════════════════════════════════════════════════════════════════
-- يُشغَّل قبل pilot-01 لو أظهر preflight أن current_app_user_id/role مفقودتان
-- (كما في هذا الـStaging). تربطان جلسة Supabase Auth بصف المستخدم عبر
-- users.auth_id = auth.uid() — نفس النمط الذي تعتمده كل سياسات RLS للموديولات.
--
-- SECURITY DEFINER: تقرأ users بتجاوز RLS لتحديد هوية المتصل بأمان.
-- STABLE: قيمتها ثابتة داخل الاستعلام الواحد. آمن لإعادة التشغيل.
--
-- ملاحظة: إن كانت الدالتان موجودتين مسبقًا بنفس التعريف، فهذا الملف لا يغيّر
-- شيئًا. إن كانتا موجودتين بتعريف مختلف على Production، لا تشغّل هذا على
-- Production — هو لتجهيز Staging فقط.
-- ═══════════════════════════════════════════════════════════════════════

-- معرّف المستخدم الحالي (bigint) من جلسة Auth
CREATE OR REPLACE FUNCTION current_app_user_id()
RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM users WHERE auth_id = auth.uid();
$$;

-- دور المستخدم الحالي (text) من جلسة Auth
CREATE OR REPLACE FUNCTION current_app_role()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM users WHERE auth_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION current_app_user_id() FROM public;
REVOKE ALL ON FUNCTION current_app_role() FROM public;
GRANT EXECUTE ON FUNCTION current_app_user_id() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION current_app_role() TO authenticated, anon;

-- ═══ تأكيد ═══
SELECT p.proname AS function,
       CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security,
       pg_get_function_result(p.oid) AS returns
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('current_app_user_id','current_app_role')
ORDER BY 1;
