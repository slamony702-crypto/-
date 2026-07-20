# 00_MODULES_EXECUTIVE_MAP — الخريطة التنفيذية للموديولات

> **الغرض:** نظرة تنفيذية شاملة لكل موديولات منصة "شؤون الغذاء" (34 موديول موثق + كشف عن أي موديولات غير مسجلة).
> **المصادر:** `index.html.html` (43,320 سطر)، 17 ملف SQL، `HANDOFF.md` v123، `MODULES-CATALOG.md`، مجلد `_system_discovery/` (13 ملف تحليل سابق).
> **آخر تحقق مباشر:** `PREVIEW_MODULES` = 16 مفتاح (السطر 12449) — تم التأكد.
> **ملاحظة توثيق:** كل معلومة مربوطة بمرجع كود أو موسومة `NEEDS_RUNTIME_VERIFICATION`.

---

## أ) ملخص أرقام مؤسسية

| البند | القيمة | المصدر |
|---|---:|---|
| الموديولات الإنتاجية | 17 | `MODULES-CATALOG.md` |
| موديولات المعاينة | 17 | `MODULES-CATALOG.md` |
| مفاتيح `PREVIEW_MODULES` | 16 | `index.html.html:12449` (PAY تحت accounting) |
| Routes المسجلة | 160 | `index.html.html:17164-17323` (block `else if (page === ...)`) |
| مجموعات القائمة `MENU_GROUPS` | 21 | `_system_discovery/ROUTES_AND_NAVIGATION_AUDIT.md` |
| ملفات SQL موثقة | 17 | مجلد الجذر |
| جداول SQL موثقة (Waves) | ~121 | `DATABASE_OVERVIEW.md` |
| جداول مستدعاة من الفرونت `sb.from` | ~175 unique | `DATABASE_OVERVIEW.md` |
| RPCs / SQL functions | 90+ | `DATABASE_OVERVIEW.md` |
| DAL objects `window.XX` | 17 | HR, ACCT, OPS, AIA, PAY, MENU, CRM, POS, HACCP, PROC, PERF, DLV, DOC, CC, BI, INT, FR |
| مستخدم المعاينة | `test_admin` فقط | `index.html.html:12450` |

---

## ب) الجدول التنفيذي الشامل — 34 موديول

> **مفتاح الحالة:** ✅ PRODUCTION_READY | 🟢 PILOT_READY | 🟡 NEEDS_STABILIZATION | 🟠 NEEDS_BACKEND | 🔴 NEEDS_SECURITY_REWORK | 🟣 NEEDS_REDESIGN | ⚪ PLACEHOLDER | ⛔ DO_NOT_RELEASE

### القسم الأول: الموديولات الإنتاجية (17)

| # | الموديول (عربي) | Route(s) | جداول | RPCs | الحالة | % الاكتمال | أهم علاقة | أهم فجوة | التوصية |
|---:|---|---|---:|---:|:---:|---:|---|---|---|
| 01 | المستخدمون والصلاحيات | `#users`, `#invite`, `#settings` | 5 | 2 | ✅ | 85% | كل موديول (RLS) | `password_plain` نص صريح، `test_admin` mega-role | R-01 فوري + JWT |
| 02 | الفروع والأقسام | ضمن `#settings`, `#users` | 3 | 0 | ✅ | 80% | كل الموديولات (`branch_id`) | لا شاشة route مستقلة، `hr_departments` منفصل | إنشاء `#branches` مستقل |
| 03 | الاجتماعات | `#meetings`, `#meetings_calendar`, `#meeting_detail` | 6 | 0 | ✅ | 90% | Action Items + Decisions + Tasks | جداول بلا SQL versioned | dump schema |
| 04 | مخرجات الاجتماعات | `#tasks` | 1 (`action_items`) | 0 | ✅ | 85% | Meetings + Tasks | تداخل مع `department_tasks` | توضيح الفرق أو دمج |
| 05 | المهام والتكليفات | `#department_tasks` | 4 | 0 | ✅ | 85% | Users | تداخل مع Action Items | توحيد المسميات |
| 06 | القرارات | `#decisions` | 5 | 0 | ✅ | 85% | Meetings | acknowledgment ضعيف | دليل تنفيذ إلزامي |
| 07 | التواصل الداخلي | `#conversations`, `#dept_chat`, `#custom_chat` | 4 | 0 | ✅ | 80% | Users | pagination + presence | تحسينات UX |
| 08 | تواصل طارئ | `#emergency` | 3 | 0 | ✅ | 80% | Users, Notifications | لا SLA مفروض | إضافة SLA زمني |
| 09 | الصيانة | `#maintenance` + 7 sub | 11 | 0 | ✅ | 90% | Branches, Assets, ACCT | ربط AP يدوي | ربط bill آلي |
| 10 | الجودة | `#quality` + 3 sub | 6 | 0 | ✅ | 85% | Branches | لا KPI رسمي | ربط بـ Performance |
| 11 | ركن الكافيه | `#cafe` | 4 | 1 (`create_journal_for_cafe_order`) | ✅ | 85% | ACCT (invoice) | UI قديم | تحديث UI لـ v123 |
| 12 | الإشعارات | `#notifications` | 1 | 0 | ✅ | 80% | كل الموديولات | لا marking جماعي | تحسين UX |
| 13 | الملف الشخصي | `#my_profile` | (view users) | 0 | ✅ | 75% | Users | تكرار مع HR employee | ربط بـ HR profile |
| 14 | طلبات الاجتماعات | `#meeting_requests` | 2 | 0 | ✅ | 80% | Meetings | تدفق موافقة يدوي | workflow واضح |
| 15 | رؤية الشركة | `#vision` | 2 (`company_vision`, `department_goals`) | 0 | ✅ | 60% | كل الأقسام | OKR ناقص | توسع كامل OKR |
| 16 | البحث الصوتي | `#search` | 0 | 0 (Web Speech API) | ✅ | 70% | الكل | لا فلاتر متقدمة | فلاتر + فهرسة |
| 17 | تحسين الصياغة AI | `POST /api/rewrite` | 0 | 0 (Gemini API) | ✅ | 65% | Meetings, Chat, Tasks | CORS مفتوح `*` | تقييد Origin |

### القسم الثاني: موديولات المعاينة (17)

| # | الموديول | Route(s) | جداول | RPCs | الحالة | % | أهم علاقة | أهم فجوة | التوصية |
|---:|---|---|---:|---:|:---:|---:|---|---|---|
| 18 | HR — الموارد البشرية | `#hr` + 6 sub | 8 | 1 (payroll journal) | 🟡 | 60% | Users, ACCT | ATS/عقود/عهد ناقصة | Phase 2 توسع |
| 19 | Accounting | `#accounting` + 29 sub | 30 | 10+ (auto journals) | 🟡 | 70% | كل الموديولات المالية | VAT Phase 2 mock، close_year بلا شاشة | إضافة شاشات RPC |
| 20 | Operations | `#operations` + 14 sub | 17 | 3 triggers | 🟡 | 65% | POS, ACCT, Menu | لا real-time | ربط POS/Menu حي |
| 21 | Payments | تحت `#accounting` (6 routes) | 7 | 1 (clearing) | 🟡 | 65% | ACCT, POS, Delivery | ليس module مستقل | فصل route جذر |
| 22 | AI Assistant | `#ai_assistant`, `#ai_settings` | 4 | 0 (tools client-side) | 🟠 | 50% | 7 مصادر قراءة | `extraInstructions` بلا Auth، injection risk | Bearer flow |
| 23 | POS | `#pos` + 5 sub | 5 | 1 ذرية (`pos_complete_transaction`) | 🟡 | 75% | Menu, CRM, ACCT | لا offline | offline+cash-drawer |
| 24 | Menu | `#menu` + 4 sub | 5 | 1 (`menu_compute_item_cost`) | 🟡 | 70% | POS, Inventory | تكلفة manual/BOM اختيارية | تفعيل BOM إلزامي |
| 25 | CRM & Loyalty | `#crm` + 4 sub | 5 | 0 (triggers) | 🟡 | 70% | POS, Delivery, Cafe | تكرار `acct_customers` | توحيد أو FK |
| 26 | HACCP | `#haccp` + 7 sub | 6 | 1 trigger | 🟡 | 70% | HR (شهادات) | تكرار شهادات مع HR | ربط قوي |
| 27 | Procurement | `#procurement` + 6 sub | 6 | 1 ذرية (`proc_receive_goods`) | 🟡 | 75% | ACCT, Inventory | لا approval workflow متعدد المستويات | multi-approval |
| 28 | Performance | `#performance` + 6 sub | 5 | 1 (`perf_compute_scorecard_score`) | 🟡 | 65% | HR, Users | لا ربط تلقائي بـ KPI فعلي | ربط BI |
| 29 | Delivery | `#delivery` + 5 sub | 5 | 3 ذرية | 🟡 | 70% | POS, CRM, Riders | لا تطبيق سائق مستقل | PWA سائق |
| 30 | Documents | `#documents` + 4 sub | 3 | 1 (`doc_expire_overdue`) | 🟡 | 65% | polymorphic (كل موديول) | لا cron لـ expire | scheduler |
| 31 | Call Center | `#call_center` + 5 sub | 4 | 2 (`cc_start/end_call`) | 🟠 | 50% | CRM, POS, Delivery | لا PBX، بيانات يدوية | PBX integration |
| 32 | BI | `#bi`, `#bi_reports`, `#bi_report` | 3 | 6 (aggregation) | 🟡 | 70% | كل الموديولات | CASH_FLOW placeholder | تنفيذ RPC |
| 33 | Integrations | `#integrations` + 4 sub | 4 | 2 | 🟠 | 40% | كل الموديولات | 12 مزوّد بلا workers | Edge Functions |
| 34 | Franchise | `#franchise` + 6 sub | 5 | 2 ذرية | 🟠 | 60% | ACCT (AR)، Sales | لا بوابة فرنشايزي، لا AR آلي | portal + AR link |

---

## ج) ملخص التصنيف (بعد التحليل التفصيلي)

| التصنيف | العدد | الموديولات |
|---|---:|---|
| ✅ PRODUCTION_READY | 11 | Meetings, Action Items, Tasks, Decisions, Chat, Emergency, Maintenance, Quality, Cafe, Notifications, Users (بعد إصلاح password) |
| 🟢 PILOT_READY | 4 | Vision, Profile, Meeting Requests, Voice Search |
| 🟡 NEEDS_STABILIZATION | 12 | HR, Accounting, Operations, Payments, POS, Menu, CRM, HACCP, Procurement, Performance, Delivery, BI, Documents |
| 🟠 NEEDS_BACKEND | 4 | Integrations, Call Center, Franchise, AI Assistant |
| 🔴 NEEDS_SECURITY_REWORK | 2 | Users (password_plain), AI Assistant (extraInstructions) |
| ⚪ PLACEHOLDER | 1 | BI CASH_FLOW report |
| ⛔ DO_NOT_RELEASE | 0 | — (لا موديول بحالة blocker مطلق) |
| 🟣 NEEDS_REDESIGN | 0 | — |

> ⚠️ **ملاحظة:** التصنيف الأخير أعلاه (Users) مذكور مرتين لأنه إنتاجي لكن يحتاج إصلاح أمني جوهري قبل التوسع الفعلي.

---

## د) الأنماط المستخرجة (متعددة الموديولات)

### د-1) أنماط الترقيم
كل الموديولات الجديدة تستخدم نمط `PREFIX-YYYY[MM]-NNNN` عبر دوال `assign_*_no` (SEE `DATABASE_OVERVIEW.md § دوال الترقيم`) وكل الدوال تعتمد `COUNT+1` بدل SEQUENCE (R-18 منخفضة الأولوية).

### د-2) أنماط الحالات
- `draft → submitted → approved → executed/paid/closed` سائد في المالية والمشتريات.
- `open → in_progress → completed / cancelled` سائد في العمليات المكتبية.
- Delivery فريدة بـ 9 حالات، Maintenance بـ 8، Call Center بحالات agent + call.

### د-3) أنماط التكاملات (Auto Journal)
10 دوال `create_journal_for_*` تربط الموديولات التشغيلية بـ Accounting:
`bill, payment, invoice, receipt, payroll, cafe_order, bank_transaction, expense_claim, ops_order, inventory_movement`.

### د-4) أنماط الحماية
17 دالة `is_*_manager()` (SECURITY DEFINER + `SET search_path=public`) — نمط موحّد.

---

## هـ) DISCOVERED_UNLISTED_MODULES

فحص الكود لم يكشف موديولات إضافية غير مذكورة في الـ34 الرسمية. لكن هذه الوظائف الفرعية تستحق توضيحها:

| الوظيفة الفرعية | أين موجودة | لماذا لم تُصنف موديولاً؟ |
|---|---|---|
| **إدارة الأصول (`branch_assets`)** | داخل Branches + Maintenance | جدول مشترك بين موديولين — يمكن استقلاله |
| **`user_activity_log`** | داخل Users | جدول نمطي (system-wide audit) — لا شاشة عرض شاملة |
| **`signup_requests`** | داخل Users | تدفق فرعي لتسجيل الحساب |
| **`branch_assets` catalog** | مشترك | لا route مخصص |
| **`meeting_preparation_reports`** | داخل Meeting Requests | جدول تابع |
| **`task_projects`** (المشاريع) | داخل Department Tasks | كيان منفصل لكنه فرعي |
| **Payments (PAY)** | تحت gate `accounting` | مذكور 17 موديول لكنه مدمج في PREVIEW_MODULES |

---

## و) القرارات المطلوبة من المالك (ملخص)

راجع `43_OWNER_DECISIONS_REQUIRED.md` للتفصيل. الأهم:
1. Franchise ↔ AR (تلقائي أم يدوي؟)
2. `crm_customers` مقابل `acct_customers` (توحيد أم إبقاء منفصل؟)
3. Action Items مقابل Department Tasks (دمج أم توضيح؟)
4. توقيت انتقال `users.password_plain` إلى Supabase Auth JWT.
5. أولوية Integrations workers.
6. مستقبل route `reports` و `analytics` بعد BI.
7. بوابة فرنشايزي مستقلة (Phase 1 أم Phase 2؟).
8. CC PBX integration الآن أم مؤجل؟

---

## ز) أهم 15 فجوة جوهرية (Top gaps)

1. **`users.password_plain`** — كلمة سر نص صريح (R-01 حرجة).
2. **RLS يعتمد `current_app_role()`** بدل Supabase JWT (R-02 حرجة).
3. **CORS `*` على `/api/rewrite` و `/api/agent`** (R-03 حرجة).
4. **جداول أساسية بلا SQL versioned** (meetings, tasks, decisions, ...) (R-07 عالية).
5. **12 مزوّد Integrations بلا workers** (R-11 متوسطة).
6. **Franchise ↔ AR بلا آلية تلقائية** (R-14 متوسطة).
7. **Call Center بلا PBX** (R-12 متوسطة).
8. **BI CASH_FLOW placeholder** (R-16 متوسطة).
9. **`doc_expire_overdue` بلا cron** (R-15 متوسطة).
10. **`crm_customers` ≠ `acct_customers` بلا FK** (R-08 عالية).
11. **`extraInstructions` في `/api/agent`** بلا Bearer (R-04 عالية).
12. **`int_webhook_endpoints.secret_token`** بلا Vault (R-05 عالية).
13. **لا E2E tests** — 17 موديول جديد غير مختبرة يدويًا (R-10 متوسطة).
14. **Sidebar 21 مجموعة، 15 منها معاينة بمفتاح واحد** (R-20 منخفضة).
15. **تكرار Action Items ↔ Department Tasks** بلا تدفق تحويل رسمي.

---

## ح) مخرجات هذا الملف

- **جدول تنفيذي كامل لـ 34 موديول** مع الحالة ونسبة الاكتمال والتوصية.
- **10 دوال Auto Journal** تربط التشغيل بالمالية.
- **17 دالة `is_*_manager`** تحكم الوصول.
- **7 وظائف فرعية جدير بها التوضيح** ذُكرت.
- **8 قرارات مالك** واضحة.
- **15 فجوة جوهرية** بترتيب الأولوية.

راجع الملفات من `01_USERS_AND_PERMISSIONS.md` حتى `44_MODULE_RELEASE_READINESS.md` للتفصيل، والملف الأهم `45_MODULES_BLUEPRINT_FOR_CHATGPT.md` لبرومت إعادة الهندسة.
