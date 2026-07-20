# 30 — المستندات والعقود المؤسسية (Documents)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | إدارة المستندات / Documents Management |
| Routes | `#documents`, `#doc_list`, `#doc_detail`, `#doc_categories`, `#doc_expiring` (17265-17269) |
| DAL | `window.DOC` |
| الجداول | `doc_categories`, `doc_documents`, `doc_access_log` |
| SQL | `doc-schema-1.sql` |
| RPCs | `doc_log_access`, `doc_expire_overdue`, `is_doc_manager`, ترقيم |
| Feature flag | `documents` |
| الغرض | 14 تصنيف + polymorphic linking + سرية + سجل وصول. |
| الكيان المركزي | `doc_documents` |

## 2) الصفحات

5 routes.

## 3) تحليل

- 14 تصنيف مبذور (سجل تجاري، بلدية، دفاع مدني، صحية، ...).
- `tags[]` GIN index.
- `metadata JSONB`.
- `related_entity_type/id` polymorphic.
- `supersedes_id` للتاريخ.
- سرية (RLS).
- سجل وصول كامل (view/download).

## 4) دورة العمل

Upload → active → expired (بواسطة `doc_expire_overdue`) → archived.

## 5) الحالات

`active → expired → archived`.

## 6) قاعدة البيانات

3 جداول.

## 7) الـBackend

`window.DOC`.

## 8) الصلاحيات

`hr_manager`, `is_doc_manager`.

## 9) العلاقات

polymorphic — يخدم أي موديول.

## 10) التقارير

Expiring documents.

## 11) الإشعارات

Expiring soon (يحتاج cron).

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

`haccp_health_certificates` قد تُدار كـ documents.

## 14) الاكتمال

Backend 80 | DB 85 | RPCs 75 | UI 75 | Perm 80 | Workflow 75 | Notif 60 (لا cron) | Audit 85 | Reports 70 | Cross 90 | Docs 85 | Tests 15 → **~73/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة المستندات والعقود (DMS).
2. **الصفحات:** كل + `#doc_workflow` (approval), `#doc_signatures`, `#doc_templates`, `#doc_bulk_upload`.
3. **الجداول:** إضافة `doc_signatures`, `doc_workflows`, `doc_versions`.
4. **APIs:** `doc_request_signature`, `doc_lock_version`.
5. **Workflows:** signature workflow.
6. **قرار المالك:** توحيد HACCP certs مع documents.
7. **RLS.**
8. **Reports:** compliance report.
9. **Notifications:** cron scheduler (R-15).
10. **Integrations:** DocuSign.
11. **AI hook:** OCR + auto-tag.
12. **BI.**
13. **Design.**
14. **Mobile.**
15. **KPI:** expiry compliance.
16. **Compliance.**
17. **Roadmap Phase 1:** cron scheduler.
18. **Roadmap Phase 2:** signatures.
19-28. توسيع.
