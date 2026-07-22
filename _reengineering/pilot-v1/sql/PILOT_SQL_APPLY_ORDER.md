# ترتيب تطبيق SQL — Pilot v1

> ⚠️ **لا تُطبَّق هذه الملفات على Production قبل اختبارها على Supabase Staging.**
> سياسات RLS تعتمد على `auth.uid()` عبر `current_app_user_id()`؛ تفعيلها على
> مستخدمين لم يُرحَّلوا إلى Supabase Auth (بلا `auth_id` / بلا جلسة) **سيحجبهم**.
> لذلك تطبيق RLS مرهون بإتمام ترحيل Auth أولًا (موديول 7).

## المتطلبات المسبقة
- `current_app_user_id()` و`current_app_role()` موجودتان (مؤكَّد من preflight ✅).
- شغّل `pilot-core-preflight.sql` (قراءة فقط) للتوثيق قبل البدء.

## الترتيب

| # | الملف | يعتمد على | ملاحظة |
|---|-------|-----------|--------|
| 0 | `pilot-core-preflight.sql` | — | قراءة فقط، شغّله أولًا |
| 1 | `pilot-01-foundation.sql` | current_app_* | جدول التدقيق + الدوال العامة (إضافي بحت) |
| 2 | `pilot-02-meetings.sql` | 01 | يعرّف `core_is_company_admin/core_current_dept` |
| 3 | `pilot-03-maintenance.sql` | 01 | مستقل (يعرّف دواله الخاصة) |
| 4 | `pilot-04-quality.sql` | 01 | مستقل |
| 5 | `pilot-05-delivery.sql` | 01 | مستقل |
| 6 | `pilot-06-tasks.sql` | 01, (02 لدوال core) | يعيد تعريف core_* idempotent |
| 7 | `pilot-07-decisions.sql` | 01, (02) | يعيد تعريف core_* idempotent |
| 8 | `pilot-08-emergency.sql` | 01, (02) | يشمل منع الحذف |
| 9 | `pilot-09-iam.sql` | 01, (02) | **الأخطر** — راجع تحذير Auth أدناه |
| 10 | `pilot-10-reports.sql` | 01..09 | دوال تجميع (قراءة فقط) |

> الترتيب 2→10 آمن بأي تسلسل عمليًا لأن كل ملف يعيد تعريف `core_*` بـ
> `CREATE OR REPLACE` (idempotent)، لكن يُفضَّل الترتيب أعلاه.

## اختبار كل ملف بعد تطبيقه
شغّل ملف الاختبار المرافق `pilot-0X-*.tests.sql` وتحقق من النتائج المتوقعة
المكتوبة في رأسه. الاختبارات الموسومة `EXECUTED LOCALLY, PASS` نُفِّذت فعلًا
على PostgreSQL 16 معزول؛ الموسومة `REQUIRES SUPABASE STAGING` تحتاج جلسات
`authenticated` حقيقية لكل دور.

## التراجع (Rollback)
لكل ملف `pilot-0X-*.rollback.sql` يعيد الحالة السابقة (سياسات `using(true)`)
دون حذف بيانات أو أعمدة. طبّقها بالترتيب العكسي عند الحاجة.

## ⚠️ تحذير خاص بموديول 9 (IAM) وترحيل Auth
`pilot-09-iam.sql`:
- يُلغي قراءة عمود `password_plain` عبر API (`REVOKE SELECT`). `verify_login`
  (SECURITY DEFINER) يظل يعمل، لكن **تأكد أن الدخول الحالي لا يقرأ العمود
  مباشرة من العميل** قبل التطبيق على Production.
- يقصر كتابة `users`/`role_permissions`/`user_permission_overrides` على الإدارة.
  عند تفعيل RLS الصارمة، **أي مستخدم بلا جلسة Auth حقيقية سيُحجب** — لذلك
  طبّقه **بعد** إتمام ترحيل Auth واختبار الدخول لكل الأدوار على Staging.

## بعد التطبيق على Production
`pilot-01` (التدقيق) و`pilot-10` (التقارير) آمنان للتطبيق مبكرًا (إضافيان،
لا يقيّدان الوصول). أما ملفات RLS (02–09) فبوابتها ترحيل Auth.
