# 17 — تحسين الصياغة بالذكاء الاصطناعي (AI Rewrite)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | تحسين الصياغة AI / AI Rewrite |
| Endpoint | `POST /api/rewrite` (Vercel Serverless — `api/rewrite.js`) |
| Provider | Gemini |
| الجداول | لا |
| SQL versioned | لا |
| الغرض | تحسين صياغة نص عربي (اجتماعات، مهام، ...). |

## 2) الصفحات

- زر "تحسين الصياغة" داخل شاشات Meetings/Tasks/Chat.

## 3) تحليل

- endpoint سرفرليس.
- v121: fetchWithTimeout 25s.
- استخدام يدوي (زر).

## 4) دورة العمل

نص خام → إرسال → Gemini → نص محسّن → استبدال.

## 5) الحالات

—

## 6) قاعدة البيانات

لا storage.

## 7) الـBackend

`api/rewrite.js` — CORS `*` (R-03).

## 8) الصلاحيات

الجميع (بلا Auth — R-03).

## 9) العلاقات

يخدم Meetings, Tasks, Chat, Decisions.

## 10) التقارير

—

## 11) الإشعارات

—

## 12) UI/UX

زر بسيط.

## 13) التكرارات

مع AI Assistant (خدمات Gemini مختلفة).

## 14) الاكتمال

Backend 70 | DB - | UI 70 | Perm 40 (R-03) | Workflow 80 | Notif - | Reports - | Cross 80 | Docs 70 | Tests 10 → **~65/100 (بلا Auth = مخاطرة)**.
**التصنيف:** 🔴 NEEDS_SECURITY_REWORK ثم ✅.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** توليد وصياغة (Text Assistant).
2. **الصفحات:** integrated buttons.
3. **APIs:** `/api/rewrite` + `/api/translate` + `/api/summarize`.
4. **قرار المالك:** تقييد Origin + Bearer.
5. **RLS.**
6. **Notifications.**
7. **AI:** Gemini + fallback.
8. **BI:** usage.
9. **Design:** inline.
10. **Mobile.**
11. **KPI:** usage per user.
12. **Cross-module:** كل النصوص الطويلة.
13. **Compliance:** لا تسريب.
14. **Roadmap Phase 1:** إصلاح R-03.
15. **Roadmap Phase 2:** توسيع.
16-28. توسيع.
