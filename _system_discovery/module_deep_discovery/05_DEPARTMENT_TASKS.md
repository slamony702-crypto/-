# 05 — المهام والتكليفات (Department Tasks)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | المهام والتكليفات / Department Tasks & Assignments |
| Routes | `#department_tasks` (`17295`) |
| الجداول | `department_tasks`, `task_projects`, `task_project_members`, `task_project_updates` |
| SQL versioned | ❌ (R-07) |
| الغرض | تكاليف مباشرة بين مدير وموظف — لا تشترط اجتماع. |
| الكيان المركزي | `department_tasks` |
| نقطة البداية | إسناد مباشر |
| نقطة النهاية | `completed` بعد مراجعة |
| هل مستقل؟ | نعم |
| الاسم واضح؟ | ⚠️ متداخل مع Action Items (راجع 04). |

## 2) الصفحات والمسارات

| Route | نوع | Backend | حالة |
|---|---|---|---|
| `#department_tasks` | Kanban + قائمة | 4 جداول | COMPLETE |

## 3) تحليل

- Kanban board (جديدة، جاري، مراجعة، مكتملة).
- تقويم مرئي.
- مشاريع (`task_projects`) — تجميع.
- تعليقات + مرفقات + subtasks.
- v121: batch inserts للـmembers/viewers.

## 4) دورة العمل

إسناد → إخطار → استلام → تفاوض (تعليق) → تنفيذ → مراجعة → اعتماد أو إعادة → completed.

## 5) الحالات

`new → in_progress → review → completed / cancelled`.

## 6) قاعدة البيانات

جداول بلا SQL versioned. FKs: `task_projects.id ← department_tasks.project_id`.

## 7) الـBackend

`pageDepartmentTasks` — يشمل filters + Kanban rendering.

## 8) الصلاحيات

المديرون يكلفون. الجميع ينفذ. RLS نعم.

## 9) العلاقات

- **يستقبل من:** Users, Departments, Meetings (تحويل يدوي من Action Items).
- **يرسل إلى:** notifications, conversations (chat خاص بالمهمة).

## 10) التقارير

- لوحة مهامي/فريقي.
- تحليل الأعباء (workload).
- المتأخرات.

## 11) الإشعارات

عند الإسناد، اقتراب الموعد، التأخر، التعليقات الجديدة.

## 12) UI/UX

- Kanban جيد.
- `.hero-card` قديم.
- Chat خاص بالمهمة.

## 13) التكرارات

**⚠️ Action Items** (راجع 04 §13).

## 14) الاكتمال

Backend 85 | DB 60 | UI 85 | Perm 80 | Workflow 85 | Notif 85 | Reports 75 | Cross 75 | Docs 85 | Tests 25 → **~74/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** التكاليف والمشاريع الداخلية (Internal Assignments).
2. **الصفحات:** `#tasks_hub`, `#task/:id`, `#projects`, `#project/:id`, `#tasks_kanban`, `#tasks_analytics`.
3. **الجداول:** إضافة `task_dependencies` (سلسلي)، `task_watchers`.
4. **APIs:** `task_from_meeting_action(id)`, `task_bulk_reassign`, `task_workload_by_user`.
5. **Workflow:** approval قبل completed.
6. **قرار المالك:** دمج مع Action Items أم تسميات أوضح.
7. **RLS:** assignee + manager + department.
8. **Reports:** workload balancing، cycle time.
9. **Notifications:** تصعيد ذكي.
10. **Integrations:** WhatsApp، Google Calendar.
11. **AI hook:** "مهامي اليوم"، "لخّص تقدم مشروع".
12. **Design:** hero موحد.
13. **Mobile:** priority عالي.
14. **Voice input:** إسناد بالصوت (Voice Search integration).
15. **Templates:** قوالب مهام متكررة.
16. **Subtasks:** مدعوم.
17. **Time tracking:** اختياري.
18. **KPI:** avg cycle time، backlog.
19. **BI:** productivity heatmap.
20. **Documentation:** فارق واضح مع Action Items.
21. **Data model:** حقل `source_type` (manual/meeting/incident/complaint).
22. **AI suggestion:** موعد واقعي.
23. **Compliance:** retention.
24. **Approval workflow:** متعدد المستويات (اختياري).
25. **Roadmap Phase 1:** dump schema + توضيح ARC.
26. **Roadmap Phase 2:** subtasks + dependencies.
27. **Roadmap Phase 3:** AI ranking + workload balancing.
28. **UI polish:** توحيد مع v123.
