# 15 — رؤية الشركة والأهداف (Company Vision)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | رؤية الشركة / Company Vision & Goals |
| Routes | `#vision` (`17166`) |
| الجداول | `company_vision`, `department_goals` |
| SQL versioned | `vision-schema.sql` (يحتاج تحقق) |
| الغرض | أساس OKR — رؤية + أهداف قسم. |

## 2) الصفحات

`#vision` — عرض الرؤية + أهداف الأقسام.

## 3) تحليل

- نص الرؤية.
- قائمة أهداف مع KPIs.

## 4) دورة العمل

تعريف رؤية سنوية → أهداف أقسام → متابعة → تقييم.

## 5) الحالات

يحتاج تحقق (NEEDS_RUNTIME_VERIFICATION).

## 6) قاعدة البيانات

جدولان.

## 7) الـBackend

`pageVision`.

## 8) الصلاحيات

- Admin/CM يعدل الرؤية.
- Dept managers يعدلون أهداف قسمهم.

## 9) العلاقات

يجب ربطه مع كل الموديولات كسياق KPI.

## 10) التقارير

—

## 11) الإشعارات

—

## 12) UI/UX

بسيط جدًا.

## 13) التكرارات

مع Performance (KPI).

## 14) الاكتمال

Backend 60 | DB 55 | UI 60 | Perm 75 | Workflow 50 | Notif 30 | Reports 40 | Cross 40 | Docs 50 | Tests 10 → **~47/100**.
**التصنيف:** 🟢 PILOT_READY (قابل للتوسع كـ OKR كامل).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** الأهداف الاستراتيجية (OKR / Vision & Goals).
2. **الصفحات:** `#vision`, `#okrs`, `#okr/:id`, `#okr_by_dept`, `#okr_progress`.
3. **الجداول:** توسع — `okr_objectives`, `okr_key_results`, `okr_quarterly_reviews`, `strategic_themes`.
4. **APIs:** `okr_progress_rollup`, `okr_align_with_kpi`.
5. **Workflows:** ربع سنوي review.
6. **قرار المالك:** تبني OKR كامل؟
7. **RLS:** dept-based.
8. **Reports:** progress heatmap.
9. **Notifications:** تذكيرات ربعية.
10. **Integrations:** —
11. **AI hook:** توليد أهداف SMART.
12. **BI:** strategic dashboard.
13. **Design:** hero + tree.
14. **Mobile.**
15. **Templates:** OKR templates.
16. **KPI ↔ OKR:** ربط.
17. **Cross-module:** Meeting → OKR alignment.
18. **Compliance.**
19. **Data model:** cascading (company → dept → team → person).
20. **Roadmap Phase 1:** OKR base.
21. **Roadmap Phase 2:** cascading + reviews.
22. **Roadmap Phase 3:** AI + BI.
23-28. توسيع.
