# 02 — الفروع والأقسام (Branches & Departments)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| الاسم العربي | الفروع والأقسام |
| الاسم الإنجليزي | Branches & Departments Management |
| Routes | لا route جذر مستقل — يُدار عبر `#settings` وشاشات فرعية |
| DAL | لا `window.BRANCH` — استعلامات مباشرة `sb.from('branches')` |
| الجداول | `branches`, `departments`, `branch_assets` |
| SQL versioned | `branches-seed.sql`, `branch-assets-setup.sql` (لا schema كامل — R-07) |
| الغرض التجاري | التنظيم المؤسسي: كل موظف مرتبط بفرع/قسم، كل حركة مالية/تشغيلية تُنسب لفرع. |
| الكيان المركزي | `branches` (فرع) |
| نقطة البداية | Admin ينشئ فرع |
| نقطة النهاية | `is_active = false` (soft close) |
| المدخلات | بيانات فرع كاملة (اسم، عنوان، GPS، تراخيص، ساعات) |
| المخرجات | فرع مسجَّل + مركز تكلفة + شاشات فرع |
| هل مستقل؟ | نعم |
| هل الاسم واضح؟ | نعم |
| هل مكانه منطقي؟ | ❌ **لا** — لا `#branches` route جذر. حاجة ماسة لـ dashboard مستقل. |

## 2) الصفحات والمسارات

| Route | نوع | حالة | ملاحظات |
|---|---|---|---|
| ضمن `#settings` | tab | COMPLETE | الفروع مدمجة في إعدادات النظام |
| ضمن `#users` | فلتر | COMPLETE | فلترة المستخدمين بالفرع |
| `#hr_organization` | صفحة | COMPLETE | تدير أقسام HR + مناصب |
| لا `#branches_dashboard` | — | MISSING | 🟥 لا شاشة KPI للفرع |

## 3) تحليل كل صفحة

- **Branches tab في `#settings`:** جدول فروع + زر إضافة. لا خريطة تفاعلية موحدة (رغم أن العنوان يحتوي GPS).
- **Departments في `#hr_organization`:** يجمع `hr_departments` + مناصب. الأقسام العامة (`departments`) مقابل `hr_departments` — فرق مربك.

## 4) دورة العمل التفصيلية

**Happy Path:**
1. قرار افتتاح فرع (خارج النظام).
2. Admin يدخل بيانات الفرع في `#settings`.
3. تعيين مدير فرع (تعديل `users.branch_id`).
4. ربط موظفين (HR).
5. إضافة `branch_assets`.
6. تشغيل: يظهر في كل الفلاتر والتقارير.
7. إغلاق: `is_active = false` — سجلاته تبقى.

**Failure Path:** حذف فرع → `SET NULL` على `branch_id` في السجلات المرتبطة (R-17).

## 5) الحالات والانتقالات

- `branches.is_active`: `true → false` (لا `closed_at` صريح — يحتاج تحقق NEEDS_RUNTIME_VERIFICATION).

## 6) قاعدة البيانات

| الجدول | حالة | مصدر |
|---|---|---|
| `branches` | بلا SQL versioned كامل | seed file فقط |
| `departments` | بلا SQL versioned | R-07 |
| `hr_departments` | ضمن `hr-schema.sql` | منفصل عن `departments` (تكرار مقصود) |
| `branch_assets` | `branch-assets-setup.sql` | مربوط بـ Maintenance + Ops |

## 7) الـBackend (DAL)

لا `window.BRANCH`. كل الاستعلامات في `pageSettings`, `pageHrOrganization`, وفلاتر داخل شاشات موديولات أخرى.

## 8) الصلاحيات

| Role | Read | Write |
|---|:---:|:---:|
| admin, company_manager | كل الفروع | ✅ |
| branch_manager, deputy_manager | فرعه فقط | جزئي |
| operations_manager | كل الفروع | Read only |
| employee | فرعه | Read only |

RLS: نعم (كل جدول Wave 1-4 يفحص `branch_id` عبر `can_access_branch_ops` أو مشابه).

## 9) العلاقات

- **يرسل إلى:** كل موديول تقريبًا (`branch_id` FK).
- **يستقبل من:** Users (branch_manager).

## 10) التقارير والمؤشرات

- خريطة الفروع — غير موجودة كصفحة موحدة.
- تقرير مقارنة أداء الفروع — عبر BI (`bi_branch_ranking`).
- تقرير أصول الفرع — عبر Maintenance.

## 11) الإشعارات وسجل التدقيق

- تعديل فرع: لا audit log صريح — NEEDS_RUNTIME_VERIFICATION.

## 12) UI/UX Assessment

- **الاسم:** واضح.
- **الموقع:** ❌ ضعيف — لا hub مركزي.
- **الاتساق:** أقسام HR منفصلة عن `departments` تخلق إرباك.

## 13) التكرارات

- `departments` مقابل `hr_departments` — R-07 + قرار قديم.

## 14) مستوى الاكتمال

- Backend 60 | DB 50 | UI 65 | Permissions 75 | Workflow 70 | Notifications 30 | Reports 55 | Cross-module 90 | Docs 80 | Tests 10 → **~58/100**
- **التصنيف:** 🟡 NEEDS_STABILIZATION (بحاجة hub + توثيق schema).

## 15) FUTURE_BLUEPRINT

1. **الاسم:** إدارة الفروع والأقسام (Organizational Setup).
2. **القسم:** الحوكمة والبنية.
3. **الصفحات:** `#branches` (dashboard + KPI), `#branch/:id` (details), `#branches_map`, `#departments`, `#branch_assets`, `#branch_hours`, `#branch_licenses`.
4. **الجداول:** `branches` (توسيع: أنواع، رخصة، ساعات، صيانة)، `departments` (توحيد مع `hr_departments`).
5. **APIs:** `branch_deactivate(id)`, `branch_transfer_assets(from,to)`.
6. **Workflows:** فتح فرع (جدول checklist)، إغلاق فرع (نقل موظفين + جرد + بيع أصول).
7. **قرار المالك:** توحيد `departments` و `hr_departments`؟
8. **قرار:** dump schemas إلى SQL versioned.
9. **RLS:** `is_branch_accessible(user, branch)` موحد.
10. **Reports:** خريطة حرارية، مقارنة، ملف فرع PDF.
11. **Notifications:** تنبيه انتهاء رخصة، تنبيه تغيير المدير.
12. **Cross-module:** ربط قوي مع Maintenance (`branch_assets`), Ops, HR.
13. **Integrations:** خرائط Google / Mapbox.
14. **AI Assistant hook:** أدوات "الفروع الأدنى أداءً"، "الفروع التي رخصتها تنتهي".
15. **BI:** فرع بأداء منخفض → alerts.
16. **Design:** خريطة رئيسية + بطاقات بيانية لكل فرع.
17. **Mobile-first:** بطاقة فرع مضغوطة.
18. **Cross-module:** ربط مع Franchise (فروع الفرنشايز `franchise_branches`).
19. **KPI:** revenue/branch, complaints/branch, staff turnover/branch.
20. **Historical retention:** 7+ سنوات.
21. **Test:** E2E فتح فرع + نقل موظف.
22. **Roadmap Phase 1:** إنشاء `#branches` dashboard.
23. **Roadmap Phase 2:** توحيد `departments` + خرائط.
24. **Roadmap Phase 3:** ربط licenses مع Documents.
25. **Compliance:** خزن التراخيص كمستندات.
26. **Documents:** فئات مستندات فرع محددة.
27. **Cost centers:** ربط تلقائي فرع ← `acct_cost_centers`.
28. **UX priority:** بحث سريع بفرع في header.
