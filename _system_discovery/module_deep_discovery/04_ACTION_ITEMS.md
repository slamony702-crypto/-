# 04 — مخرجات الاجتماعات (Action Items)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | مخرجات الاجتماعات / Meeting Action Items |
| Routes | `#tasks` (`index.html.html:17294`) |
| DAL | لا DAL منفصل |
| الجداول | `action_items` |
| SQL versioned | ❌ لا (R-07) |
| الغرض | تحويل نقاش الاجتماعات لتنفيذ فعلي بمسؤول وموعد. |
| الكيان المركزي | `action_items` |
| نقطة البداية | داخل اجتماع أو مستقل |
| نقطة النهاية | `completed` (بدليل إنجاز) |
| هل مستقل؟ | مرتبط بـ Meetings |
| الاسم واضح؟ | ⚠️ **مربك** — الاسم "tasks" في الـ route يتعارض مع "department_tasks" |
| المكان منطقي؟ | جزئي — يظهر في السايدبار كـ "المهام" وليس "المخرجات" |

## 2) الصفحات والمسارات

| Route | نوع | Backend | حالة |
|---|---|---|---|
| `#tasks` | قائمة + Kanban | `sb.from('action_items')` | COMPLETE |

## 3) تحليل الصفحة

- header + KPIs (مفتوح، متأخر، مكتمل).
- فلاتر (المسؤول، الأولوية، الاجتماع).
- Kanban أو List.
- تعليقات + مرفقات.
- إعادة إسناد.

## 4) دورة العمل

توليد من الاجتماع → إسناد → إشعار → تنفيذ → تحديث تقدم → دليل الإنجاز → مراجعة → completed.

## 5) الحالات

`open → in_progress → completed / cancelled` (+ `overdue` محسوبة عند `due_date < now()`).

## 6) قاعدة البيانات

`action_items` — بلا SQL versioned. أعمدة رئيسية: `id`, `meeting_id`, `title`, `description`, `assigned_to`, `assigned_by`, `due_date`, `priority`, `status`, `progress_percent`, `linked_task_id`.

## 7) الـBackend

استعلامات مباشرة في `pageTasks`.

## 8) الصلاحيات

- المسند: المدير أو منظم الاجتماع.
- المسؤول: الموظف المُسند.
- الجميع (invited to meeting): read.
- RLS: نعم.

## 9) العلاقات

- **يستقبل من:** Meetings.
- **يرسل إلى:** notifications، أحيانًا department_tasks (linked_task_id اختياري).

## 10) التقارير

- تقرير المتأخرات.
- نسبة التنفيذ للموظف.
- تقرير التنفيذ للاجتماع.

## 11) الإشعارات

- عند الإسناد، اقتراب الموعد (3 أيام + يوم قبل)، التأخر.

## 12) UI/UX

- `.hero-card` قديم.
- Kanban واضح.
- Loading states.

## 13) التكرارات

**⚠️ التكرار الأبرز في النظام:** `action_items` مقابل `department_tasks`. الفرق:
- `action_items`: تخرج من اجتماع، ترتبط بـ `meeting_id`.
- `department_tasks`: تكليف مباشر بين مدير وموظف.

الفرق مربك للمستخدم العادي (`DISCOVERY_SUMMARY_FOR_CHATGPT.md §15`).

## 14) مستوى الاكتمال

Backend 85 | DB 60 | UI 80 | Perm 80 | Workflow 85 | Notif 80 | Reports 70 | Cross 80 | Docs 85 | Tests 20 → **~72/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** المخرجات والالتزامات (Meeting Commitments).
2. **القسم:** التنفيذ والمتابعة.
3. **الصفحات:** `#action_items`, `#action_item/:id`, `#action_items_overdue`, `#action_items_by_meeting`.
4. **الجداول:** dump إلى SQL versioned + إضافة `action_item_evidence` (روابط لملفات دليل).
5. **APIs:** `action_convert_to_task(id)`, `action_reassign(id, new_user)`, `action_close_with_evidence(id, evidence_url)`.
6. **Workflows:** فرض دليل إنجاز قبل الإغلاق.
7. **قرار المالك:** إلغاء `action_items` ودمج في `department_tasks` بحقل `source_meeting_id`؟ أو الحفاظ مع تسمية أوضح ("التزامات الاجتماعات").
8. **قرار:** إعادة تسمية route من `#tasks` لـ `#action_items` لإزالة الالتباس.
9. **RLS:** meeting-attendee based.
10. **Reports:** تقرير أداء موظف في المخرجات.
11. **Notifications:** تصعيد ذكي (بعد يوم من التأخر → المدير).
12. **Integrations:** WhatsApp reminders.
13. **AI Assistant hook:** "مخرجاتي المتأخرة"، "مخرجات قسمي".
14. **BI:** action items health.
15. **Design:** hero موحد.
16. **Mobile:** priority للـmobile (يوظف في الميدان).
17. **Cross-module:** تحويل إلى Task أوتوماتيكي.
18. **Approval loop:** المسند يوافق قبل الإغلاق.
19. **KPI:** avg time to close, ratio in-time.
20. **AI suggestion:** اقتراح مسؤول مناسب.
21. **Voice input:** كتابة المخرج بالصوت.
22. **Compliance:** archive سنوات.
23. **Documentation:** توضيح الفرق مع Tasks بشكل رسمي.
24. **UX priority:** بحث سريع.
25. **Data model:** حقل `sub_actions` (subtasks).
26. **Dependencies:** ربط سلسلي (action A blocks action B).
27. **Roadmap Phase 1:** dump schema + تسمية جديدة.
28. **Roadmap Phase 2:** AI + convert to task.
