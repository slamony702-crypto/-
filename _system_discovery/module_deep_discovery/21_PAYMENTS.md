# 21 — المدفوعات والمقاصات (Payments)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | المدفوعات والمقاصات / Payments & Clearing |
| Routes | 6 sub-routes under Accounting: `#acct_pay_partners`, `#acct_pay_partner/:id`, `#acct_pay_statements`, `#acct_pay_statement/:id`, `#acct_pay_clearing`, `#acct_pay_clearing_batch/:id` (17198-17203) |
| DAL | `window.PAY` |
| الجداول | `pay_partners`, `pay_partner_contracts`, `pay_statements`, `pay_statement_lines`, `pay_clearing_batches`, `pay_clearing_items`, `pay_payouts` |
| SQL | `pay-schema-p1` + `p2` + `p3` |
| RPCs | ترقيم + `PAY.clearing.calculate` (v121: batch inserts). |
| Feature flag | تحت `accounting` (لا مفتاح مستقل — HANDOFF §PREVIEW_MODULES) |
| الغرض | شركاء ماليون (Jahez/HungerStation/Mada/STC/...) + عقود + كشوف + مقاصة + تحويلات. |
| الكيان المركزي | `pay_partners` |

## 2) الصفحات

راجع `MODULE_INVENTORY §21`.

## 3) تحليل

- Partners: قائمة + تفاصيل.
- Statements: شهرية بحساب صافي POS/Delivery.
- Clearing: تجميع كشوف + payout.

## 4) دورة العمل

Partner → Contract → Statement شهري → Clearing batch → Payout.

## 5) الحالات

- `pay_statements.status`: `draft → approved → settled`.
- `pay_clearing_batches.status`: `draft → approved → paid`.
- `pay_payouts.status`: `pending → sent → confirmed`.

## 6) قاعدة البيانات

7 جداول.

## 7) الـBackend

`window.PAY`.

## 8) الصلاحيات

- `finance_manager`, `ap_officer`.

## 9) العلاقات

- **يستقبل من:** POS, Delivery.
- **يرسل إلى:** Accounting (bank_transactions).

## 10) التقارير

Statements + Clearing reports.

## 11) الإشعارات

Approval flows.

## 12) UI/UX

مدمج داخل Accounting.

## 13) التكرارات

—

## 14) الاكتمال

Backend 85 | DB 90 | UI 70 | Perm 85 | Workflow 85 | Notif 70 | Reports 75 | Cross 85 | Docs 85 | Tests 15 → **~76/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** المدفوعات والتسويات (Financial Partners).
2. **الصفحات:** فصل route جذر `#payments` (dashboard مستقل).
3. **الجداول:** توسيع للـ multi-currency.
4. **APIs:** `pay_auto_generate_statements`, `pay_reconcile_bank`.
5. **Workflows:** approval matrix.
6. **قرار المالك:** فصل من Accounting؟
7. **RLS.**
8. **Reports.**
9. **Notifications.**
10. **Integrations:** Jahez, HungerStation, Mada Pay APIs (Wave 4).
11. **AI hook.**
12. **BI.**
13. **Design.**
14. **Mobile.**
15. **KPI:** collection cycle.
16. **Compliance.**
17. **Roadmap Phase 1:** فصل UI جذر.
18. **Roadmap Phase 2:** integration APIs.
19-28. توسيع.
