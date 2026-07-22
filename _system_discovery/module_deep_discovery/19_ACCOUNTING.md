# 19 — الحسابات والمالية (Accounting)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الحسابات والمالية / Accounting & Finance |
| Routes | 25+ route: `#accounting`, `#acct_chart`, `#acct_cost_centers`, `#acct_periods`, `#acct_journal`, `#acct_journal_entry/:id`, `#acct_vendors`, `#acct_bills`, `#acct_bill/:id`, `#acct_payments`, `#acct_customers`, `#acct_invoices`, `#acct_invoice/:id`, `#acct_receipts`, `#acct_bank_accounts`, `#acct_petty_cash`, `#acct_expense_claims`, `#acct_expense_claim/:id`, `#acct_fixed_assets`, `#acct_fixed_asset/:id`, `#acct_inventory`, `#acct_vat_returns`, `#acct_reports`, `#acct_budgets`, + Payments sub-pages 6 (`#acct_pay_*`) |
| DAL | `window.ACCT` (سطر ~6608)، `window.PAY` (سطر ~9690 تقريبًا) |
| الجداول | 30+ (`DATABASE_OVERVIEW §Accounting`) |
| SQL | `acct-schema.sql` + `2b-ap.sql` + `2c-ar.sql` + `2d-treasury.sql` + `2e-assets.sql` + `2f-closing.sql` |
| RPCs | 10 دوال Auto Journal + 7 دوال Reporting (Trial Balance, IS, BS, VAT, Depreciation, Close FY, Budget vs Actual) + دوال ترقيم |
| Feature flag | `accounting` |
| الغرض | مالية كاملة: GL + AP + AR + Treasury + Fixed Assets + Inventory + VAT + Closing + Budgets + Payments شركاء. |
| الكيان المركزي | `acct_journal_entries` (Ledger Truth) |
| نقاط | من إنشاء قيد → posted → إغلاق فترة/سنة. |

## 2) الصفحات والمسارات

راجع `MODULE_INVENTORY §19`.
- **Chart of Accounts:** `#acct_chart` — 65+ حساب.
- **Journal:** `#acct_journal` (v121: limit 300) + `#acct_journal_entry/:id`.
- **AP:** vendors, bills, payments.
- **AR:** customers, invoices, receipts.
- **Treasury:** bank_accounts, petty_cash, expense_claims.
- **Assets:** fixed_assets + depreciation.
- **Inventory:** items + movements.
- **VAT:** returns.
- **Reports:** trial balance, IS, BS.
- **Budgets.**
- **Payments (PAY 3-stage):** partners → contracts → statements → clearing → payouts.

## 3) تحليل كل صفحة

- **Dashboard `#accounting`:** KPIs (revenue, expenses, receivables، payables، cash).
- **Journal detail:** header + lines + posting rules.
- **Bill detail:** approval trigger `acct_validate_bill_approval`.
- **Reports:** trial balance, IS, BS تعتمد `get_*` RPCs.
- **VAT:** إعتماد جزئي على `compute_vat_totals` (BACKEND_GAPS §Accounting).

## 4) دورة العمل

- **Journal:** `draft → posted` (posted immutable).
- **Bill (AP):** `draft → pending_approval → approved → paid / cancelled`.
- **Payment (AP):** `draft → approved → paid / cancelled`.
- **Invoice (AR):** `draft → issued → paid / partially_paid / cancelled` + `zatca_status: phase1_qr → phase2_signed → reported → cleared`.
- **Period:** `open → closed → locked`.
- **Fixed Asset:** `active → disposed` + auto depreciation schedule.
- **Expense Claim:** `draft → submitted → approved / rejected → paid`.
- **Purchase Order (in acct schemas):** `draft → approved → received → closed / cancelled`.

## 5) الحالات والانتقالات

راجع `WORKFLOW_STATUS_AUDIT §2`.

## 6) قاعدة البيانات

30+ جدول، 10+ RPCs Auto Journal، 7+ RPCs Reporting. Triggers: `acct_validate_journal_posting`, `acct_validate_bill_approval`, `acct_apply_inventory_movement`, `acct_fa_auto_schedule`, `acct_generate_periods_for_fy`.

## 7) الـBackend (DAL)

`window.ACCT` — 20+ وظيفة (journals, bills, invoices, receipts, banks, treasury, assets, inventory, VAT, reports, budgets).

## 8) الصلاحيات

- `finance_manager` — عام.
- `gl_accountant` — post journals.
- `ap_officer` — AP approval.
- `ar_officer` — AR issuing.
- `payroll_officer` — payroll journals only.
- `is_accounting_role`, `is_finance_manager` تفحص الوصول.

## 9) العلاقات

**يستقبل من:**
- POS → journal (source `pos_sale`).
- Procurement → bills (5101).
- HR → payroll journal.
- Cafe → invoice (`cafe_order`).
- Ops → orders + inventory + waste.
- Franchise → AR (يدوي!).
- Fixed Assets → depreciation.
- Bank transactions.

**يرسل إلى:** BI (aggregations).

## 10) التقارير

- Trial Balance, IS, BS, VAT, Budget vs Actual.
- زر تشغيل `run_monthly_depreciation` غير موجود صراحة (BACKEND_ONLY - راجع BACKEND_GAPS).
- `close_fiscal_year` بلا شاشة اعتماد.

## 11) الإشعارات وسجل التدقيق

- عند approval bill، عند issue invoice، عند posting.
- Immutable posted entries.

## 12) UI/UX

- **Hero:** `.mod-hero` (بعض الشاشات) + `.hero-card` (الأقدم).
- **Layout:** جدول كثير + form modals.
- **VAT Phase 2 mock** يحتاج توضيح للمستخدم.

## 13) التكرارات

- `acct_customers` مقابل `crm_customers` (R-08 عالية).
- `acct_inventory_items` مقابل `menu_item_recipes` (BOM link).

## 14) مستوى الاكتمال

Backend 85 | DB 95 | RPCs 90 | UI 80 | Perm 85 | Workflow 90 | Notif 75 | Audit 80 | Reports 85 | Cross 90 | Docs 95 | Tests 20 → **~82/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION (VAT Phase 2, close_year UI, دمج CRM).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** الحسابات والمالية (Financial ERP).
2. **الصفحات:** كل الحالية + `#acct_dashboard_finance`, `#acct_close_period_ui`, `#acct_depreciation_run`, `#acct_zatca_phase2`.
3. **الجداول:** توحيد `acct_customers` مع `crm_customers` (قرار المالك).
4. **APIs:** `acct_auto_reconcile_bank`, `acct_zatca_phase2_sign`, دوال إضافية.
5. **Workflows:** approval matrix متعدد المستويات.
6. **قرار المالك:** توحيد العملاء (R-08).
7. **قرار:** تفعيل Franchise → AR تلقائي.
8. **RLS:** موحد.
9. **Reports:** cash flow (حل CASH_FLOW في BI).
10. **Notifications:** approval requests.
11. **Integrations:** SADAD, Mada, ZATCA Phase 2 real.
12. **AI hook:** anomaly detection.
13. **BI:** حي.
14. **Design:** v123.
15. **Mobile:** approval fast.
16. **KPI:** DSO, DPO, cash cycle.
17. **Compliance:** SOCPA + ZATCA + IFRS.
18. **Data model:** multi-currency (اختياري).
19. **Roadmap Phase 1:** UI للـ RPCs backend-only.
20. **Roadmap Phase 2:** ZATCA Phase 2.
21. **Roadmap Phase 3:** advanced reporting.
22. **Documentation.**
23. **Templates:** قوالب قيود.
24. **Auto-post rules.**
25. **Approval matrix.**
26. **Cost centers.**
27. **Budgets tracking.**
28. **Cross-module discipline.**
