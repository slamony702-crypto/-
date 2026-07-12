-- ═══════════════════════════════════════════════════════════
-- تنظيف الحسابات الوهمية والتجريبية
-- ═══════════════════════════════════════════════════════════
-- ⚠️ لا تُشغّل هذا الملف إلا لما تخلّص اختبار الفيتشرز.
-- بيمسح: admin (أحمد المدير العام)، mona.emp، test_admin، test_manager، test_employee
-- ═══════════════════════════════════════════════════════════

begin;

-- تنظيف الارتباطات قبل الحذف
delete from user_permission_overrides
  where user_id in (
    select id from users
    where username in ('admin', 'mona.emp', 'test_admin', 'test_manager', 'test_employee')
  );

-- فكّ المدير المباشر لو كان يشير لأحد الحسابات دي
update users set direct_manager_id = null
  where direct_manager_id in (
    select id from users
    where username in ('admin', 'mona.emp', 'test_admin', 'test_manager', 'test_employee')
  );

-- حذف الحسابات
delete from users
where username in ('admin', 'mona.emp', 'test_admin', 'test_manager', 'test_employee');

-- عرض المتبقّي للتأكد
select id, username, full_name, role, is_active
from users
order by id;

commit;

-- ملاحظة: لو حابب تشيل الحسابات المقابلة من Supabase Auth كمان،
-- روح Authentication → Users → احذف اليدويًا بنفس الإيميلات:
-- admin@shouon.internal, monaemp@shouon.internal, test_admin@example.com,
-- test_manager@example.com, test_employee@example.com
