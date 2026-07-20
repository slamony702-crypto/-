# DATABASE_OVERVIEW — الجداول والدوال والسياسات

> استُخرجت من الـ17 ملف SQL + `sb.from()` في الفرونت.
> ⚠️ الجداول الأصلية (meetings, action_items, decisions, department_tasks, quality_*, maintenance_*, cafe_*, conversations, ...) موجودة في Supabase مباشرة **بدون ملف SQL versioned** — مصدر مخاطرة migrations.

## 1) الجداول (تصنيف حسب الملف)

### أساس (بلا SQL versioned)
`users`, `role_permissions`, `user_permission_overrides`, `user_activity_log`, `notifications`, `signup_requests`, `branches`, `departments`, `branch_assets`.

### اجتماعات ومهام (بلا SQL versioned)
`meetings`, `meeting_attendees`, `meeting_agenda`, `meeting_tasks`, `meeting_requests`, `meeting_preparation_reports`, `action_items`, `decisions`, `decision_sub_responsibles`, `decision_viewers`, `decision_acknowledgments`, `decision_activity_log`, `department_tasks`, `task_projects`, `task_project_members`, `task_project_updates`.

### تواصل + طوارئ (بلا SQL versioned)
`conversations`, `conversation_members`, `messages`, `message_reads`, `emergency_alerts`, `emergency_recipients`, `emergency_activity_log`.

### صيانة (بلا SQL versioned)
`maintenance_requests`, `maintenance_suppliers`, `maintenance_equipment`, `maintenance_timeline`, `maintenance_preventive_schedule`, `maintenance_repairs`, `maintenance_quotes`, `maintenance_inspections`, `maintenance_receipts`, `maintenance_attachments`, `maintenance_finance_approvals`.

### جودة (بلا SQL versioned)
`quality_visits`, `quality_sections`, `quality_items`, `quality_visit_sections`, `quality_visit_items`, `quality_attachments`.

### كافيه + رؤية (بلا SQL versioned)
`cafe_items`, `cafe_orders`, `cafe_order_items`, `cafe_order_status_log`, `company_vision`, `department_goals`.

### HR — `hr-schema.sql`
`hr_positions`, `hr_employee_profile`, `hr_attendance`, `hr_leave_types`, `hr_leaves`, `hr_payroll`, `hr_payroll_items`.

### Accounting — `acct-schema.sql` + 2b/2c/2d/2e/2f
`acct_settings`, `acct_chart_of_accounts`, `acct_cost_centers`, `acct_fiscal_years`, `acct_periods`, `acct_journal_entries`, `acct_journal_lines`, `acct_vendors`, `acct_purchase_orders`, `acct_purchase_order_lines`, `acct_bills`, `acct_bill_lines`, `acct_payments`, `acct_customers`, `acct_invoices`, `acct_invoice_lines`, `acct_receipts`, `acct_bank_accounts`, `acct_bank_transactions`, `acct_petty_cash`, `acct_petty_cash_transactions`, `acct_expense_claims`, `acct_expense_claim_lines`, `acct_fixed_assets`, `acct_asset_depreciation_schedule`, `acct_inventory_items`, `acct_inventory_movements`, `acct_vat_returns`, `acct_budgets`, `acct_budget_lines`.

### Ops — `ops-schema-3a/3b/3c.sql`
`ops_settings`, `ops_shift_templates`, `ops_shifts`, `ops_shift_handovers`, `ops_station_assignments`, `ops_daily_checklists`, `ops_checklist_items`, `ops_prep_plans`, `ops_prep_plan_items`, `ops_orders`, `ops_order_items`, `ops_branch_inventory_levels`, `ops_stock_transfers`, `ops_stock_transfer_items`, `ops_waste_records`, `ops_issues`, `ops_issue_escalations`.

### AI — `ai-schema-1-assistant.sql`
`ai_settings`, `ai_sessions`, `ai_session_messages`, `ai_audit_log`.

### Payments — `pay-schema-p1/p2/p3.sql`
`pay_partners`, `pay_partner_contracts`, `pay_statements`, `pay_statement_lines`, `pay_clearing_batches`, `pay_clearing_items`, `pay_payouts`.

### Menu — `menu-schema-1.sql`
`menu_settings`, `menu_categories`, `menu_items`, `menu_item_recipes`, `menu_channel_prices`.

### CRM — `crm-schema-1.sql`
`crm_customers`, `crm_customer_addresses`, `loyalty_accounts`, `loyalty_transactions`, `crm_complaints`.

### POS — `pos-schema-1a.sql`
`pos_terminals`, `pos_sessions`, `pos_transactions`, `pos_transaction_items`, `pos_payment_splits`.

### HACCP — `haccp-schema-1.sql`
`haccp_settings`, `haccp_equipment`, `haccp_temperature_logs`, `haccp_food_batches`, `haccp_health_certificates`, `haccp_incidents`.

### Procurement — `proc-schema-1.sql`
`proc_requisitions`, `proc_requisition_items`, `proc_purchase_orders`, `proc_purchase_order_items`, `proc_goods_receipts`, `proc_goods_receipt_items`.

### Performance — `perf-schema-1.sql`
`perf_kpi_definitions`, `perf_scorecards`, `perf_scorecard_entries`, `perf_reviews`, `perf_goals`.

### Delivery — `dlv-schema-1.sql`
`delivery_settings`, `delivery_zones`, `delivery_riders`, `delivery_orders`, `delivery_tracking`.

### Documents — `doc-schema-1.sql`
`doc_categories`, `doc_documents`, `doc_access_log`.

### Call Center — `cc-schema-1.sql`
`cc_agents`, `cc_dispositions`, `cc_calls`, `cc_scripts`.

### BI — `bi-schema-1.sql`
`bi_report_definitions`, `bi_snapshots`, `bi_saved_views`.

### Integrations — `int-schema-1.sql`
`int_providers`, `int_connections`, `int_webhook_endpoints`, `int_events`.

### Franchise — `fr-schema-1.sql`
`franchise_partners`, `franchise_agreements`, `franchise_branches`, `franchise_sales_reports`, `franchise_royalty_invoices`.

**الإجمالي:** ≈ 175 جدول (100+ في SQL versioned + 75 أساسية غير موثقة).

## 2) الدوال (Functions) الرئيسية

### حراس الأدوار (`is_*`)
`is_finance_manager`, `is_gl_accountant`, `is_ap_officer`, `is_ar_officer`, `is_accounting_role`, `is_hr_admin`, `is_payroll_authorized`, `is_manager_of`, `is_menu_manager`, `is_crm_manager`, `is_haccp_manager`, `is_procurement_manager`, `is_perf_manager`, `is_delivery_manager`, `is_doc_manager`, `is_cc_manager`, `is_bi_manager`, `is_integrations_manager`, `is_franchise_manager`, `is_ops_manager`.
- كلها SECURITY DEFINER + `SET search_path = public` (v120 fix).
- `current_app_user_id()`, `current_app_role()` — تُقرأ من app context.

### دوال الترقيم (Numbering)
`acct_assign_vendor_code`, `acct_assign_customer_code`, `acct_assign_asset_no`, `acct_assign_sku`, `acct_assign_petty_cash_code`, `menu_assign_sku`, `crm_assign_customer_code`, `crm_assign_complaint_no`, `haccp_assign_equipment_code`, `haccp_assign_batch_no`, `haccp_assign_incident_no`, `proc_assign_requisition_no/po_no/grn_no`, `pos_assign_terminal_code/session_no/transaction_no`, `perf_assign_scorecard_no/review_no/goal_no`, `dlv_assign_rider_code/order_no`, `doc_assign_document_no`, `cc_assign_call_no`, `int_assign_event_no`, `franchise_assign_partner_no/agr_no/sr_no/roy_no`, `pay_assign_partner_code/batch_no`, `ops_assign_order_number`.

### دوال محاسبية آلية (Auto Journal)
`create_journal_for_bill`, `create_journal_for_payment`, `create_journal_for_invoice`, `create_journal_for_receipt`, `create_journal_for_payroll`, `create_journal_for_cafe_order`, `create_journal_for_bank_transaction`, `create_journal_for_expense_claim`, `create_journal_for_ops_order`, `create_journal_for_inventory_movement`.

### دوال أعمال ذرية
- `pos_complete_transaction`
- `proc_receive_goods`
- `delivery_assign_rider`, `delivery_update_status`, `delivery_mark_delivered`
- `franchise_compute_royalty`, `franchise_issue_royalty`
- `cc_start_call`, `cc_end_call`
- `int_log_event`, `int_complete_event`
- `menu_compute_item_cost`
- `perf_compute_scorecard_score`
- `loyalty_apply_transaction` (trigger)
- `haccp_compute_within_range` (trigger)
- `doc_log_access`, `doc_expire_overdue`

### دوال مالية Reporting
`compute_vat_totals`, `get_trial_balance`, `get_income_statement`, `get_balance_sheet`, `close_fiscal_year`, `get_budget_vs_actual`, `run_monthly_depreciation`, `acct_generate_depreciation_schedule`.

### دوال BI
`bi_daily_summary`, `bi_branch_ranking`, `bi_top_menu_items`, `bi_customer_segments`, `bi_operations_health`, `bi_delivery_kpis`, `bi_save_snapshot`, `dashboard_summary` (perf-fix-1).

### دوال Triggers
`set_updated_at`, `acct_validate_journal_posting`, `acct_validate_line_edit`, `acct_validate_bill_approval`, `acct_validate_payment_approval`, `acct_validate_expense_claim_approval`, `acct_apply_inventory_movement`, `acct_setup_bank_account`, `acct_fa_auto_schedule`, `acct_generate_periods_for_fy`, `ops_apply_stock_transfer`, `ops_apply_waste_to_branch_inventory`, `can_access_branch_ops`.

## 3) Enums (CHECK constraints أهم القيم)
- `pos_transactions.status`: `draft/completed/refunded/void`
- `pos_transactions.type`: `sale/refund/void`
- `acct_bills.status`: `draft/pending_approval/approved/paid/cancelled`
- `acct_payments.status`: `draft/approved/paid/cancelled`
- `acct_invoices.status`: `draft/issued/paid/partially_paid/cancelled`
- `acct_invoices.zatca_status`: `phase1_qr/phase2_signed/reported/cleared`
- `acct_invoices.source_type`: `manual/cafe_order`
- `acct_journal_entries.status`: `draft/posted`
- `acct_periods.status`: `open/closed/locked`
- `acct_fixed_assets.status`: `active/disposed`
- `hr_attendance.status`: `present/absent/late/leave/holiday/sick/remote`
- `hr_leaves.status`: `draft/submitted/approved/rejected/cancelled`
- `hr_payroll.status`: `draft/approved/paid`
- `delivery_orders.status`: 9 قيم من `new` إلى `delivered/cancelled/returned/failed`.
- `franchise_partners.status`: `prospect/active/paused/terminated/on_hold`
- `int_events.status`: `pending/sent/failed/retrying`
- `int_connections.status`: `active/paused/error`
- `bi_snapshots.snapshot_type`: `daily/weekly/monthly/ad_hoc`
- `cc_calls.disposition_id` → `cc_dispositions` (11 نتيجة مبذورة).
- `ops_shifts.status`, `ops_orders.status`, ...

## 4) Triggers (نماذج)
- 100+ trigger من نوع `updated_at` (`BEFORE UPDATE`).
- Auto-numbering triggers (`BEFORE INSERT`) لكل موديول جديد.
- `haccp_compute_within_range` — يحدّث `is_within_range` تلقائيًا.
- `loyalty_apply_transaction` — يحدّث `points_balance` + `lifetime_points`.
- `acct_apply_inventory_movement` — يحدّث `on_hand` بعد INSERT.
- `acct_validate_*` — يمنع التعديل بعد approval.

## 5) Indexes (نماذج مهمة)
- `pos_txn_completed_date_idx` على `pos_transactions(completed_at) WHERE status='completed'` (v120 fix للأداء).
- Partial unique indexes على `crm_customer_addresses(customer_id) WHERE is_default = TRUE`.
- Partial unique indexes على `perf_scorecards` (branch/employee).
- GIN index على `doc_documents.tags`.

## 6) RLS Policies (ملخص)
- كل جدول تقريبًا `ENABLE ROW LEVEL SECURITY`.
- سياسات نمطية: `_sel` (SELECT) للجميع؛ `_wr` (ALL) لدور مدير + `admin`/`company_manager`.
- لكل schema Wave 1-4 دالة `is_XX_manager` تُستدعى في السياسة.
- الأدوار الحساسة (مالية، HR) لها سياسات مخصصة أكثر (finance_manager فقط للفواتير الإدارية، إلخ).

## 7) الجداول غير المستخدمة في الفرونت
لم يُرصد أي جدول عمومي بلا `sb.from`. لكن:
- الجداول الأصلية للـ`quality_sections/items` (كتالوج) — تُستخدم قراءة فقط في form.
- `int_webhook_endpoints` — يظهر في `int_connection_detail` لكن السجل شبه فارغ.
- `acct_asset_depreciation_schedule` — تُقرأ لعرض جدول، لا شاشة قائمة مستقلة.

## 8) نقاط الاهتمام
- **جداول العمليات الجوهرية بلا SQL versioned** = مخاطر إدارة تغيير على الإنتاج.
- **`users.password_plain` عمود موجود** — دَين قديم.
- **`int_webhook_endpoints.secret_token`** نص صريح.
- **`acct_customers` vs `crm_customers`** — جدولان منفصلان لبيانات العميل.
