# MODULE_INVENTORY — جرد شامل للـ34 موديول

> اعتمد الاكتشاف على `MENU_GROUPS`, `PAGE_TITLES`, `PREVIEW_MODULES`, DAL objects (`window.HR`, `window.ACCT`, …)، جداول SQL، ودوال RPC.
> التصنيفات: **COMPLETE** = يعمل كامل • **PARTIALLY_COMPLETE** = يعمل جزئيًا • **UI_ONLY** = شاشة بلا Backend • **BACKEND_ONLY** = بلا شاشة • **PLACEHOLDER** = "قريبًا" • **MOCK_DATA** = بيانات وهمية • **BROKEN** • **UNUSED** • **UNKNOWN**.

---

## القسم الأول: 17 موديول إنتاج (مفتوح للجميع)

### 1) المستخدمون والصلاحيات (Users & Permissions)
- **الغرض:** إدارة الهوية والوصول. الأساس لكل موديول.
- **المستخدمون:** admin + company_manager + hr_manager. الكل يرى ملفه.
- **Routes:** `#users`, `#my_profile`, `#invite`, `#settings`.
- **الجداول:** `users`, `role_permissions`, `user_permission_overrides`, `user_activity_log`, `signup_requests`.
- **الأدوار:** 18 role مذكورة في CATALOG.
- **الحالات:** `is_active` (soft delete)، `signup_requests.status` (pending/approved/rejected).
- **الاكتمال:** COMPLETE.
- **التبعيات:** لا شيء.
- **يرسل إلى:** كل موديول تقريبًا (RLS + `assigned_to`, `created_by`, …).

### 2) الفروع والأقسام (Branches & Departments)
- **Routes:** لا route مستقل — يُدار عبر `#settings` و`#users` وشاشات فرعية.
- **الجداول:** `branches`, `departments`, `branch_assets`.
- **الأدوار:** admin/company_manager يعدل. الكل يقرأ حسب RLS.
- **الحالات:** `is_active` (فرع مغلق يبقى مؤرشفًا).
- **الاكتمال:** COMPLETE.
- **التبعيات:** المستخدمون.
- **يرسل إلى:** كل الجداول تقريبًا (`branch_id`, `department_id`).

### 3) الاجتماعات (Meetings)
- **Routes:** `#meetings`, `#meetings_calendar`, `#meeting_detail/:id`, `#meeting_requests`.
- **الجداول:** `meetings`, `meeting_attendees`, `meeting_agenda`, `meeting_tasks`, `meeting_requests`, `meeting_preparation_reports`.
- **الأدوار:** الجميع (كل واحد يرى اجتماعاته). admin/company_manager يرى الكل.
- **الحالات:** `scheduled`, `in_progress`, `completed`, `in_follow_up`, `closed`, `cancelled`, `postponed`.
- **الاكتمال:** COMPLETE.
- **التبعيات:** المستخدمون، الأقسام، الفروع.
- **يرسل إلى:** `action_items`, `decisions`, `department_tasks`, `notifications`.

### 4) مخرجات الاجتماعات (Action Items)
- **Route:** `#tasks`.
- **الجداول:** `action_items`.
- **الأدوار:** المسند/المسؤول.
- **الحالات:** `open`, `in_progress`, `completed`, `cancelled`, `overdue` (محسوبة).
- **الاكتمال:** COMPLETE.
- **التبعيات:** الاجتماعات، المستخدمون.
- **يرسل إلى:** notifications.

### 5) المهام والتكليفات (Department Tasks)
- **Route:** `#department_tasks`.
- **الجداول:** `department_tasks`, `task_projects`, `task_project_members`, `task_project_updates`.
- **الأدوار:** المديرون يكلفون، الجميع ينفذ.
- **الحالات:** `new`, `in_progress`, `review`, `completed`, `cancelled`.
- **الاكتمال:** COMPLETE.
- **التبعيات:** المستخدمون.
- **يرسل إلى:** notifications, conversations.

### 6) القرارات (Decisions)
- **Route:** `#decisions`.
- **الجداول:** `decisions`, `decision_sub_responsibles`, `decision_viewers`, `decision_acknowledgments`, `decision_activity_log`.
- **الأدوار:** الإدارة والمدراء يتخذون. المشاهدون يعلمون.
- **الحالات:** `draft`, `active`, `executed`, `cancelled`.
- **الاكتمال:** COMPLETE.
- **التبعيات:** الاجتماعات، المستخدمون.
- **يرسل إلى:** notifications.

### 7) التواصل الداخلي (Internal Chat)
- **Routes:** `#conversations`, `#dept_chat/:id`, `#custom_chat/:id`.
- **الجداول:** `conversations`, `messages`, `message_reads`, `conversation_members`.
- **الأدوار:** الجميع.
- **الحالات:** `sent`/`read`/`edited`/`deleted` (soft) على مستوى الرسالة.
- **الاكتمال:** COMPLETE.
- **التبعيات:** المستخدمون.

### 8) تواصل طارئ (Emergency)
- **Route:** `#emergency`.
- **الجداول:** `emergency_alerts`, `emergency_recipients`, `emergency_activity_log`.
- **الأدوار:** admin/managers يرسلون؛ الكل يستقبل.
- **الحالات:** `active`, `resolved`.
- **الاكتمال:** COMPLETE.

### 9) الصيانة (Maintenance)
- **Routes:** `#maintenance`, `#maintenance_new`, `#maintenance_detail/:id`, `#maintenance_suppliers`, `#maintenance_equipment`, `#maintenance_preventive`, `#maintenance_assets`, `#maintenance_reports`.
- **الجداول:** `maintenance_requests`, `maintenance_suppliers`, `maintenance_equipment`, `maintenance_timeline`, `maintenance_preventive_schedule`, `maintenance_repairs`, `maintenance_quotes`, `maintenance_inspections`, `maintenance_receipts`, `maintenance_attachments`, `maintenance_finance_approvals`.
- **الأدوار:** `maintenance_officer`, `branch_manager`, `finance_manager` (لاعتماد ملي).
- **الحالات:** `open`, `assigned`, `in_progress`, `awaiting_parts`, `awaiting_quote`, `completed`, `closed`, `rejected`.
- **الاكتمال:** COMPLETE.
- **التبعيات:** الفروع، المستخدمون.
- **يرسل إلى:** الحسابات (تكلفة صيانة).

### 10) الجودة (Quality Visits)
- **Routes:** `#quality`, `#quality_new`, `#quality_detail/:id`, `#quality_reports`.
- **الجداول:** `quality_visits`, `quality_sections`, `quality_items`, `quality_visit_sections`, `quality_visit_items`, `quality_attachments`.
- **الأدوار:** `quality_manager`, `branch_manager`.
- **الحالات:** زيارة (`draft`, `submitted`, `approved`).
- **الاكتمال:** COMPLETE.
- **التبعيات:** الفروع، المستخدمون.

### 11) ركن الكافيه (Cafe Corner)
- **Route:** `#cafe`.
- **الجداول:** `cafe_items`, `cafe_orders`, `cafe_order_items`, `cafe_order_status_log`.
- **الحالات:** `pending`, `preparing`, `ready`, `delivered`, `cancelled`.
- **الاكتمال:** COMPLETE (مع ربط لدالة `create_journal_for_cafe_order`).
- **يرسل إلى:** `acct_invoices` (source_type='cafe_order').

### 12) الإشعارات (Notifications)
- **Route:** `#notifications`.
- **الجدول:** `notifications`.
- **الاكتمال:** COMPLETE.

### 13) الملف الشخصي (My Profile)
- **Route:** `#my_profile`.
- **الاكتمال:** COMPLETE.

### 14) طلبات الاجتماعات (Meeting Requests)
- **Route:** `#meeting_requests`.
- **الجدول:** `meeting_requests`, `meeting_preparation_reports`.
- **الاكتمال:** COMPLETE.

### 15) رؤية الشركة (Company Vision)
- **Route:** `#vision`.
- **الجداول:** `company_vision`, `department_goals`.
- **الاكتمال:** COMPLETE (أساسي — قابل للتوسع كـ OKR كامل).

### 16) البحث الصوتي والأوامر (Voice Search)
- **Route:** `#search`.
- **الاكتمال:** COMPLETE (يستخدم Web Speech API — `interimResults=true`).

### 17) تحسين الصياغة بالذكاء الاصطناعي (Rewrite)
- **Endpoint:** `POST /api/rewrite` (Gemini).
- **الاكتمال:** COMPLETE. يعتمد على `GEMINI_API_KEY` env var.
- **مخاطر:** لا Bearer token — CORS مفتوح `*`.

---

## القسم الثاني: 17 موديول معاينة (خلف feature flag `test_admin`)

### 18) HR — الموارد البشرية (`window.HR`)
- **Routes (7):** `#hr`, `#hr_employees`, `#hr_employee/:id`, `#hr_organization`, `#hr_attendance`, `#hr_leaves`, `#hr_payroll`.
- **الجداول:** `hr_positions`, `hr_employee_profile`, `hr_attendance`, `hr_leave_types`, `hr_leaves`, `hr_payroll`, `hr_payroll_items`, `hr_departments` (منفصل عن `departments`).
- **الأدوار:** `hr_manager`, `payroll_officer`, `admin`, `company_manager`.
- **الحالات:** attendance (`present/absent/late/leave/holiday/sick/remote`); leaves (`draft/submitted/approved/rejected/cancelled`); payroll (`draft/approved/paid`).
- **الاكتمال:** PARTIALLY_COMPLETE — SQL و DAL كاملان، الشاشات كاملة، لكن اعتمدت على test_admin بلا اعتماد نهائي؛ لا ATS/عقود/تعلم/سلامة موظفين موسّعة (تظهر في `COMING_SOON_MODULES.hr` كخارطة طريق).
- **يستقبل من:** المستخدمون، الأقسام.
- **يرسل إلى:** Accounting (Payroll journals).

### 19) Accounting (`window.ACCT`) — أضخم موديول
- **Routes (25):** `#accounting`, `#acct_chart`, `#acct_cost_centers`, `#acct_periods`, `#acct_journal`, `#acct_journal_entry/:id`, `#acct_vendors`, `#acct_bills`, `#acct_bill/:id`, `#acct_payments`, `#acct_customers`, `#acct_invoices`, `#acct_invoice/:id`, `#acct_receipts`, `#acct_bank_accounts`, `#acct_petty_cash`, `#acct_expense_claims`, `#acct_expense_claim/:id`, `#acct_fixed_assets`, `#acct_fixed_asset/:id`, `#acct_inventory`, `#acct_vat_returns`, `#acct_reports`, `#acct_budgets`, + Payments sub-pages `#acct_pay_partners`, `#acct_pay_partner/:id`, `#acct_pay_statements`, `#acct_pay_statement/:id`, `#acct_pay_clearing`, `#acct_pay_clearing_batch/:id`.
- **الجداول (30+):** `acct_settings`, `acct_chart_of_accounts`, `acct_cost_centers`, `acct_fiscal_years`, `acct_periods`, `acct_journal_entries`, `acct_journal_lines`, `acct_vendors`, `acct_purchase_orders`, `acct_purchase_order_lines`, `acct_bills`, `acct_bill_lines`, `acct_payments`, `acct_customers`, `acct_invoices`, `acct_invoice_lines`, `acct_receipts`, `acct_bank_accounts`, `acct_bank_transactions`, `acct_petty_cash`, `acct_petty_cash_transactions`, `acct_expense_claims`, `acct_expense_claim_lines`, `acct_fixed_assets`, `acct_asset_depreciation_schedule`, `acct_inventory_items`, `acct_inventory_movements`, `acct_vat_returns`, `acct_budgets`, `acct_budget_lines`.
- **الأدوار:** `finance_manager`, `gl_accountant`, `ap_officer`, `ar_officer`.
- **الحالات (متعددة):** Journal (`draft/posted`); Bill (`draft/pending_approval/approved/paid/cancelled`); Payment (`draft/approved/paid/cancelled`); Invoice (`draft/issued/paid/partially_paid/cancelled`); Fixed asset (`active/disposed`); Period (`open/closed/locked`).
- **الاكتمال:** PARTIALLY_COMPLETE — SQL + DAL + شاشات موجودة. Payments 3-stage (partners→statements→clearing) موجود.
- **يستقبل من:** POS (sale journals), Procurement (bills), HR (payroll), Cafe, Franchise (royalty).
- **يرسل إلى:** BI, تقارير مالية.

### 20) Operations (`window.OPS`)
- **Routes (15):** `#operations`, `#ops_shift_templates`, `#ops_shifts`, `#ops_shift_detail/:id`, `#ops_checklists`, `#ops_prep_plans`, `#ops_prep_plan_detail/:id`, `#ops_orders`, `#ops_order_detail/:id`, `#ops_branch_inventory`, `#ops_stock_transfers`, `#ops_waste`, `#ops_issues`, `#ops_issue_detail/:id`, `#ops_settings`.
- **الجداول:** `ops_settings`, `ops_shift_templates`, `ops_shifts`, `ops_shift_handovers`, `ops_station_assignments`, `ops_daily_checklists`, `ops_checklist_items`, `ops_prep_plans`, `ops_prep_plan_items`, `ops_orders`, `ops_order_items`, `ops_branch_inventory_levels`, `ops_stock_transfers`, `ops_stock_transfer_items`, `ops_waste_records`, `ops_issues`, `ops_issue_escalations`.
- **الحالات:** shift (`draft/confirmed/completed`); order (`draft/confirmed/cancelled/…`).
- **الاكتمال:** PARTIALLY_COMPLETE — يحتاج تفعيل real-time و الربط مع POS.
- **يرسل إلى:** Accounting (ops order → journal), Inventory movements.

### 21) Payments (`window.PAY`) — تحت gate الحسابات
- **Routes:** ضمن acct_pay_* (مذكورة في ACCT).
- **الجداول:** `pay_partners`, `pay_partner_contracts`, `pay_statements`, `pay_statement_lines`, `pay_clearing_batches`, `pay_clearing_items`, `pay_payouts`.
- **الحالات:** batch (`draft/approved/paid`).
- **الاكتمال:** PARTIALLY_COMPLETE.
- **ملاحظة:** لا يظهر كموديول منفصل في `PREVIEW_MODULES` (16 مفتاح vs 17 موديول موثقة — الفرق هنا).

### 22) AI Assistant (`window.AIA`)
- **Routes:** `#ai_assistant`, `#ai_settings`.
- **الجداول:** `ai_settings`, `ai_sessions`, `ai_session_messages`, `ai_audit_log`.
- **الأدوات (7):** get_overdue_tasks, get_branches_status, get_expiring_documents, get_financial_summary, get_recent_decisions, get_open_maintenance_requests, get_partners_settlements.
- **Endpoint:** `POST /api/agent` (Gemini function-calling).
- **الاكتمال:** PARTIALLY_COMPLETE — قراءة فقط. `extraInstructions` يقبل نصًا بلا Auth (مخاطرة).
- **feature flag key:** `ai_agents`.

### 23) POS (`window.POS`)
- **Routes:** `#pos`, `#pos_terminals`, `#pos_sessions`, `#pos_session/:id`, `#pos_cashier/:terminal`, `#pos_transaction/:id`.
- **الجداول:** `pos_terminals`, `pos_sessions`, `pos_transactions`, `pos_transaction_items`, `pos_payment_splits`.
- **الحالات:** transaction (`draft/completed/refunded/void`); session (`open/closed`).
- **الاكتمال:** PARTIALLY_COMPLETE — دالة ذرية `pos_complete_transaction` تنشئ قيد. لا offline.
- **يستقبل من:** Menu (snapshot سعر), CRM (customer_id).
- **يرسل إلى:** Accounting (draft journal source `pos_sale`), CRM loyalty.

### 24) Menu (`window.MENU`)
- **Routes:** `#menu`, `#menu_categories`, `#menu_items`, `#menu_item/:id`, `#menu_settings`.
- **الجداول:** `menu_settings`, `menu_categories`, `menu_items`, `menu_item_recipes`, `menu_channel_prices`.
- **الحالات:** item `is_available` / `is_active`.
- **الاكتمال:** PARTIALLY_COMPLETE.
- **يستقبل من:** `acct_inventory_items` (BOM).
- **يرسل إلى:** POS (snapshot), BI (top items).

### 25) CRM & Loyalty (`window.CRM`)
- **Routes:** `#crm`, `#crm_customers`, `#crm_customer/:id`, `#crm_complaints`, `#crm_complaint/:id`.
- **الجداول:** `crm_customers`, `crm_customer_addresses`, `loyalty_accounts`, `loyalty_transactions` (**ثابت**), `crm_complaints`.
- **الحالات:** complaint (severity + SLA).
- **الاكتمال:** PARTIALLY_COMPLETE.
- **يرسل إلى:** POS (customer), Delivery.

### 26) HACCP (`window.HACCP`)
- **Routes:** `#haccp`, `#haccp_equipment`, `#haccp_temperature`, `#haccp_batches`, `#haccp_certs`, `#haccp_incidents`, `#haccp_incident/:id`, `#haccp_settings`.
- **الجداول:** `haccp_settings`, `haccp_equipment`, `haccp_temperature_logs`, `haccp_food_batches`, `haccp_health_certificates`, `haccp_incidents`.
- **الاكتمال:** PARTIALLY_COMPLETE.

### 27) Procurement (`window.PROC`)
- **Routes:** `#procurement`, `#proc_requisitions`, `#proc_requisition/:id`, `#proc_orders`, `#proc_order/:id`, `#proc_receipts`, `#proc_receipt/:id`.
- **الجداول:** `proc_requisitions`, `proc_requisition_items`, `proc_purchase_orders`, `proc_purchase_order_items`, `proc_goods_receipts`, `proc_goods_receipt_items`.
- **دالة ذرية:** `proc_receive_goods` → مخزون + AP bill.
- **الاكتمال:** PARTIALLY_COMPLETE.
- **يرسل إلى:** Accounting (`acct_bills`), Inventory movements.

### 28) Performance (`window.PERF`)
- **Routes:** `#performance`, `#perf_kpis`, `#perf_scorecards`, `#perf_scorecard/:id`, `#perf_reviews`, `#perf_review/:id`, `#perf_goals`.
- **الجداول:** `perf_kpi_definitions`, `perf_scorecards`, `perf_scorecard_entries`, `perf_reviews`, `perf_goals`.
- **الاكتمال:** PARTIALLY_COMPLETE.

### 29) Delivery (`window.DLV`)
- **Routes:** `#delivery`, `#dlv_zones`, `#dlv_riders`, `#dlv_orders`, `#dlv_order/:id`, `#dlv_settings`.
- **الجداول:** `delivery_settings`, `delivery_zones`, `delivery_riders`, `delivery_orders`, `delivery_tracking`.
- **9 حالات لطلب التوصيل** — RPC `delivery_update_status`, `delivery_assign_rider`, `delivery_mark_delivered`.
- **الاكتمال:** PARTIALLY_COMPLETE — لا تطبيق سائق مستقل.
- **يستقبل من:** POS / CRM.

### 30) Documents (`window.DOC`)
- **Routes:** `#documents`, `#doc_list`, `#doc_detail/:id`, `#doc_categories`, `#doc_expiring`.
- **الجداول:** `doc_categories`, `doc_documents`, `doc_access_log`.
- **الاكتمال:** PARTIALLY_COMPLETE. `doc_expire_overdue` يحتاج cron scheduler.

### 31) Call Center (`window.CC`)
- **Routes:** `#call_center`, `#cc_agents`, `#cc_calls`, `#cc_call/:id`, `#cc_scripts`, `#cc_followups`.
- **الجداول:** `cc_agents`, `cc_calls`, `cc_dispositions`, `cc_scripts`.
- **الاكتمال:** PARTIALLY_COMPLETE — لا PBX integration.

### 32) BI (`window.BI`)
- **Routes:** `#bi`, `#bi_reports`, `#bi_report/:code`.
- **الجداول:** `bi_report_definitions`, `bi_snapshots`, `bi_saved_views`.
- **7 تقارير مبذورة** — 6 دوال RPC + 1 (CASH_FLOW) بلا `rpc_name` = **PLACEHOLDER**.
- **الاكتمال:** PARTIALLY_COMPLETE.

### 33) Integrations (`window.INT`)
- **Routes:** `#integrations`, `#int_marketplace`, `#int_connections`, `#int_connection/:id`, `#int_events`.
- **الجداول:** `int_providers`, `int_connections`, `int_webhook_endpoints`, `int_events`.
- **12 مزوّد مبذور.** DAL و السجل يعمل. **workers الفعلية غير موجودة** → BACKEND_ONLY لكل provider.
- **الاكتمال:** UI_ONLY + مخزنة config (لا اتصال حقيقي).

### 34) Franchise (`window.FR`)
- **Routes:** `#franchise`, `#fr_partners`, `#fr_partner/:id`, `#fr_agreements`, `#fr_agreement/:id`, `#fr_reports`, `#fr_royalties`.
- **الجداول:** `franchise_partners`, `franchise_agreements`, `franchise_branches`, `franchise_sales_reports`, `franchise_royalty_invoices`.
- **دوال ذرية:** `franchise_compute_royalty`, `franchise_issue_royalty`.
- **الاكتمال:** PARTIALLY_COMPLETE — ربط AR invoice مطلوب قرار المالك.
- **بوابة فرنشايزي مستقلة (login منفصل + رفع تقارير):** غير موجودة → UI_ONLY لهذا الجزء.

---

## ملخص الأرقام
| البند | العدد |
|---|---:|
| موديولات إنتاج | 17 |
| موديولات معاينة | 17 |
| مفاتيح `PREVIEW_MODULES` | 16 (PAY تحت accounting) |
| إجمالي routes مسجلة | 160 (سطور 16967–17126) |
| جداول SQL (schemas الجديدة) | 121 |
| جداول مستدعاة من الفرونت (`sb.from`) | 175 unique |
| RPC/دوال SQL | 90+ |
| مزوّدو Integrations مبذورون | 12 |
| تقارير BI مبذورة | 7 (6 لها دالة + 1 placeholder) |
