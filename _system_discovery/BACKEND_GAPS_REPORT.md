# BACKEND_GAPS_REPORT — فجوات ربط الشاشات بـ Backend

> منهج الفحص: كل موديول من Waves 1-4 — هل شاشاته تستدعي `sb.from(...)` أو `sb.rpc(...)` فعلاً؟ هل يوجد جدول SQL مقابل؟ هل توجد شاشة لكل جدول؟
> استُخدم Grep لجمع 175 اسم جدول متكرر في `sb.from(...)`.

## الرمز
- ✅ UI ↔ Backend مربوط بالكامل
- 🟨 UI ↔ Backend مربوط جزئيًا
- 🟥 UI بلا Backend حقيقي (Mock)
- 🟦 Backend بلا UI

---

## Wave 0

### HR
- ✅ كل جداول `hr_*` (attendance, leaves, payroll, positions, employee_profile) لها استعلامات فعلية في `pageHrAttendance`, `pageHrLeaves`, `pageHrPayroll`, `pageHrEmployees`.
- 🟦 لا شاشة لـ `hr_departments` (منفصل عن departments) — يُدار من هيكل عام.
- 🟨 لا شاشة لملف تعليمي/شهادات/عقود (المخطط في `COMING_SOON_MODULES.hr` روادماب).

### Accounting
- ✅ كل جداول `acct_*` الرئيسية مربوطة (الاستعلامات ظاهرة).
- 🟦 `acct_asset_depreciation_schedule` — لا شاشة عرض جدول الإهلاك المفصل (فقط ملخص).
- 🟨 `acct_vat_returns` — الشاشة موجودة لكن `compute_vat_totals(p_start,p_end)` RPC غير مستدعاة بشكل واضح؛ يعتمد على استعلامات مباشرة.

### Operations
- ✅ كل جداول `ops_*` (17 جدول) مربوطة بشاشات.
- 🟨 `ops_stock_transfers` / `ops_stock_transfer_items` — الشاشة موجودة، لكن دالة `ops_apply_stock_transfer` تُستدعى؟ يوجد trigger — القرار على من ينفذها.
- 🟨 `ops_waste_records` مع `ops_apply_waste_to_branch_inventory` (trigger).

### AI Assistant
- 🟥 الأدوات الـ7 تُنفَّذ **client-side** بعد أن يطلبها Gemini — لا شاشة تدير أدوات مباشرة. تعمل كخدمة.
- ✅ `ai_settings`, `ai_sessions`, `ai_session_messages`, `ai_audit_log` مربوطة.

### Payments (PAY)
- ✅ كل جداول `pay_*` مربوطة بـ `pageAcctPayPartners`, `pageAcctPayStatements`, `pageAcctPayClearing`.

---

## Wave 1

### Menu
- ✅ `menu_settings`, `menu_categories`, `menu_items`, `menu_item_recipes`, `menu_channel_prices` — كلها مربوطة.
- 🟨 `menu_compute_item_cost` RPC — يُستدعى في `pageMenuItemDetail`؟ يحتاج تحقق تشغيلي.

### CRM & Loyalty
- ✅ `crm_customers`, `crm_customer_addresses`, `loyalty_accounts`, `loyalty_transactions`, `crm_complaints` — كلها مربوطة.
- 🟨 لا شاشة للاطلاع على تفاصيل حساب ولاء العميل بلوحة منفصلة (يُدمج في customer detail).

### POS
- ✅ `pos_terminals`, `pos_sessions`, `pos_transactions`, `pos_transaction_items`, `pos_payment_splits` — كلها مربوطة.
- ✅ `pos_complete_transaction` RPC مستدعاة من `pagePosCashier`.
- 🟨 لا شاشة `#pos_terminals` واضحة في السايدبار (فقط عبر `#pos` dashboard).

---

## Wave 2

### HACCP
- ✅ كل جداول `haccp_*` مربوطة.
- 🟨 `haccp_health_certificates` — يشترك مع HR employee (تكرار محتمل مع جدول HR employee).

### Procurement
- ✅ كل جداول `proc_*` مربوطة.
- ✅ `proc_receive_goods` RPC مستدعاة.

### Performance
- ✅ كل جداول `perf_*` مربوطة.
- 🟨 `perf_compute_scorecard_score` RPC — استخدامها الفعلي في UI يحتاج تحقق.

---

## Wave 3

### Delivery
- ✅ كل جداول `delivery_*` مربوطة.
- ✅ 3 دوال ذرية مستدعاة.
- 🟨 لا تطبيق مستقل للسائق — الاستخدام من نفس PWA.

### Documents
- ✅ `doc_categories`, `doc_documents`, `doc_access_log` مربوطة.
- 🟦 `doc_expire_overdue()` بلا cron — يحتاج مشغل خارجي.

### Call Center
- ✅ `cc_agents`, `cc_calls`, `cc_dispositions`, `cc_scripts` مربوطة.
- 🟥 لا PBX integration — الأرقام تُدخل يدويًا؛ لا تسجيل مكالمات فعلي.

---

## Wave 4

### BI
- ✅ `bi_report_definitions`, `bi_snapshots`, `bi_saved_views` مربوطة.
- 🟥 التقرير `CASH_FLOW` — بلا `rpc_name` (NULL) → **PLACEHOLDER**. الشاشة موجودة لكن الحساب غير مُنفَّذ.
- ✅ الـ6 تقارير الباقية لها RPCs مربوطة.

### Integrations
- ✅ `int_providers`, `int_connections`, `int_webhook_endpoints`, `int_events` مربوطة.
- 🟥 12 مزوّد مبذور بلا workers فعليين — الإرسال والاستقبال لا يعمل. البنية والسجل جاهزان لكن المزودون بلا فعل حقيقي.
- 🟥 `int_log_event` / `int_complete_event` تُستدعى فقط من UI عند اختبارات يدوية.

### Franchise
- ✅ `franchise_partners`, `franchise_agreements`, `franchise_branches`, `franchise_sales_reports`, `franchise_royalty_invoices` مربوطة.
- 🟥 **بوابة الفرنشايزي المستقلة** — غير موجودة (تسجيل دخول منفصل + رفع تقارير سرعة الفروع بنفسه) → PLACEHOLDER في خطة Phase 2.
- 🟨 `franchise_compute_royalty` تُنشئ الفاتورة، لكن الربط التلقائي بـ `acct_invoices` لم يُفعَّل.

---

## Backend بلا UI (BACKEND_ONLY)
| الوظيفة | تفصيل |
|---|---|
| `compute_vat_totals` | RPC موجود؛ الاستخدام في `acct_vat_returns` جزئي. |
| `run_monthly_depreciation` | RPC للإهلاك الشهري — لا زر تشغيل مرئي. |
| `close_fiscal_year` | RPC إغلاق سنة — يحتاج شاشة اعتماد. |
| `get_budget_vs_actual` | RPC للموازنة — الشاشة موجودة لكن Drill-down جزئي. |
| `doc_expire_overdue` | لا Cron مضبوط. |
| كل triggers auto-numbering (haccp/menu/pos/proc/perf/dlv/doc/cc/int/fr) | تعمل بذاتها — لا شاشة. |
| Franchise → AR link | القرار مؤجل. |
| Delivery cross-integration (Jahez/HungerStation) | webhook endpoints جاهزة، لا workers. |

## UI بلا Backend حقيقي (UI_ONLY / MOCK_DATA)
| الشاشة | لماذا |
|---|---|
| Integrations Marketplace (`#int_marketplace`) | يعرض 12 مزوّد لكن الاتصال يتوقف بعد إدخال config. |
| CC Call recording | لا PBX. |
| BI report `CASH_FLOW` | لا RPC. |
| بوابة الفرنشايزي | غير موجودة. |
| Delivery driver mobile app | لا PWA خاصة. |

## جداول مستدعاة من UI ولا يوجد لها ملف SQL versioned
جداول من الأصل الأول (بلا SQL في المجلد):
- `meetings`, `meeting_attendees`, `meeting_agenda`, `meeting_tasks`, `meeting_requests`, `meeting_preparation_reports`
- `action_items`, `decisions`, `decision_sub_responsibles`, `decision_viewers`, `decision_acknowledgments`, `decision_activity_log`
- `department_tasks`, `task_projects`, `task_project_members`, `task_project_updates`
- `conversations`, `messages`, `message_reads`, `conversation_members`
- `emergency_alerts`, `emergency_recipients`, `emergency_activity_log`
- `notifications`, `user_activity_log`, `signup_requests`
- `maintenance_*` (11 جدول)
- `quality_*` (6 جداول)
- `cafe_*` (4 جداول)
- `company_vision`, `department_goals`
- `branches`, `departments`, `role_permissions`, `user_permission_overrides`
- `branch_assets`

→ Schema هذه الجداول لم يُوثَّق في SQL versioned files — يوجد فقط في Supabase مباشرة. **مخاطرة migrations كبيرة**.
