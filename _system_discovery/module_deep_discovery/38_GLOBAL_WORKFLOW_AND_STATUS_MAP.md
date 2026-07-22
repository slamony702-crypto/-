# 38 — خريطة سير العمل والحالات (Global Workflow & Status Map)

> **المرجع:** `_system_discovery/WORKFLOW_STATUS_AUDIT.md`.

## أ) خريطة الحالات لكل موديول

### 1) POS
- `pos_sessions.status`: `open → closed`.
- `pos_transactions.status`: `draft → completed → refunded / void`.
- `pos_transactions.type`: `sale / refund / void`.

### 2) Accounting
- `acct_journal_entries.status`: `draft → posted` (posted immutable).
- `acct_bills.status`: `draft → pending_approval → approved → paid / cancelled`.
- `acct_payments.status`: `draft → approved → paid / cancelled`.
- `acct_invoices.status`: `draft → issued → paid / partially_paid / cancelled`.
- `acct_invoices.zatca_status`: `phase1_qr → phase2_signed → reported → cleared`.
- `acct_periods.status`: `open → closed → locked`.
- `acct_fixed_assets.status`: `active → disposed`.
- `acct_purchase_orders.status`: `draft → approved → received → closed / cancelled`.
- `acct_expense_claims.status`: `draft → submitted → approved / rejected → paid`.

### 3) HR
- `hr_attendance.status`: `present / absent / late / leave / holiday / sick / remote` (لا انتقال).
- `hr_leaves.status`: `draft → submitted → approved / rejected → cancelled`.
- `hr_payroll.status`: `draft → approved → paid`.

### 4) Meetings
- `meetings.status`: `scheduled → in_progress → completed → in_follow_up → closed` (+ `cancelled / postponed`).
- `action_items.status`: `open → in_progress → completed / cancelled` (+ `overdue` محسوبة).
- `decisions.status`: `draft → active → executed / cancelled`.
- `department_tasks.status`: `new → in_progress → review → completed / cancelled`.

### 5) Cafe
- `cafe_orders.status`: `pending → preparing → ready → delivered / cancelled`.

### 6) Maintenance
- `maintenance_requests.status`: `open → assigned → in_progress → awaiting_parts / awaiting_quote → completed → closed / rejected`.

### 7) Ops
- `ops_shifts.status`: `draft → confirmed → completed`.
- `ops_orders.status`: `draft → confirmed → cancelled`.

### 8) Menu
- `menu_items.is_available` / `is_active` (لا CHECK).

### 9) CRM
- `crm_complaints.status`: `open / in_progress / resolved / escalated`.
- `loyalty_transactions`: ثابت (بلا status).

### 10) Delivery — 9 حالات
- `new → assigned → preparing → ready_for_pickup → picked_up → on_the_way → delivered` (+ `cancelled / returned / failed`).

### 11) HACCP
- `haccp_incidents.status`: `open → investigating → resolved → closed`.
- `haccp_food_batches.status`: `created → in_use → consumed / disposed`.
- `haccp_temperature_logs.is_within_range`: BOOLEAN.

### 12) Procurement
- `proc_requisitions.status`: `draft → submitted → approved → converted_to_po / rejected / cancelled`.
- `proc_purchase_orders.status`: `draft → sent_to_vendor → confirmed → partially_received → received → closed / cancelled`.
- `proc_goods_receipts.status`: `draft → received`.

### 13) Performance
- `perf_scorecards.status`: `draft → submitted → approved → published`.
- `perf_reviews.status`: `draft → submitted_by_reviewer → acknowledged_by_employee → completed`.
- `perf_goals.status`: `draft → active → completed / cancelled`.

### 14) Documents
- `doc_documents.status`: `active → expired → archived`.

### 15) Call Center
- `cc_calls.status`: `queued → in_progress → completed / abandoned`.
- `cc_agents.availability_status`: `available → on_call → busy / away / offline`.

### 16) BI
- `bi_snapshots.snapshot_type`: `daily / weekly / monthly / ad_hoc` (تصنيف).

### 17) Integrations
- `int_connections.status`: `active → paused → error`.
- `int_events.status`: `pending → sent / failed → retrying`.

### 18) Franchise
- `franchise_partners.status`: `prospect → active → paused / on_hold → terminated`.
- `franchise_agreements.status`: `draft → active → expired / terminated`.
- `franchise_sales_reports.status`: `submitted → verified → royalty_computed`.
- `franchise_royalty_invoices.status`: `draft → issued → paid / cancelled`.

### 19) Payments
- `pay_statements.status`: `draft → approved → settled`.
- `pay_clearing_batches.status`: `draft → approved → paid`.
- `pay_payouts.status`: `pending → sent → confirmed`.

## ب) عمليات بلا نهاية واضحة (Open-Ended)

راجع `WORKFLOW_STATUS_AUDIT §Open-ended`:
1. `conversations / messages` — بلا إغلاق.
2. `decisions.executed` — بلا آلية دليل تنفيذ إلزامي.
3. `meetings.closed` — يعتمد على إغلاق كل الـaction_items بلا فحص آلي.
4. `franchise_partners on_hold` — بلا آلية عودة تلقائية.
5. `int_connections.error` — يظل حتى تدخل يدوي.
6. `ai_sessions` — بلا إغلاق.
7. `emergency_alerts` — resolved بلا SLA زمني.

## ج) من يملك انتقالات خاصة

- **Post journal:** `finance_manager / gl_accountant`.
- **Approve bill:** `finance_manager / ap_officer`.
- **Complete POS transaction:** كاشير + `is_ops_manager`.
- **Receive goods:** `is_procurement_manager` + branch access.
- **Issue royalty:** `is_franchise_manager`.
- **Assign rider:** `is_delivery_manager`.
- **Post journal, close_period:** `finance_manager` (بلا شاشة).

## د) الأنماط المتكررة

- **`draft → submitted → approved → paid/closed`** (المالية والمشتريات).
- **`open → in_progress → completed / cancelled`** (المهام).
- **Complex n-stage flows:** Delivery (9), Maintenance (8), Franchise (متعدد الكيانات).

## هـ) توصيات

1. **إلزام دليل تنفيذ** قبل `decisions.executed`.
2. **آلية auto-close للاجتماعات** عند إنجاز كل مخرجاتها.
3. **SLA زمني** لـ emergency_alerts و integrations.error.
4. **دوال state-machine** موحدة (بدل if/else في DAL).
5. **audit trail** لكل transition (خاصة المالية).
