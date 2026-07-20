# 33 — التكاملات الخارجية (Integrations)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | التكاملات / Integrations |
| Routes | `#integrations`, `#int_marketplace`, `#int_connections`, `#int_connection/:id`, `#int_events` (17279-17283) |
| DAL | `window.INT` |
| الجداول | `int_providers`, `int_connections`, `int_webhook_endpoints`, `int_events` |
| SQL | `int-schema-1.sql` |
| RPCs | `int_log_event`, `int_complete_event`, `is_integrations_manager` |
| Feature flag | `integrations` |
| الغرض | 12 مزوّد config + webhooks + event log. |
| الكيان المركزي | `int_providers` |

## 2) الصفحات

- Dashboard, Marketplace, Connections, Connection detail, Events.

## 3) تحليل

- 12 مزوّد مبذور (WhatsApp Cloud، Twilio، Slack، Jahez، HungerStation، Mrsool، Mada Pay، STC Pay، ZATCA، Zapier، GA4، Webhook).
- `config_schema JSONB` → dynamic form.
- webhook endpoints.
- **Workers الفعلية غير موجودة** → UI_ONLY.

## 4) دورة العمل

Provider → Connection → Event: pending → sent / failed → retrying.

## 5) الحالات

- Connection: `active / paused / error`.
- Event: `pending → sent / failed → retrying`.

## 6) قاعدة البيانات

4 جداول.

## 7) الـBackend

`window.INT` + لا Edge Functions فعلية.

## 8) الصلاحيات

`is_integrations_manager` (admin/company_manager فقط).

## 9) العلاقات

يخدم كل الموديولات (POS, Delivery, CC, ...).

## 10) التقارير

Event log analysis (لا شاشة موحدة).

## 11) الإشعارات

Failure notifications.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

—

## 14) الاكتمال

Backend 40 (لا workers) | DB 80 | RPCs 65 | UI 70 | Perm 80 | Workflow 50 | Notif 55 | Audit 75 | Reports 40 | Cross 80 | Docs 80 | Tests 10 → **~60/100**.
**التصنيف:** 🟠 NEEDS_BACKEND (workers أولوية أولى).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** التكاملات الخارجية (Integrations Hub).
2. **الصفحات:** كل + `#int_playbooks`, `#int_test_console`, `#int_secrets_manager`.
3. **الجداول:** توسيع للـ retry policy per provider، secrets manager.
4. **APIs:** Edge Functions لكل مزوّد (12 dedicated).
5. **Workflows:** retry ذكي، circuit breaker.
6. **قرار المالك:** أولوية المزودين (Jahez أولاً؟).
7. **قرار:** Supabase Vault للـ secrets (R-05).
8. **RLS.**
9. **Reports:** provider health.
10. **Notifications:** provider down.
11. **Integrations:** —
12. **AI hook:** classification.
13. **BI:** integration health.
14. **Design.**
15. **Mobile.**
16. **KPI:** success rate per provider.
17. **Compliance:** PII masking.
18. **Roadmap Phase 1:** Jahez + WhatsApp workers + Vault.
19. **Roadmap Phase 2:** all 12 workers.
20. **Roadmap Phase 3:** advanced routing.
21-28. توسيع.
