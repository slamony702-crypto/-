# 03 — الاجتماعات (Meetings)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الاجتماعات / Meetings Management |
| Routes | `#meetings`, `#meetings_calendar`, `#meeting_detail/:id`, `#meeting_requests` (`index.html.html:17291-17293, 17323`) |
| DAL | لا DAL منفصل — `pageMeetings`, `pageMeetingDetail` تستدعي `sb.from` مباشرة |
| الجداول | `meetings`, `meeting_attendees`, `meeting_agenda`, `meeting_tasks`, `meeting_requests`, `meeting_preparation_reports` |
| SQL versioned | جزئي — `meeting-minutes.sql` موجود، الجداول الأساسية بلا schema versioned (R-07) |
| الغرض التجاري | توثيق كامل للاجتماعات: جدولة، حضور، محضر، مخرجات، قرارات. |
| الكيان المركزي | `meetings` |
| نقاط البداية | إنشاء اجتماع (يدوي أو من قالب) |
| نقاط النهاية | `closed` (بعد تنفيذ كل المخرجات) |
| هل مستقل؟ | يعتمد على Users, Departments, Branches — لكن مركزي |
| هل الاسم واضح؟ | نعم |
| هل مكانه منطقي؟ | نعم (تحت `__exec` group) |

## 2) الصفحات والمسارات

| Route | نوع | Backend | Database | حالة |
|---|---|---|---|---|
| `#meetings` | قائمة + فلاتر | `sb.from('meetings')` مع limit 300 (v121) | `meetings` | COMPLETE |
| `#meetings_calendar` | تقويم | نفس | `meetings` | COMPLETE |
| `#meeting_detail/:id` | تفاصيل | متعدد | 6 جداول | COMPLETE |
| `#meeting_requests` | قائمة طلبات | نفس | `meeting_requests` | COMPLETE |

## 3) تحليل كل صفحة

- **`#meetings`:** header + KPIs (مجدول، جاري، مكتمل) + جدول + فلاتر (نوع، حالة، تاريخ). Loading skeleton. Empty state.
- **`#meetings_calendar`:** grid تقويمي بألوان hardcoded (`#12372F`, `#245B4B`) لكل نوع.
- **`#meeting_detail/:id`:** الأثقل — أجندة + حضور + محضر + مرفقات + مخرجات + قرارات. PDF export موجود.
- **`#meeting_requests`:** استعراض طلبات + preparation reports.

## 4) دورة العمل التفصيلية

**Happy Path:** إنشاء → دعوة → RSVP → تذكيرات (24h/1h/15m) → انعقاد → محضر مباشر (autosave 30s) → مخرجات + قرارات → توزيع → إغلاق بعد إنجاز المخرجات.

**Cancellation/Postponement:** حالة `cancelled` أو `postponed` قبل `completed`.

**Failure:** انقطاع أثناء الاجتماع → localStorage backup (NEEDS_RUNTIME_VERIFICATION — الكود يذكرها كتوقع).

## 5) الحالات والانتقالات

`scheduled → in_progress → completed → in_follow_up → closed` (+ `cancelled` / `postponed`).

## 6) قاعدة البيانات

جداول بلا SQL versioned (R-07). العلاقات: `meetings.id ← action_items.meeting_id`, `decisions.meeting_id`, `meeting_attendees.meeting_id`, `meeting_agenda.meeting_id`.

## 7) الـBackend

- `pageMeetings` — 300 limit (v121 pagination).
- `pageMeetingDetail` — يفتح 6 جداول متوازية.
- `pageMeetingsCalendar` — grid + join.
- `pageDeepDataMeetings` — تحليل.

## 8) الصلاحيات

الجميع (invited). `meeting_organizer` أو `department_manager` ينظم. Admin/CM يرون الكل. RLS نعم.

## 9) العلاقات

- **يرسل إلى:** `action_items`, `decisions`, `department_tasks` (تحويل يدوي)، `notifications` (تذكيرات).
- **يستقبل من:** Users, Departments.

## 10) التقارير

- تقارير الاجتماعات الشهرية.
- نسبة الحضور.
- زمن التنفيذ الوسيط للمخرجات.

## 11) الإشعارات

24h/1h/15m قبل الاجتماع. تنبيه للحضور المدعوين. تعتمد على `notifications` جدول.

## 12) UI/UX

- **Hero:** `.hero-card` نمط قديم.
- ألوان hardcoded في calendar.
- Loading states جيدة.
- **PDF export:** جيد.

## 13) التكرارات

- `meeting_tasks` مقابل `action_items` — نفس الفكرة تقريبًا، جدولان مختلفان (NEEDS_RUNTIME_VERIFICATION للحدود بينهما).
- `meeting_requests` مقابل `meetings` — الطلبات تنتقل لاجتماعات (تدفق يدوي).

## 14) مستوى الاكتمال

Backend 90 | DB 65 | UI 85 | Permissions 80 | Workflow 90 | Notifications 80 | Reports 70 | Cross 90 | Docs 85 | Tests 30 → **~76/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** الاجتماعات والحوكمة.
2. **القسم:** التنفيذ والمتابعة.
3. **الصفحات:** `#meetings` (dashboard), `#meeting/:id` (unified detail), `#meeting_templates`, `#meeting_calendar`, `#meeting_analytics`, `#meeting_archive`.
4. **الجداول:** dump إلى SQL versioned. توسيع: `meeting_recordings` (فيديو/صوت)، `meeting_transcripts` (AI transcription).
5. **APIs:** `meeting_create_from_template`, `meeting_convert_action_to_task`, `meeting_close_when_all_actions_done`.
6. **Workflows:** فرض إغلاق أوتوماتيكي عند إنجاز كل المخرجات.
7. **قرار المالك:** توحيد `meeting_tasks` مع `action_items` أو `department_tasks`.
8. **قرار:** فرض PDF محضر إلزامي قبل الإغلاق.
9. **RLS:** attendee-based + department-based.
10. **Reports:** attendance rate، execution rate.
11. **Notifications:** تذكيرات AI ذكية (خلاصة قبل الاجتماع).
12. **Integrations:** Zoom/Meet/Teams API لجدولة (Wave 4 int_providers).
13. **AI Assistant hook:** "أهم مخرجات آخر اجتماع"، "تلخيص محضر".
14. **BI:** meetings health snapshot.
15. **Design:** unified hero + KPI stripe.
16. **Mobile:** notes سريعة + push.
17. **Cross-module:** ربط مع Vision (كل اجتماع يعالج هدف).
18. **Templates library:** 10 قوالب مبذورة (تنفيذي/مالي/جودة/سلامة/...).
19. **KPI:** avg meeting duration، action items open ratio.
20. **Data model:** فصل `meeting_tasks` أو حذفه.
21. **AI transcription:** بديل السكرتير.
22. **Voting:** لتوثيق قرارات جماعية.
23. **Compliance:** archive 10 سنوات.
24. **UI polish:** توحيد `.hero-card` مع `.mod-hero` (v123).
25. **Search:** فهرسة نصية لمحاضر.
26. **Cross-module:** meeting → decision → task تسلسل تلقائي.
27. **Roadmap Phase 1:** dump schema + توحيد tasks.
28. **Roadmap Phase 2:** AI transcription + templates.
