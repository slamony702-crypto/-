-- ============================================================
-- ضبط الصلاحيات + إنشاء 3 يوزرات تجريبية
-- ============================================================
-- انسخ الكود كله والصقه في Supabase SQL Editor واضغط Run
-- ============================================================


-- ═══ الخطوة 1: مسح الصلاحيات القديمة وإعادة ضبطها ═══
delete from role_permissions where role in ('admin', 'department_manager', 'employee');


-- ═══ الخطوة 2: إدراج الصلاحيات الجديدة ═══
insert into role_permissions (role, section_key, can_view, can_manage) values

-- ┌─────────────────────────────────────────────────────────┐
-- │ ADMIN — صلاحيات كاملة على كل شيء                       │
-- └─────────────────────────────────────────────────────────┘
('admin', 'dashboard',        true, true),
('admin', 'vision',           true, true),
('admin', 'meetings',         true, true),
('admin', 'tasks',            true, true),
('admin', 'department_tasks', true, true),
('admin', 'decisions',        true, true),
('admin', 'maintenance',      true, true),
('admin', 'quality',          true, true),
('admin', 'conversations',    true, true),
('admin', 'emergency',        true, true),
('admin', 'reports',          true, true),
('admin', 'users',            true, true),
('admin', 'settings',         true, true),

-- ┌─────────────────────────────────────────────────────────┐
-- │ DEPARTMENT_MANAGER — إدارة قسمه + عرض عام              │
-- │ ممنوع: إدارة المستخدمين والإعدادات                     │
-- └─────────────────────────────────────────────────────────┘
('department_manager', 'dashboard',        true, false),
('department_manager', 'vision',           true, false),
('department_manager', 'meetings',         true, true),
('department_manager', 'tasks',            true, true),
('department_manager', 'department_tasks', true, true),
('department_manager', 'decisions',        true, true),
('department_manager', 'maintenance',      true, true),
('department_manager', 'quality',          true, true),
('department_manager', 'conversations',    true, true),
('department_manager', 'emergency',        true, false),
('department_manager', 'reports',          true, false),
('department_manager', 'users',            false, false),
('department_manager', 'settings',         false, false),

-- ┌─────────────────────────────────────────────────────────┐
-- │ EMPLOYEE — عرض ما يخصه فقط + إنشاء طلبات صيانة          │
-- │ ممنوع: تقارير، مستخدمين، إعدادات                       │
-- └─────────────────────────────────────────────────────────┘
('employee', 'dashboard',        true, false),
('employee', 'vision',           true, false),
('employee', 'meetings',         true, false),
('employee', 'tasks',            true, false),
('employee', 'department_tasks', true, false),
('employee', 'decisions',        true, false),
('employee', 'maintenance',      true, true),
('employee', 'quality',          true, false),
('employee', 'conversations',    true, true),
('employee', 'emergency',        true, false),
('employee', 'reports',          false, false),
('employee', 'users',            false, false),
('employee', 'settings',         false, false);


-- ═══ الخطوة 3: إنشاء 3 يوزرات تجريبية (واحد لكل دور) ═══
insert into users (full_name, username, password_plain, email, mobile_number, role, status, is_active) values
('تجريبي - أدمن',       'test_admin',    'test123', 'test_admin@example.com',    '0500000010', 'admin',              'active', true),
('تجريبي - مدير قسم',  'test_manager',  'test123', 'test_manager@example.com',  '0500000011', 'department_manager', 'active', true),
('تجريبي - موظف',      'test_employee', 'test123', 'test_employee@example.com', '0500000012', 'employee',           'active', true);


-- ═══ الخطوة 4: عرض النتيجة النهائية للمراجعة ═══
select id, username, full_name, role, email from users order by id;
