# 07 — التواصل الداخلي (Internal Chat)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | التواصل الداخلي / Internal Communications |
| Routes | `#conversations`, `#dept_chat/:id`, `#custom_chat/:id` (`17297-17299`) |
| الجداول | `conversations`, `conversation_members`, `messages`, `message_reads` |
| SQL versioned | جزئي — `custom-chats-schema.sql` موجود. الأساسي بلا versioned (R-07) |
| الغرض | تواصل مؤسسي محفوظ بدل واتساب. |
| الكيان المركزي | `conversations` |
| نقاط | لا "إغلاق" — يستمر للأبد |

## 2) الصفحات والمسارات

| Route | نوع | حالة |
|---|---|---|
| `#conversations` | inbox | COMPLETE |
| `#dept_chat/:id` | قناة قسم | COMPLETE |
| `#custom_chat/:id` | محادثة مخصصة | COMPLETE |

## 3) تحليل

- Inbox + list.
- 1:1 + جماعي + قناة قسم.
- v121: pagination 300.
- تنسيق (bold, ألوان).
- مرفقات (صور، PDF).
- ذكر @mention.
- تحرير + حذف soft.
- Read receipts.

## 4) دورة العمل

بدء → تبادل مستمر → أرشفة تلقائية.

## 5) الحالات

على مستوى الرسالة: `sent → read → edited / deleted (soft)`.

## 6) قاعدة البيانات

`conversations` + `messages` + `message_reads` + `conversation_members`. بلا SQL versioned.

## 7) الـBackend

`pageConversations`, `pageDeptChat`, `pageCustomChat`.

## 8) الصلاحيات

الجميع. RLS: `conversation_members` تحدد الوصول.

## 9) العلاقات

- **يستقبل:** meeting-related chats، task-related chats.
- **يرسل:** notifications.

## 10) التقارير

- المحادثات النشطة.
- الرسائل غير المقروءة.
- audit trail per employee.

## 11) الإشعارات

Push فوري للرسائل الجديدة. لا SLA على unread.

## 12) UI/UX

- WhatsApp-like.
- typing indicator (NEEDS_RUNTIME_VERIFICATION).
- No presence indicator موحد.
- Loading tail (pagination) للمحادثات الطويلة.

## 13) التكرارات

`emergency_alerts` يستخدم `conversations` structure (بنية مشتركة).

## 14) الاكتمال

Backend 80 | DB 55 | UI 80 | Perm 80 | Workflow 75 | Notif 85 | Reports 50 | Cross 75 | Docs 75 | Tests 15 → **~68/100**.
**التصنيف:** ✅ PRODUCTION_READY (لكن بحاجة تحسينات).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** التواصل والتعاون الداخلي.
2. **الصفحات:** `#chat_hub`, `#thread/:id`, `#channels`, `#dms`, `#chat_search`, `#chat_archive`.
3. **الجداول:** dump schemas. إضافة `chat_reactions`, `chat_pinned`, `chat_polls`.
4. **APIs:** `chat_search(query)`, `chat_pin(msg_id)`, `chat_poll_create`.
5. **Workflows:** channels تلقائية لكل branch/dept.
6. **قرار المالك:** encryption at rest?
7. **RLS:** members-based موحد.
8. **Reports:** engagement per channel.
9. **Notifications:** ذكاء اصطناعي (priority messages).
10. **Integrations:** WhatsApp Business (Wave 4).
11. **AI hook:** تلخيص محادثة، بحث ذكي.
12. **BI:** engagement metrics.
13. **Design:** unified.
14. **Mobile:** priority.
15. **Presence:** online/offline/typing.
16. **Voice messages:** aim.
17. **Data model:** `thread_id` (threading).
18. **Compliance:** retention 3+ سنوات.
19. **KPI:** avg response time.
20. **UX polish:** توحيد.
21. **Data export:** compliance.
22. **Roadmap Phase 1:** dump + presence.
23. **Roadmap Phase 2:** threading + polls.
24. **Roadmap Phase 3:** AI summarization.
25. **Search UX:** advanced filters.
26. **Attachments:** حجم أقصى + antivirus.
27. **Encryption:** at rest.
28. **Real-time:** Supabase Realtime (verify).
