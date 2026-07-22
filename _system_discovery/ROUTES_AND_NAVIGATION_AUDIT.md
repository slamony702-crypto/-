# ROUTES_AND_NAVIGATION_AUDIT

> استُخرجت من: `else if (page === '...')` block في `index.html.html` (الأسطر 16967–17126) + `MENU_GROUPS` (12321–12395) + `PAGE_TITLES` (السطر 12398) + `PREVIEW_MODULES` (12292) + `gatedModuleForPage()` (12299).

## إجمالي Routes: **160 route**

### التوزيع حسب الموديول
| البادئة | العدد | المفتاح المقفل |
|---|---:|---|
| `hr_*` + `hr` | 7 | `hr` |
| `acct_*` + `accounting` | 30 | `accounting` |
| `ops_*` + `operations` | 15 | `operations` |
| `ai_*` + `ai_assistant` | 2 | `ai_agents` |
| `menu_*` + `menu` | 5 | `menu` |
| `crm_*` + `crm` | 5 | `crm` |
| `pos_*` + `pos` | 6 | `pos` |
| `haccp_*` + `haccp` | 8 | `haccp` |
| `proc_*` + `procurement` | 7 | `procurement` |
| `perf_*` + `performance` | 7 | `performance` |
| `dlv_*` + `delivery` | 6 | `delivery` |
| `doc_*` + `documents` | 5 | `documents` |
| `cc_*` + `call_center` | 6 | `call_center` |
| `bi_*` + `bi` | 3 | `bi` |
| `int_*` + `integrations` | 5 | `integrations` |
| `fr_*` + `franchise` | 7 | `franchise` |
| **الإنتاج (routes أساسية)** | ~36 | — |

## MENU_GROUPS (السايدبار الحالي) — 21 مجموعة
1. `__main` — الأساسيات: `myday`, `dashboard`, `vision`.
2. `__exec` — التنفيذ والمتابعة: `meetings`, `tasks`, `department_tasks`, `decisions`.
3. `__ops` — العمليات والجودة: `maintenance`, `quality`, `operations` (badge قريبًا).
4. `__erp` — الإدارة المؤسسية: `hr` (قريبًا), `accounting` (قريبًا).
5. `__ai` — مركز الذكاء: `ai_assistant` (قريبًا).
6. `__menu` — المطبخ: `menu` (قريبًا).
7. `__crm` — علاقات العملاء: `crm` (قريبًا).
8. `__pos` — نقاط البيع: `pos` (قريبًا).
9. `__haccp`: `haccp` (قريبًا).
10. `__procurement`: `procurement` (قريبًا).
11. `__performance`: `performance` (قريبًا).
12. `__delivery`: `delivery` (قريبًا).
13. `__documents`: `documents` (قريبًا).
14. `__call_center`: `call_center` (قريبًا).
15. `__bi`: `bi` (قريبًا).
16. `__integrations`: `integrations` (قريبًا).
17. `__franchise`: `franchise` (قريبًا).
18. `__cafe`: `cafe`.
19. `__comm`: `conversations`, `emergency`.
20. `__admin`: `analytics`, `invite`, `reports`, `users`, `settings`.

⚠️ **15 مجموعة من الـ21 = عنصر واحد فقط + badge "قريبًا"** — انفوجرافيك ضعيف. Sidebar UX يحتاج إعادة تجميع.

## PAGE_TITLES
مصفوفة flat ضخمة (160 مفتاح تقريبًا) — نفس routes المسجلة.

## Routes ظاهرة في القائمة لكن مقفولة بـ feature flag
- كل عنصر معلَّم `badge: 'قريبًا'` هو gated. لكل مستخدم غير `test_admin` يفتح صفحة `pageComingSoonModule` (تعريفية، لا شاشة حقيقية).
- المستخدم `test_admin` وحده يعبر إلى الشاشات الحقيقية.

## Routes ليست في السايدبار (وصول بروابط داخلية فقط)
| Route | من أين يُفتح |
|---|---|
| `#meetings_calendar` | زر داخل `#meetings` |
| `#meeting_detail/:id` | من قائمة الاجتماعات |
| `#meeting_requests` | من ملف المستخدم / إشعار |
| `#notifications` | من الجرس أعلى الشاشة |
| `#search` | من الشريط العلوي (البحث) |
| `#my_profile` | من صورة المستخدم |
| `#install_app` | Banner PWA |
| `#pos_cashier/:terminal` | من `#pos_sessions` |
| `#pos_transaction/:id` | من التقارير |
| `#pos_terminals`, `#pos_sessions`, `#pos_session/:id` | من `#pos` |
| كل الـ `:id` detail routes (~25) | من الصفحات الأم |
| كل `hr_employee/:id`, `menu_item/:id`, ... | من قوائم أم |
| `#dept_chat/:id`, `#custom_chat/:id` | من `#conversations` |
| `#maintenance_new`, `#maintenance_detail/:id`, `#maintenance_reports`, `#maintenance_equipment`, `#maintenance_preventive`, `#maintenance_assets`, `#maintenance_suppliers` | من `#maintenance` |
| `#quality_new`, `#quality_detail/:id`, `#quality_reports` | من `#quality` |
| `#ai_settings` | من `#ai_assistant` |
| `#acct_journal_entry/:id`, `#acct_bill/:id`, `#acct_invoice/:id`, `#acct_expense_claim/:id`, `#acct_fixed_asset/:id` | detail من قوائم أم |
| كل detail routes للأمر معاينة | كذلك |

## Routes بدون شاشة تستدعيها (مشتبه بها كـ dead / نادرة الوصول)
- `#pos_terminals` — تظهر ضمن dashboard POS، لكن لا يوجد menu item يفتحها.
- `#pos_transaction/:id` — يُفتح فقط من report/history داخلي.
- `#analytics` مقابل `#reports`: كلاهما في القائمة `__admin`. لا يعرف بوضوح الفرق.

## تكرارات محتملة
- **`tasks` (مخرجات اجتماعات) vs `department_tasks` (مهام وتكليفات):** جدولان مختلفان (`action_items` vs `department_tasks`) لكن نفس الفكرة العامة. في القائمة يظهران معًا مما يربك المستخدم.
- **`reports` مقابل `analytics` مقابل `bi_reports`:** ثلاثة routes لتقارير — مصادر بيانات مختلفة (Reports قديم + Analytics قديم + BI جديد).
- **`hr_organization` مقابل جدول `hr_positions`:** الصفحة نفسها تدير المناصب والأقسام معًا.
- **maintenance list vs maintenance_equipment vs maintenance_assets:** ثلاثة routes، وظائف متقاربة.
- **`acct_customers` (Accounting AR) مقابل `crm_customers` (CRM):** جدولان منفصلان (`acct_customers`, `crm_customers`) — يخلق تكرارًا في بيانات العميل.

## عناصر ظاهرة في السايدبار مقفولة بـ role
- `users` — مسموح لـ `admin`, `company_manager`, `department_manager` فقط.
- `settings` — يظهر للكل لكن الأقسام الحساسة مقفولة داخليًا.

## ملاحظات
- `MENU_ITEMS` = `MENU_GROUPS.flatMap(g => g.items)` للتوافق العكسي مع كود قديم.
- كل الموديولات الجديدة معلَّمة بـ badge "قريبًا" ثابت — لا نظام حالة ديناميكي.
- لا Breadcrumbs موحّدة عبر الصفحات — كل صفحة تبني header خاص.
