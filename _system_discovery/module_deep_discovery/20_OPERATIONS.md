# 20 — تشغيل المطاعم (Operations)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | تشغيل المطاعم / Restaurant Operations |
| Routes | 15 route (17204-17218) |
| DAL | `window.OPS` (~7132) |
| الجداول | 17 (`ops_*`) |
| SQL | `ops-schema-3a` + `3b` + `3c` |
| RPCs | `create_journal_for_ops_order`, `ops_apply_stock_transfer`, `ops_apply_waste_to_branch_inventory`, `can_access_branch_ops` |
| Feature flag | `operations` |
| الغرض | ورديات + قوائم فتح/إغلاق + خطط تحضير + طلبات مطعم + مخزون فرع + هدر + مشكلات. |
| الكيان المركزي | `ops_shifts` |

## 2) الصفحات

راجع `MODULE_INVENTORY §20`.
- Shift templates, shifts, shift detail, checklists, prep plans, orders, branch_inventory, stock_transfers, waste, issues, settings.

## 3) تحليل

- Dashboard + KPIs (وردية جارية، مشاكل مفتوحة، هدر).
- Kanban.
- Waste + Issues.

## 4) دورة العمل

فتح وردية → قوائم فتح → طلبات + تحضير + POS + Delivery → هدر + مشاكل → إغلاق وردية + handover.

## 5) الحالات

- `ops_shifts.status`: `draft → confirmed → completed`.
- `ops_orders.status`: `draft → confirmed → cancelled`.
- Others مفصلة في `WORKFLOW_STATUS_AUDIT §7`.

## 6) قاعدة البيانات

17 جدول. Triggers للـ inventory + waste.

## 7) الـBackend (DAL)

`window.OPS`.

## 8) الصلاحيات

- `operations_manager`, `branch_manager`, `deputy_manager`, `employee` (station).
- `is_ops_manager`, `can_access_branch_ops`.

## 9) العلاقات

- **يستقبل من:** Users, Branches, Menu.
- **يرسل إلى:** Accounting (order journal + inventory movements), POS (طلبات مطبخ داخلي).

## 10) التقارير

Waste, Issues, Prep plans, Shifts. `#ops_waste`, `#ops_issues`.

## 11) الإشعارات

Handovers, escalations.

## 12) UI/UX

`.mod-hero` (بعض)، بحاجة توحيد.

## 13) التكرارات

- `ops_orders` مقابل POS transactions (طلبات داخلية مقابل بيع).

## 14) الاكتمال

Backend 80 | DB 90 | RPCs 70 | UI 75 | Perm 85 | Workflow 80 | Notif 70 | Audit 60 | Reports 75 | Cross 80 | Docs 85 | Tests 15 → **~74/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION (real-time + POS link).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** تشغيل المطاعم (Restaurant Ops).
2. **الصفحات:** كل الحالية + `#ops_kitchen_display` (KDS)، `#ops_realtime_dashboard`.
3. **الجداول:** توسيع للـ station-level tracking.
4. **APIs:** `ops_start_shift`, `ops_close_shift_with_handover`, دوال real-time.
5. **Workflows:** kitchen display integration مع POS.
6. **قرار المالك:** KDS الآن أم Phase 2.
7. **RLS:** branch.
8. **Reports:** waste analysis، prep accuracy.
9. **Notifications:** issue escalation.
10. **Integrations:** POS + Menu.
11. **AI hook:** توقع الطلبات، تنبيهات هدر.
12. **BI.**
13. **Design.**
14. **Mobile:** priority عالي (line workers).
15. **KPI:** avg ticket time, waste %.
16. **Compliance:** HACCP.
17. **Cross-module:** HACCP (temperature at prep)، Menu (recipe changes).
18. **Data model.**
19. **Roadmap Phase 1:** POS integration realtime.
20. **Roadmap Phase 2:** KDS.
21. **Roadmap Phase 3:** AI forecasting.
22-28. توسيع.
