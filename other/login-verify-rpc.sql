-- ==========================================
-- دالة آمنة للتحقق من بيانات الدخول لمستخدم لم يُنشئ حساب Auth بعد
-- تُستخدم بدل قراءة جدول users مباشرة (المحمي بـ RLS) من زائر غير مسجّل (anon)
-- بترجع أعمدة محدودة بس (مش كل بيانات المستخدم الحساسة)
-- Safe to re-run.
-- ==========================================
create or replace function verify_login(p_username text, p_password text)
returns table(id bigint, full_name text, email text, auth_id uuid, is_active boolean)
language sql
security definer
set search_path = public
as $$
  select id, full_name, email, auth_id, is_active
  from users
  where username = p_username
    and password_plain = p_password
    and is_active = true
  limit 1;
$$;

revoke all on function verify_login(text, text) from public;
grant execute on function verify_login(text, text) to anon, authenticated;
