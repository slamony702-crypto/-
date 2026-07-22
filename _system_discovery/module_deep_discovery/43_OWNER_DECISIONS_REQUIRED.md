# 43 — قرارات المالك المطلوبة (Owner Decisions Required)

> **مصدر:** `DISCOVERY_SUMMARY_FOR_CHATGPT.md §17` + تحليل هذا التقرير.

## القرارات المرقّمة (اللازم قبل الإطلاق أو التوسع)

### 🔴 قرارات حرجة

#### D1 — Franchise ↔ Accounting AR
**السؤال:** هل الروياليتي تُنشئ فاتورة AR تلقائيًا أم يدويًا؟
**السياق:** `franchise_issue_royalty` ينشئ `franchise_royalty_invoices` لكن لا يُنشئ `acct_invoices` تلقائيًا (R-14).
**الخيارات:**
- **A: تلقائي (recommended):** trigger أو RPC اختيارية.
- **B: يدوي:** الاحتفاظ بالوضع الحالي مع زر "إنشاء AR invoice".

#### D2 — توحيد `crm_customers` و `acct_customers`
**السياق:** جدولان لبيانات العميل بلا FK (R-08).
**الخيارات:**
- **A: توحيد:** جدول واحد `customers` مشترك.
- **B: FK ربط:** إبقاء منفصل + ربط `crm_customers.acct_customer_id`.
- **C: sync trigger:** إبقاء منفصل + trigger يزامن.

#### D3 — `users.password_plain` → Supabase Auth JWT
**السياق:** R-01 حرجة (كلمة مرور نص صريح) + R-02 (RLS يعتمد `current_app_role()` لا JWT).
**الخيارات:**
- **A: انتقال فوري (recommended):** sprint مخصص قبل أي توسع.
- **B: تأجيل:** خطر أمني.

### 🟠 قرارات عالية

#### D4 — Action Items ↔ Department Tasks
**السؤال:** هل ندمج أم نوضح المسميات؟
**الخيارات:**
- **A: دمج:** `department_tasks` مع حقل `source_meeting_id`.
- **B: توضيح:** تسمية `action_items` كـ "التزامات الاجتماعات".
- **C: تحويل تلقائي:** `action_to_task(id)` بضغطة.

#### D5 — بوابة فرنشايزي مستقلة
**السؤال:** الآن أم Phase 2؟
**الخيارات:**
- **A: Phase 1:** login منفصل + رفع تقارير.
- **B: Phase 2 (recommended قصير الأمد):** التركيز على مراجعة الحالي أولاً.

#### D6 — أولوية Integrations workers
**السؤال:** أي 12 مزوّد أولاً؟
**الاقتراح:** WhatsApp Cloud + Jahez + Mada Pay أولاً (أكثر أثرًا تجاريًا).

#### D7 — CC PBX integration
**السؤال:** الآن أم مؤجل؟
**الاقتراح:** Phase 2 (يحتاج contract مع مزوّد).

#### D8 — مصير `#reports` و `#analytics` القديمة
**السؤال:** إبقاء أم إلغاء بعد BI؟
**الاقتراح:** إلغاء + إعادة توجيه إلى BI.

### 🟡 قرارات متوسطة

#### D9 — توحيد `departments` مع `hr_departments`
**السؤال:** توحيد أم إبقاء منفصل؟

#### D10 — توحيد `branch_assets` + `maintenance_equipment` + `maintenance_assets`
**السؤال:** جدول واحد `assets` مع `category`؟

#### D11 — BOM إلزامي في Menu
**السؤال:** جعل `menu_item_recipes` إلزامي أم اختياري؟

#### D12 — CASH_FLOW RPC
**السؤال:** بناء الآن أم إلغاء التقرير؟

#### D13 — تفعيل `dashboard_summary` RPC (R-13)
**السؤال:** تحديث الفرونت الآن أم إبقاء الاستعلامات الثلاثة؟

#### D14 — Cron scheduler لـ `doc_expire_overdue`
**السؤال:** pg_cron أم Supabase scheduled function أم external?

#### D15 — Supabase Vault لـ `int_webhook_endpoints.secret_token`
**السؤال:** تكامل الآن أم مؤجل؟

#### D16 — POS offline
**السؤال:** أولوية Phase 1؟

#### D17 — Delivery driver PWA مستقل
**السؤال:** Phase 1 أم Phase 2?

### 🟢 قرارات منخفضة

#### D18 — Numbering scheme (COUNT+1 → SEQUENCE)
**السؤال:** إعادة هيكلة أم إبقاء؟ **الاقتراح:** إبقاء (R-18 منخفضة).

#### D19 — Font-size + border-radius (--fs-* / --radius-*)
**السؤال:** توحيد؟ **الاقتراح:** إبقاء (تجميلي، مكلف بلا فائدة مرئية).

#### D20 — Lazy loading للـ preview modules
**السؤال:** تقسيم الملف؟ **الاقتراح:** يخالف فلسفة "ملف واحد بلا build" — يحتاج نقاش.

## ملخص السريع (لصاحب المشروع)

| # | القرار | أولوية | الاقتراح |
|---|---|---|---|
| D1 | Franchise ↔ AR | 🔴 | A (تلقائي) |
| D2 | Customers توحيد | 🔴 | A أو C (recommended sync) |
| D3 | Supabase Auth JWT | 🔴 | A (فوري) |
| D4 | Action Items ↔ Tasks | 🟠 | C (تحويل تلقائي) |
| D5 | بوابة فرنشايزي | 🟠 | B (Phase 2) |
| D6 | Integrations أولوية | 🟠 | WhatsApp + Jahez + Mada |
| D7 | CC PBX | 🟠 | B (Phase 2) |
| D8 | Reports/Analytics القديمة | 🟠 | إلغاء |
| D9 | departments توحيد | 🟡 | توحيد |
| D10 | Assets توحيد | 🟡 | توحيد |
| D11 | BOM إلزامي | 🟡 | إبقاء اختياري لكن bug reporting |
| D12 | CASH_FLOW RPC | 🟡 | بناء |
| D13 | dashboard_summary فرونت | 🟡 | تحديث |
| D14 | Cron | 🟡 | Supabase scheduled |
| D15 | Vault | 🟡 | تكامل |
| D16 | POS offline | 🟡 | Phase 2 |
| D17 | Delivery PWA | 🟡 | Phase 2 |
| D18 | Numbering | 🟢 | إبقاء |
| D19 | Design tokens | 🟢 | إبقاء |
| D20 | Lazy loading | 🟢 | نقاش |
