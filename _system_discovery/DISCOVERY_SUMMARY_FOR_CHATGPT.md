# DISCOVERY_SUMMARY_FOR_CHATGPT — ملخص شامل لإرساله لـ ChatGPT

> جاهز للنسخ. اللغة عربية بحتة.

---

## 1) ما هو النظام؟
منصة ERP + Restaurant OS شاملة لشركة مطاعم سعودية متعددة الفروع. مبنية كتطبيق ويب PWA بملف HTML واحد (43,152 سطر) + قاعدة بيانات Supabase + Vercel Serverless Functions. الواجهة عربية RTL كاملة.

## 2) النشاط الذي يخدمه
- تشغيل يومي لعدة فروع (مطاعم، كافيهات، مطابخ مركزية، مستودعات).
- بيع مباشر (POS) + توصيل داخلي + توصيل عبر منصات (Jahez/HungerStation/Mrsool) + امتياز تجاري.
- الإدارة المركزية: اجتماعات، قرارات، مهام، جودة، صيانة، حسابات، HR، أمن غذائي (HACCP).

## 3) المستخدمون
18 دورًا رسميًا: admin, company_manager, department_manager, projects_manager, development_manager, meeting_organizer, branch_manager, deputy_manager, employee, maintenance_officer, operations_manager, quality_manager, finance (قديم), hr_manager, payroll_officer, finance_manager, gl_accountant, ap_officer, ar_officer.

## 4) دورة العمل الأساسية
1. تشغيلي: فتح وردية ← POS + Delivery ← تسجيل جودة/حرارة ← إغلاق وردية.
2. محاسبي: كل POS/GRN/Payroll/Cafe/Ops ← قيد GL آلي.
3. إداري: اجتماع ← مخرجات + قرارات + مهام ← متابعة ← إغلاق.
4. مالي تكاملي: Franchise sales ← compute royalty ← invoice AR (الربط جاهز، يدوي حاليًا).
5. معرفي: AI Assistant قراءة فقط عبر 7 أدوات (Gemini function-calling).

## 5) الموديولات الحالية (بالأرقام والحالات)
- 34 موديول إجمالاً = 17 إنتاج + 17 معاينة.
- 16 مفتاح PREVIEW_MODULES (PAY تحت accounting).
- كل موديولات المعاينة خلف feature flag، مفتوحة فقط لـ test_admin.

## 6) محتوى كل موديول (تفصيل موجز)

### إنتاج (17):
1. المستخدمون والصلاحيات — 18 دور + استثناءات فردية + soft delete + heartbeat.
2. الفروع والأقسام — بيانات فرع كاملة + خرائط GPS + branch_assets.
3. الاجتماعات — قوالب + أجندة + RSVP + محضر + مخرجات + قرارات + PDF.
4. مخرجات الاجتماعات (action_items) — إسناد + متابعة + تصعيد.
5. المهام والتكليفات — Kanban + مشاريع + subtasks.
6. القرارات — رئيسي + فرعيين + مشاهدون + acknowledgments.
7. التواصل الداخلي — chat 1:1 + جماعي + قناة قسم + mention + ملفات.
8. تواصل طارئ — بث + إجبار استلام + سجل.
9. الصيانة — طلبات + موردون + معدات + وقائية + إيصالات + اعتماد مالي.
10. الجودة — زيارات + أقسام قابلة للتخصيص + مرفقات + تقارير.
11. ركن الكافيه — كتالوج + طلبات + حالات + قيود GL.
12. الإشعارات.
13. الملف الشخصي.
14. طلبات الاجتماعات — meeting request + preparation report.
15. رؤية الشركة والأهداف.
16. البحث الصوتي (Web Speech API).
17. تحسين الصياغة (Gemini rewrite).

### معاينة (17):
18. HR — موظفون + هيكل + حضور + إجازات + رواتب + قيد GL.
19. Accounting — دليل حسابات + 30 جدول + AR/AP + خزينة + أصول + مخزون + VAT + ZATCA Phase 1 + إقفال سنوي + موازنات + 6 مراحل schemas.
20. Operations — 17 جدول: ورديات + قوائم + تحضير + طلبات + مخزون فرع + هدر + مشكلات.
21. Payments — شركاء (Jahez/…) + عقود + كشوف + مقاصة + تحويلات (3 مراحل).
22. AI Assistant — 7 أدوات قراءة + RLS + audit log.
23. POS — أجهزة + جلسات (cash_variance) + معاملات + splits + QR ZATCA + كاشير لمس.
24. Menu — أصناف + تصنيفات + BOM + أسعار قنوات + snapshot.
25. CRM & Loyalty — عملاء + عناوين + حسابات ولاء (سجل ثابت INSERT-only) + شكاوى SLA.
26. HACCP — SASO 2233 + معدات + سجلات حرارة (is_within_range trigger) + دفعات + شهادات + حوادث.
27. Procurement — PR ← PO ← GRN ← AP آلي.
28. Performance — 9 KPIs + سكوركاردات + تقييمات + أهداف SMART + تصنيف A+←F.
29. Delivery — مناطق + سائقين + طلبات (9 حالات) + Kanban + 3 دوال ذرية.
30. Documents — 14 تصنيف + متعدد الأنواع + polymorphic + سجل وصول.
31. Call Center — Agents + Calls + Dispositions + Scripts + Followups.
32. BI — 7 تقارير مبذورة + 6 دوال cross-module + snapshots + saved views.
33. Integrations — 12 مزوّد config + webhook endpoints + event log (workers غير موجودين).
34. Franchise — شركاء + عقود + فروع + تقارير مبيعات + royalties.

## 7) الصفحات الموجودة (بأرقام)
- 160 route مسجلة في السطور 16967 إلى 17126.
- 21 مجموعة في MENU_GROUPS (السايدبار).
- 15 من الـ21 مجموعة = عنصر واحد + badge قريبًا.

## 8) العلاقات بين الموديولات (رئيسية)
- Menu ← POS (snapshot سعر).
- CRM customer ← POS/Delivery/Cafe (FK).
- POS completed ← Accounting (قيد draft).
- POS payment ← CRM loyalty (trigger).
- Cafe delivered ← Accounting invoice.
- Procurement GRN ← Accounting AP bill + Inventory movement.
- HR payroll ← Accounting (قيد).
- Franchise royalty ← Accounting AR (ربط جاهز، غير مفعّل تلقائيًا).
- Ops order ← Accounting + Inventory movement.
- All modules ← BI aggregations.
- CC calls ← CRM/POS/Delivery FKs اختيارية.
- Documents polymorphic ← أي موديول (soft link).

## 9) الوظائف المكتملة (COMPLETE)
كل الموديولات الـ17 الإنتاج تعمل بالفعل يوميًا: Users, Branches, Meetings, Action Items, Tasks, Decisions, Chat, Emergency, Maintenance, Quality, Cafe, Notifications, Profile, Meeting Requests, Vision, Voice Search, Rewrite.

## 10) الوظائف الجزئية (PARTIALLY_COMPLETE)
- كل موديولات المعاينة الـ17: SQL + DAL + شاشات موجودة كلها، لكن E2E غير مختبرة، والاستخدام خلف gate.
- Accounting VAT Phase 2 mock.
- Delivery بلا تطبيق سائق منفصل.
- CC بلا PBX.
- Integrations بلا workers.
- Franchise بلا بوابة فرنشايزي مستقلة.
- Franchise ← AR ربط بلا آلية تلقائية.

## 11) الصفحات بلا Backend حقيقي (UI_ONLY)
- Integrations Marketplace (تعرض 12 مزوّد، الاتصال يتوقف بعد config).
- CC Call recording (لا PBX).
- BI CASH_FLOW report (بلا rpc_name).
- بوابة الفرنشايزي (غير موجودة أصلاً).
- Delivery driver mobile app (غير موجود).

## 12) Backend بلا واجهة (BACKEND_ONLY)
- compute_vat_totals (استخدام جزئي في UI).
- run_monthly_depreciation (لا زر تشغيل).
- close_fiscal_year (لا شاشة اعتماد).
- doc_expire_overdue (لا cron).
- dashboard_summary RPC جاهز لكن الفرونت لم يُحدَّث.
- كل triggers auto-numbering.
- Franchise ← AR link.
- Integrations webhook workers.

## 13) التكرارات
- action_items مقابل department_tasks (شبيهان لكن جدولان مختلفان).
- reports مقابل analytics مقابل bi_reports (3 مسارات للتقارير).
- crm_customers مقابل acct_customers (جدولا عميل منفصلان).
- maintenance list vs equipment vs assets (3 routes متقاربة).
- 4 أنماط hero + 4 أنماط KPI.
- 3 أنماط stat card.

## 14) مشكلات القائمة الحالية (Sidebar UX)
- 21 مجموعة، 15 منها بمفتاح واحد + badge — قائمة منتفخة بلا معنى.
- بادج قريبًا ثابت بلا تلوين حالة.
- كل موديول Wave 0 إلى 4 له group مستقل بمفتاح واحد فقط — يخالف مبدأ التجميع.
- لا Breadcrumbs موحدة.

## 15) المسميات غير الواضحة
- المهام والتكليفات مقابل مخرجات الاجتماعات — الفرق دقيق للمستخدم العادي.
- التقارير (قديم) مقابل تحليلات الأداء (قديم) مقابل الذكاء التحليلي BI.
- الحسابات والمالية تحتوي المدفوعات والمقاصات (Payments) بلا اسم واضح.
- إعدادات النظام شاملة جدًا (users + branches + roles + system settings + AI settings ...).
- الملف الشخصي مقابل ملف الموظف (HR) — لا تكامل واضح.

## 16) أهم الفجوات (Top 10)
1. جداول الأساس (meetings/tasks/…) بلا SQL versioned = مخاطرة migrations.
2. users.password_plain نص صريح — دَين أمني حرج.
3. RLS يعتمد على current_app_role() وليس Supabase JWT الفعلي.
4. 12 مزوّد integrations بلا workers حقيقيين.
5. Franchise ← AR بلا آلية تلقائية (قرار المالك).
6. CC بلا PBX — كل بيانات المكالمة يدوية.
7. Delivery بلا تطبيق سائق مستقل.
8. BI CASH_FLOW في الكتالوج بلا rpc_name.
9. لا E2E tests، لا Cron scheduling لـ doc_expire_overdue.
10. Sidebar بـ 21 مجموعة غير مجدولة استخدامًا.

## 17) القرارات التي تحتاج سؤال المالك
1. هل روياليتي الفرنشايز تُنشئ فاتورة AR تلقائيًا أم يدويًا؟
2. هل نوحّد crm_customers مع acct_customers أم نبقيهما منفصلين مع sync؟
3. هل نلغي المهام والتكليفات أم مخرجات الاجتماعات أم نحتفظ بكليهما مع تسميات أوضح؟
4. هل نبني بوابة فرنشايزي مستقلة الآن أم في Phase 2؟
5. هل ننتقل إلى Supabase Auth الحقيقي (JWT) الآن أم بعد إطلاق كل الموديولات؟
6. ما ترتيب أولويات Integrations workers (Jahez أولاً؟ WhatsApp؟ Mada Pay؟).
7. هل نبني CC PBX integration الآن أم يبقى بيانات يدوية؟
8. ما مصير route reports و analytics القديم بعد BI؟

## 18) المسارات والملفات المهمة
- الجذر: `D:\ملفات تم نقلها\Desktop\عبدالرحمن\مشاريع\فعالة\برنامج الإجتماعات\shouon-al-ghithaa\`
- الرئيسي: `index.html.html` (43,152 سطر)
- Handoff: `HANDOFF.md` + `MODULES-CATALOG.md`
- Backend: `api/agent.js`, `api/rewrite.js`, `service-worker.js`
- SQL Waves 0-4 (17 ملف): hr-schema.sql, acct-schema*.sql (6), ops-schema-3*.sql (3), ai-schema-1-assistant.sql, pay-schema-p*.sql (3), menu-schema-1.sql, crm-schema-1.sql, pos-schema-1a.sql, haccp-schema-1.sql, proc-schema-1.sql, perf-schema-1.sql, dlv-schema-1.sql, doc-schema-1.sql, cc-schema-1.sql, bi-schema-1.sql, int-schema-1.sql, fr-schema-1.sql.
- أدوات مساعدة: perf-fix-1-dashboard-rpc.sql (RPC جاهز غير مفعّل).
- Repo: https://github.com/slamony702-crypto/-
- Live: https://shouon-al-ghithaa.vercel.app
- Supabase: dfuqmmagtteemtpywody

## المواقع الحرجة داخل index.html.html
- سطر 12292: PREVIEW_MODULES (16 مفتاح).
- سطر 12293: MODULE_PREVIEW_USERS = ["test_admin"].
- سطر 12299: gatedModuleForPage().
- سطر 12321: MENU_GROUPS (21 مجموعة).
- سطر 12398: PAGE_TITLES (160 مفتاح).
- سطور 16967 إلى 17126: routes (160 route).
- سطر 25682: COMING_SOON_MODULES (17 موديول تعريفية).
- سطور 5639, 6608, 7132, 7397, 7562, 7729, 7990, 8186, 8376, 8535, 8699, 8819, 8965, 9058, 9157, 9291, 9690: window.HR/ACCT/OPS/AIA/MENU/CRM/POS/HACCP/PROC/PERF/DLV/DOC/CC/BI/INT/FR/PAY DAL objects.
