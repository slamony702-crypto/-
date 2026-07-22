# 34 — الامتياز التجاري (Franchise)

## 1) هوية

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الفرنشايز / Franchise |
| Routes | `#franchise`, `#fr_partners`, `#fr_partner/:id`, `#fr_agreements`, `#fr_agreement/:id`, `#fr_reports`, `#fr_royalties` (17284-17290) |
| DAL | `window.FR` |
| الجداول | `franchise_partners`, `franchise_agreements`, `franchise_branches`, `franchise_sales_reports`, `franchise_royalty_invoices` |
| SQL | `fr-schema-1.sql` |
| RPCs | `franchise_compute_royalty` (ذرية), `franchise_issue_royalty`, `is_franchise_manager` |
| Feature flag | `franchise` |
| الغرض | شركاء + عقود + فروع فرنشايز + تقارير مبيعات + فواتير روياليتي. |
| الكيان المركزي | `franchise_agreements` |

## 2) الصفحات

7 routes.

## 3) تحليل

- Partners (`FR-00001`) — 5 حالات.
- Agreements (`FRA-YYYY-00001`) — 4 أنواع + royalty % + marketing % + min_royalty.
- Sales reports (`FSR-YYYYMM-0001`) — upsert لمنع تكرار.
- **v120 fix #8:** partial unique index (NULL branch).
- `franchise_compute_royalty` = net_sales × royalty% + marketing + VAT 15% + apply min_royalty.
- `franchise_issue_royalty` يُصدر.
- **ربط بـ AR** غير مفعّل تلقائيًا (R-14 — قرار المالك).

## 4) دورة العمل

Partner → Agreement → Branches → Monthly sales report → compute_royalty → invoice draft → issue → (يدوي: إنشاء `acct_invoices`).

## 5) الحالات

- Partner: `prospect → active → paused / on_hold → terminated`.
- Agreement: `draft → active → expired / terminated`.
- Sales report: `submitted → verified → royalty_computed`.
- Royalty invoice: `draft → issued → paid / cancelled`.

## 6) قاعدة البيانات

5 جداول.

## 7) الـBackend

`window.FR`.

## 8) الصلاحيات

`finance_manager`, `is_franchise_manager`.

## 9) العلاقات

- **يرسل إلى:** Accounting (AR — يدوي حاليًا).

## 10) التقارير

Royalties per period, partner performance.

## 11) الإشعارات

Report due, royalty issued.

## 12) UI/UX

`.mod-hero`.

## 13) التكرارات

`franchise_branches` مقابل `branches` — نطاقان مختلفان.

## 14) الاكتمال

Backend 75 | DB 85 | RPCs 85 | UI 75 | Perm 80 | Workflow 80 | Notif 65 | Audit 70 | Reports 70 | Cross 60 (لا AR link) | Docs 85 | Tests 15 → **~71/100**.
**التصنيف:** 🟠 NEEDS_BACKEND (AR link + بوابة).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** الفرنشايز والامتيازات (Franchise Management).
2. **الصفحات:** كل + `#franchisee_portal` (بوابة فرنشايزي مستقلة), `#fr_analytics`, `#fr_compliance`.
3. **الجداول:** توسع + `franchisee_users` (login منفصل).
4. **APIs:** `franchise_auto_ar_invoice`, `franchisee_upload_report`.
5. **Workflows:** بوابة تسجيل دخول منفصل.
6. **قرار المالك:** R-14 (AR link) + بوابة الآن أم Phase 2.
7. **RLS:** partner scope.
8. **Reports.**
9. **Notifications.**
10. **Integrations:** —
11. **AI hook:** compliance detection.
12. **BI.**
13. **Design.**
14. **Mobile:** بوابة موبايل للفرنشايزي.
15. **KPI:** revenue, compliance.
16. **Compliance:** brand standards.
17. **Roadmap Phase 1:** AR auto + بوابة MVP.
18. **Roadmap Phase 2:** compliance monitoring.
19. **Roadmap Phase 3:** analytics.
20-28. توسيع.
