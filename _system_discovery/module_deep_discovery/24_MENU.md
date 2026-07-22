# 24 — المنيو والوصفات (Menu)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | المنيو والوصفات / Menu Management |
| Routes | `#menu`, `#menu_categories`, `#menu_items`, `#menu_item/:id`, `#menu_settings` (17221-17225) |
| DAL | `window.MENU` (~7562) |
| الجداول | `menu_settings`, `menu_categories`, `menu_items`, `menu_item_recipes`, `menu_channel_prices` |
| SQL | `menu-schema-1.sql` |
| RPCs | `menu_compute_item_cost`, `is_menu_manager`, `menu_assign_sku` |
| Feature flag | `menu` |
| الغرض | قوائم طعام + BOM + أسعار قنوات (dine-in/takeaway/delivery). |
| الكيان المركزي | `menu_items` |

## 2) الصفحات

- Dashboard, Categories, Items (`MENU-00001`), Item detail, Settings.

## 3) تحليل

- BOM اختياري ← acct_inventory_items.
- `menu_compute_item_cost` من BOM أو manual.
- ترقيم `MENU-00001`.
- **v118 fix:** `menu_categories_name_ar_unique` + ON CONFLICT.

## 4) دورة العمل

Add category → Add item → Recipe (BOM) → Channel prices → Available.

## 5) الحالات

- `menu_items.is_available` / `is_active` (بدل status).

## 6) قاعدة البيانات

5 جداول.

## 7) الـBackend

`window.MENU`.

## 8) الصلاحيات

`operations_manager`, `is_menu_manager`.

## 9) العلاقات

- **يستقبل من:** `acct_inventory_items` (BOM).
- **يرسل إلى:** POS (snapshot), BI (top items via `bi_top_menu_items`).

## 10) التقارير

Top items, cost margin.

## 11) الإشعارات

—

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

—

## 14) الاكتمال

Backend 85 | DB 90 | RPCs 75 | UI 80 | Perm 80 | Workflow 80 | Notif 60 | Audit 65 | Reports 70 | Cross 85 | Docs 85 | Tests 20 → **~73/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة المنيو والوصفات (Menu Engineering).
2. **الصفحات:** كل الحالية + `#menu_engineering` (matrix ربحية × شعبية), `#menu_seasonal`, `#menu_photos`.
3. **الجداول:** إضافة `menu_variants`, `menu_modifiers`, `menu_combos`, `menu_allergens`.
4. **APIs:** `menu_bulk_price_update`, `menu_engineering_score`.
5. **Workflows:** approval لتغيير الأسعار.
6. **قرار المالك:** BOM إلزامي؟
7. **RLS.**
8. **Reports:** menu engineering matrix.
9. **Notifications:** margin drops.
10. **Integrations:** Delivery platforms (Jahez).
11. **AI hook:** توصيات ابتكار صنف.
12. **BI:** menu health.
13. **Design.**
14. **Mobile:** editor.
15. **KPI:** popularity, profitability.
16. **Compliance:** allergen disclosure.
17. **Roadmap Phase 1:** BOM إلزامي.
18. **Roadmap Phase 2:** modifiers/combos.
19. **Roadmap Phase 3:** AI engineering.
20-28. توسيع.
