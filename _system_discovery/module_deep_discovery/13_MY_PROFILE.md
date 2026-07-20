# 13 — الملف الشخصي (My Profile)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الملف الشخصي / My Profile |
| Routes | `#my_profile` (`17322`) |
| الجداول | يقرأ `users`, `notifications`, `meetings`, `department_tasks`, `action_items`, `hr_employee_profile` (لـ test_admin) |
| SQL versioned | ❌ |
| الغرض | لوحة شخصية بكل ما يخص الموظف. |

## 2) الصفحات

`#my_profile` — hero بصورة + KPIs + قوائم مختصرة.

## 3) تحليل

- v121: 4 استعلامات محدودة بـ 300.
- KPIs: اجتماعات قادمة، مهام مفتوحة، إشعارات، مخرجات.
- بيانات شخصية.

## 4) دورة العمل

فتح → عرض بيانات → تحديث محدود → التنقل لتفاصيل.

## 5) الحالات

—

## 6) قاعدة البيانات

Read only على `users` + جداول ملحقة.

## 7) الـBackend

`pageMyProfile`.

## 8) الصلاحيات

self only. RLS.

## 9) العلاقات

يستقبل من كل الموديولات الشخصية.

## 10) التقارير

- Personal dashboard.

## 11) الإشعارات

عرض قائمة.

## 12) UI/UX

`.hr-emp-hero` (HR variant).

## 13) التكرارات

مع HR `hr_employee_profile` (بيانات مكررة).

## 14) الاكتمال

Backend 75 | DB 60 | UI 80 | Perm 90 | Workflow 70 | Notif 80 | Reports 60 | Cross 85 | Docs 70 | Tests 20 → **~68/100**.
**التصنيف:** 🟢 PILOT_READY (يحتاج ربط أعمق مع HR).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** ملفي (My Hub).
2. **الصفحات:** `#me`, `#me/tasks`, `#me/meetings`, `#me/documents`, `#me/settings`, `#me/security`.
3. **الجداول:** لا حاجة جديدة.
4. **APIs:** aggregate واحد بدل 4 استعلامات.
5. **Workflows:** —
6. **قرار المالك:** توحيد مع HR employee profile؟
7. **RLS:** self.
8. **Reports:** أدائي شخصي.
9. **Notifications:** ملخصات يومية.
10. **Integrations:** Google Calendar sync.
11. **AI hook:** "لخّص يومي".
12. **BI:** personal KPIs.
13. **Design:** hero موحد (`.mod-hero` v123).
14. **Mobile:** priority.
15. **Sections:** tabs.
16. **Preferences:** theme + language.
17. **Security:** password change + sessions.
18. **KPI:** engagement.
19. **Compliance.**
20. **Data privacy:** control on visibility.
21. **Roadmap Phase 1:** توحيد hero + aggregation RPC.
22. **Roadmap Phase 2:** ربط HR profile.
23. **Roadmap Phase 3:** AI daily brief.
24. **UX polish.**
25. **Documentation.**
26. **Cross-module.**
27. **Avatar upload:** موجود (`user-avatars-setup.sql`).
28. **Templates.**
