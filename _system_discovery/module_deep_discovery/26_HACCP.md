# 26 — سلامة الغذاء (HACCP)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | سلامة الغذاء / HACCP |
| Routes | `#haccp`, `#haccp_equipment`, `#haccp_temperature`, `#haccp_batches`, `#haccp_certs`, `#haccp_incidents`, `#haccp_incident/:id`, `#haccp_settings` (17237-17244) |
| DAL | `window.HACCP` |
| الجداول | `haccp_settings`, `haccp_equipment`, `haccp_temperature_logs`, `haccp_food_batches`, `haccp_health_certificates`, `haccp_incidents` |
| SQL | `haccp-schema-1.sql` |
| RPCs | `haccp_compute_within_range` (trigger), `is_haccp_manager`, ترقيم |
| Feature flag | `haccp` |
| الغرض | معايير SASO 2233 + معدات + سجلات حرارة + دفعات + شهادات + حوادث. |
| الكيان المركزي | `haccp_incidents` (توحيد الحوادث) |

## 2) الصفحات

- Dashboard, equipment, temperature logs, batches (`BATCH-YYYYMMDD-00001`), health certificates, incidents (`HACCP-YYYY-00001`), settings.

## 3) تحليل

- SASO 2233 مبذور.
- `is_within_range` محسوب من trigger.
- ترقيم يومي للدفعات.
- منهجية حل: سبب جذري + تصحيحي + وقائي.

## 4) دورة العمل

- Batch: created → in_use → consumed/disposed.
- Temperature log: continuous.
- Incident: open → investigating → resolved → closed.

## 5) الحالات

راجع `WORKFLOW_STATUS_AUDIT §11`.

## 6) قاعدة البيانات

6 جداول.

## 7) الـBackend

`window.HACCP`.

## 8) الصلاحيات

`quality_manager`, `is_haccp_manager`.

## 9) العلاقات

- **يستقبل من:** HR (شهادات موظفين — تكرار مع `hr_employee_profile`).
- **يرسل إلى:** BI (`bi_operations_health`), Emergency (حالات خطيرة).

## 10) التقارير

incidents, breaches, certifications expiring.

## 11) الإشعارات

Alerts on out-of-range temperature, expiring certs.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

**⚠️ `haccp_health_certificates` مقابل بيانات HR — تكرار محتمل.**

## 14) الاكتمال

Backend 85 | DB 90 | RPCs 80 | UI 80 | Perm 80 | Workflow 85 | Notif 80 | Audit 75 | Reports 75 | Cross 75 | Docs 90 | Tests 20 → **~76/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** سلامة الغذاء والامتثال (HACCP / Food Safety).
2. **الصفحات:** كل + `#haccp_iot` (sensors), `#haccp_audit_trail`, `#haccp_ccps` (Critical Control Points).
3. **الجداول:** توسع للـ IoT: `haccp_sensor_readings`.
4. **APIs:** `haccp_generate_daily_report`, `haccp_export_audit`.
5. **Workflows:** incident escalation.
6. **قرار المالك:** توحيد الشهادات مع HR.
7. **RLS.**
8. **Reports:** SASO compliance report.
9. **Notifications:** breach alerts.
10. **Integrations:** IoT (thermometers) — Wave 4 int_providers.
11. **AI hook:** anomaly detection.
12. **BI:** operations_health.
13. **Design.**
14. **Mobile:** priority (field workers).
15. **KPI:** breach rate.
16. **Compliance:** SASO 2233 + SFDA.
17. **Roadmap Phase 1:** IoT + توحيد certs.
18. **Roadmap Phase 2:** AI anomaly.
19. **Roadmap Phase 3.**
20-28. توسيع.
