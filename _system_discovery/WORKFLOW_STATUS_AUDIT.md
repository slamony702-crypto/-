# WORKFLOW_STATUS_AUDIT — الحالات والانتقالات

> استُخرجت من `CHECK (status IN ...)` في SQL + منطق الانتقال في `window.XX` DAL + دوال RPC.

## 1) POS

**`pos_sessions.status`:** `open` → `closed`
- من يفتح: الكاشير (`employee` + branch match).
- من يغلق: الكاشير عند نهاية الوردية.

**`pos_transactions.status`:** `draft` → `completed` → `refunded` / `void`
- `draft`: عند البدء.
- `completed`: عند نجاح `pos_complete_transaction`.
- `refunded/void`: يتطلب transaction جديد بـ type مختلف.

## 2) Accounting

**`acct_journal_entries.status`:** `draft` → `posted`
- `posted` غير قابل للتعديل (validate trigger).

**`acct_bills.status`:** `draft` → `pending_approval` → `approved` → `paid` / `cancelled`
- Approval يحتاج `is_finance_manager` أو `is_ap_officer` (validate trigger).

**`acct_payments.status`:** `draft` → `approved` → `paid` / `cancelled`

**`acct_invoices.status`:** `draft` → `issued` → `paid` / `partially_paid` / `cancelled`

**`acct_invoices.zatca_status`:** `phase1_qr` → `phase2_signed` → `reported` → `cleared`
- Phase 2 غير مفعّل (mock).

**`acct_periods.status`:** `open` → `closed` → `locked`
- Closed: لا قيود جديدة.
- Locked: يحتاج إعادة فتح بدور `finance_manager`.

**`acct_fixed_assets.status`:** `active` → `disposed`

**`acct_purchase_orders.status`:** `draft` → `approved` → `received` → `closed` / `cancelled`

**`acct_expense_claims.status`:** `draft` → `submitted` → `approved` / `rejected` → `paid`

## 3) HR

**`hr_attendance.status`:** `present` / `absent` / `late` / `leave` / `holiday` / `sick` / `remote` (لا انتقال — سجل يومي).

**`hr_leaves.status`:** `draft` → `submitted` → `approved` / `rejected` → `cancelled`
- Approval: `hr_manager` أو مدير القسم المباشر (`is_manager_of`).

**`hr_payroll.status`:** `draft` → `approved` → `paid`

## 4) Meetings

**`meetings.status`:** `scheduled` → `in_progress` → `completed` → `in_follow_up` → `closed`
- `cancelled` / `postponed` من أي حالة قبل `completed`.

**`action_items.status`:** `open` → `in_progress` → `completed` / `cancelled`
- `overdue` محسوبة (لا مخزنة).

**`decisions.status`:** `draft` → `active` → `executed` / `cancelled`
- Executed: يحتاج دليل تنفيذ.

**`department_tasks.status`:** `new` → `in_progress` → `review` → `completed` / `cancelled`

## 5) Cafe

**`cafe_orders.status`:** `pending` → `preparing` → `ready` → `delivered` / `cancelled`

## 6) Maintenance

**`maintenance_requests.status`:** `open` → `assigned` → `in_progress` → `awaiting_parts` / `awaiting_quote` → `completed` → `closed` / `rejected`
- Approval مالي عبر `maintenance_finance_approvals`.

## 7) Ops

**`ops_shifts.status`:** `draft` → `confirmed` → `completed`
- `handover` عبر `ops_shift_handovers` (سجل ثابت).

**`ops_orders.status`:** `draft` → `confirmed` → `cancelled`

## 8) Menu
`menu_items.is_available` / `is_active` (بدل status). لا CHECK.

## 9) CRM

**`crm_complaints.status`:** open/in_progress/resolved/escalated.
**`loyalty_transactions`:** ثابت (INSERT فقط، بلا status).

## 10) Delivery — 9 حالات
**`delivery_orders.status`:**
`new` → `assigned` → `preparing` → `ready_for_pickup` → `picked_up` → `on_the_way` → `delivered`
+ `cancelled` / `returned` / `failed` كأمور جانبية.

**من يملك انتقالًا:**
- `assigned`: `is_delivery_manager` عبر `delivery_assign_rider`.
- `preparing/ready_for_pickup`: العمليات.
- `picked_up/on_the_way/delivered`: السائق نفسه عبر `delivery_update_status`.

## 11) HACCP

**`haccp_incidents.status`:** open → investigating → resolved → closed.
**`haccp_food_batches.status`:** created → in_use → consumed / disposed.
**`haccp_temperature_logs.is_within_range`:** BOOLEAN (لا status).

## 12) Procurement

**`proc_requisitions.status`:** `draft` → `submitted` → `approved` → `converted_to_po` / `rejected` / `cancelled`
**`proc_purchase_orders.status`:** `draft` → `sent_to_vendor` → `confirmed` → `partially_received` → `received` → `closed` / `cancelled`
**`proc_goods_receipts.status`:** `draft` → `received` (عند `proc_receive_goods`).

## 13) Performance

**`perf_scorecards.status`:** `draft` → `submitted` → `approved` → `published`
**`perf_reviews.status`:** `draft` → `submitted_by_reviewer` → `acknowledged_by_employee` → `completed`
**`perf_goals.status`:** `draft` → `active` → `completed` / `cancelled`

## 14) Documents

**`doc_documents.status`:** `active` → `expired` (عبر `doc_expire_overdue`) → `archived`.

## 15) Call Center

**`cc_calls.status`:** `queued` → `in_progress` → `completed` / `abandoned`
- `cc_start_call` / `cc_end_call` تديران الانتقالات.

**`cc_agents.availability_status`:** `available` → `on_call` → `busy` / `away` / `offline`

## 16) BI

**`bi_snapshots.snapshot_type`:** `daily` / `weekly` / `monthly` / `ad_hoc` (تصنيف، لا انتقال).

## 17) Integrations

**`int_connections.status`:** `active` → `paused` → `error`
- Error يُضبط تلقائيًا عند فشل `int_complete_event`.

**`int_events.status`:** `pending` → `sent` / `failed` → `retrying` → `sent` / `failed`

## 18) Franchise

**`franchise_partners.status`:** `prospect` → `active` → `paused` / `on_hold` → `terminated`
**`franchise_agreements.status`:** `draft` → `active` → `expired` / `terminated`
**`franchise_sales_reports.status`:** `submitted` → `verified` → `royalty_computed`
**`franchise_royalty_invoices.status`:** `draft` → `issued` → `paid` / `cancelled`

## 19) Payments

**`pay_statements.status`:** `draft` → `approved` → `settled`
**`pay_clearing_batches.status`:** `draft` → `approved` → `paid`
**`pay_payouts.status`:** `pending` → `sent` → `confirmed`

## عمليات بلا نهاية واضحة (Open-ended)
1. **`conversations` / `messages`:** لا حالة إغلاق — تبقى مفتوحة للأبد إلا بحذف الحساب.
2. **`decisions.executed`:** لا آلية تحقق دليل تنفيذ إلزامي (يمكن التحديث يدويًا).
3. **`meetings.closed`:** يعتمد على إغلاق كل الـ`action_items` لكن لا فحص آلي.
4. **`franchise_partners`:** `on_hold` بلا آلية عودة تلقائية.
5. **`int_connections.error`:** يبقى `error` حتى يعالج المستخدم يدويًا.
6. **`ai_sessions`:** بلا حالة إغلاق.
7. **`emergency_alerts`:** حالة `resolved` بلا زمن SLA مفروض.

## من يملك انتقالًا خاصًا
- **Post journal:** `finance_manager` / `gl_accountant` عبر `acct_validate_journal_posting`.
- **Approve bill:** `finance_manager` / `ap_officer` عبر `acct_validate_bill_approval`.
- **Complete POS:** الكاشير + دور `is_ops_manager`.
- **Receive goods:** `is_procurement_manager` + branch access.
- **Issue royalty:** `is_franchise_manager`.
- **Assign rider:** `is_delivery_manager`.
