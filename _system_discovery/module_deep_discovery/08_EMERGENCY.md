# 08 — تواصل طارئ (Emergency Communications)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | تواصل طارئ / Emergency Communications |
| Routes | `#emergency` (`17301`) |
| الجداول | `emergency_alerts`, `emergency_recipients`, `emergency_activity_log` |
| SQL versioned | ❌ (R-07) |
| الغرض | قناة طوارئ (تسمم، حريق، أعطال، شكاوى خطيرة). |
| الكيان المركزي | `emergency_alerts` |
| نقاط | من `active` إلى `resolved` (بلا SLA زمني مفروض — WORKFLOW_STATUS_AUDIT §Open-ended) |

## 2) الصفحات والمسارات

`#emergency` — قائمة + إنشاء بث + استقبال.

## 3) تحليل

- header أحمر مميز.
- نموذج بث (نص + مستوى + نطاق).
- v121: batch inserts للـ `emergency_recipients` + `notifications`.
- إجبار الاستلام.

## 4) دورة العمل

وقوع → بلاغ → بث فوري → استلام + استجابة → متابعة → resolved + تقرير.

## 5) الحالات

`active → resolved`.

## 6) قاعدة البيانات

3 جداول بلا SQL versioned.

## 7) الـBackend

`pageEmergency`.

## 8) الصلاحيات

- من يرسل: admin, company_manager, branch_manager, quality_manager, maintenance_officer.
- من يستقبل: الكل حسب النطاق.

## 9) العلاقات

- **يرسل إلى:** notifications (bulk).

## 10) التقارير

- عدد الطوارئ الشهرية.
- سرعة الاستجابة.

## 11) الإشعارات

- Push بصوت مميز.
- إجبار استلام.

## 12) UI/UX

- Design أحمر مميز.
- لا محاكاة صوت اختباري واضح.

## 13) التكرارات

مع Notifications + Chat (يستخدم بنية `conversations` جزئيًا).

## 14) الاكتمال

Backend 80 | DB 55 | UI 75 | Perm 85 | Workflow 70 | Notif 90 | Reports 50 | Cross 70 | Docs 80 | Tests 15 → **~67/100**.
**التصنيف:** ✅ PRODUCTION_READY (لكن SLA بحاجة).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة الطوارئ والاستجابة (Incident Response).
2. **الصفحات:** `#emergency` (dashboard), `#emergency/:id`, `#emergency_playbooks`, `#emergency_drills`.
3. **الجداول:** dump. إضافة `emergency_playbooks` (خطوات استجابة موحدة)، `emergency_response_log`.
4. **APIs:** `emergency_broadcast_all_branches`, `emergency_escalate(id, level)`, `emergency_close_with_report`.
5. **Workflows:** SLA زمني (min/max response time بحسب level).
6. **قرار المالك:** ربط تلقائي مع HACCP incidents؟
7. **RLS:** manager-based scope.
8. **Reports:** trend analysis (شهري/ربعي).
9. **Notifications:** SMS + WhatsApp + Push + Email.
10. **Integrations:** Twilio SMS (Wave 4).
11. **AI hook:** تصنيف تلقائي، اقتراح خطة استجابة.
12. **BI:** operations_health بالفعل يستقبل.
13. **Design:** hero أحمر + priority.
14. **Mobile:** push بصوت خاص.
15. **Cross-module:** ربط مع Maintenance (طارئ صيانة), HACCP (طارئ سلامة), CRM (شكوى خطرة).
16. **Playbooks:** خطوات موحدة.
17. **Drills:** تدريبات دورية.
18. **KPI:** response time p95, false positive rate.
19. **Voice input:** بث بالصوت.
20. **Location:** إحداثيات GPS اختيارية.
21. **Compliance:** archive 5+ سنوات.
22. **Templates:** قوالب رسائل.
23. **Roadmap Phase 1:** SLA + playbooks.
24. **Roadmap Phase 2:** Twilio + drills.
25. **Roadmap Phase 3:** AI triage.
26. **UX polish:** v123.
27. **Data model:** `severity` enum (critical/high/med/low).
28. **Documentation:** إجراءات صارمة.
