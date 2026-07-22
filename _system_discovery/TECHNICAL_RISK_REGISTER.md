# TECHNICAL_RISK_REGISTER — سجل المخاطر التقنية والتشغيلية

> استُخرجت من HANDOFF v120/v121 audit results + فحص الكود والـ SQL.

## الأولوية: 🔴 حرجة | 🟠 عالية | 🟡 متوسطة | 🟢 منخفضة

---

## 🔴 حرجة

### R-01 users.password_plain — كلمة السر بنص صريح
- المصدر: عمود قديم في جدول users من Wave 0.
- الأثر: تسرب قاعدة البيانات = تسرب كل كلمات السر مباشرة.
- الحل الموصى به (مؤجَّل في HANDOFF): إعادة هيكلة كاملة لـ Supabase Auth + رابط استعادة عبر البريد.
- مذكور صراحة في HANDOFF: "يستحق sprint منفصل".

### R-02 RLS يعتمد على current_app_role()/current_app_user_id() بدل Supabase JWT
- المصدر: نمط RLS في hr-schema + كل schemas الجديدة.
- الأثر: العميل يمكنه تلاعب localStorage → تجاوز RLS.
- الحل: نقل المصادقة إلى Supabase Auth الحقيقي + JWT claims.

### R-03 CORS مفتوح على * في /api/rewrite و /api/agent
- المصدر: api/rewrite.js, api/agent.js.
- الأثر: أي origin يمكنه استدعاء الـ endpoints؛ استنزاف Gemini quota.
- الحل: تقييد Access-Control-Allow-Origin على domain الفعلي.

---

## 🟠 عالية

### R-04 extraInstructions في /api/agent بلا Bearer verification
- المصدر: api/agent.js body param.
- الأثر: prompt injection على الـ system instruction الذكي.
- الحل (مؤجَّل): Supabase Auth Bearer flow لتحقّق قراءة من ai_settings server-side.

### R-05 int_webhook_endpoints.secret_token نص صريح
- الأثر: تسرب الجدول = تسرب أسرار webhook.
- الحل (مؤجَّل): Supabase Vault.

### R-06 GEMINI_API_KEY يعتمد على env var واحد
- الأثر: quota exhaustion يوقف المساعد الذكي + rewrite.
- ملاحظة HANDOFF: quota حاليًا على مشروع Google Cloud خاطئ.

### R-07 جداول عمليات جوهرية بلا SQL versioned
- meetings, action_items, decisions, department_tasks, maintenance_*, quality_*, cafe_*, conversations, ... schemas موجودة في Supabase مباشرة.
- الأثر: أي migration أو رجوع لحالة أقدم = فقدان تاريخ.
- الحل: dump كل schemas إلى ملفات SQL versioned.

### R-08 acct_customers مقابل crm_customers جدولان منفصلان لبيانات العميل
- الأثر: تكرار بيانات، عدم اتساق، صعوبة تحديث.
- الحل: توحيد أو foreign key ربط.

---

## 🟡 متوسطة

### R-09 الملف الرئيسي 43,152 سطر (index.html.html)
- الأثر: صعوبة الصيانة، load time على شبكات ضعيفة، dead code.
- الحل (مؤجَّل صراحة): Lazy loading للموديولات المعاينة (~11,000 سطر = 26% dead code لمستخدم عادي).

### R-10 لا E2E tests
- الأثر: يوجد فقط Node syntax check. 17 موديول جديد لم تُختبر يدويًا كل سيناريوهاتها.
- الحل: Playwright/Cypress basic smoke tests.

### R-11 Integrations workers غير موجودين
- الأثر: 12 مزوّد UI بلا اتصال حقيقي؛ تضليل UX ("قد يعمل" بينما لا يعمل).

### R-12 CC PBX integration غير موجودة
- الأثر: كل تفاصيل المكالمة تُدخل يدويًا.

### R-13 dashboard aggregation عبر 3 استعلامات منفصلة بدل RPC
- SQL جاهزة (dashboard_summary) لكن الفرونت لم يُحدَّث.
- الأثر: ضغط أداء تحت الحمل. .limit(500) الحالي كافٍ لمنع التعليق لكن غير أمثل.

### R-14 Franchise → AR invoice creation بلا آلية تلقائية
- الأثر: قد تُفوَّت فواتير روياليتي في تسجيل AR.
- الحل: قرار المالك مطلوب.

### R-15 doc_expire_overdue بلا cron scheduler
- الأثر: انتهاء صلاحية المستندات لن يُكتشف تلقائيًا.

### R-16 BI CASH_FLOW بلا rpc_name
- الأثر: تقرير في الكتالوج بلا تنفيذ = خطأ عند فتحه.

### R-17 delete cascade على branches → SET NULL على branch_id
- الأثر: فقدان ربط تاريخي عند حذف فرع (مقابل قرار احتفاظ soft).
- الحل: is_active بدل حذف — مطبَّق نظريًا لكن FKs تحتوي ON DELETE SET NULL.

---

## 🟢 منخفضة

### R-18 COUNT+1 numbering scheme بدل SEQUENCE
- 15+ دالة ترقيم تستخدم COUNT+1 (race condition تحت concurrency عالية).
- HANDOFF يقول: "القيمة تحت الحمل الحالي منخفضة".

### R-19 41 قيمة font-size مختلفة، 34+ border-radius حرفية
- الأثر: عدم اتساق بصري.
- الحل (مؤجَّل): تطبيق --fs-* و --radius-*.

### R-20 Sidebar 21 مجموعة، 15 منها معاينة بمفتاح واحد
- الأثر: UX ضعيف، إحساس بامتلاء بلا معنى.

### R-21 lucide icon "palm-tree" غير موجودة
- v121 fix: palm-tree → tree-palm. آمنة الآن.

### R-22 4 خطوات محادثة AI (Gemini function calling loop)
- HANDOFF: "يحتاج نقاش UX/تكلفة" — قد يبطئ الاستجابة.

### R-23 proc_grn CHECK قيمة غير مستخدمة
- Dead code، غير ضار.

### R-24 PREVIEW_MODULES 16 مفتاح مقابل 17 موديول موثقة
- PAY تحت gate accounting — سلوك صحيح لكن مربك في التوثيق.

---

## ملخص المخاطر
| الأولوية | العدد |
|---|---:|
| 🔴 حرجة | 3 |
| 🟠 عالية | 5 |
| 🟡 متوسطة | 9 |
| 🟢 منخفضة | 7 |
| **الإجمالي** | **24** |

## المخاطر المؤجَّلة تحتاج قرار المالك
1. R-01 password_plain — sprint منفصل.
2. R-04 extraInstructions — تصميم أمني منفصل.
3. R-05 Vault — تكامل منفصل.
4. R-07 versioning للجداول الأصلية.
5. R-14 Franchise → AR — قرار تجاري.
6. R-08 توحيد العملاء — قرار بنيوي.
