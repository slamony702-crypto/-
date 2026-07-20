# SYSTEM_OVERVIEW — نظرة عامة على نظام «شؤون الغذاء»

> مصدر البيانات: `index.html.html` + 17 ملف SQL + `api/agent.js` + `api/rewrite.js` + `service-worker.js` + `HANDOFF.md` + `MODULES-CATALOG.md`.
> إصدار مرصود عند الاكتشاف: v123-2026-07-18-desktop-polish-2 / MODULES CATALOG v117.
> ⚠️ هذا مستند اكتشاف — لا يوصي بتغييرات ولا ينفذها.

## 1) طبيعة النظام
منصة **ERP + Restaurant OS** لشركة مطاعم سعودية متعددة الفروع، تجمع بين:
- **إدارة تنفيذية** (اجتماعات، قرارات، مهام، مخرجات، تواصل داخلي/طارئ).
- **تشغيل مطعم** (ورديات، تحضير، طلبات، مخزون، هدر، مشكلات).
- **مالية كاملة** (دليل حسابات، AR/AP، خزينة، أصول، مخزون، VAT، إغلاق سنوي، موازنات، ZATCA Phase 1 QR).
- **HR** (موظفون، حضور، إجازات، رواتب) + **Payroll** أساسي.
- **قنوات مبيعات** (POS كاشير لمس + Delivery داخلي + Franchise).
- **علاقات عملاء** (CRM + Loyalty ثابت + شكاوى).
- **جودة وسلامة** (Quality Visits + HACCP بمعايير SASO 2233).
- **مشتريات** (PR → PO → GRN → AP آلي).
- **أداء** (KPI + Scorecards + تقييمات + أهداف).
- **مركز اتصال** (Inbound/Outbound + سكريبتات + متابعات).
- **BI + Integrations + AI Assistant** طبقة استراتيجية.

## 2) النشاط المخدوم
شركة مطاعم/كافيهات سعودية متعددة الفروع، تشمل: مطعم، كافيه، مطبخ مركزي، مستودع.
دورات الأعمال المدعومة: بيع مباشر (POS)، توصيل داخلي، توصيل عبر منصات (Jahez/HungerStation/Mrsool)، امتياز تجاري (Franchise)، إدارة مركزية للفروع.

## 3) المستخدمون
تعتمد المنصة على 18 دورًا مذكورًا في CATALOG وعلى فحوصات دور مباشرة في الكود:
- إدارة عليا: `admin`, `company_manager`.
- إدارة أقسام/فروع: `department_manager`, `branch_manager`, `deputy_manager`, `operations_manager`, `quality_manager`, `maintenance_officer`, `projects_manager`, `development_manager`, `meeting_organizer`, `hr_manager`.
- مالية: `finance_manager`, `gl_accountant`, `ap_officer`, `ar_officer`, `payroll_officer`, `finance` (اسم قديم).
- تشغيلي: `employee`.
- (ضمنيًا في دوال SQL) روابط CRM/Menu/HACCP/CC/PROC/PERF/DLV/DOC/BI/INT/FR/OPS تتحقق من مجموعات مصفوفة بالكود (`is_menu_manager`, `is_crm_manager`, `is_haccp_manager`, `is_cc_manager`, `is_procurement_manager`, `is_perf_manager`, `is_delivery_manager`, `is_doc_manager`, `is_bi_manager`, `is_integrations_manager`, `is_franchise_manager`, `is_ops_manager`, `is_finance_manager`, `is_ap_officer`, `is_ar_officer`, `is_gl_accountant`, `is_accounting_role`, `is_hr_admin`, `is_payroll_authorized`, `is_manager_of`).

## 4) الكيان المركزي
لا يوجد كيان "شركة" مركزي منفصل — الفرع (`branches`) هو الكيان التشغيلي المحوري، والمستخدم (`users`) هو الكيان الأمني. الحسابات المركزية مربوطة بشركة واحدة (بلا `companies` table).

## 5) دورة العمل الكبرى (End-to-End حسب الواقع البرمجي)
1. **المسار التشغيلي:** فتح وردية (Ops) → قوائم الفتح → طلبات POS + Delivery → تسجيل بيانات جودة/حرارة (HACCP) → إغلاق وردية → تسليم للوردية القادمة.
2. **المسار المحاسبي:** POS transaction (paid) → journal entry تلقائي (مسودة) • GRN → AP bill • Payroll → journal • كل تحرك مخزون → قيد.
3. **المسار الإداري:** اجتماع → مخرجات + قرارات + مهام (`action_items`, `decisions`, `department_tasks`) → متابعة + إشعارات → إغلاق.
4. **المسار المالي التكاملي:** Franchise sales report → compute royalty → invoice AR (ربط جاهز، لكن قرار AR auto غير مفعّل).
5. **المسار المعرفي:** AI Assistant يقرأ 7 مصادر (Overdue tasks, Branches status, Expiring docs, Financial summary, Recent decisions, Open maintenance, Partners settlements) — قراءة فقط.

## 6) المخرجات
- محاضر اجتماعات (PDF قابل للطباعة).
- فواتير بيع (POS) بـ QR ZATCA Phase 1.
- فواتير موردين وعملاء (AP/AR) + مقبوضات ومدفوعات.
- قسائم رواتب شهرية.
- تقارير جودة/صيانة/HACCP/BI.
- كشوف شركاء دفع + دفعات مقاصة.
- فواتير روياليتي للفرنشايز.

## 7) المشكلات الحالية الموثقة (من HANDOFF + الكود)
- **v121/v120 audit debt:**
  - `users.password_plain` لا يزال مخزّنًا صراحة (medium).
  - `api/agent.js` يقبل `extraInstructions` بلا Bearer verification — مخاطر Injection (medium).
  - Franchise → AR invoice creation بلا قرار تجاري نهائي (لا ربط تلقائي مفعّل).
  - `int_webhook_endpoints.secret_token` نص صريح — لا Vault.
- **Test coverage:** لا E2E tests؛ الاعتماد على Node syntax check فقط. 17 موديول جديد لم تُختبر يدويًا كل سيناريوهاتها.
- **Backend workers:** Integrations providers بلا Edge Functions فعلية (البنية جاهزة فقط).
- **UI/UX التوسع:** 34+ قيمة `border-radius` حرفية، 41 قيمة `font-size` مختلفة، media queries بأنماط `max-width` vs `min-width` غير موحدة.
- **قائمة جانبية (MENU_GROUPS) منتفخة:** 21 مجموعة، 15 منها موديول معاينة واحد داخله.
- **بوابة فرنشايزي مستقلة** غير موجودة (Phase 2).
- **POS offline، تطبيق سائق** بلا PWA خاص، PBX integration فعلي مفقود.
- **Gemini quota** على مشروع Google Cloud منفصل (تشغيلي، ليس تقنيًا).

## 8) ما الذي يفصل الحالي عن الإطلاق الفعلي؟
- 17 موديول جديد كامل في SQL + DAL + شاشات، لكنها كلها خلف `PREVIEW_MODULES` — فقط `test_admin` يصلها. أي إطلاق فعلي يتطلب:
  1. مراجعة نهائية E2E لكل موديول.
  2. قرار المالك حول ربط Franchise ↔ AR تلقائيًا أم يدويًا.
  3. سياسة أمنية جديدة لكلمات المرور و`extraInstructions` قبل الإنتاج.
  4. تنفيذ Integrations workers (Edge Functions).
