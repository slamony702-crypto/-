# 10 — الجودة (Quality Visits)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الجودة / Quality Visits |
| Routes | `#quality`, `#quality_new`, `#quality_detail/:id`, `#quality_reports` (`17306-17309`) |
| الجداول | `quality_visits`, `quality_sections`, `quality_items`, `quality_visit_sections`, `quality_visit_items`, `quality_attachments` |
| SQL versioned | جزئي — `quality-schema.sql`, `quality-severity-role.sql` |
| الغرض | زيارات جودة دورية للفروع (نظافة، خدمة، معايير). |
| الكيان المركزي | `quality_visits` |

## 2) الصفحات والمسارات

| Route | نوع | حالة |
|---|---|---|
| `#quality` | قائمة | COMPLETE |
| `#quality_new` | فورم زيارة | COMPLETE |
| `#quality_detail/:id` | تفاصيل + تقييم | COMPLETE |
| `#quality_reports` | تقارير | COMPLETE |

## 3) تحليل

- header + KPIs (زيارات، نتيجة متوسطة).
- Sections + Items قابلة للتخصيص (kaталог).
- مرفقات (صور).
- تقييم بالدرجات.

## 4) دورة العمل

جدولة زيارة → إجراء (مسؤول الجودة) → تسجيل نقاط → مرفقات → submitted → approved.

## 5) الحالات

زيارة: `draft → submitted → approved`.

## 6) قاعدة البيانات

6 جداول. `quality_sections/items` كتالوج مشترك.

## 7) الـBackend

`pageQuality*`.

## 8) الصلاحيات

- `quality_manager` — Read/Write.
- `branch_manager` — يرى.
- RLS: نعم.

## 9) العلاقات

- **يرسل إلى:** notifications, reports.
- **يستقبل من:** Branches.

## 10) التقارير

`#quality_reports` — نتائج، اتجاهات، فروع أدنى تقييمًا.

## 11) الإشعارات

- عند submission، عند approval.

## 12) UI/UX

- `.hero-card` قديم.

## 13) التكرارات

قد يتداخل مع HACCP (سلامة غذاء) وMaintenance (صيانة).

## 14) الاكتمال

Backend 85 | DB 70 | UI 80 | Perm 80 | Workflow 80 | Notif 75 | Reports 75 | Cross 70 | Docs 85 | Tests 20 → **~72/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** الجودة والامتثال (Quality & Compliance).
2. **الصفحات:** `#quality`, `#visit/:id`, `#quality_templates`, `#quality_analytics`, `#quality_action_plans`.
3. **الجداول:** إضافة `quality_action_plans` (خطط تصحيحية بعد زيارة).
4. **APIs:** `quality_generate_action_plan(visit_id)`, `quality_score_branch(period)`.
5. **Workflows:** ربط تلقائي مع Action Items عند نتيجة منخفضة.
6. **قرار المالك:** توحيد الجودة مع HACCP؟
7. **RLS:** quality_manager + branch scope.
8. **Reports:** trend، ranking.
9. **Notifications:** عند فشل معيار، اقتراب زيارة.
10. **Integrations:** —
11. **AI hook:** تحليل الصور (image recognition).
12. **BI:** `bi_operations_health`.
13. **Design:** unified.
14. **Mobile:** priority.
15. **Templates:** 5+ قوالب زيارة.
16. **Photos:** قبل/بعد.
17. **KPI:** avg score, standard failure rate.
18. **Cross-module:** ربط بـ Performance (KPI فرع).
19. **Compliance:** archive.
20. **Voice input:** ملاحظات صوتية.
21. **Data model:** severity per item.
22. **Roadmap Phase 1:** action plans.
23. **Roadmap Phase 2:** AI image.
24. **Roadmap Phase 3:** cross-standard mapping.
25. **UX polish:** v123.
26. **Templates library:** SASO/ISO.
27. **Auto-schedule:** cron.
28. **Documentation.**
