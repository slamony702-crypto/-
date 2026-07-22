# 31 — مركز الاتصال (Call Center)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | مركز الاتصال / Call Center |
| Routes | `#call_center`, `#cc_agents`, `#cc_calls`, `#cc_call/:id`, `#cc_scripts`, `#cc_followups` (17270-17275) |
| DAL | `window.CC` |
| الجداول | `cc_agents`, `cc_dispositions`, `cc_calls`, `cc_scripts` |
| SQL | `cc-schema-1.sql` |
| RPCs | `cc_start_call`, `cc_end_call`, `is_cc_manager` |
| Feature flag | `call_center` |
| الغرض | Agents + Calls + Dispositions + Scripts + Followups + دمج مع CRM/POS/Delivery. |
| الكيان المركزي | `cc_calls` |

## 2) الصفحات

6 routes.

## 3) تحليل

- inbound/outbound.
- 7 أغراض، 11 نتيجة (dispositions مبذورة).
- 6 سكريبتات مبذورة.
- **v118 fix #3:** UNIQUE `cc_scripts.title`.

## 4) دورة العمل

Queue → start_call → in_progress + agent on_call → end_call → completed + agent available + إحصائيات.

## 5) الحالات

- Call: `queued → in_progress → completed / abandoned`.
- Agent: `available → on_call → busy / away / offline`.

## 6) قاعدة البيانات

4 جداول.

## 7) الـBackend

`window.CC`.

## 8) الصلاحيات

`operations_manager`, `is_cc_manager`.

## 9) العلاقات

- `related_customer_id` (CRM), `related_pos_transaction_id` (POS), `related_delivery_order_id` (Delivery).

## 10) التقارير

Calls, dispositions, followups.

## 11) الإشعارات

Followup reminders.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

`cc_calls.disposition` قد يعادل `complaint_created` (CRM) — بلا FK صريح.

## 14) الاكتمال

Backend 65 (لا PBX) | DB 85 | RPCs 80 | UI 75 | Perm 80 | Workflow 75 | Notif 70 | Audit 60 | Reports 60 | Cross 85 | Docs 85 | Tests 15 → **~65/100**.
**التصنيف:** 🟠 NEEDS_BACKEND (PBX integration مفقود).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** مركز الاتصال ومعالجة الشكاوى (Contact Center).
2. **الصفحات:** كل + `#cc_omnichannel` (WhatsApp/Email/SMS), `#cc_realtime_wallboard`.
3. **الجداول:** توسع للـ omnichannel + `cc_chat_sessions`, `cc_email_threads`.
4. **APIs:** `cc_pbx_start_call`, `cc_omnichannel_route`.
5. **Workflows:** IVR flows.
6. **قرار المالك:** PBX integration timing.
7. **RLS.**
8. **Reports:** service level (%).
9. **Notifications.**
10. **Integrations:** Twilio, WhatsApp Business, Zendesk-like.
11. **AI hook:** sentiment analysis, auto-summarization.
12. **BI.**
13. **Design.**
14. **Mobile.**
15. **KPI:** AHT, FCR, CSAT.
16. **Compliance:** call recording consent.
17. **Roadmap Phase 1:** PBX/Twilio.
18. **Roadmap Phase 2:** omnichannel.
19. **Roadmap Phase 3:** AI.
20-28. توسيع.
