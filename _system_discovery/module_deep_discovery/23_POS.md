# 23 — نقاط البيع (POS)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | نقاط البيع / Point of Sale |
| Routes | `#pos`, `#pos_terminals`, `#pos_sessions`, `#pos_session/:id`, `#pos_cashier/:terminal`, `#pos_transaction/:id` (17231-17236) |
| DAL | `window.POS` (~7729) |
| الجداول | `pos_terminals`, `pos_sessions`, `pos_transactions`, `pos_transaction_items`, `pos_payment_splits` |
| SQL | `pos-schema-1a.sql` |
| RPCs | `pos_complete_transaction` (ذرية), `pos_assign_terminal_code/session_no/transaction_no` |
| Feature flag | `pos` |
| الغرض | نقطة بيع كاملة: أجهزة + جلسات + معاملات + دفع مختلط + ZATCA QR + قيد GL. |
| الكيان المركزي | `pos_transactions` |

## 2) الصفحات

- Dashboard, Terminals, Sessions, Session detail (cash_variance), Cashier touch UI, Transaction detail (receipt).

## 3) تحليل

- **Cashier UI:** touch-optimized (UI_AUDIT §9).
- **QR ZATCA Phase 1** يُبنى client-side قبل RPC.
- **cash_variance GENERATED column** (v107).
- **v120 fix:** `type check` قبل create journal.
- **v121:** pos_txn_completed_date_idx.
- **v120 audit fix #9:** partial index.

## 4) دورة العمل

open_session (رصيد نقدي) → transaction draft → add items + payment_splits → build QR → `pos_complete_transaction(txn_id)` → `status=completed` + journal draft (`pos_sale`) + loyalty trigger → refund/void (`type<>'sale'` blocked) → close_session (`cash_variance`).

## 5) الحالات

- `pos_sessions.status`: `open → closed`.
- `pos_transactions.status`: `draft → completed → refunded / void`.
- `pos_transactions.type`: `sale / refund / void`.

## 6) قاعدة البيانات

5 جداول (POS domain).

## 7) الـBackend

`window.POS` + `pos_complete_transaction` RPC.

## 8) الصلاحيات

- Cashier (employee + branch match).
- Ops manager oversight.
- RLS: نعم.

## 9) العلاقات

- **يستقبل من:** Menu (snapshot سعر), CRM (customer_id).
- **يرسل إلى:** Accounting (journal draft), CRM (loyalty via trigger), Delivery (اختياري).

## 10) التقارير

- Session variance, top items, transaction details.

## 11) الإشعارات

- عند session close، عند refund.

## 12) UI/UX

- Touch cashier UI.
- Print receipt.

## 13) التكرارات

- POS transactions مقابل Ops orders (بيع vs طلب داخلي).
- POS terminals مقابل devices.

## 14) الاكتمال

Backend 90 | DB 90 | RPCs 90 | UI 85 | Perm 85 | Workflow 85 | Notif 70 | Audit 75 | Reports 70 | Cross 90 | Docs 90 | Tests 20 → **~80/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION (offline + printer + cash drawer).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** نقاط البيع (POS 2.0).
2. **الصفحات:** كل الحالية + `#pos_offline_queue`, `#pos_daily_report`, `#pos_kds_link`.
3. **الجداول:** إضافة `pos_offline_queue`, `pos_receipt_templates`.
4. **APIs:** `pos_sync_offline_batch`, `pos_open_drawer`, `pos_print_receipt`.
5. **Workflows:** offline-first.
6. **قرار المالك:** offline priority؟
7. **RLS.**
8. **Reports:** daily Z-report.
9. **Notifications:** end-of-day.
10. **Integrations:** ZATCA Phase 2 real, Mada terminal, cash drawer, thermal printer.
11. **AI hook:** upsell suggestions.
12. **BI:** hourly sales.
13. **Design:** touch optimization.
14. **Mobile:** iPad/Android.
15. **KPI:** avg ticket, TPS.
16. **Compliance:** ZATCA.
17. **Roadmap Phase 1:** offline + printer.
18. **Roadmap Phase 2:** ZATCA Phase 2.
19. **Roadmap Phase 3:** AI + KDS.
20-28. توسيع.
