# 28 — الأداء والأهداف (Performance)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الأداء والأهداف / Performance Management |
| Routes | `#performance`, `#perf_kpis`, `#perf_scorecards`, `#perf_scorecard/:id`, `#perf_reviews`, `#perf_review/:id`, `#perf_goals` (17252-17258) |
| DAL | `window.PERF` |
| الجداول | `perf_kpi_definitions`, `perf_scorecards`, `perf_scorecard_entries`, `perf_reviews`, `perf_goals` |
| SQL | `perf-schema-1.sql` |
| RPCs | `perf_compute_scorecard_score`, `is_perf_manager`, ترقيم |
| Feature flag | `performance` |
| الغرض | KPI + سكوركاردات (فرع/موظف) + تقييمات دورية + أهداف SMART. |
| الكيان المركزي | `perf_scorecards` |

## 2) الصفحات

7 routes.

## 3) تحليل

- 3 أنواع أهداف: higher_better / lower_better / range.
- weighted average → 0-150 → A+ (≥110) / A (95) / B (80) / C (65) / D (50) / F.
- 9 KPIs مبذورة.
- **v120 fix #6:** partial unique indexes.

## 4) دورة العمل

Define KPIs → Scorecard شهري → tally entries → compute score → review دوري → employee acknowledgment.

## 5) الحالات

- Scorecard: `draft → submitted → approved → published`.
- Review: `draft → submitted_by_reviewer → acknowledged_by_employee → completed`.
- Goal: `draft → active → completed / cancelled`.

## 6) قاعدة البيانات

5 جداول.

## 7) الـBackend

`window.PERF`.

## 8) الصلاحيات

`hr_manager`, `is_perf_manager`.

## 9) العلاقات

- **يستقبل من:** HR (employees), Users.
- **يرسل إلى:** BI.

## 10) التقارير

Scorecard rankings.

## 11) الإشعارات

Review scheduled, acknowledgment required.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

مع Vision (Goals) — يمكن دمج.

## 14) الاكتمال

Backend 80 | DB 85 | RPCs 80 | UI 75 | Perm 80 | Workflow 80 | Notif 75 | Audit 70 | Reports 70 | Cross 75 | Docs 85 | Tests 15 → **~72/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة الأداء (Performance Management).
2. **الصفحات:** كل + `#perf_360` (360-degree), `#perf_talent_matrix` (9-box), `#perf_dev_plans`.
3. **الجداول:** توسع لـ 360 + talent matrix.
4. **APIs:** `perf_auto_compute_from_bi`, `perf_link_to_okr`.
5. **Workflows:** review cycle موحد.
6. **قرار المالك:** ربط تلقائي مع KPI من BI.
7. **RLS.**
8. **Reports.**
9. **Notifications.**
10. **Integrations:** —
11. **AI hook:** review draft.
12. **BI:** performance dashboard.
13. **Design.**
14. **Mobile.**
15. **KPI:** review completion rate.
16. **Compliance:** OKR framework.
17. **Roadmap Phase 1:** ربط BI.
18. **Roadmap Phase 2:** 360.
19-28. توسيع.
