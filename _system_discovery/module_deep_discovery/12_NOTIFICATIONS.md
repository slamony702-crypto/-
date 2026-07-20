# 12 — الإشعارات (Notifications)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الإشعارات / Notifications |
| Routes | `#notifications` (`17311`) |
| الجداول | `notifications` |
| SQL versioned | ❌ (R-07) |
| الغرض | مركز إشعارات موحد لكل الموديولات. |
| الكيان المركزي | `notifications` |

## 2) الصفحات

`#notifications` — inbox + قراءة/عدم قراءة.

## 3) تحليل

- header + جدول + فلاتر.
- Read/Unread state.
- Dropdown في الشريط العلوي (UI_AUDIT §10).

## 4) دورة العمل

جدول insert من كل موديول → عرض → قراءة → أرشفة.

## 5) الحالات

`is_read` boolean.

## 6) قاعدة البيانات

`notifications` — بلا SQL versioned. أعمدة: `user_id`, `title`, `body`, `type`, `link`, `is_read`, `created_at`.

## 7) الـBackend

- إما trigger أو DAL manual insert من كل موديول.

## 8) الصلاحيات

- الجميع (self only).
- RLS: نعم.

## 9) العلاقات

مركزي — يستقبل من كل الموديولات.

## 10) التقارير

- Unread count per user.

## 11) الإشعارات

هو نفسه.

## 12) UI/UX

- Dropdown top bar.
- لا "mark all as read" واضح (NEEDS_RUNTIME_VERIFICATION).

## 13) التكرارات

`emergency_alerts` يستخدم `notifications` bulk insert.

## 14) الاكتمال

Backend 75 | DB 55 | UI 70 | Perm 85 | Workflow 75 | Notif 90 | Reports 40 | Cross 95 | Docs 75 | Tests 15 → **~68/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** مركز الإشعارات (Notification Center).
2. **الصفحات:** `#notifications`, `#notification_settings`.
3. **الجداول:** dump. إضافة `notification_channels_prefs` (email/push/whatsapp).
4. **APIs:** `notification_mark_all_read`, `notification_bulk_delete`.
5. **Workflows:** batching + digest يومي.
6. **قرار المالك:** أولوية القنوات.
7. **RLS:** self.
8. **Reports:** delivery rate.
9. **Notifications channels:** email + push + WhatsApp + SMS.
10. **Integrations:** Twilio, WhatsApp Business (Wave 4).
11. **AI hook:** priority sorting.
12. **BI:** engagement.
13. **Design:** unified inbox.
14. **Mobile:** push priority.
15. **Preferences:** per user + per module.
16. **Grouping:** by type.
17. **KPI:** avg time to read.
18. **Compliance.**
19. **Data model:** `severity`.
20. **Snooze:** مؤجل.
21. **Roadmap Phase 1:** preferences + digest.
22. **Roadmap Phase 2:** WhatsApp/SMS.
23. **Roadmap Phase 3:** AI priority.
24. **UX polish:** v123.
25. **Search.**
26. **Cross-module:** deep-links.
27. **Silent hours:** قابل للتخصيص.
28. **Documentation.**
