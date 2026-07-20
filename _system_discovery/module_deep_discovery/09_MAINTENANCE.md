# 09 — الصيانة (Maintenance)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| العربي/الإنجليزي | الصيانة / Maintenance Management |
| Routes | `#maintenance`, `#maintenance_new`, `#maintenance_detail/:id`, `#maintenance_suppliers`, `#maintenance_equipment`, `#maintenance_preventive`, `#maintenance_assets`, `#maintenance_reports` (`17302-17315`) |
| الجداول | `maintenance_requests`, `maintenance_suppliers`, `maintenance_equipment`, `maintenance_timeline`, `maintenance_preventive_schedule`, `maintenance_repairs`, `maintenance_quotes`, `maintenance_inspections`, `maintenance_receipts`, `maintenance_attachments`, `maintenance_finance_approvals` |
| SQL versioned | `maintenance-schema.sql` + `preventive-maintenance.sql` — جزئي |
| الغرض | إدارة أعطال + صيانة وقائية + موردين + معدات + اعتمادات مالية. |
| الكيان المركزي | `maintenance_requests` |
| نقاط | `open → closed` أو `rejected` |

## 2) الصفحات والمسارات

| Route | نوع | حالة |
|---|---|---|
| `#maintenance` | dashboard + قائمة | COMPLETE |
| `#maintenance_new` | فورم | COMPLETE |
| `#maintenance_detail/:id` | تفاصيل + timeline | COMPLETE |
| `#maintenance_suppliers` | قائمة | COMPLETE |
| `#maintenance_equipment` | قائمة معدات | COMPLETE |
| `#maintenance_preventive` | جدول وقائي | COMPLETE (v121: batch update) |
| `#maintenance_assets` | أصول فرع | COMPLETE |
| `#maintenance_reports` | تقارير | COMPLETE |

## 3) تحليل كل صفحة

- **`#maintenance`:** KPIs (مفتوح، معتمد، مغلق) + جدول + فلاتر (فرع، نوع، مورد).
- **`#maintenance_new`:** فورم بمرفقات صور.
- **`#maintenance_detail/:id`:** timeline زمنية + عروض أسعار + إيصالات + اعتماد مالي.
- **`#maintenance_reports`:** تكلفة، زمن استجابة، أعطال متكررة.

## 4) دورة العمل

بلاغ → assigned (مورد أو داخلي) → in_progress → awaiting_parts/quote → completed → closed. مع اعتماد مالي عند التكلفة الكبيرة.

## 5) الحالات

`open → assigned → in_progress → awaiting_parts / awaiting_quote → completed → closed / rejected`.

## 6) قاعدة البيانات

11 جدول (WORKFLOW_STATUS_AUDIT §6). `maintenance_finance_approvals` لاعتماد ملي.

## 7) الـBackend

استعلامات مباشرة في `pageMaintenance*`.

## 8) الصلاحيات

- `maintenance_officer` — Read/Write.
- `branch_manager` — يبلغ ويرى.
- `finance_manager` — يعتمد ملي.
- RLS: نعم.

## 9) العلاقات

- **يستقبل من:** Branches, Assets.
- **يرسل إلى:** Accounting (`acct_bills` — ربط يدوي حاليًا).

## 10) التقارير

- تكلفة الصيانة الشهرية.
- زمن الاستجابة/الإصلاح.
- معدات بأعطال متكررة.
- تقييم الموردين.

## 11) الإشعارات

عند الإسناد، اقتراب SLA، الإغلاق، اعتماد مالي.

## 12) UI/UX

- `.hero-card` قديم.
- Timeline جيدة.
- Loading جيد.

## 13) التكرارات

`maintenance list` مقابل `maintenance_equipment` مقابل `maintenance_assets` مقابل `branch_assets` — 4 مسارات متشابهة (ROUTES_AUDIT §تكرارات).

## 14) الاكتمال

Backend 90 | DB 75 | UI 80 | Perm 80 | Workflow 90 | Notif 85 | Reports 80 | Cross 70 | Docs 90 | Tests 30 → **~77/100**.
**التصنيف:** ✅ PRODUCTION_READY.

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة الأصول والصيانة (EAM — Enterprise Asset Management).
2. **الصفحات:** `#eam` (dashboard), `#eam/tickets`, `#eam/preventive`, `#eam/vendors`, `#eam/assets`, `#eam/costs`, `#eam/reports`.
3. **الجداول:** توحيد `branch_assets` مع `maintenance_equipment` مع `maintenance_assets` → جدول واحد `assets` بحقل `category`.
4. **APIs:** `maintenance_auto_bill(request_id)`, `preventive_generate_next_schedule`, `asset_lifecycle_transition`.
5. **Workflows:** ربط تلقائي مع Procurement (طلب قطع غيار PR).
6. **قرار المالك:** توحيد الأصول (اقتراح).
7. **قرار:** تفعيل ربط تلقائي مع AP bill.
8. **RLS:** branch-based + role.
9. **Reports:** MTBF, MTTR per asset.
10. **Notifications:** تذكيرات وقائية مسبقة.
11. **Integrations:** SAP-like ERP إن لزم.
12. **AI hook:** توقع أعطال، تصنيف بلاغ.
13. **BI:** `bi_operations_health` بالفعل يقرأ.
14. **Design:** hero + timeline + kanban.
15. **Mobile:** priority (يستخدم في الميدان).
16. **QR code:** كل أصل له QR (اقتراح).
17. **KPI:** downtime, cost per asset.
18. **Compliance:** archive.
19. **Suppliers rating:** موضوعي.
20. **Preventive engine:** cron scheduler.
21. **Photos:** قبل/بعد.
22. **Voice input:** بلاغ سريع بالصوت.
23. **Roadmap Phase 1:** توحيد الأصول.
24. **Roadmap Phase 2:** AP link + AI.
25. **Roadmap Phase 3:** IoT sensors.
26. **UX polish:** v123.
27. **Cross-module:** ربط مع HACCP (معدات مبردات).
28. **Documentation:** كتيب.
