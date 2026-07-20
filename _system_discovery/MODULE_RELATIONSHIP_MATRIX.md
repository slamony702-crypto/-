# MODULE_RELATIONSHIP_MATRIX — العلاقات بين الموديولات

> استُخرجت من FKs في SQL + دوال cross-module (auto journals, cross RPCs).

## جدول التدفق (المصدر → البيانات → الوجهة)

| من (Source) | ماذا ينتقل | إلى (Target) | آلية النقل |
|---|---|---|---|
| Menu | `item_id` + snapshot سعر | POS `pos_transaction_items` | Insert |
| CRM customer | `customer_id` | POS `pos_transactions.customer_id` | FK |
| CRM customer | `customer_id` | Delivery `delivery_orders.customer_id` | FK |
| CRM customer | `customer_id` | Cafe `cafe_orders.customer_id` | FK |
| POS completed transaction | مبلغ + بنود + VAT | Accounting `acct_journal_entries` (draft, source=pos_sale) | `pos_complete_transaction` RPC |
| POS payment splits | loyalty points | CRM `loyalty_transactions` | Trigger |
| Cafe order (delivered) | invoice | Accounting `acct_invoices` (source=cafe_order) | `create_journal_for_cafe_order` |
| Procurement GRN | `bill_id` | Accounting `acct_bills` (draft, account 5101) | `proc_receive_goods` |
| Procurement GRN | كميات + تكلفة | Inventory `acct_inventory_movements` | `proc_receive_goods` |
| Accounting bill (approved) | قيد | `acct_journal_entries` | `create_journal_for_bill` |
| Accounting payment (approved) | قيد | `acct_journal_entries` | `create_journal_for_payment` |
| Accounting invoice (issued) | قيد AR | `acct_journal_entries` | `create_journal_for_invoice` |
| Accounting receipt | قيد | `acct_journal_entries` | `create_journal_for_receipt` |
| Accounting bank transaction | قيد | `acct_journal_entries` | `create_journal_for_bank_transaction` |
| Accounting expense claim (approved) | قيد | `acct_journal_entries` | `create_journal_for_expense_claim` |
| Accounting inventory movement | قيد | `acct_journal_entries` | `create_journal_for_inventory_movement` |
| Fixed asset (setup) | جدول إهلاك | `acct_asset_depreciation_schedule` | `acct_fa_auto_schedule` |
| Depreciation schedule (monthly) | قيد | `acct_journal_entries` | `run_monthly_depreciation` |
| HR payroll (approved) | قيد | `acct_journal_entries` | `create_journal_for_payroll` |
| Franchise sales report | `royalty_invoice_id` | Franchise `franchise_royalty_invoices` (draft) | `franchise_compute_royalty` |
| Franchise royalty (issued) | فاتورة AR | Accounting `acct_invoices` (**غير مفعّل تلقائيًا**) | قرار المالك |
| Ops order | تحرك مخزون | `acct_inventory_movements` | Trigger |
| Ops order | قيد | `acct_journal_entries` | `create_journal_for_ops_order` |
| Ops stock transfer | حركة | `acct_inventory_movements` (branch A → B) | `ops_apply_stock_transfer` |
| Ops waste record | حركة سالبة | `acct_inventory_movements` | `ops_apply_waste_to_branch_inventory` |
| Menu item BOM | `acct_inventory_item_id` | Menu `menu_item_recipes` | FK |
| Menu item | تكلفة | `menu_compute_item_cost` RPC | حسابيًا |
| Delivery order | يمكن `pos_transaction_id` | POS `pos_transactions.id` | Optional FK |
| Meeting | `meeting_id` | `action_items` + `decisions` | FK |
| Action item | `linked_task_id` | `department_tasks` | Optional FK |
| Decision | `linked_task_id` | `department_tasks` | Optional FK |
| Emergency alert | `recipients` | `notifications` | Insert bulk |
| Any state change | notification | `notifications` | Trigger أو DAL |
| POS transactions | metrics | BI `bi_daily_summary`, `bi_top_menu_items` | RPC aggregation |
| Delivery orders | metrics | BI `bi_delivery_kpis` | RPC |
| CRM customers | segments | BI `bi_customer_segments` | RPC |
| HACCP incidents + certificates | health | BI `bi_operations_health` | RPC |
| Complaints | count | BI `bi_operations_health` | RPC |
| CC calls | `related_customer_id`, `related_pos_transaction_id`, `related_delivery_order_id` | CRM/POS/Delivery | Optional FKs |
| CC call end | agent stats | `cc_agents.total_calls`, `total_duration` | `cc_end_call` |
| Documents | polymorphic `related_entity_type` + `related_entity_id` | أي موديول | soft link (بلا FK صارم) |
| Integrations event | webhook payload | `int_events.payload_json` | Insert |
| Integration failure | connection status | `int_connections.status='error'` | `int_complete_event` |
| Payments partner statement | POS + Delivery net | `pay_statement_lines` | Client aggregation |
| Payments clearing | multiple statements | `pay_clearing_items` + payout | `PAY.clearing.calculate` |
| HR position | `position_id` | `users.position_id` (اختياري) | FK |
| HR employee_profile | `user_id` | `users.id` | 1:1 |
| Signup request | approved → user | `users` insert | manual DAL |
| Maintenance request | `bill_id` (اختياري) | Accounting AP | manual link |
| Quality visit | `attachments` | file storage | Supabase Storage |
| Documents | expiring | `notifications` | يفترض عبر `doc_expire_overdue` |

## علاقات مفقودة / ضعيفة
1. **CRM `crm_customers` ↔ Accounting `acct_customers`**: جدولان مستقلان. لا FK ولا sync — تكرار متعمد ولكن مصدر ارتباك.
2. **HR employee ↔ HACCP health_certificates**: كلاهما يخزن شهادات — لا ربط واضح.
3. **Meetings ↔ action_items ↔ department_tasks ↔ decisions**: أربع كيانات مترابطة، لكن التدفق يدوي (لا آلية `convert_action_item_to_task`).
4. **POS transaction ↔ Delivery order**: FK اختياري فقط. لا آلية إنشاء delivery order تلقائيًا من POS بقناة delivery.
5. **Complaints (CRM) ↔ Call Center**: `cc_calls.disposition_id` قد يعادل `complaint_created` لكن بلا FK صريح.
6. **BI CASH_FLOW report ↔ Accounting/POS**: التقرير موجود بلا RPC.
7. **AI Assistant tools ↔ Franchise/BI/HR**: الأدوات لا تشمل قراءة من هذه الموديولات (فقط 7 أدوات مذكورة في `api/agent.js`).

## الاعتمادات (Dependencies) الحرجة
- **Accounting هو المستقر الأخير:** يستقبل من POS + Cafe + Procurement + HR + Ops + Delivery + Franchise + Fixed Assets. أي كسر في `acct_journal_entries` يوقف الإغلاق الشهري.
- **Users + Branches أساس الكل:** حذف/تعطيل branch = SET NULL على كل الفروع في السجلات.
- **RLS `current_app_user_id()` مرتبط بـ Postgres GUC** — لو تُعطلت تُعطل الحماية.

## علاقات دائرية محتملة
- Franchise agreement ↔ Franchise partner: مباشر (لا دائري).
- POS ↔ CRM (loyalty): trigger واحد اتجاه واحد — آمن.
- لا دورات دائرية مرصودة.
