# 14 — طلبات الاجتماعات (Meeting Requests)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | طلبات الاجتماعات / Meeting Requests |
| Routes | `#meeting_requests` (`17323`) |
| الجداول | `meeting_requests`, `meeting_preparation_reports` |
| SQL versioned | ❌ |
| الغرض | تدفق طلب اجتماع + تقرير تحضيري. |

## 2) الصفحات

`#meeting_requests` — قائمة + إنشاء + مراجعة.

## 3) تحليل

- header + KPIs.
- فورم طلب.
- Preparation reports.
- تحويل لاجتماع فعلي.

## 4) دورة العمل

طلب → تقرير تحضيري → اعتماد → إنشاء `meetings` row.

## 5) الحالات

يحتاج تحقق (NEEDS_RUNTIME_VERIFICATION للحالات الدقيقة).

## 6) قاعدة البيانات

جدولان بلا SQL versioned.

## 7) الـBackend

`pageMeetingRequests`.

## 8) الصلاحيات

- الجميع (submit).
- Managers (approve).

## 9) العلاقات

- **يرسل إلى:** Meetings.
- **يستقبل من:** Users.

## 10) التقارير

—

## 11) الإشعارات

عند submission, approval.

## 12) UI/UX

بسيط.

## 13) التكرارات

مع Meetings (تدفق فرعي).

## 14) الاكتمال

Backend 80 | DB 55 | UI 75 | Perm 80 | Workflow 75 | Notif 75 | Reports 40 | Cross 80 | Docs 70 | Tests 15 → **~65/100**.
**التصنيف:** 🟢 PILOT_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** طلبات وتحضير الاجتماعات.
2. **الصفحات:** `#meeting_request`, `#request/:id`, `#preparation_reports`, `#request_analytics`.
3. **الجداول:** dump + توسيع reports.
4. **APIs:** `mr_convert_to_meeting`, `mr_reject_with_reason`.
5. **Workflows:** approval واضح.
6. **قرار المالك:** دمج مع Meetings كتبويب؟
7. **RLS.**
8. **Reports:** approval rate.
9. **Notifications.**
10. **AI hook:** توليد تقرير تحضيري.
11. **BI.**
12. **Design.**
13. **Mobile.**
14. **Templates.**
15. **KPI.**
16. **Cross-module:** Vision (طلب يرتبط بهدف).
17. **Voice input.**
18. **Compliance.**
19. **Roadmap Phase 1:** توحيد UI مع Meetings.
20. **Roadmap Phase 2:** AI generation.
21. **Roadmap Phase 3.**
22-28. توسيعات.
