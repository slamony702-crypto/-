# BUSINESS_WORKFLOW_MAP — دورات العمل الحقيقية

> استُخرجت من CHECK constraints في SQL + دوال RPC (`pos_complete_transaction`, `proc_receive_goods`, `delivery_*`, `franchise_*`, `int_*`, `cc_*`) + طبقات DAL في `index.html.html`.
> ⚠️ ما هو موثق هنا فقط ما يظهر في الكود — أي انتقال غير مذكور غير مطبَّق.

---

## 1) POS Transaction Lifecycle
**الجداول:** `pos_sessions` → `pos_transactions` → `pos_transaction_items` + `pos_payment_splits`.

1. `open_session` (المستخدم يفتح جلسة كاشير برصيد ابتدائي نقدي).
2. `pos_transactions.status = draft` (فتح فاتورة، إضافة أصناف).
3. إضافة `pos_payment_splits` (نقد + بطاقة + ولاء ... حتى تصل للمجموع).
4. QR ZATCA يُبنى في المتصفح قبل الإرسال.
5. **دالة ذرية `pos_complete_transaction(p_txn_id)`:**
   - تتحقق أن `type = 'sale'` (v120 fix).
   - تتحقق أن مجموع splits ≥ total.
   - تنشئ `acct_journal_entries` بحالة `draft`, `source_type = 'pos_sale'`.
   - تحدّث `crm_customers.loyalty` (عبر triggers CRM).
   - `status → completed` + `completed_at = now()`.
6. Refund / void → `type <> 'sale'` (لا قيد موجب).
7. **close_session** → `cash_variance` GENERATED (المطلوب vs الفعلي).

**المخرج:** فاتورة بيع + قيد محاسبي مسودة + تحديث ولاء العميل.

---

## 2) Delivery Order Lifecycle
**الجداول:** `delivery_orders`, `delivery_tracking` (ثابت).

الحالات الـ9 (استُخرجت من CHECK constraint):
`new` → `assigned` → `preparing` → `ready_for_pickup` → `picked_up` → `on_the_way` → `delivered` (نقطة النهاية) — أو `cancelled` / `returned` / `failed`.

- **`delivery_assign_rider(order_id, rider_id)`** — يزيد `current_orders` للسائق ويحوّل حالته إلى `busy` عند تجاوز الحد.
- **`delivery_update_status(order_id, new_status)`** — يسجل في `delivery_tracking` (INSERT فقط).
- **`delivery_mark_delivered(order_id)`** — ينقص `current_orders`؛ إذا `<= 1` يعيد السائق إلى `available` (v120 fix).

**المصدر:** `pos_transaction_id` اختياري — يدعم طلبات من منصات خارجية.

---

## 3) Meeting → Decisions → Tasks Lifecycle
**الجداول:** `meetings`, `meeting_attendees`, `meeting_agenda`, `action_items`, `decisions`, `department_tasks`.

1. Meeting `status = scheduled` → `in_progress` → `completed` → `in_follow_up` → `closed`.
2. أثناء الاجتماع: `action_items` (INSERT) + `decisions` (INSERT).
3. `decisions.status`: `draft` → `active` → `executed` أو `cancelled`.
4. Action item `status`: `open` → `in_progress` → `completed`/`cancelled` (`overdue` محسوبة عند `due_date < now()`).
5. **إغلاق الاجتماع** = عند اكتمال كل مخرجاته/قراراته (منطق تطبيقي في `pageMeetings`).

---

## 4) Procurement (PR → PO → GRN → AP)
**الجداول:** `proc_requisitions` → `proc_purchase_orders` → `proc_goods_receipts` → `acct_bills`.

1. **PR** (`PR-YYYY-00001`): `draft` → `submitted` → `approved` → `converted_to_po` → `cancelled`.
2. **PO** (`PO-YYYY-00001`): `draft` → `sent_to_vendor` → `confirmed` → `partially_received` → `received` → `closed`.
3. **GRN** (`GRN-YYYY-00001`): `draft` → `received` (عند تنفيذ `proc_receive_goods`).
4. **دالة ذرية `proc_receive_goods(p_grn_id)`:**
   - تتحقق أن الكميات ≤ المطلوب.
   - تخصم `acct_inventory_movements` (in-movement) وتحدّث `acct_inventory_items.on_hand`.
   - تنشئ `acct_bills` بحالة `draft` + `acct_bill_lines` على حساب 5101 (تكلفة المواد).
   - VAT 15% تلقائي.
   - تحدّث حالة PO (partially_received/received).
5. **AP flow:** `acct_bills.status`: `draft` → `pending_approval` → `approved` → `paid` / `cancelled`.
6. **دفع:** `acct_payments`: `draft` → `approved` → `paid`.

**النقطة النهائية:** فاتورة مورد مدفوعة + مخزون مُحدَّث + قيود GL/AP.

---

## 5) Franchise (Sales report → Royalty → AR)
**الجداول:** `franchise_partners` → `franchise_agreements` → `franchise_sales_reports` → `franchise_royalty_invoices`.

1. Partner `FR-00001` (`prospect/active/paused/terminated/on_hold`).
2. Agreement `FRA-YYYY-00001` (نوع + royalty% + marketing% + minimum_royalty).
3. Sales report شهري (`FSR-YYYYMM-0001`) بـ upsert idempotent.
4. **`franchise_compute_royalty(sales_report_id)`:**
   - يحسب royalty = net_sales × royalty% + marketing + VAT 15%.
   - يطبّق `min_royalty` لو النسبة أقل → يسمّ `min_royalty_applied = TRUE`.
   - ينشئ `franchise_royalty_invoices` بحالة `draft`.
5. **`franchise_issue_royalty(royalty_id)`:** يُصدر الفاتورة.
6. **الربط بـ AR:** `acct_invoices` **غير مفعّل تلقائيًا** — قرار المالك مطلوب (medium debt).

---

## 6) HR (Attendance → Leaves → Payroll)
**الجداول:** `hr_attendance`, `hr_leaves`, `hr_payroll`, `hr_payroll_items`.

1. Attendance يومي — status: `present/absent/late/leave/holiday/sick/remote`.
2. Leave: `draft` → `submitted` → `approved`/`rejected` → `cancelled`. أنواع من `hr_leave_types`.
3. Payroll: `draft` → `approved` → `paid`.
4. **`create_journal_for_payroll(payroll_id)`** — يولّد قيد GL تلقائيًا.

---

## 7) Cafe Corner (طلب مباشر → فاتورة AR)
**الجداول:** `cafe_orders`, `cafe_order_items`, `cafe_order_status_log`.
1. Order status: `pending` → `preparing` → `ready` → `delivered` أو `cancelled`.
2. عند delivered → `create_journal_for_cafe_order` + `acct_invoices.source_type = 'cafe_order'`.

---

## 8) HACCP (Batch + Temperature + Incident)
**الجداول:** `haccp_temperature_logs`, `haccp_food_batches`, `haccp_incidents`.
1. Batch (`BATCH-YYYYMMDD-00001`) — كل يوم عداد جديد.
2. Temperature log: يحسب `is_within_range` تلقائيًا (trigger).
3. Incident (`HACCP-YYYY-00001`) بمنهجية: سبب جذري + إجراء تصحيحي + إجراء وقائي.

---

## 9) Documents (Upload → Access → Expire)
**الجداول:** `doc_documents`, `doc_access_log`, `doc_categories`.
1. Document (`DOC-YYYY-00001`) → active → expired (بواسطة `doc_expire_overdue()`).
2. `doc_log_access` عند فتح/تحميل — سجل ثابت.

---

## 10) Call Center (Call lifecycle)
**الجداول:** `cc_calls`, `cc_agents`, `cc_dispositions`, `cc_scripts`.
1. Call (`CALL-YYYY-00000001`) — inbound/outbound.
2. `cc_start_call(call_id)` → `in_progress` + agent `on_call`.
3. `cc_end_call(call_id, disposition_id, ...)` → `completed` + agent `available` + إحصائيات (`total_calls`, `total_duration`).

---

## 11) Payments (Partners → Statements → Clearing)
1. Partner + Contract (رسوم أساس + عمولة).
2. Statement شهري (`draft` → `approved`) بتفاصيل POS/Delivery الصافي.
3. Clearing batch (`draft` → `approved` → `paid`) يجمّع كشوفًا ويولد payout.

---

## 12) Integrations (Event lifecycle)
1. Connection: `active/paused/error`.
2. Event (`INT-YYYY-00000001`): `pending` → `sent` / `failed` / `retrying`.
3. `int_log_event` / `int_complete_event` تحدّث إحصائيات الاتصال تلقائيًا.
4. **لا worker حقيقي** — فقط سجل UI.
