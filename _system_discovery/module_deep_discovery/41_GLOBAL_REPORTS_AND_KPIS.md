# 41 — التقارير والمؤشرات الشاملة

> **المرجع:** `_system_discovery/REPORTS_INVENTORY.md`.

## أ) تقارير BI (7 مبذورة)

| code | name | RPC | حالة |
|---|---|---|---|
| DAILY_SUMMARY | ملخص يومي | bi_daily_summary | ✅ |
| BRANCH_RANKING | ترتيب فروع | bi_branch_ranking | ✅ |
| TOP_MENU_ITEMS | أصناف مبيعًا | bi_top_menu_items | ✅ (v118 fix) |
| CUSTOMER_SEGMENTS | شرائح عملاء | bi_customer_segments | ✅ |
| OPERATIONS_HEALTH | صحة تشغيلية | bi_operations_health | ✅ |
| DELIVERY_KPIS | أداء توصيل | bi_delivery_kpis | ✅ |
| CASH_FLOW | تدفقات نقدية | NULL | ⚪ PLACEHOLDER (R-16) |

## ب) تقارير Accounting

- `compute_vat_totals`
- `get_trial_balance`
- `get_income_statement`
- `get_balance_sheet`
- `get_budget_vs_actual`
- `close_fiscal_year`
- `run_monthly_depreciation`

**الشاشات:** `#acct_reports`, `#acct_vat_returns`, `#acct_budgets`.

## ج) تقارير HR

- Attendance summary (شهري).
- Leaves balance.
- Payroll register.
- **جميعها استعلامات مباشرة، بلا RPC خاصة.**

## د) تقارير Operations, Quality, Maintenance, POS, CRM, Delivery, Franchise, CC

راجع `REPORTS_INVENTORY §5-14`.

## هـ) تقارير قديمة

- `#reports` (meetings/tasks/decisions).
- `#analytics` (KPI شركة).
- `#dashboard`.

## و) `dashboard_summary` RPC

- جاهز في `perf-fix-1-dashboard-rpc.sql`.
- **الفرونت لم يُحدَّث** لاستخدامه (R-13 متوسطة).

## ز) الفجوات

1. **CASH_FLOW** — placeholder.
2. **`compute_vat_totals`** — استخدام جزئي.
3. **`close_fiscal_year`** — بلا شاشة اعتماد.
4. **`run_monthly_depreciation`** — بلا زر تشغيل.
5. **تصدير:** CSV/XLSX غير متوفر (PDF client-side فقط).
6. **بوابة فرنشايزي:** بلا تقارير خاصة.
7. **Integrations analytics:** بلا لوحة تلخيص فوق `int_events`.
8. **Cross-module AI analytics:** 7 أدوات نصية فقط.

## ح) KPIs المتاحة عبر النظام

راجع كل ملف موديول (`§10 التقارير والمؤشرات`) للـ KPIs المقترحة.

**أهم KPIs العالمية:**
- إيرادات يومية/شهرية (POS + Delivery + Cafe + Franchise).
- Cost of goods sold (COGS).
- Cash flow (يحتاج CASH_FLOW RPC).
- Gross margin.
- Employee turnover.
- Avg transaction value.
- Avg ticket time.
- Waste %.
- Complaint response time.
- HACCP breach rate.
- Rider utilization.
- Vendor performance score.
- Franchise royalty per period.

## ط) توصيات

1. **إكمال CASH_FLOW RPC** (R-16).
2. **تصدير CSV/XLSX** (Excel export).
3. **جدولة snapshots** (cron).
4. **إلغاء `#reports` و `#analytics`** بعد BI stable.
5. **`dashboard_summary` RPC** — تحديث الفرونت (R-13).
6. **AI-generated executive summary** (integration مع AI Assistant).
7. **Scheduled reports via integrations** (Slack/Teams/Email).
