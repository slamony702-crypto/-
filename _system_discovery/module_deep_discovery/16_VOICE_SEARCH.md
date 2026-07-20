# 16 — البحث الصوتي والأوامر (Voice Search)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | البحث الصوتي / Voice Search & Commands |
| Routes | `#search` (`17312`) |
| API | Web Speech API (متصفح) |
| الجداول | لا |
| SQL versioned | لا |
| الغرض | بحث نصي + صوتي عام. |

## 2) الصفحات

`#search` — inputbar + نتائج.

## 3) تحليل

- Web Speech API — `interimResults=true` (fix v107 لـ Android PWA — HANDOFF §تحسينات).
- تجميع النص في `onend`.
- بحث نصي أساسي.

## 4) دورة العمل

مايك → استقبال → تحويل نص → بحث → نتائج.

## 5) الحالات

—

## 6) قاعدة البيانات

يقرأ متعدد (اجتماعات، مهام، ...) — NEEDS_RUNTIME_VERIFICATION للنطاق الفعلي.

## 7) الـBackend

`pageGlobalSearch`.

## 8) الصلاحيات

الجميع (يفلتر بالـRLS).

## 9) العلاقات

يقرأ من كل الموديولات.

## 10) التقارير

—

## 11) الإشعارات

—

## 12) UI/UX

- مايك في الشريط العلوي.

## 13) التكرارات

—

## 14) الاكتمال

Backend 70 | DB 40 | UI 75 | Perm 80 | Workflow 65 | Notif 30 | Reports 30 | Cross 70 | Docs 60 | Tests 15 → **~55/100**.
**التصنيف:** 🟢 PILOT_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** المساعد الصوتي الشامل.
2. **الصفحات:** `#search`, `#voice_commands`.
3. **APIs:** بحث موحّد.
4. **Workflows:** أوامر صوتية (فتح صفحة، إسناد مهمة).
5. **قرار المالك:** توحيد مع AI Assistant.
6. **RLS.**
7. **Reports.**
8. **Integrations:** —
9. **AI hook:** LLM-based intent.
10. **BI.**
11. **Design.**
12. **Mobile.**
13. **KPI:** search success.
14. **Cross-module:** deep-links.
15. **Voice commands library.**
16-28. توسيع.
