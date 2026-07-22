# 35 — العلاقات بين الموديولات (Cross-Module Relationships)

> **المرجع:** `_system_discovery/MODULE_RELATIONSHIP_MATRIX.md` + هذا الملف تلخيص وتحليل معمّق.

## أ) الخريطة الكلية للعلاقات

```
Users ←── الأساس الأمني (RLS) لكل جدول
   │
Branches / Departments ←── يُنسب لهما كل شيء (branch_id/dept_id)
   │
   ├── HR (moduels employee data)
   ├── Menu ──→ POS (snapshot سعر)
   ├── CRM ──→ POS/Delivery/Cafe (customer_id) + Loyalty trigger
   ├── POS ──→ Accounting (journal draft `pos_sale`)
   ├── POS ──→ CRM loyalty (trigger)
   ├── Procurement (PR→PO→GRN) ──→ Accounting (AP bill 5101 + Inventory)
   ├── Ops orders ──→ Accounting + Inventory
   ├── Ops stock transfers/waste ──→ Inventory
   ├── HR payroll ──→ Accounting (create_journal_for_payroll)
   ├── Cafe orders ──→ Accounting (invoice cafe_order)
   ├── HACCP ──→ BI (operations_health) + Emergency
   ├── Delivery ──→ POS (اختياري) + CRM + BI
   ├── Documents ──→ polymorphic (كل موديول)
   ├── Call Center ──→ CRM/POS/Delivery (اختياري)
   ├── Franchise ──→ Accounting AR (يدوي — R-14)
   ├── Payments (partners) ──→ POS/Delivery aggregation + bank
   ├── Integrations ──→ كل موديول (workers غير موجودين — R-11)
   └── BI ──→ يجمع من كل ما سبق
      └── AI Assistant tools (7) تقرأ من: Tasks, Branches, Docs, Financial, Decisions, Maintenance, Payments
```

## ب) جدول التدفقات الأساسية

| المصدر | البيانات | الوجهة | آلية |
|---|---|---|---|
| Menu | item_id + snapshot | POS transaction items | INSERT |
| CRM customer | customer_id | POS/Delivery/Cafe | FK |
| POS completed | مبلغ + VAT | acct_journal_entries (draft, source=pos_sale) | RPC `pos_complete_transaction` |
| POS payment | loyalty | crm loyalty_transactions | Trigger |
| Cafe delivered | invoice | acct_invoices (cafe_order) | `create_journal_for_cafe_order` |
| Procurement GRN | bill | acct_bills (5101) | `proc_receive_goods` |
| Procurement GRN | كميات | acct_inventory_movements | `proc_receive_goods` |
| Accounting bill (approved) | قيد | acct_journal_entries | `create_journal_for_bill` |
| Accounting payment (approved) | قيد | acct_journal_entries | `create_journal_for_payment` |
| Accounting invoice (issued) | قيد AR | acct_journal_entries | `create_journal_for_invoice` |
| Accounting receipt | قيد | acct_journal_entries | `create_journal_for_receipt` |
| Bank transaction | قيد | acct_journal_entries | `create_journal_for_bank_transaction` |
| Expense claim (approved) | قيد | acct_journal_entries | `create_journal_for_expense_claim` |
| Fixed asset setup | جدول إهلاك | acct_asset_depreciation_schedule | Trigger `acct_fa_auto_schedule` |
| Depreciation (monthly) | قيد | acct_journal_entries | `run_monthly_depreciation` |
| HR payroll (approved) | قيد | acct_journal_entries | `create_journal_for_payroll` |
| Franchise sales report | royalty | franchise_royalty_invoices (draft) | `franchise_compute_royalty` |
| Franchise royalty (issued) | فاتورة AR | acct_invoices | **يدوي — R-14** |
| Ops order | تحرك مخزون + قيد | acct_inventory_movements + acct_journal_entries | Trigger + `create_journal_for_ops_order` |
| Ops stock transfer | حركة branch A→B | acct_inventory_movements | `ops_apply_stock_transfer` |
| Ops waste | حركة سالبة | acct_inventory_movements | `ops_apply_waste_to_branch_inventory` |
| Menu BOM | inventory ref | menu_item_recipes | FK |
| Delivery order | pos_transaction_id | POS | Optional FK |
| Meeting | meeting_id | action_items + decisions | FK |
| Action item | linked_task_id | department_tasks | Optional FK |
| Decision | linked_task_id | department_tasks | Optional FK |
| Emergency alert | recipients | notifications | Insert bulk |
| Any state change | notification | notifications | Trigger or DAL |
| POS metrics | aggregation | bi_daily_summary, bi_top_menu_items | RPC |
| Delivery metrics | aggregation | bi_delivery_kpis | RPC |
| CRM customers | segments | bi_customer_segments | RPC |
| HACCP + complaints | health | bi_operations_health | RPC |
| CC call | related_customer/pos/delivery | CRM/POS/Delivery | Optional FKs |
| Documents | polymorphic (entity_type, entity_id) | أي موديول | Soft link |
| Integrations event | payload | int_events | Insert |
| Integration failure | connection status | int_connections.status=error | `int_complete_event` |
| Payments partner statement | POS + Delivery net | pay_statement_lines | Client aggregation |
| Payments clearing | statements | pay_clearing_items + payout | `PAY.clearing.calculate` |

## ج) العلاقات المفقودة أو الضعيفة

1. **CRM `crm_customers` ↔ Accounting `acct_customers`** — جدولان مستقلان (R-08).
2. **HR employee ↔ HACCP health_certificates** — تكرار محتمل.
3. **Meetings ↔ action_items ↔ department_tasks ↔ decisions** — أربع كيانات مترابطة بلا `convert_*` آلي.
4. **POS ↔ Delivery** — FK اختياري فقط.
5. **CRM Complaints ↔ CC Calls** — بلا FK صريح.
6. **BI CASH_FLOW ↔ Accounting/POS** — بلا RPC.
7. **AI Assistant tools ↔ Franchise/BI/HR** — أدوات محدودة (7).
8. **Franchise ↔ Accounting AR** — R-14.

## د) الاعتماديات الحرجة

- **Accounting هو المستقر الأخير:** يستقبل من POS + Cafe + Procurement + HR + Ops + Delivery + Franchise + Fixed Assets.
- **Users + Branches أساس الكل.**
- **RLS يعتمد `current_app_user_id()`** — لو تعطلت الدالة تعطلت الحماية (R-02).

## هـ) العلاقات الدائرية

- لم يُرصد دورات دائرية.

## و) دوال Auto Journal (10)

`create_journal_for_bill / payment / invoice / receipt / payroll / cafe_order / bank_transaction / expense_claim / ops_order / inventory_movement`.

## ز) نقاط التحسين

1. **إضافة `convert_action_item_to_task(id)`** لتوحيد Meetings↔Tasks.
2. **آلية auto-AR للفرنشايز.**
3. **توحيد `crm_customers` مع `acct_customers`** (قرار R-08).
4. **آلية auto-createDeliveryOrder من POS بقناة delivery.**
5. **ربط Complaints مع CC calls (FK).**
6. **CASH_FLOW RPC.**
7. **توسع AI tools لتشمل Franchise + BI + HR.**
