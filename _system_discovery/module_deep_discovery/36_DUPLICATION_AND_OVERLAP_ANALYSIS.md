# 36 — تحليل التكرارات والتداخل (Duplication & Overlap)

## أ) التكرارات على مستوى البيانات

| # | التكرار | المصدر | التأثير | التوصية |
|---|---|---|---|---|
| 1 | `crm_customers` مقابل `acct_customers` | R-08 | تكرار بيانات، عدم اتساق | توحيد (قرار المالك) |
| 2 | `hr_departments` مقابل `departments` | HR schema | تكرار مقصود لكن مربك | توحيد أو توضيح النطاق |
| 3 | `hr_employee_profile.branch_id` مقابل `users.branch_id` | HR | احتمال عدم تزامن | trigger sync أو FK |
| 4 | `haccp_health_certificates` مقابل بيانات HR | HACCP | تكرار شهادات | ربط FK لموظف |
| 5 | `branch_assets` مقابل `maintenance_equipment` مقابل `maintenance_assets` | Maintenance | 3 مسارات متقاربة | توحيد `assets` مع `category` |
| 6 | `acct_purchase_orders` مقابل `proc_purchase_orders` | Accounting/Procurement | نطاقان لكن مربك | توضيح أو دمج |
| 7 | `franchise_branches` مقابل `branches` | Franchise | عمدي (فروع الفرنشايز غير مملوكة) | إبقاء منفصل مع توثيق |
| 8 | `meeting_tasks` مقابل `action_items` | Meetings | تكرار محتمل | توحيد |
| 9 | `action_items` مقابل `department_tasks` | Meetings/Tasks | مسميات مربكة | إعادة تسمية أو دمج |
| 10 | POS transactions مقابل Ops orders | POS/Ops | نطاقان (بيع/مطبخ) | توضيح UI |

## ب) التكرارات على مستوى الصفحات (Routes)

| # | التكرار | التوصية |
|---|---|---|
| 1 | `#tasks` (Action Items) مقابل `#department_tasks` | إعادة تسمية `#tasks` → `#action_items` |
| 2 | `#reports` مقابل `#analytics` مقابل `#bi_reports` | إلغاء القديمين بعد اعتماد BI |
| 3 | `#maintenance` مقابل `#maintenance_equipment` مقابل `#maintenance_assets` | توحيد assets |
| 4 | `#hr_organization` مقابل `#users` (كلاهما يعرض هيكل) | توضيح الفرق |
| 5 | `#my_profile` مقابل `#hr_employee/:id` | توحيد كـ tabs |

## ج) التكرارات على مستوى UI

| # | التكرار | الحل |
|---|---|---|
| 1 | 4 أنماط hero (`.mod-hero`, `.hr-emp-hero`, `.hero-card`, `.task-page-header`) | توحيد `.mod-hero` v123 |
| 2 | 4 أنماط KPI (`.kpi-card`, `.kpi-value`, `.stat-card-premium`, `.stat-card .value`) | توحيد |
| 3 | 41 قيمة font-size حرفية | تطبيق `--fs-*` |
| 4 | 34+ قيمة border-radius | تطبيق `--radius-*` |
| 5 | ألوان hardcoded في meetings calendar | نقل إلى CSS variables |

## د) التكرارات على مستوى الوظائف

| # | التكرار | الحل |
|---|---|---|
| 1 | AI Assistant (7 tools) مقابل AI Rewrite (Gemini) | خدمتان لنفس Provider — قد يُجمعان في `/api/ai/*` |
| 2 | Voice Search مقابل AI Assistant | تكامل: مايك واحد + AI |
| 3 | Emergency channel مقابل Chat channel | يستخدمان نفس البنية `conversations` — قد يُوضح |
| 4 | Vision goals مقابل Performance goals | ربط أو دمج |
| 5 | Documents مقابل Attachments في كل موديول | تحويل كل المرفقات إلى Documents مع polymorphic |

## هـ) التداخل الوظيفي (Function Overlap)

| # | الوظيفة | الموديولات المتداخلة | التوضيح |
|---|---|---|---|
| 1 | إسناد مهمة | Meetings, Action Items, Department Tasks, Decisions | 4 مصادر لنفس الفكرة |
| 2 | تسجيل عميل | CRM, Accounting | R-08 |
| 3 | شهادة موظف | HR, HACCP, Documents | 3 أماكن |
| 4 | فاتورة | POS, Cafe, Franchise, Accounting AR | 4 مصادر تنشئ فواتير |
| 5 | إشعار | Notifications, Emergency, Chat, Push, WhatsApp | 5 قنوات (اختياري لكن غير موحد) |
| 6 | تقرير | Reports, Analytics, BI | 3 مسارات |
| 7 | إعدادات | System settings, Module settings (كل موديول له `_settings`) | disperse |

## و) توصيات التوحيد (Priority)

1. **HIGH:** `crm_customers` + `acct_customers` (R-08).
2. **HIGH:** Action Items + Department Tasks (تسميات/دمج).
3. **HIGH:** توحيد `assets` (branch_assets + maintenance_equipment + maintenance_assets).
4. **MEDIUM:** توحيد `departments` + `hr_departments`.
5. **MEDIUM:** إلغاء `#reports` و `#analytics` القديمة بعد BI stable.
6. **MEDIUM:** UI unified hero + KPI (توسيع v123).
7. **LOW:** توحيد AI endpoints.

## ز) قرارات المالك المطلوبة

راجع `43_OWNER_DECISIONS_REQUIRED.md`. المرتبطة بهذا الملف: 1, 2, 3, 4.
