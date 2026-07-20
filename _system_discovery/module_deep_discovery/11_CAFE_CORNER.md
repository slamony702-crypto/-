# 11 — ركن الكافيه (Cafe Corner)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | ركن الكافيه / Cafe Corner |
| Routes | `#cafe` (`17300`) |
| الجداول | `cafe_items`, `cafe_orders`, `cafe_order_items`, `cafe_order_status_log` |
| SQL versioned | `cafe-schema.sql`, `cafe-storage-bucket.sql` |
| RPC | `create_journal_for_cafe_order` |
| الغرض | نظام طلبات داخلي لركن كافيه (موظفين + زوار). |
| الكيان المركزي | `cafe_orders` |

## 2) الصفحات والمسارات

`#cafe` — قائمة + إضافة طلب + متابعة.

## 3) تحليل

- header + KPIs.
- كتالوج أصناف (`cafe_items`).
- طلبات جديدة + متابعة حالة.
- سجل حالات (`cafe_order_status_log`).

## 4) دورة العمل

طلب → preparing → ready → delivered → قيد GL آلي عبر `create_journal_for_cafe_order` (invoice source `cafe_order`).

## 5) الحالات

`pending → preparing → ready → delivered / cancelled`.

## 6) قاعدة البيانات

4 جداول + storage bucket للصور.

## 7) الـBackend

`pageCafe`.

## 8) الصلاحيات

- الجميع (طلب).
- إعداد الأصناف: admin/operations_manager.

## 9) العلاقات

- **يرسل إلى:** Accounting (invoice).
- **يستقبل من:** CRM (customer_id اختياري).

## 10) التقارير

- إيرادات الكافيه، الأصناف الأكثر طلبًا.

## 11) الإشعارات

عند الاستلام، الجاهزية، التسليم.

## 12) UI/UX

- UI قديم (UI_UX_AUDIT §8).

## 13) التكرارات

مع POS (يستطيع POS إجراء نفس الوظيفة).

## 14) الاكتمال

Backend 85 | DB 80 | UI 65 | Perm 80 | Workflow 80 | Notif 75 | Reports 70 | Cross 80 | Docs 80 | Tests 20 → **~73/100**.
**التصنيف:** ✅ PRODUCTION_READY (UI بحاجة تحديث).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** طلبات الكافيه الداخلية (Internal F&B).
2. **الصفحات:** `#cafe`, `#cafe_menu`, `#cafe_orders`, `#cafe_reports`.
3. **الجداول:** توسيع للـ multi-branch.
4. **APIs:** —
5. **Workflows:** ربط تلقائي مع POS للطلبات الخارجية.
6. **قرار المالك:** دمج مع POS؟ أو الحفاظ منفصل.
7. **RLS:** branch scope.
8. **Reports:** popular items، revenue.
9. **Notifications:** ready notification.
10. **Integrations:** —
11. **AI hook:** توصيات.
12. **BI:** revenue.
13. **Design:** v123.
14. **Mobile:** priority.
15. **Photos:** لكل صنف.
16. **Loyalty:** ربط مع CRM.
17. **KPI:** avg order value, prep time.
18. **Cross-module:** POS (اقتراح).
19. **Data model:** يتوسع.
20. **Roadmap Phase 1:** UI refresh.
21. **Roadmap Phase 2:** loyalty.
22. **Roadmap Phase 3:** dine-in app.
23. **UX polish.**
24. **Templates.**
25. **Documentation.**
26. **Compliance.**
27. **Search.**
28. **Archive.**
