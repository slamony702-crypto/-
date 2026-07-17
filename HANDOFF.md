# HANDOFF — شؤون الغذاء

## 1) المشروع
- **الاسم:** شؤون الغذاء (Shouon Al-Ghithaa)
- **الهدف:** نظام ERP متكامل لشركة مطاعم سعودية متعددة الفروع — تشغيل، مطاعم، توصيل، عملاء، شكاوى، محاسبة، سلامة غذاء، مشتريات، أداء، مستندات، مركز اتصال، تكاملات، فرنشايز، ذكاء تحليلي، ومساعد ذكي.
- **اللغة:** الواجهة عربية RTL، أسماء الكود/الجداول/الـ routes إنجليزية.
- **المستخدمون:** الإدارة، المالية، HR، التشغيل، الفروع، الجودة، الصيانة، الشركاء، مركز الاتصال، الفرنشايز.

## 2) التقنيات
- **Frontend:** ملف HTML واحد (`index.html.html`) — Vanilla JS، صفر Framework، صفر build step. خط Almarai. Lucide icons.
- **Backend:** Supabase (Postgres + Auth + Storage + RLS). المفتاح المستخدم client-side هو anon/publishable key فقط — كل الحماية عبر Row Level Security.
- **Serverless:** Vercel (مجلد `api/`): `api/rewrite.js` + `api/agent.js` (Gemini function-calling).
- **PWA:** service worker (`service-worker.js`) — إصدارات موازية مع `APP_VERSION`.
- **Repo:** https://github.com/slamony702-crypto/- (branch: `main`)
- **Live:** https://shouon-al-ghithaa.vercel.app
- **Supabase Project:** `dfuqmmagtteemtpywody`
- **إصدار حالي:** `v123-2026-07-18-desktop-polish-2`

## 3) هيكل الملفات
```
shouon-al-ghithaa/
├── index.html.html          ← الملف الأساسي (35,000+ سطر): كل CSS + JS + شاشات
├── service-worker.js         ← Kill-switch SW
├── manifest.json / vercel.json
├── api/rewrite.js, api/agent.js
├── acct-schema.sql, acct-schema-2b-ap.sql ... acct-schema-2f-closing.sql
├── hr-schema.sql
├── ops-schema-3a-shifts.sql, ops-schema-3b-prep-orders-inventory.sql, ops-schema-3c-issues-settings.sql
├── ai-schema-1-assistant.sql
├── pay-schema-p1-partners.sql → p3-clearing.sql
├── menu-schema-1.sql, crm-schema-1.sql, pos-schema-1a.sql       ← Wave 1
├── haccp-schema-1.sql, proc-schema-1.sql, perf-schema-1.sql     ← Wave 2
├── dlv-schema-1.sql, doc-schema-1.sql, cc-schema-1.sql          ← Wave 3
├── bi-schema-1.sql, int-schema-1.sql, fr-schema-1.sql            ← Wave 4
├── HANDOFF.md, MODULES-CATALOG.md, MODULES-CATALOG.csv
└── WAVE-1-PLAN.md
```

## 4) ما تم تنفيذه حتى الآن

### 4.1) الموديولات الأصلية (قبل موجات التوسع)
المستخدمون، الصلاحيات، الفروع، الأقسام، الاجتماعات، مخرجات الاجتماعات، المهام والتكليفات، القرارات، الإشعارات، التواصل الداخلي، تواصل طارئ، الصيانة (بمزودين ومعدات)، الجودة، ركن الكافيه، التقارير، إعدادات النظام، رؤية الشركة، البحث الصوتي، تحسين الصياغة بالذكاء الاصطناعي.

### 4.2) الموديولات المؤسسية (Wave 0 — كلها خلف feature flag)
1. **HR — الموارد البشرية:** موظفون، هيكل تنظيمي، حضور، إجازات، رواتب. `window.HR`.
2. **Accounting (2.a → 2.f):** دليل حسابات (65+)، مراكز تكلفة، فترات، قيود يومية، AP، AR، ZATCA QR، خزينة، أصول ثابتة، مخزون، VAT، تقارير مالية، موازنات. `window.ACCT`.
3. **Operations (3.a → 3.c):** ورديات، طلبات المطعم بقيد آلي، مخزون فرعي، هدر، مشكلات بتصعيد. `window.OPS`.
4. **AI Assistant Phase 1:** 7 أدوات قراءة، RLS تلقائي (client-side execution)، سجل تدقيق. `window.AIA`.
5. **Payments (P1 → P3):** شركاء ماليون، عقود، محرك عمولات، كشوف، مطابقة، مقاصة، تحويلات. `window.PAY`.

### 4.3) Wave 1 — الأساس التشغيلي (Menu → CRM → POS)
6. **Menu — قوائم الطعام:** أصناف، تصنيفات، BOM/وصفات مرتبطة بمخزون، أسعار قنوات (dine-in/takeaway/delivery)، ترقيم `MENU-00001`. جداول: `menu_settings`, `menu_categories`, `menu_items`, `menu_item_recipes`, `menu_channel_prices`. RPC: `menu_compute_item_cost`. `window.MENU`.
7. **CRM & Loyalty — العملاء والولاء:** ملفات عملاء، عناوين متعددة، حسابات ولاء بمستويات (bronze→platinum)، سجل حركات ولاء **ثابت (بلا UPDATE/DELETE)**، شكاوى بتصنيف وخطورة وSLA. ترقيم `CUS-00001` + `CMP-YYYY-00001`. `window.CRM`.
8. **POS — نقاط البيع Phase 1a:** أجهزة، جلسات كاشير (بـ `cash_variance` GENERATED)، معاملات، بنود، دفع مختلط. **دالة ذرية `pos_complete_transaction`**: تحقق الدفعات + قيد محاسبي مسودة (مصدر `pos_sale`) + تحديث رولد العميل. QR ZATCA client-side. ترقيم `POS-YYYY-BR{n}-00001` + `TXN-YYYY-00000001`. شاشة كاشير لمس كاملة. `window.POS`.

### 4.4) Wave 2 — المؤسسية (HACCP → Procurement → Performance)
9. **HACCP — سلامة الغذاء:** إعدادات (SASO 2233)، معدات، سجلات حرارة (`is_within_range` محسوب بـ trigger)، دفعات غذائية (`BATCH-YYYYMMDD-00001`)، شهادات صحية للموظفين، حوادث (`HACCP-YYYY-00001`) بمنهجية حل (سبب جذري + تصحيحي + وقائي). `window.HACCP`.
10. **Procurement — المشتريات:** طلبات شراء (`PR-YYYY-00001`) → أوامر شراء (`PO-YYYY-00001`) → إيصالات استلام (`GRN-YYYY-00001`). **دالة ذرية `proc_receive_goods`**: تحقق كميات + خصم مخزون (`acct_inventory_movements`) + إنشاء فاتورة مورد AP (`acct_bills` بحساب 5101) + تحديث حالة PO تلقائيًا. `window.PROC`.
11. **Performance — إدارة الأداء:** تعريفات KPI (3 أنواع أهداف: higher_better/lower_better/range)، سكوركارد شهري (فرع/موظف)، تقييمات دورية بإقرار الموظف، أهداف SMART بنسبة إنجاز. **دالة `perf_compute_scorecard_score`**: weighted average → درجة 0-150 + تصنيف حرفي (A+ → F). 9 KPIs مبذورة. `window.PERF`.

### 4.5) Wave 3 — الخبرة (Delivery → Documents → Call Center)
12. **Delivery — التوصيل:** إعدادات، مناطق دائرية (نصف قطر + رسوم + زمن)، السائقين (بحالة توفر لحظية)، طلبات (`DLV-YYYY-00000001`) بـ 9 حالات، سجل تتبع زمني. **3 دوال ذرية:** `delivery_assign_rider` + `delivery_update_status` + `delivery_mark_delivered`. بورد كانبان تفاعلي. `window.DLV`.
13. **Documents — إدارة المستندات:** 14 تصنيف مبذور (السجل التجاري، رخصة البلدية، الدفاع المدني، شهادات صحية، إلخ)، مستندات (`DOC-YYYY-00001`) بـ `tags[]` (GIN index) + `metadata JSONB` + `related_entity_type/id` polymorphic + `supersedes_id` للتاريخ، سرية (RLS)، سجل وصول كامل (view/download). دالة `doc_expire_overdue`. `window.DOC`.
14. **Call Center — مركز الاتصال:** موظفين بحالة توفر + إحصائيات (إجمالي، مدة، تقييم)، مكالمات (`CALL-YYYY-00000001`) inbound/outbound بـ 7 أغراض، 11 نتيجة مبذورة، 6 سكريبتات مبذورة، متابعات followup، دمج مع CRM/POS/Delivery. **دالتان:** `cc_start_call` + `cc_end_call` (تحديث إحصائيات الموظف تلقائيًا). `window.CC`.

### 4.6) Wave 4 — الاستراتيجية (BI → Integrations → Franchise)
15. **BI — الذكاء التحليلي:** 7 تقارير مبذورة + **6 دوال تجميع cross-module**: `bi_daily_summary` (POS+Delivery+CRM+Complaints) • `bi_branch_ranking` • `bi_top_menu_items` • `bi_customer_segments` (segments + loyalty tiers) • `bi_operations_health` (HACCP + docs + certs) • `bi_delivery_kpis`. لقطات JSONB (`bi_save_snapshot` بـ upsert)، عروض محفوظة (شخصية/مشتركة). `window.BI`.
16. **Integrations — التكاملات:** 12 مزوّد مبذور (WhatsApp Cloud، Twilio، Slack، Jahez، HungerStation، Mrsool، Mada Pay، STC Pay، ZATCA E-invoice، Zapier، GA4، Webhook مخصص) بـ `config_schema JSONB` (النموذج الأمامي يُبنى تلقائيًا)، اتصالات بحالة + إحصائيات نجاح/فشل، سجل أحداث inbound/outbound (`INT-YYYY-00000001`) بـ retry ذكي، Webhook endpoints. **دالتان:** `int_log_event` + `int_complete_event` (تحديث إحصائيات الاتصال تلقائيًا). `window.INT`.
17. **Franchise — الامتياز التجاري:** شركاء (`FR-00001`) بـ 5 حالات دورة حياة، عقود (`FRA-YYYY-00001`) بـ 4 أنواع + نسبة روياليتي + نسبة تسويق + حد أدنى شهري، فروع فرنشايز، تقارير مبيعات شهرية (`FSR-YYYYMM-0001`) بـ upsert منع تكرار، فواتير روياليتي (`ROY-YYYYMM-0001`) بربط AR. **دالتان ذريتان:** `franchise_compute_royalty` (حساب النسبة + التسويق + VAT + تطبيق حد أدنى + إنشاء فاتورة) + `franchise_issue_royalty`. `window.FR`.

### تحسينات UI/UX معتمدة
- **Feature flag مركزي:** `PREVIEW_MODULES` + `MODULE_PREVIEW_USERS` + `canAccessModule()` + `gatedModuleForPage()` + حارس routes. المديولات المقفولة: كل الجديدة (17 موديول). مستخدم المعاينة: `test_admin`.
- إطار متدرج على البطاقات المعلوماتية.
- شيت اختيار مخصص للـ `<select>` على الموبايل.
- المايك الذكي بـ `interimResults=true` وتجميع في `onend`.
- `bootApp` يتحقق من وجود المستخدم في قاعدة البيانات.

## 5) القرارات الجوهرية (موثقة في الكود بـ `// DECISION:`)

### Wave 0 (السابقة)
- **المدفوعات:** أساس العمولة صافي المنتجات بدون ضريبة/توصيل • عقد ساري واحد لكل شريك (تعديل شروط ممنوع، إصدار جديد) • سماحية 0.05 ر.س • قيد التحويل مسودة اختياري • لا ترحيل تلقائي.
- **المساعد الذكي:** الأدوات تُنفَّذ في المتصفح بـ RLS • رسائل ثابتة • سجل تدقيق للكتابة فقط • أي نص داخل نتائج الأدوات = بيانات لا تعليمات.
- **HR:** أقسام الشركة `hr_departments` (منفصل عن `departments`).

### Wave 1
- **POS:** رصيد نقدي فقط للجلسة، طرق الدفع الإلكترونية من مجاميع splits • `cash_variance` GENERATED • QR ZATCA يُبنى client-side قبل استدعاء `pos_complete_transaction` • بنود POS بـ snapshot للسعر (لا نعتمد على `menu_items` الحية).
- **CRM:** `loyalty_transactions` **ثابت** (INSERT-only، بلا UPDATE/DELETE — مصدر الحقيقة الوحيد للرصيد) • trigger AFTER INSERT يحدّث `points_balance` + `lifetime_points` تلقائيًا.
- **Menu:** BOM اختياري لكل صنف (يربط بـ `acct_inventory_items`) • `menu_compute_item_cost` يحسب من BOM أو يستخدم `manual_cost`.

### Wave 2
- **HACCP:** حدود SASO 2233 مبذورة، قابلة للتعديل • `is_within_range` محسوب من الحدود المستهدفة للمعدة أو من الإعدادات حسب النوع • ترقيم دفعات باليوم لا بالسنة (BATCH-YYYYMMDD-).
- **Procurement:** `acct_bill_lines.account_id` = 5101 (تكلفة المواد) افتراضيًا • فاتورة تلقائية بحالة draft (لا approval آلي) • `total` محسوب GENERATED في `acct_bills` (لا نحدّثه يدويًا) • VAT 15% تلقائيًا على subtotal.
- **Performance:** درجة سقفها 150% (تسمح بتجاوز الهدف) • `range` KPI يخصم بنسبة الانحراف من `target_min/max` • تصنيف حرفي A+(≥110)/A(95)/B(80)/C(65)/D(50)/F.

### Wave 3
- **Delivery:** منطقة دائرية بنصف قطر (polygon مؤجل لـ Phase 2) • `pos_transaction_id` اختياري (يدعم طلبات من مصادر خارجية) • `delivery_tracking` لوج ثابت بلا حذف • تسليم يقلل عداد السائق ويعيد حالته لـ available تلقائيًا.
- **Documents:** polymorphic linking بسيط (`related_entity_type` enum + `related_entity_id`) • مستندات سرية مرئية للمالك + مدير المستندات + الموظف المرتبط • `doc_log_access` يُستدعى تلقائيًا عند فتح المستند • `doc_expire_overdue` للتشغيل الدوري (cron).
- **Call Center:** rider ممكن يكون user أو مستقل (بدون user_id) • مكالمة `in_progress` تحدّث حالة الموظف تلقائيًا • `cc_end_call` يعيد الحالة لـ available.

### Wave 4
- **BI:** لقطات JSONB (schema مرنة لكل تقرير) • upsert على `(report_code, snapshot_type, period_start, period_end, branch_id)` • دوال RPC تعيد JSON منسق للفرونت.
- **Integrations:** `config_schema JSONB` لكل مزوّد → الفرونت يبني نموذج تلقائي • فشل حدث يحوّل الاتصال لـ `error` تلقائيًا • كلمة المرور معروضة كـ •••• في الواجهة (تخزين مباشر — يُوصى بـ Supabase Vault للإنتاج).
- **Franchise:** `franchise_compute_royalty` يطبق **الحد الأدنى** لو النسبة أقل، ويسم `min_royalty_applied = TRUE` • VAT 15% تلقائيًا على (royalty + marketing) • fk من `franchise_sales_reports` لـ `franchise_royalty_invoices` مضاف بـ `ALTER TABLE ... ADD CONSTRAINT` بعد إنشاء الجدولين (لتفادي forward reference).

### إصلاحات جوهرية
- `palm-tree` → `tree-palm` (lucide).
- `interimResults=true` للتعرف الصوتي على PWA أندرويد.
- Gemini tools بلا parameters ← حذف `parameters` كليًا.
- خطأ `department_tasks_assigned_by_fkey` ← revalidation في `bootApp`.
- CSS `.meeting-form-card.collapsed` ← layered background-image.
- **Procurement:** `acct_vendor_bills` → `acct_bills` (اسم الجدول الحقيقي في AP).
- **Audit Fix #1 (v118):** `bi-schema-1.sql` — دالة `bi_top_menu_items` كانت تشير لأعمدة غير موجودة (`mi.name`, `mc.name`). صُحِّحت إلى `mi.name_ar` و `mc.name_ar` في `SELECT` و `GROUP BY`. **بدون الإصلاح تقرير "الأصناف الأكثر مبيعًا" يفشل بـ `column "name" does not exist`.**
- **Audit Fix #2 (v118):** `menu-schema-1.sql` — بذر `menu_categories` كان يستخدم `ON CONFLICT DO NOTHING` بدون target column ولا UNIQUE constraint → 6 فئات مكررة عند كل rerun. أُضيف `ALTER TABLE ... ADD CONSTRAINT menu_categories_name_ar_unique UNIQUE (name_ar)` بنمط idempotent (`DO $$ IF NOT EXISTS ...`)، وتغيّرت العبارة إلى `ON CONFLICT (name_ar) DO NOTHING`.
- **Audit Fix #3 (v118):** `cc-schema-1.sql` — نفس المشكلة في بذر `cc_scripts`. أُضيف UNIQUE على `title` بنفس النمط، وتغيّرت إلى `ON CONFLICT (title) DO NOTHING`.
- **Audit Fix #2b/3b (v119):** الـ runs السابقة للإصلاح أدخلت الفئات/السكريبتات مكررة، فحاول ALTER TABLE ADD UNIQUE يفشل بـ `23505 could not create unique index`. أُضيفت خطوة تنظيف تسبق ADD CONSTRAINT في كل من `menu-schema-1.sql` (تحويل إشارات menu_items إلى canonical + DELETE) و `cc-schema-1.sql` (DELETE مباشر). كل الخطوات idempotent وآمنة للتشغيل المتكرر.

### دفعة إصلاحات (v120) — بنود Medium/Cosmetic من التقرير
- **Fix #4 (search_path على 13 دالة):** أُضيف `SET search_path = public` على كل دوال `is_XXX_manager` الـ11 + `menu_compute_item_cost` + `doc_expire_overdue`. الملفات المعدَّلة: `menu-schema-1.sql`, `crm-schema-1.sql`, `haccp-schema-1.sql`, `proc-schema-1.sql`, `perf-schema-1.sql`, `dlv-schema-1.sql`, `doc-schema-1.sql`, `cc-schema-1.sql`, `bi-schema-1.sql`, `int-schema-1.sql`, `fr-schema-1.sql`. تُطبَّق تلقائيًا بـ `CREATE OR REPLACE FUNCTION` عند إعادة تشغيل الملفات.
- **Fix #5 (POS type check):** `pos_complete_transaction` في `pos-schema-1a.sql` أصبحت ترمي `RAISE EXCEPTION` لو `v_txn.type <> 'sale'` (منع إنشاء قيد بيع موجب على refund/void).
- **Fix #6 (perf_scorecards uniqueness):** استُبدلت `CONSTRAINT perf_sc_unique_branch` بـ partial unique indexes منفصلة لكل من branch/employee. يشمل `DROP CONSTRAINT IF EXISTS` للـ installs القديمة. يمنع سكوركاردات مكررة لنفس الموظف في نفس الشهر.
- **Fix #7 (crm addresses updated_at + default unique):** أُضيف `updated_at` مع trigger في `crm_customer_addresses` + `ALTER TABLE ADD COLUMN IF NOT EXISTS` للـ installs القديمة + partial unique index يضمن عنوان افتراضي واحد لكل عميل.
- **Fix #8 (franchise sales reports NULL branch):** نفس نمط partial unique في `franchise_sales_reports` — يمنع تكرار تقارير لعقد بلا فرع محدد.
- **Fix #9 (BI perf index):** `CREATE INDEX pos_txn_completed_date_idx` على `pos_transactions(completed_at) WHERE status = 'completed'` — يسرّع كل تقارير BI اللي بتفلتر بالتاريخ.
- **Fix #10 (delivery CASE readability):** تغيير `CASE WHEN current_orders - 1 = 0` إلى `CASE WHEN current_orders <= 1` في `delivery_mark_delivered` — أوضح ومكافئ منطقيًا (نستخدم القيمة القديمة قبل الإنقاص).

### بنود مؤجَّلة تحتاج مناقشة قبل التنفيذ
- **`users.password_plain` (medium):** ديون قديمة من Wave 0. يتطلب إعادة هيكلة لـ Supabase Auth + رابط استعادة عبر البريد. يستحق sprint منفصل.
- **`api/agent.js extraInstructions` (medium):** يحتاج Supabase Auth Bearer flow لتحقّق قراءة من `ai_settings` server-side. تصميم أمني منفصل.
- **Franchise → AR invoice creation (medium):** قرار تجاري — هل الروياليتي تُنشئ فاتورة AR تلقائيًا أم يدويًا؟ يستحق نقاش مع صاحب المشروع.
- **`COUNT+1` → SEQUENCE (cosmetic):** إعادة هيكلة كبيرة على 15+ دالة ترقيم. القيمة تحت الحمل الحالي منخفضة.
- **`int_webhook_endpoints.secret_token` → Supabase Vault (cosmetic):** يحتاج تكامل Vault. تصميم منفصل.
- **الحلقة المحادثة AI = 4 خطوات (cosmetic):** يحتاج نقاش UX/تكلفة.
- **`proc_grn` قيمة CHECK غير مستخدمة (cosmetic):** dead code لكن غير ضار. تُترك.
- **`PREVIEW_MODULES` = 16 vs التوثيق 17 (cosmetic):** فرق تسمية فقط (PAY لا يظهر كمديول منفصل — تحت gate accounting). سلوك صحيح.

### دفعة تحسينات الأداء (v121) — منع التعليق تحت الحمل
- **Perf Fix #1 (fetchWithTimeout):** أُضيف helper مركزي `fetchWithTimeout(url, opts, ms)` بعد إنشاء `sb`. كل `fetch()` عام في الفرونت الآن يستخدمه بدل `fetch` مباشرة: SW check (8s)، /api/agent (60s)، /api/rewrite (25s)، مواقيت الصلاة (10s × 2). رسالة عربية واضحة عند انتهاء المهلة.
- **Perf Fix #2 (Gemini timeout في api/agent.js):** `AbortSignal` مع 25s لكل موديل. بدل انتظار مفتوح للطلب، الآن يتم إلغاء الطلب وينتقل للموديل التالي بلطف مع رسالة عربية.
- **Perf Fix #3 (Pagination على 10 استعلامات):** أُضيف `.limit()` + `.order()` على استعلامات كانت تجيب كل الصفوف بلا حد:
  - `pageDashboard`: meetings + action_items + maintenance_requests (500 لكل واحد).
  - `pageMeetings` + `pageDeepDataMeetings`: 300.
  - `pageConversations`: meetings + tasks (300 لكل).
  - Statistics query: meetings + tasks + decisions (500 لكل).
  - `pageMyProfile`: 4 استعلامات (300).
  - `HR.attendance`, `ACCT.journal.list`, `ACCT.bills.list`, `ACCT.invoices.list`, `PAY.statements.list`: 300-500.
- **Perf Fix #4 (Batch inserts × 5):** استُبدل `for...await sb.insert(...)` بـ `sb.insert(rows[])` واحد في:
  - `PAY.clearing.calculate`: pay_clearing_items + pay_statements update (بـ `.in()`).
  - إنشاء اجتماع: meeting_agenda.
  - إنشاء قرار (شاشتين): decision_sub_responsibles + decision_viewers.
  - إنشاء تنبيه طارئ: emergency_recipients + notifications.
  - تحديث الصيانة الوقائية: maintenance_preventive_schedule update بـ `.in()`.

### بنود بنيوية مؤجَّلة تحتاج قرار المستخدم (v121)
- **Lazy loading للموديولات المعاينة (~11,000 سطر = 26% من الملف):** المستخدمون العاديون يحمّلون كود موديولات الـ17 المعاينة كـ dead code. الحل يخالف فلسفة "ملف واحد بلا build step" — يحتاج نقاش.
- **RPC للـ Dashboard aggregation:** `perf-fix-1-dashboard-rpc.sql` جاهزة بدالة `dashboard_summary(uid, dept_id, is_admin)` تُرجع json_build_object بكل KPIs. الفرونت لم يُحدَّث بعد — الـ `.limit(500)` الحالي كافٍ لمنع التعليق. للتفعيل: استدعِ `sb.rpc('dashboard_summary', {...})` بدل 3 استعلامات في `pageDashboard`.

### دفعة Design System خفيف (v122) — تحسين واجهة الديسكتوب
- **إضافات إلى `:root`:** سلّم `--fs-{xs,sm,base,md,lg,xl,2xl}` للخطوط + سلّم `--sp-{1..8}` للمسافات + `--content-{max=1440,tight=1120,narrow=780}` لسقف عرض المحتوى.
- **إصلاح جراحي على `.page-body`:** `.page-body > * { max-width: var(--content-max); margin-inline: auto; }`. **يحل تمدد الجداول والفورمز على شاشات 1920px+ في كل الشاشات دفعة واحدة بلا لمس أي شاشة**. الشاشات الأصغر (موبايل + ديسكتوب < 1440px) لا تتأثر.
- **استثناء `.app-full-bleed`:** للعناصر التي تريد full-width (بانرات، هيرو ممتد).
- **كلاسات opt-in:** `.page-tight` (1120px للـ detail pages) و `.page-narrow` (780px للفورمز الطويلة). المستخدم يضيفهم يدويًا على `body` (المعامل في pageXxx) عند الحاجة.

### دفعة Desktop Polish v123 — بلوك media queries شامل للديسكتوب
- **الأسلوب:** كل التحسينات محاطة بـ `@media (min-width: 1024px)` و `@media (min-width: 1440px)` — **صفر تأثير على الموبايل**.
- **توحيد بصري للـ hero cards:** `.mod-hero`, `.hr-emp-hero`, `.hero-card` كلها تأخذ نفس padding (32-36px حسب عرض الشاشة) + border-radius 22px + margin-bottom 24-28px. الفرق الوظيفي بينهم يفضل، لكن البصر متسق.
- **تكبير KPI numbers للديسكتوب:** `.mod-stat-val`, `.kpi-value`, `.stat-card .value` من 26px → 32px (1024px+) → 36px (1440px+). قابلية القراءة على شاشات 27" تحسنت بشكل ملحوظ.
- **جداول أوضح:** `.hr-emp-table` حصلت hover state واضح (rgba(18,55,47,0.03))، `thead` أصبح sticky top، الصفوف بحواف أنقى.
- **Forms أنقى:** `.form-input`, `.form-select` بـ max-width 640px على الديسكتوب (لتجنب حقول اسم بعرض 1500px). الحقول الطويلة داخل `.form-field.full` تفضل full-width كالسابق.
- **Page-body padding أكبر:** 24px → 28px 32px (1024px+) → 32px 40px (1440px+).
- **الأزرار موحّدة:** `.btn` min-height 38px، `.mod-hero-badge` 7px 14px، `.hr-emp-hero-btn` 8px 16px.
- **`.mt-hero-header` عناوين أكبر على الديسكتوب:** h2 20px → 22px، p 12.5px → 13.5px.

### ما زال مؤجَّل
- استبدال 34+ قيمة `border-radius` حرفية بـ `var(--radius-*)` — تجميلي بحت، مكلف بلا فائدة مرئية.
- تطبيق `--fs-*` بدل الأرقام الحرفية في الشاشات الفردية — نفس السبب.
- **قرار:** الـ media queries الجديدة أصبحت المصدر الرسمي للتحسين البصري على الديسكتوب. أي شاشة يظهر فيها تفاوت واضح بعد تجربة v123 → نضيف قاعدة مستهدفة داخل نفس media query.

## 6) المشكلات الحالية

### 🟡 ليست عاجلة
- Gemini API quota (السبب: فوترة على مشروع Google Cloud مختلف). الحل: مفتاح جديد على المشروع الصحيح + Redeploy Production بلا build cache. (خطوات مفصلة في section 8 من HANDOFF الأصلي القديم).
- كل الموديولات الـ17 الجديدة SQL شُغِّل ومُتحقق، لكن سيناريوهات end-to-end لم تُختبر يدويًا كلها — التوثيق سبق الاستخدام.
- لا ربط API فعلي مع أي مزوّد في Integrations — البنية جاهزة، لكن الـ workers الفعليون في Phase 2 (edge functions).
- Node syntax check يمر بصفر أخطاء لكن مفيش end-to-end tests.
- بوابة الفرنشايزي المستقلة (login منفصل + رفع تقاريره بنفسه) في Phase 2.

## 7) آخر خطوة وصلنا إليها
- **آخر إصدار:** `v117-2026-07-17-wave4-franchise`
- **آخر task completed:** #58 — Wave 4 Franchise DAL + screens.
- **الحالة:** 17 موديول جديد كامل (Wave 0 → Wave 4)، كلها خلف feature flag، كلها SQL idempotent، كلها Syntax نظيف.

## 8) الخطوة التالية المطلوبة
اختيار المستخدم من:
1. **مراجعة نهائية شاملة** لكل الموديولات الـ17 لاكتشاف bugs/inconsistencies قبل العرض.
2. **Phase 2 لموديول محدد** (POS offline، تطبيق سائق، PBX integration، workflow builder، بوابة فرنشايزي).
3. **دمج cross-module جديد** (مثلاً: طلب توصيل يفتح مكالمة CC تلقائيًا • HACCP breach ينشئ document alert • BI report مجدول عبر Integrations لـ Slack).

## 9) تعليمات مهمة يجب ألا تتغير
- ❌ **لا تكسر أي فيتشر شغالة.**
- ❌ **لا تلمس `authLogin` أو منطق تسجيل الدخول** — التعديلات فقط على `bootApp` (revalidation).
- ❌ **لا تعدّل schema بشكل مدمّر** — كل SQL جديد `IF NOT EXISTS` / `ON CONFLICT` / `DROP POLICY IF EXISTS`, idempotent.
- ❌ **لا تنفّذ SQL بنفسك أبدًا** — المستخدم يشغّله يدويًا في Supabase وقيل "خلص".
- ❌ **لا تسرّب المفاتيح** — `GEMINI_API_KEY` في Vercel env vars فقط.
- ❌ **لا تلمس الـ routing الأساسي** — أضف routes جديدة فقط بنمط `else if (page === '...') await pageXxx(body, param, query);`.
- ✅ **كل فيتشر جديدة خلف `canAccessModule()` — test_admin فقط حتى الاعتماد.**
- ✅ **كل تعديل يمر بفحص syntax عبر Node** قبل commit.
- ✅ **APP_VERSION + SW_VERSION يترقّيا معًا.**
- ✅ **اللغة:** الواجهة عربية 100%، الكود إنجليزي، `// DECISION:` لكل قرار مؤسسي.
- ✅ **اسأل قبل الأفعال الخطرة** (نشر، حذف، إعادة كتابة موديول).

## 10) الملفات المهمة للمراجعة في أي جلسة قادمة
| الملف | لماذا |
|---|---|
| `HANDOFF.md` (هذا الملف) | نقطة البداية |
| `MODULES-CATALOG.md` / `.csv` | كتالوج الموديولات التفصيلي |
| `index.html.html` | الملف الرئيسي — كل شيء هنا |
| `api/agent.js` / `api/rewrite.js` | خوادم Gemini |
| `service-worker.js` | Kill-switch SW |

**SQL الرئيسية (بترتيب التطبيق):**
1. `hr-schema.sql` — HR + `users.branch_id`
2. `acct-schema.sql` → `acct-schema-2f-closing.sql` — 6 مراحل للحسابات
3. `ops-schema-3a` → `-3c` — 3 مراحل للتشغيل
4. `ai-schema-1-assistant.sql` — المساعد الذكي
5. `pay-schema-p1-partners.sql` → `p3-clearing.sql` — 3 مراحل للمدفوعات
6. `menu-schema-1.sql` — Wave 1a
7. `crm-schema-1.sql` — Wave 1b
8. `pos-schema-1a.sql` — Wave 1c
9. `haccp-schema-1.sql` — Wave 2a
10. `proc-schema-1.sql` — Wave 2b (يحتاج AP schema)
11. `perf-schema-1.sql` — Wave 2c
12. `dlv-schema-1.sql` — Wave 3a (يحتاج POS + CRM)
13. `doc-schema-1.sql` — Wave 3b
14. `cc-schema-1.sql` — Wave 3c (يحتاج CRM + POS + Delivery)
15. `bi-schema-1.sql` — Wave 4a (تعتمد دوالها على كل الموديولات)
16. `int-schema-1.sql` — Wave 4b
17. `fr-schema-1.sql` — Wave 4c (يحتاج AR/acct_customers + acct_invoices)

### مواقع مهمة داخل `index.html.html`
- `PREVIEW_MODULES` (17 مفتاح الآن) + `canAccessModule` + `gatedModuleForPage`
- `MENU_GROUPS` → السايدبار (كل موديول له group `__xxx`)
- `PAGE_TITLES` → عناوين الصفحات
- `async function route()` → توجيه الصفحات
- `COMING_SOON_MODULES` → صفحات "قريبًا" لكل موديول (17 entry الآن)
- `window.HR/ACCT/OPS/AIA/PAY/MENU/CRM/POS/HACCP/PROC/PERF/DLV/DOC/CC/BI/INT/FR` → طبقات الوصول للبيانات

### روابط عملية
- **Live:** https://shouon-al-ghithaa.vercel.app
- **GitHub:** https://github.com/slamony702-crypto/-
- **Supabase SQL Editor:** https://supabase.com/dashboard/project/dfuqmmagtteemtpywody/sql/new
- **Vercel Project:** `shouon-al-ghithaa`
- **Gemini API Keys:** https://aistudio.google.com/app/apikey
