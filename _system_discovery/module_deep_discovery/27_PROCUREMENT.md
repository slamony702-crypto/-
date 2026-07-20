# 27 — المشتريات (Procurement)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | المشتريات / Procurement |
| Routes | `#procurement`, `#proc_requisitions`, `#proc_requisition/:id`, `#proc_orders`, `#proc_order/:id`, `#proc_receipts`, `#proc_receipt/:id` (17245-17251) |
| DAL | `window.PROC` |
| الجداول | `proc_requisitions`, `proc_requisition_items`, `proc_purchase_orders`, `proc_purchase_order_items`, `proc_goods_receipts`, `proc_goods_receipt_items` |
| SQL | `proc-schema-1.sql` |
| RPCs | `proc_receive_goods` (ذرية), ترقيم |
| Feature flag | `procurement` |
| الغرض | PR → PO → GRN → AP آلي. |
| الكيان المركزي | `proc_purchase_orders` |

## 2) الصفحات

7 routes: dashboard + PR list + PR detail + PO list + PO detail + GRN list + GRN detail.

## 3) تحليل

- Numbering: `PR-YYYY-00001`, `PO-YYYY-00001`, `GRN-YYYY-00001`.
- **دالة ذرية `proc_receive_goods`:** تحقق كميات + خصم مخزون + إنشاء AP bill (5101) + VAT 15% + تحديث حالة PO.

## 4) دورة العمل

PR → submitted → approved → converted_to_po → PO → sent_to_vendor → confirmed → partially_received / received → GRN → AP bill (draft) → AP flow.

## 5) الحالات

راجع `WORKFLOW_STATUS_AUDIT §12`.

## 6) قاعدة البيانات

6 جداول.

## 7) الـBackend

`window.PROC`.

## 8) الصلاحيات

`operations_manager`, `finance_manager`, `is_procurement_manager`.

## 9) العلاقات

- **يرسل إلى:** Accounting (`acct_bills`), Inventory movements.

## 10) التقارير

PR/PO/GRN reports, vendor performance.

## 11) الإشعارات

Approval, receiving.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

`acct_purchase_orders` (في Accounting) مقابل `proc_purchase_orders` — نطاقان مختلفان (نظريًا) لكن مربك.

## 14) الاكتمال

Backend 90 | DB 90 | RPCs 90 | UI 80 | Perm 85 | Workflow 90 | Notif 80 | Audit 80 | Reports 75 | Cross 90 | Docs 90 | Tests 25 → **~80/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION (multi-approval).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** المشتريات الاستراتيجية (Strategic Procurement).
2. **الصفحات:** كل + `#proc_rfp` (RFQ/RFP), `#proc_vendor_scorecards`, `#proc_contracts`.
3. **الجداول:** إضافة `proc_rfps`, `proc_vendor_scorecards`.
4. **APIs:** `proc_multi_approval`, `proc_rfq_send_to_vendors`.
5. **Workflows:** approval matrix متعدد المستويات.
6. **قرار المالك:** توحيد `acct_purchase_orders` مع `proc_*`.
7. **RLS.**
8. **Reports:** vendor scorecard.
9. **Notifications.**
10. **Integrations:** vendor portals.
11. **AI hook:** anomaly في الأسعار.
12. **BI.**
13. **Design.**
14. **Mobile.**
15. **KPI:** cycle time, savings.
16. **Compliance.**
17. **Roadmap Phase 1:** multi-approval.
18. **Roadmap Phase 2:** RFP + scorecards.
19-28. توسيع.
