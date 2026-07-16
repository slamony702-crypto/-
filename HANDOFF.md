# HANDOFF — شؤون الغذاء

## 1) المشروع
- **الاسم:** شؤون الغذاء (Shouon Al-Ghithaa)
- **الهدف:** نظام ERP متكامل لشركة مطاعم سعودية متعددة الفروع — اجتماعات، مهام، قرارات، صيانة، جودة، كافيه، إشعارات، HR، حسابات، تشغيل مطاعم، مدفوعات ومقاصات، ومساعد ذكي بالذكاء الاصطناعي.
- **اللغة:** الواجهة عربية RTL، أسماء الكود/الجداول/الـ routes إنجليزية.
- **المستخدمون:** الإدارة، المالية، HR، التشغيل، الفروع، الجودة، الصيانة، الشركاء.

## 2) التقنيات
- **Frontend:** ملف HTML واحد (`index.html.html`) — Vanilla JS، صفر Framework، صفر build step. خط Almarai. Lucide icons.
- **Backend:** Supabase (Postgres + Auth + Storage + RLS). المفتاح المستخدم client-side هو anon/publishable key فقط — كل الحماية عبر Row Level Security.
- **Serverless:** Vercel (مجلد `api/`): `api/rewrite.js` (تحسين صياغة بالعربي) و`api/agent.js` (المساعد الذكي عبر Gemini function-calling). المفاتيح في Vercel Environment Variables، لا تظهر للعميل.
- **PWA:** service worker (`service-worker.js`) — إصدارات موازية مع `APP_VERSION` في `index.html.html`.
- **Repo:** https://github.com/slamony702-crypto/- (branch: `main`)
- **Live:** https://shouon-al-ghithaa.vercel.app
- **Supabase Project:** `dfuqmmagtteemtpywody` — https://supabase.com/dashboard/project/dfuqmmagtteemtpywody
- **إصدار حالي:** `v105-2026-07-16-ai-settlements-settings`

## 3) هيكل الملفات
```
shouon-al-ghithaa/
├── index.html.html          ← الملف الأساسي (30,000+ سطر): كل CSS + JS + شاشات
├── service-worker.js         ← Kill-switch SW (SW_VERSION موازي لـ APP_VERSION)
├── manifest.json / vercel.json / robots.txt
├── api/
│   ├── rewrite.js            ← تحسين صياغة الرسائل (Gemini)
│   └── agent.js              ← المساعد الذكي (Gemini function-calling)
├── ai-schema-1-assistant.sql
├── acct-schema.sql, acct-schema-2b-ap.sql ... acct-schema-2f-closing.sql
├── hr-schema.sql
├── ops-schema-3a-shifts.sql, ops-schema-3b-prep-orders-inventory.sql, ops-schema-3c-issues-settings.sql
├── pay-schema-p1-partners.sql, pay-schema-p2-statements.sql, pay-schema-p3-clearing.sql
├── cafe-schema.sql, custom-chats-schema.sql, branches-seed.sql, ...
└── (ملفات SQL أخرى قديمة: FINAL-setup.sql, ALL-IN-ONE-setup.sql, cleanup-*.sql)
```

## 4) ما تم تنفيذه حتى الآن

### الموديولات القائمة قبل هذه الجلسة
- المستخدمون، الصلاحيات، الفروع، الأقسام، الاجتماعات، مخرجات الاجتماعات (action_items)، المهام والتكليفات (department_tasks)، القرارات، الإشعارات، التواصل الداخلي، تواصل طارئ، الصيانة (بمزودين ومعدات)، الجودة، ركن الكافيه، التقارير، إعدادات النظام، رؤية الشركة، الملف الشخصي، طلبات الاجتماعات، البحث الصوتي، تحسين الصياغة بالذكاء الاصطناعي.

### الموديولات الجديدة الكاملة (كلها خلف feature flag — test_admin فقط)
1. **HR — الموارد البشرية:** موظفون، هيكل تنظيمي (أقسام/مناصب)، حضور وانصراف، إجازات، رواتب. جداول: `hr_employee_profile`, `hr_departments`, `hr_positions`, `hr_attendance`, `hr_leave_types`, `hr_leaves`, `hr_payroll`. namespace: `window.HR`.
2. **Accounting (2.a → 2.f):** دليل حسابات (65 حسابًا مبدئيًا)، مراكز تكلفة، سنوات وفترات مالية، قيود يومية بمحرك توازن مزدوج ودالة `close_fiscal_year`، موردون وفواتير موردين (`acct_bills`) بموافقة مزدوجة عبر `acct_settings.dual_approval_threshold`، مدفوعات، عملاء وفواتير مبيعات مع QR **ZATCA Phase 1** (TLV+base64 client-side)، مقبوضات، حسابات بنكية (مع GL sub-account تلقائي)، عهد نقدية، مصروفات موظفين، أصول ثابتة (إهلاك سنوي تلقائي)، مخزون، إقرارات VAT، تقارير مالية (`get_trial_balance`, `get_income_statement`, `get_balance_sheet`)، موازنات. namespace: `window.ACCT`.
3. **Operations (3.a → 3.c):** قوالب ورديات، ورديات، تسليم واستلام، توزيع محطات، قوائم فتح/إغلاق يومية، خطط تحضير، طلبات المطعم (`ops_orders` بقيد محاسبي تلقائي `create_journal_for_ops_order`)، مخزون فرعي منفصل، نقل مخزون بين الفروع، سجل هدر مرتبط بحركة مخزون محاسبية، مشكلات تشغيلية بتصعيد لـ `department_tasks`، إعدادات وحدة. namespace: `window.OPS`.
4. **المساعد الذكي (AI Assistant Phase 1 — قراءة فقط):** `api/agent.js` على Vercel بتعليمات نظام صارمة + 7 أدوات قراءة (`get_overdue_tasks`, `get_branches_status`, `get_expiring_documents`, `get_financial_summary`, `get_recent_decisions`, `get_open_maintenance_requests`, `get_partners_settlements`). القاعدة الذهبية: **الخادم لا يلمس قاعدة البيانات إطلاقًا — الأدوات تُنفَّذ في المتصفح بجلسة المستخدم، فتخضع لـ RLS تلقائيًا**. جداول: `ai_settings`, `ai_sessions`, `ai_session_messages`, `ai_audit_log`. حد يومي قابل للتعديل، سجل تدقيق كامل، شاشة إعدادات لـ admin/company_manager. namespace: `window.AIA`.
5. **المدفوعات (Payments P1 → P3) — تحت قسم الحسابات:** شركاء ماليون (`pay_partners`) بأنواع متعددة (منصات توصيل، بوابات دفع، ملاك مطاعم مُدارة)، عقود عمولات بإصدارات (`pay_partner_contracts`)، محرك عمولات JS قابل للتفسير (`PAY.computeCommission` يعيد explanation array)، محاكي عمولة حي، حقل `funds_holder` + `pay_partner_id` على `ops_orders`، كشوف الشركاء (`pay_statements` + `pay_statement_lines`) باستيراد CSV أو لصق نص، محرك مطابقة على مرحلتين (بمرجع الطلب ثم بالمبلغ+التاريخ) بسماحية 0.05 ر.س، مقاصة (`pay_clearing_batches` + `pay_clearing_items`) بصافي موقّع، تسويات يدوية، تحويلات (`pay_payouts`) بربط بنكي وقيد محاسبي مسودة اختياري (`source_type = 'pay_settlement'`). namespace: `window.PAY`.

### تحسينات UI/UX معتمدة
- **Feature flag مركزي:** `PREVIEW_MODULES` + `MODULE_PREVIEW_USERS` + `canAccessModule()` + `gatedModuleForPage()` + حارس routes. المديولات المقفولة: `hr`, `accounting`, `operations`, `ai_agents`. مستخدم المعاينة: `test_admin`.
- إطار متدرج (أخضر ← بنفسجي) على كل البطاقات المعلوماتية عبر `::before` بقناع — لا يلمس خلفية الكارت ولا الـ border-radius.
- ستيبر خطوات الصيانة أعيد تصميمه كدوائر مرقّمة يربط بينها خط، بدون scroll أفقي.
- شيت اختيار مخصص للـ `<select>` على الموبايل، معمّم على كل نقاط الرندر.
- المايك الذكي: يعمل على PWA أندرويد بـ `interimResults=true` مع تجميع النص وتنفيذه في `onend`. عند فشل مطابقة الأمر أو فشل البحث عن اسم موظف، يستخدم `voiceFindPersonLoose` مطابقة مرنة كلمة-بكلمة، ثم يعرض شيت "يمكن تقصد؟" بالاقتراحات.
- إصلاح جلسات قديمة: `bootApp` يتحقق من وجود المستخدم في قاعدة البيانات ويسجّل خروج المستخدمين المحذوفين تلقائيًا برسالة عربية واضحة، ويصلح خطأ `department_tasks_assigned_by_fkey`.

## 5) القرارات والتعديلات المعتمدة

### قرارات مركزية موثقة في الكود بـ `// DECISION:`
- **المدفوعات — أساس العمولة الافتراضي:** صافي المنتجات بعد الخصم بدون ضريبة وتوصيل (توصية وثيقة المرجع).
- **المدفوعات — عقد ساري واحد لكل شريك:** تفعيل عقد ينهي أي عقد ساري آخر لنفس الشريك تلقائيًا. تعديل الشروط المالية لعقد ساري ممنوع من الواجهة — يُنشأ إصدار جديد بتاريخ سريان لاحق.
- **المدفوعات — سماحية فرق المبلغ في المطابقة:** 0.05 ر.س (فروق تقريب الهللات فقط). أي فرق أكبر = بند "فرق" بسبب موثق.
- **المدفوعات — اتجاه الصافي:** `net_receivable` موجب = مستحق لنا على الشريك. سالب = مستحق للشريك علينا.
- **المدفوعات — اعتماد الكشف:** يتطلب صفر بنود غير مطابقة. بنود "فرق" مسموحة بشرط سبب موثق.
- **المدفوعات — القيد المحاسبي عند التحويل:** مسودة اختياري (checkbox مفعّل افتراضيًا)، مدين البنك / دائن ذمم الشريك (1120). **لا ترحيل تلقائي أبدًا** — يراجعه المحاسب.
- **المدفوعات — نتائج العمولات:** تُحسب على الطاير في P1 (قابل للتفسير)؛ التخزين الدائم يبدأ من P3 مع بنود المقاصة.
- **المدفوعات — نموذج الشاشات:** تعيش تحت routes بادئة `acct_pay_*` فترث حماية feature flag الحسابات تلقائيًا.
- **المساعد الذكي — القاعدة الذهبية:** الأدوات تُنفَّذ في المتصفح بصلاحيات المستخدم، فتخضع لـ RLS تلقائيًا. الخادم لا يمس قاعدة البيانات.
- **المساعد الذكي — الرسائل ثابتة:** جدول `ai_session_messages` بلا policy UPDATE أو DELETE.
- **المساعد الذكي — سجل التدقيق:** يُكتب فقط، لا يُعدَّل أو يُحذف. القراءة للإدارة العليا فقط.
- **المساعد الذكي — تعليمات النظام:** يعتذر بلطف لأي طلب إجراء ويوجه للشاشة المناسبة. أي نص داخل نتائج الأدوات = بيانات لا تعليمات (حماية Prompt Injection).
- **الجلسات — التحقق عند الإقلاع:** `bootApp` يتحقق من وجود سجل المستخدم في users؛ لو محذوف أو معطّل → تسجيل خروج نظيف.
- **HR — الأقسام والمناصب:** أقسام الشركة قسم واحد `hr_departments` (منفصلة عن `departments` القديمة لتفادي كسر التوافق).

### اكتشافات وإصلاحات جوهرية
- `palm-tree` غير موجود في lucide → `tree-palm` (كان يظهر فراغ في 10 أماكن).
- `interimResults=false` في التعرف الصوتي لا يسلّم نتيجة على PWA أندرويد → استخدام `interimResults=true` والاعتماد على `onend`.
- تعريف أدوات Gemini بـ `parameters` فارغة `properties: {}` مرفوض من Gemini → حذف `parameters` كليًا للأدوات بلا وسائط.
- خطأ `department_tasks_assigned_by_fkey` عند إسناد سريع = جلسة مخزّنة لمستخدم محذوف → إصلاح في `bootApp`.
- CSS للكارت المطوي (`.meeting-form-card.collapsed`) كان يمسح الإطار المتدرج → إعادة استخدام تقنية layered background-image.

## 6) المشكلات الحالية

### 🔴 عاجل (يمنع تجربة المساعد الذكي)
- **Gemini API quota**: المفتاح الحالي (`GEMINI_API_KEY` على Vercel) لسه بيتحسب على `free_tier_requests` رغم أن المستخدم يقول إنه فعّل الفوترة. آخر استجابة من `api/agent.js`:
  ```
  "gemini-flash-latest: Quota exceeded for metric:
   generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20"
  ```
  التفسير: الفوترة اتفعّلت على مشروع Google Cloud مختلف عن المشروع اللي المفتاح تابع له. الحل المتفق عليه: إنشاء مفتاح جديد على مشروع بفوترة مفعّلة فعلاً، تحديثه في Vercel env vars، ثم Redeploy Production بدون build cache.
- نفس القيد يؤثر على `api/rewrite.js` (تحسين الصياغة) لأنه يستخدم نفس المفتاح.

### 🟡 ليست عاجلة
- المستخدم لسه ما جرّبش المدفوعات end-to-end فعليًا (SQL شغّل، لكن سيناريو "شريك ← عقد ← كشف ← مطابقة ← مقاصة ← تحويل ← قيد" ينتظر تنفيذ يدوي).
- لا يوجد جدول عمولات ثابت في P1 — الحساب على الطاير. لو الشركة احتاجت تقارير أرشيفية لعمولات قديمة سنحتاج جدول `pay_commission_snapshots`.
- لا يوجد ربط API فعلي مع منصات التوصيل — الاستيراد CSV/يدوي فقط (وثيقة المرجع نفسها تقر بذلك).
- Node syntax check يمر بصفر أخطاء لكن مفيش end-to-end tests أوتوماتيكية.

## 7) آخر خطوة وصلنا إليها
- **آخر commit:** `1312e0b` — "Agent endpoint: clear Arabic message when Gemini quota is exhausted" — مرفوع على GitHub وVercel.
- **آخر إصدار:** `v105-2026-07-16-ai-settlements-settings` (في كل من `APP_VERSION` و`SW_VERSION`).
- **آخر تفاعل مع المستخدم:** أخبره أن الفوترة اللي فعّلها اتفعّلت على مشروع مختلف، وأرسل له خطوات بالتفصيل لإنشاء مفتاح جديد على المشروع الصحيح ووضعه في Vercel وعمل Redeploy. المستخدم لم يرد بعد.
- جدول المهام كامل (`#1` → `#34` كلها `completed`).

## 8) الخطوة التالية المطلوبة
1. **انتظار المستخدم يحل quota Gemini** (خطوات مفصلة أُرسلت له). لما يقول "خلص":
   - افحص `api/agent` مباشرة بـ `curl` بكلمة "hi" — لو رجع `text` أو `toolCalls` بدون `free_tier` → شغّال.
   - أخبر المستخدم بالتأكيد ووجّهه لصفحة `#ai_assistant`.
2. لما التجربة تشتغل:
   - سيناريو تجربة متكامل للمدفوعات (شريك ← عقد ← طلب مربوط بالشريك ← كشف ← مطابقة ← مقاصة ← تحويل ← قيد).
   - أدوات مساعد ذكي إضافية محتملة (سبق اقتراحها): تحليلات إجمالية، ملخصات فروع مقارنة، Alerts استباقية.
3. المستخدم لديه اجتماع قريب مع الإدارة لعرض المنصة — كل الميزات الجديدة يجب أن تكون خلف flag حتى الاعتماد.

## 9) تعليمات مهمة يجب ألا تتغير
- ❌ **لا تكسر أي فيتشر شغالة.** الاجتماعات، المهام، القرارات، الصيانة، الجودة، الكافيه، الإشعارات، تسجيل الدخول — كلها إنتاج فعلي.
- ❌ **لا تلمس `authLogin` أو منطق تسجيل الدخول** — التعديلات فقط على مرحلة "ما بعد الجلسة" (revalidation في `bootApp`).
- ❌ **لا تعدّل schema قاعدة البيانات بشكل مدمّر** — كل SQL جديد `IF NOT EXISTS` / `ON CONFLICT` / `DROP POLICY IF EXISTS`, idempotent، لا `DROP TABLE`.
- ❌ **لا تنفّذ SQL بنفسك أبدًا** — المستخدم يشغّله يدويًا في Supabase SQL Editor ويقول "خلص". أرسل الملف كـ attachment أو الصق المحتوى في code block.
- ❌ **لا تسرّب المفاتيح** — `GEMINI_API_KEY` يعيش في Vercel env vars فقط، لا يظهر في الكود العميل ولا في response body.
- ❌ **لا تلمس الـ routing الأساسي (`route()`)** — أضف routes جديدة فقط بنمط `else if (page === '...') await pageXxx(body, param, query);`.
- ✅ **كل فيتشر جديدة خلف `canAccessModule()` — test_admin فقط حتى الاعتماد.** إضافة مفتاح المديول إلى `PREVIEW_MODULES` + سطر جديد في `gatedModuleForPage()` كافية.
- ✅ **PATCH: كل تعديل يمر بفحص syntax عبر Node** قبل commit:
  ```bash
  node -e "const fs=require('fs');const html=fs.readFileSync('index.html.html','utf8');const scripts=[...html.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);let e=0;scripts.forEach((c,i)=>{try{new Function(c);}catch(x){e++;console.log('block',i,x.message);}});console.log('Errors:',e);"
  ```
  وإذا فيه `api/*.js` معدَّل: `node --check api/agent.js`.
- ✅ **APP_VERSION + SW_VERSION يترقّيا معًا** في كل commit مؤثر.
- ✅ **كل commit له وصف واضح**، commit منفصل لكل مرحلة رئيسية، ثم `git push origin main`.
- ✅ **اللغة:** الواجهة عربية 100%، الكود إنجليزي، التعليقات مفيدة بس مش زائدة، توثيق `// DECISION:` لكل قرار مؤسسي.
- ✅ **لو محتاج قرار حاسم:** خذ أفضل default مؤسسي وسجّل `// DECISION:` مع السبب.
- ✅ **اسأل قبل الأفعال الخطرة** (نشر، حذف، إعادة كتابة موديول).

## 10) الملفات المهمة للمراجعة في أي جلسة قادمة
| الملف | لماذا |
|---|---|
| `HANDOFF.md` (هذا الملف) | نقطة البداية |
| `index.html.html` | الملف الرئيسي — كل شيء هنا |
| `api/agent.js` | خادم المساعد الذكي (function calling + fallback + quota handling) |
| `api/rewrite.js` | خادم تحسين الصياغة (نموذج بسيط لبنية Vercel + Gemini) |
| `service-worker.js` | Kill-switch SW — SW_VERSION موازي لـ APP_VERSION |
| `vercel.json` | Cache-Control headers لبعض الأصول |
| SQL الرئيسية (بترتيب التطبيق): |  |
| ↳ `hr-schema.sql` | جداول HR + `users.branch_id` |
| ↳ `acct-schema.sql` → `acct-schema-2f-closing.sql` | 6 مراحل للحسابات |
| ↳ `ops-schema-3a` → `-3c` | 3 مراحل للتشغيل |
| ↳ `ai-schema-1-assistant.sql` | جداول المساعد الذكي |
| ↳ `pay-schema-p1-partners.sql` → `p3-clearing.sql` | 3 مراحل للمدفوعات |

### مواقع مهمة داخل `index.html.html` (قد تتزحزح بعد أي تعديل — استخدم Grep)
- `PREVIEW_MODULES` + `MODULE_PREVIEW_USERS` + `canAccessModule` + `gatedModuleForPage` → البحث عن `PREVIEW_MODULES`
- `MENU_GROUPS` → هيكل السايدبار
- `PAGE_TITLES` → عناوين الصفحات
- `async function route()` → توجيه الصفحات (كل الـ pages مسجّلة هنا)
- `bootApp` → منطق الإقلاع + revalidation
- `window.HR` / `window.ACCT` / `window.OPS` / `window.PAY` / `window.AIA` → طبقات الوصول للبيانات
- `pageComingSoonModule` + `COMING_SOON_MODULES` → صفحات "قريبًا" لكل مديول
- `handleVoiceTranscript` + `buildVoiceSuggestions` + `VOICE_COMMANDS` → منطق الصوت
- `finishLoginAndEnterApp` → إنهاء تسجيل الدخول (لا تلمسه)

### روابط عملية
- **Live:** https://shouon-al-ghithaa.vercel.app
- **GitHub:** https://github.com/slamony702-crypto/-
- **Supabase SQL Editor:** https://supabase.com/dashboard/project/dfuqmmagtteemtpywody/sql/new
- **Vercel Project:** `shouon-al-ghithaa` (org: `team_YYyp7jX6WwUm8wsaG02S4Ymk`, project id: `prj_zHeDQheJ904Mh82GY6mbkHlxSQRh`)
- **Gemini API Keys:** https://aistudio.google.com/app/apikey
