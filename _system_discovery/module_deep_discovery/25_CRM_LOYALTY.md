# 25 — إدارة العملاء وبرنامج الولاء (CRM & Loyalty)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | CRM & Loyalty / علاقات العملاء والولاء |
| Routes | `#crm`, `#crm_customers`, `#crm_customer/:id`, `#crm_complaints`, `#crm_complaint/:id` (17226-17230) |
| DAL | `window.CRM` |
| الجداول | `crm_customers`, `crm_customer_addresses`, `loyalty_accounts`, `loyalty_transactions` (**ثابت**), `crm_complaints` |
| SQL | `crm-schema-1.sql` |
| RPCs | `loyalty_apply_transaction` (trigger), `crm_assign_customer_code`, `crm_assign_complaint_no`, `is_crm_manager` |
| Feature flag | `crm` |
| الغرض | عملاء + عناوين متعددة + ولاء + شكاوى بـ SLA. |
| الكيان المركزي | `crm_customers` |

## 2) الصفحات

- Dashboard, customers, customer detail, complaints, complaint detail.

## 3) تحليل

- ترقيم `CUS-00001` + `CMP-YYYY-00001`.
- **`loyalty_transactions` INSERT-only** (مصدر حقيقة). Trigger يحدّث `points_balance` + `lifetime_points`.
- Tiers: bronze → silver → gold → platinum.
- Complaint SLA (severity).
- **v120 fix #7:** addresses updated_at + default unique.

## 4) دورة العمل

Customer creation → addresses → loyalty auto-tracked from POS payment splits → complaint intake → resolution → close.

## 5) الحالات

- Complaint: open/in_progress/resolved/escalated.
- Loyalty: بلا حالة (سجل ثابت).

## 6) قاعدة البيانات

5 جداول.

## 7) الـBackend

`window.CRM`.

## 8) الصلاحيات

`operations_manager`, `is_crm_manager`.

## 9) العلاقات

- **يستقبل من:** POS (loyalty via trigger).
- **يرسل إلى:** POS, Delivery, Cafe (customer_id), CC (related_customer_id).

## 10) التقارير

Segments (`bi_customer_segments`), complaints.

## 11) الإشعارات

Complaint escalation.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

**⚠️ `crm_customers` مقابل `acct_customers` (R-08 عالية).**

## 14) الاكتمال

Backend 85 | DB 90 | RPCs 80 | UI 80 | Perm 80 | Workflow 80 | Notif 75 | Audit 70 | Reports 75 | Cross 85 | Docs 85 | Tests 20 → **~76/100**.
**التصنيف:** 🟡 NEEDS_STABILIZATION.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** علاقات العملاء والولاء (CRM 2.0).
2. **الصفحات:** كل + `#crm_campaigns`, `#crm_segments_ai`, `#crm_referrals`.
3. **الجداول:** توحيد مع `acct_customers` (R-08) + إضافة `crm_campaigns`, `crm_referrals`, `crm_customer_notes`.
4. **APIs:** `crm_merge_duplicates`, `crm_send_campaign`.
5. **Workflows:** complaint escalation matrix.
6. **قرار المالك:** توحيد العملاء (R-08).
7. **RLS.**
8. **Reports:** LTV, churn, NPS.
9. **Notifications:** birthday, complaint stages.
10. **Integrations:** WhatsApp Business, SMS.
11. **AI hook:** segmentation, next-best-offer.
12. **BI.**
13. **Design.**
14. **Mobile.**
15. **KPI:** LTV, NPS, retention.
16. **Compliance:** GDPR-like.
17. **Roadmap Phase 1:** توحيد + campaigns.
18. **Roadmap Phase 2:** WhatsApp + AI.
19. **Roadmap Phase 3:** referrals.
20-28. توسيع.
