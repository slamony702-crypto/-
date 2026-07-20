# 37 — مصفوفة الصلاحيات العالمية (Global Permissions)

> **المرجع:** `_system_discovery/PERMISSIONS_AND_ROLES_AUDIT.md`.

## أ) الأدوار الرسمية (18)

راجع الملف المرجعي. الأدوار الأساسية:
- **إدارية عليا:** `admin`, `company_manager`.
- **إدارة أقسام/فروع:** `department_manager`, `branch_manager`, `deputy_manager`, `operations_manager`, `quality_manager`, `maintenance_officer`, `projects_manager`, `development_manager`, `meeting_organizer`, `hr_manager`.
- **مالية:** `finance_manager`, `gl_accountant`, `ap_officer`, `ar_officer`, `payroll_officer`, `finance` (قديم).
- **تشغيلي:** `employee`.

## ب) 17 دالة `is_*_manager()`

- **النمط:** `SELECT current_app_role() IN (...)`.
- **الأمن:** SECURITY DEFINER + `SET search_path=public` (v120 fix).
- **الأدوار المحتواة:** غالبًا `admin, company_manager, <specialist>_manager`.

## ج) مصفوفة الصلاحيات (Role × Module)

| Module | admin | CM | branch_mgr | ops_mgr | quality | hr | finance | ap/ar | maint | emp |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Users | RW | RW | R | R | R | RW | R | R | R | R(self) |
| Branches | RW | RW | R(own) | R | R | R | R | R | R | R |
| Meetings | RW | RW | RW(dept) | RW | RW | RW | RW | R | R | RW(invited) |
| Action Items | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW(assigned) |
| Tasks | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW(assigned) |
| Decisions | RW | RW | R | R | R | R | R | R | R | R(assigned) |
| Chat | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW |
| Emergency | RW(send) | RW | RW | R | RW | R | R | R | RW | R |
| Maintenance | RW | RW | RW | R | R | – | R(approval) | – | RW | R |
| Quality | RW | RW | R | R | RW | – | – | – | – | R |
| Cafe | RW | RW | RW | RW | R | – | R | – | – | R |
| Notifications | R(all) | R(all) | R(self) | R(self) | R(self) | R(self) | R(self) | R(self) | R(self) | R(self) |
| My Profile | R | R | R | R | R | R | R | R | R | RW(self) |
| Meeting Requests | RW | RW | RW | RW | RW | RW | RW | R | R | RW |
| Vision | RW | RW | R | R | – | – | – | – | – | R |
| Voice Search | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW |
| AI Rewrite | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW |
| **HR** | RW | RW | – | – | – | RW | R | – | – | R(self) |
| **Accounting** | RW | RW | R(branch) | R | – | – | RW | RW(own) | – | – |
| **Operations** | RW | RW | RW(own) | RW | – | – | R | – | – | RW |
| **Payments** | RW | RW | – | – | – | – | RW | RW | – | – |
| **AI Assistant** | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW |
| **POS** | RW | RW | RW | RW | – | – | R | – | – | RW(cashier) |
| **Menu** | RW | RW | R | RW | – | – | – | – | – | R |
| **CRM** | RW | RW | R | RW | – | – | R | – | – | R |
| **HACCP** | RW | RW | RW | R | RW | – | – | – | – | R |
| **Procurement** | RW | RW | R | RW | – | – | RW | – | – | R |
| **Performance** | RW | RW | R | R | – | RW | R | – | – | R(self) |
| **Delivery** | RW | RW | R | RW | – | – | R | – | – | R(rider) |
| **Documents** | RW | RW | R | R | R | RW | R | – | – | R(own) |
| **Call Center** | RW | RW | R | RW | – | – | – | – | – | R(agent) |
| **BI** | RW | RW | R(own) | R | – | – | RW | – | – | – |
| **Integrations** | RW | RW | – | – | – | – | – | – | – | – |
| **Franchise** | RW | RW | – | R | – | – | RW | – | – | – |

**RW** = read/write, **R** = read, **–** = no access.

## د) الفجوات الأمنية

1. **`test_admin` mega-role:** أي مستخدم بهذا الاسم يعبر كل gates (السطر 12450).
2. **`department_manager` مضمّن** في menu items بلا فحص role موحّد.
3. **Routes بلا `can()` client-side check:** الحماية على RLS فقط — قد تُظهر شاشة فارغة بدل رسالة "غير مصرح".
4. **الأدوار المالية الـ4** تقسيمها جزئي — كثير من AR pages يفتحها `finance_manager` تمامًا.
5. **`finance` role قديم** لم يُحذف.
6. **CC/DOC/PERF بلا role مخصص** — يعتمدون على `hr_manager` أو `operations_manager` كبديل.
7. **`user_permission_overrides`** موجود بلا شاشة إدارة تفصيلية.
8. **RLS يعتمد `current_app_role()` وليس Supabase JWT** — R-02 حرجة.

## هـ) توصيات

1. **إصلاح R-01 + R-02** أساسية.
2. **إضافة `can()` client-side** قبل كل route.
3. **حذف role `finance` القديم** بعد migration.
4. **إضافة roles جديدة:** `cc_manager`, `doc_manager`, `perf_manager` (اختياري).
5. **`test_admin` bypass** يجب إزالته قبل الإنتاج.
6. **UI لـ `user_permission_overrides`** — شاشة إدارة تفصيلية.
7. **Audit UI:** شاشة تعرض `user_activity_log`.

## و) دوال حراس Backend (17)

راجع `DATABASE_OVERVIEW §دوال حراس الأدوار`.
