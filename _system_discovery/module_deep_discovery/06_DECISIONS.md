# 06 — القرارات (Decisions)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | القرارات / Corporate Decisions |
| Routes | `#decisions` (`17296`) |
| الجداول | `decisions`, `decision_sub_responsibles`, `decision_viewers`, `decision_acknowledgments`, `decision_activity_log` |
| SQL versioned | ❌ (R-07) |
| الغرض | توثيق كل قرار مؤسسي بسبب ومسؤول وموعد وسجل. |
| الكيان المركزي | `decisions` |
| نقطة البداية | من اجتماع أو مبادرة مستقلة |
| نقطة النهاية | `executed` مع دليل، أو `cancelled` |
| هل مستقل؟ | مرتبط بـ Meetings + Users |
| الاسم واضح؟ | نعم |
| المكان منطقي؟ | نعم |

## 2) الصفحات والمسارات

| Route | نوع | حالة |
|---|---|---|
| `#decisions` | قائمة + تفاصيل modal | COMPLETE |

## 3) تحليل

- header + KPIs (نشط، منفذ، ملغى).
- تفاصيل: نص القرار + سبب + مسؤول رئيسي + فرعيون + مشاهدون + مرفقات + acknowledgments.
- سجل نشاط (`decision_activity_log`).

## 4) دورة العمل

الحاجة → دراسة → اتخاذ رسمي → إعلان → تنفيذ → تقارير دورية → executed مع تقييم أثر.

## 5) الحالات

`draft → active → executed / cancelled`.

## 6) قاعدة البيانات

5 جداول (raw), جداول بلا SQL versioned.

## 7) الـBackend

`pageDecisions` — v121: batch inserts للـ `decision_sub_responsibles` + `decision_viewers`.

## 8) الصلاحيات

الإدارة والمدراء يتخذون. المشاهدون يعلمون. RLS نعم.

## 9) العلاقات

- **يستقبل من:** Meetings (اختياري `meeting_id`).
- **يرسل إلى:** notifications، `department_tasks` (linked_task_id اختياري).

## 10) التقارير

- قرارات الشركة الشهرية.
- قرارات القسم.
- المتأخرة.

## 11) الإشعارات

عند الاتخاذ، اقتراب موعد التنفيذ، التنفيذ.

## 12) UI/UX

- `.hero-card` قديم.
- Acknowledgment ضعيف (لا فرض).
- Loading state جيد.

## 13) التكرارات

مع Meetings (قرارات مقابل مخرجات) — الفرق: القرار توجّه رسمي، المخرج تنفيذ محدد.

## 14) الاكتمال

Backend 85 | DB 60 | UI 85 | Perm 85 | Workflow 80 | Notif 80 | Reports 70 | Cross 80 | Docs 90 | Tests 20 → **~72/100**.
**التصنيف:** ✅ PRODUCTION_READY (بعد إصلاح acknowledgment + دليل التنفيذ).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** القرارات المؤسسية (Corporate Decisions).
2. **الصفحات:** `#decisions`, `#decision/:id`, `#decisions_archive`, `#decisions_analytics`, `#decisions_by_meeting`.
3. **الجداول:** dump + إضافة `decision_versions` (نسخ معدلة).
4. **APIs:** `decision_execute_with_evidence`, `decision_supersede(id, new_id)`.
5. **Workflows:** إلزام دليل تنفيذ + acknowledgment كل المشاهدين.
6. **قرار المالك:** فرض PDF قرار موقع.
7. **RLS:** viewers + role-based.
8. **Reports:** metric time-to-execute.
9. **Notifications:** تصعيد عند التأخر.
10. **Integrations:** DocuSign (تواقيع).
11. **AI Assistant hook:** "آخر 10 قرارات مؤسسية"، "قرارات لم تنفذ".
12. **BI:** decisions cycle time.
13. **Design:** hero + timeline.
14. **Cross-module:** ربط مع Documents (كل قرار = مستند).
15. **Voting:** تسجيل تصويت جماعي.
16. **Data model:** `impact_level` (strategic/tactical/operational).
17. **KPI:** execution rate.
18. **Compliance:** retention.
19. **Templates:** قوالب قرار.
20. **Approval flow:** متعدد المستويات.
21. **UX:** كتابة صوتية.
22. **Mobile:** priority read-only.
23. **Roadmap Phase 1:** dump + إلزام دليل.
24. **Roadmap Phase 2:** signatures + AI.
25. **Roadmap Phase 3:** analytics.
26. **Documentation:** فرق واضح مع action items.
27. **Search:** فهرسة نصية.
28. **UI polish:** v123.
