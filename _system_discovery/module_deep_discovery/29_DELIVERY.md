# 29 — التوصيل الداخلي (Delivery)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | التوصيل الداخلي / Delivery |
| Routes | `#delivery`, `#dlv_zones`, `#dlv_riders`, `#dlv_orders`, `#dlv_order/:id`, `#dlv_settings` (17259-17264) |
| DAL | `window.DLV` |
| الجداول | `delivery_settings`, `delivery_zones`, `delivery_riders`, `delivery_orders`, `delivery_tracking` |
| SQL | `dlv-schema-1.sql` |
| RPCs | `delivery_assign_rider`, `delivery_update_status`, `delivery_mark_delivered`, `is_delivery_manager`, ترقيم |
| Feature flag | `delivery` |
| الغرض | مناطق (دائرية) + سائقين + طلبات (9 حالات) + Kanban. |
| الكيان المركزي | `delivery_orders` |

## 2) الصفحات

- Dashboard, zones, riders, orders (Kanban), order detail, settings.

## 3) تحليل

- زون دائري (radius + fee + eta).
- Rider status: available / busy / offline.
- **3 دوال ذرية** + tracking ثابت.
- 9 حالات (WORKFLOW §10).
- **v120 fix #10:** `CASE WHEN current_orders <= 1` in mark_delivered.

## 4) دورة العمل

new → assigned (assign_rider يزيد current_orders) → preparing → ready_for_pickup → picked_up → on_the_way → delivered (mark_delivered يقلل + يعيد available).

## 5) الحالات

9 حالات.

## 6) قاعدة البيانات

5 جداول + `delivery_tracking` ثابت (log).

## 7) الـBackend

`window.DLV`.

## 8) الصلاحيات

`operations_manager`, `is_delivery_manager`.

## 9) العلاقات

- **يستقبل من:** POS (اختياري)، CRM.
- **يرسل إلى:** BI (`bi_delivery_kpis`).

## 10) التقارير

KPIs delivery.

## 11) الإشعارات

Status changes.

## 12) UI/UX

Kanban board.

## 13) التكرارات

مع Ops orders (طلبات مطبخ).

## 14) الاكتمال

Backend 85 | DB 90 | RPCs 90 | UI 80 | Perm 85 | Workflow 85 | Notif 75 | Audit 75 | Reports 75 | Cross 85 | Docs 85 | Tests 20 → **~78/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION (لا PWA سائق).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** التوصيل والسائقين (Last-Mile Delivery).
2. **الصفحات:** كل + `#dlv_driver_app`, `#dlv_realtime_map`, `#dlv_earnings`.
3. **الجداول:** توسع للـ tracking GPS + earnings.
4. **APIs:** `dlv_dispatch_auto` (auto-assignment), `dlv_realtime_broadcast`.
5. **Workflows:** إسناد ذكي.
6. **قرار المالك:** بناء PWA سائق الآن؟
7. **RLS.**
8. **Reports:** rider earnings.
9. **Notifications.**
10. **Integrations:** خرائط، دفع.
11. **AI hook:** ETA prediction.
12. **BI.**
13. **Design:** driver-first.
14. **Mobile:** priority أعلى.
15. **KPI:** avg delivery time.
16. **Compliance:** insurance.
17. **Roadmap Phase 1:** PWA سائق.
18. **Roadmap Phase 2:** integration منصات.
19-28. توسيع.
