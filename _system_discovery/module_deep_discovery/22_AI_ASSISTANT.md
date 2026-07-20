# 22 — المساعد الذكي (AI Assistant)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | المساعد الذكي / AI Assistant |
| Routes | `#ai_assistant`, `#ai_settings` (17219-17220) |
| DAL | `window.AIA` (~7397) |
| الجداول | `ai_settings`, `ai_sessions`, `ai_session_messages`, `ai_audit_log` |
| SQL | `ai-schema-1-assistant.sql` |
| Endpoint | `POST /api/agent` (Gemini function-calling) |
| الأدوات (7) | `get_overdue_tasks`, `get_branches_status`, `get_expiring_documents`, `get_financial_summary`, `get_recent_decisions`, `get_open_maintenance_requests`, `get_partners_settlements` |
| Feature flag | `ai_agents` |
| الغرض | مساعد ذكي قراءة فقط بـ 7 أدوات + RLS + audit log. |
| الكيان المركزي | `ai_sessions` |

## 2) الصفحات

- `#ai_assistant` — Chat UI.
- `#ai_settings` — إعدادات (system prompt, extra instructions).

## 3) تحليل

- 4-step conversation loop (HANDOFF §بنود مؤجلة).
- Client-side tool execution → RLS تلقائي.
- audit فقط للـ writes (لا يوجد writes حاليًا).
- v121: fetchWithTimeout 60s.

## 4) دورة العمل

user → Gemini → tool call → client executes with RLS → result → Gemini → final answer.

## 5) الحالات

`ai_sessions` بلا حالة إغلاق واضحة (WORKFLOW §Open-ended).

## 6) قاعدة البيانات

4 جداول + audit.

## 7) الـBackend

`api/agent.js` (Gemini) + `window.AIA`.

## 8) الصلاحيات

- كل الأدوار (بلا Auth حقيقي لـ endpoint - R-04).
- RLS: قراءة تلقائية حسب المستخدم.

## 9) العلاقات

يقرأ من: Tasks, Branches, Documents, Accounting, Decisions, Maintenance, Payments.

## 10) التقارير

- Audit log queries.

## 11) الإشعارات

—

## 12) UI/UX

Chat UI.

## 13) التكرارات

—

## 14) الاكتمال

Backend 65 | DB 85 | RPCs 60 | UI 75 | Perm 40 (R-04) | Workflow 70 | Notif 50 | Audit 80 | Reports 40 | Cross 75 | Docs 85 | Tests 10 → **~62/100**.
**التصنيف:** 🟠 NEEDS_BACKEND + 🔴 NEEDS_SECURITY_REWORK (R-04 حرجة).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** المساعد الذكي المؤسسي (Enterprise AI Agent).
2. **الصفحات:** `#ai_assistant`, `#ai_history`, `#ai_settings`, `#ai_tools_catalog`, `#ai_audit`.
3. **الجداول:** توسيع audit (search, filter).
4. **الأدوات:** 7 حالية + توسع لـ 30+ (كل موديول 2-3 أدوات).
5. **APIs:** Bearer flow لـ `/api/agent` (R-04).
6. **Workflows:** approval قبل writes (مستقبلية).
7. **قرار المالك:** توسع لـ writes (create task, schedule meeting)؟
8. **RLS:** موحد.
9. **Reports:** usage analytics.
10. **Notifications:** —
11. **Integrations:** Gemini + fallback (Claude/OpenAI).
12. **AI hook:** كل موديول.
13. **BI:** usage metrics.
14. **Design:** chat UI.
15. **Mobile:** priority.
16. **KPI:** tool success rate.
17. **Compliance:** لا تسريب.
18. **Roadmap Phase 1:** R-04 + توسع أدوات.
19. **Roadmap Phase 2:** writes بحرص.
20. **Roadmap Phase 3:** proactive suggestions.
21. **Voice input:** integrated.
22. **Threading:** session-based.
23. **Templates:** أسئلة شائعة.
24. **UX polish.**
25. **Documentation:** كتيب أدوات.
26. **Fallback provider.**
27. **Cost control.**
28. **Cross-module discipline.**
