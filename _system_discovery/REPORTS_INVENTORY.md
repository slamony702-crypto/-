# REPORTS_INVENTORY — جرد التقارير

## 1) BI Reports (7 مبذورة في bi_report_definitions)
| code | name | rpc_name | حالة |
|---|---|---|---|
| DAILY_SUMMARY | ملخص يومي شامل | bi_daily_summary | يعمل |
| BRANCH_RANKING | ترتيب أداء الفروع | bi_branch_ranking | يعمل |
| TOP_MENU_ITEMS | الأصناف الأكثر مبيعًا | bi_top_menu_items | يعمل (v118 fix name_ar) |
| CUSTOMER_SEGMENTS | شرائح العملاء | bi_customer_segments | يعمل |
| OPERATIONS_HEALTH | الصحة التشغيلية | bi_operations_health | يعمل |
| DELIVERY_KPIS | أداء التوصيل | bi_delivery_kpis | يعمل |
| CASH_FLOW | التدفقات النقدية | NULL | PLACEHOLDER |

## 2) دوال تجميع BI (6)
- bi_daily_summary(p_from, p_to)
- bi_branch_ranking(p_from, p_to)
- bi_top_menu_items(p_from, p_to, p_limit)
- bi_customer_segments()
- bi_operations_health(p_from, p_to)
- bi_delivery_kpis(p_from, p_to)
+ bi_save_snapshot() لتخزين النتائج في bi_snapshots.

## 3) تقارير مالية Accounting (acct-schema-2f-closing.sql)
1. compute_vat_totals(p_start, p_end)
2. get_trial_balance(p_as_of)
3. get_income_statement(p_start, p_end)
4. get_balance_sheet(p_as_of)
5. get_budget_vs_actual(p_budget_id)
6. close_fiscal_year(p_year)
7. run_monthly_depreciation(p_year, p_month)
الشاشات: #acct_reports, #acct_vat_returns, #acct_budgets.

## 4) تقارير HR
- Attendance summary (شهري)
- Leaves balance
- Payroll register
الشاشات: #hr_attendance, #hr_leaves, #hr_payroll — عبر استعلامات مباشرة، بلا RPC.

## 5) تقارير Operations
#ops_waste, #ops_issues, #ops_prep_plans, #ops_shifts.

## 6) تقارير Quality
#quality_reports.

## 7) تقارير Maintenance
#maintenance_reports — مفتوحة/مغلقة/تكلفة/زمن استجابة.

## 8) تقارير POS
#pos_sessions (cash_variance), #pos_transaction/:id.

## 9) تقارير CRM
#crm_customers, #crm_complaints.

## 10) تقارير Delivery
#dlv_orders (Kanban).

## 11) تقارير Franchise
#fr_reports, #fr_royalties.

## 12) تقارير Call Center
#cc_calls, #cc_followups.

## 13) تقارير عامة قديمة
#reports (meetings/tasks/decisions), #analytics (KPI شركة), #dashboard.

## 14) Dashboard RPC جاهز غير مفعّل
dashboard_summary(p_user_id, p_dept_id, p_is_admin) في perf-fix-1-dashboard-rpc.sql. SQL جاهز، الفرونت لم يُحدَّث لاستخدامه.

## 15) Placeholders / غير مفعّلة
- CASH_FLOW BI — rpc_name = NULL.
- بوابة الفرنشايزي — لا تقارير خاصة.
- Integrations analytics — لا لوحة تلخيص فوق int_events.
- Cross-module AI analytics — 7 أدوات نصية فقط.

## 16) الصادرات (Exports)
- PDF: محاضر اجتماعات + POS receipts (client-side).
- CSV/XLSX: غير متوفر.
