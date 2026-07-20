# PERMISSIONS_AND_ROLES_AUDIT — الأدوار والصلاحيات

> استُخرجت من `users.role CHECK`، دوال `is_*_manager()` في SQL، `role_permissions` جدول، فحوصات `CURRENT_USER.role` في `index.html.html`.

## 1) الأدوار الرسمية (18 دور)
| الدور | المصدر | الوصف |
|---|---|---|
| `admin` | كل مكان | أعلى صلاحية تقنية — يرى كل شيء |
| `company_manager` | كل مكان | مدير الشركة العام — أعلى صلاحية إدارية |
| `department_manager` | permissions-and-test-users.sql | يرى قسمه فقط |
| `projects_manager` | catalog + code | مدير مشاريع |
| `development_manager` | catalog | مدير تطوير |
| `meeting_organizer` | catalog + code | منظم اجتماعات مخصص |
| `branch_manager` | code + RLS | يرى فرعه فقط |
| `deputy_manager` | code | نائب مدير فرع |
| `employee` | افتراضي | موظف عادي |
| `maintenance_officer` | code | مسؤول الصيانة |
| `operations_manager` | code | مدير التشغيل |
| `quality_manager` | code | مدير الجودة |
| `finance` | code (قديم) | حسابات عامة قديمة |
| `hr_manager` | code + `is_hr_admin` | مدير HR |
| `payroll_officer` | `is_payroll_authorized` | مسؤول الرواتب |
| `finance_manager` | `is_finance_manager` | المدير المالي |
| `gl_accountant` | `is_gl_accountant` | محاسب دفتر أستاذ |
| `ap_officer` | `is_ap_officer` | مسؤول المدفوعات (AP) |
| `ar_officer` | `is_ar_officer` | مسؤول المقبوضات (AR) |

## 2) دوال is_*_manager() (متطابقة النمط)
كل دالة:
```sql
CREATE OR REPLACE FUNCTION is_XX_manager() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'XX_manager');
$$;
```
- `is_menu_manager` → admin, company_manager, operations_manager
- `is_crm_manager` → admin, company_manager, operations_manager
- `is_haccp_manager` → admin, company_manager, quality_manager
- `is_procurement_manager` → admin, company_manager, operations_manager, finance_manager
- `is_perf_manager` → admin, company_manager, hr_manager
- `is_delivery_manager` → admin, company_manager, operations_manager
- `is_doc_manager` → admin, company_manager, hr_manager
- `is_cc_manager` → admin, company_manager, operations_manager
- `is_bi_manager` → admin, company_manager, finance_manager
- `is_integrations_manager` → admin, company_manager
- `is_franchise_manager` → admin, company_manager, finance_manager
- `is_ops_manager` → admin, company_manager, operations_manager, branch_manager, deputy_manager
- `is_finance_manager` → admin, company_manager, finance_manager
- `is_hr_admin` → admin, company_manager, hr_manager
- `is_payroll_authorized` → admin, company_manager, finance_manager, payroll_officer

⚠️ **ملاحظة:** القيم أعلاه استنتاج من مقارنة الأنماط — قد تختلف قليلاً بين الملفات. الأصل هو الـ SQL في كل ملف Wave.

## 3) مصفوفة الصلاحيات (Role × Module) — تقديرية
| Module | admin | company_manager | branch_manager | operations_manager | quality_manager | hr_manager | finance_manager | ap/ar_officer | maintenance_officer | employee |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Users | RW | RW | R | R | R | RW | R | R | R | R (self) |
| Branches | RW | RW | R (own) | R | R | R | R | R | R | R |
| Meetings | RW | RW | RW (dept) | RW | RW | RW | RW | R | R | RW (invited) |
| Tasks | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW (assigned) |
| Decisions | RW | RW | R | R | R | R | R | R | R | R (assigned) |
| Cafe | RW | RW | RW | RW | R | – | R | – | – | R |
| Maintenance | RW | RW | RW | R | R | – | R (approval) | – | RW | R |
| Quality | RW | RW | R | R | RW | – | – | – | – | R |
| HR | RW | RW | – | – | – | RW | R (payroll) | – | – | R (self) |
| Accounting | RW | RW | R (branch) | R | – | – | RW | RW (own) | – | – |
| Operations | RW | RW | RW (own) | RW | – | – | R | – | – | RW |
| POS | RW | RW | RW | RW | – | – | R | – | – | RW (cashier) |
| Menu | RW | RW | R | RW | – | – | – | – | – | R |
| CRM | RW | RW | R | RW | – | – | R | – | – | R |
| HACCP | RW | RW | RW | R | RW | – | – | – | – | R |
| Procurement | RW | RW | R | RW | – | – | RW | – | – | R |
| Performance | RW | RW | R | R | – | RW | R | – | – | R (self) |
| Delivery | RW | RW | R | RW | – | – | R | – | – | R (rider) |
| Documents | RW | RW | R | R | R | RW | R | – | – | R (own) |
| Call Center | RW | RW | R | RW | – | – | – | – | – | R (agent) |
| BI | RW | RW | R (own) | R | – | – | RW | – | – | – |
| Integrations | RW | RW | – | – | – | – | – | – | – | – |
| Franchise | RW | RW | – | R | – | – | RW | – | – | – |
| AI Assistant | RW | RW | RW | RW | RW | RW | RW | RW | RW | RW |

**RW** = read/write • **R** = read • **–** = no access

## 4) الفجوات
1. **`test_admin` mega-role:** أي مستخدم بـ username = `test_admin` يعبر gate كل الموديولات. لا فحص إضافي.
2. **`department_manager` مضمّن** في menu items بعض الأحيان بلا فحص role موحّد.
3. **Route بلا permission check صريح:** كثير من الـ routes الجديدة تعتمد على RLS فقط، دون فحص `can()` في `route()` قبل استدعاء `pageXxx`. الحماية موجودة على الجداول لكن UX (منع الصفحة) قد يعرض شاشة فارغة بدل رسالة "غير مصرح".
4. **الأدوار المالية 4 (finance_manager, gl_accountant, ap_officer, ar_officer)** لكن التقسيم داخل الصلاحيات جزئي — كثير من AR pages يفتحها `finance_manager` تمامًا.
5. **`finance` role قديم** لم يُحذف — بعض الأماكن تفحصه، بعضها لا.
6. **مركز اتصال / إدارة مستندات / إدارة أداء** بلا `role` مخصص خاص بهم (`cc_manager`, `doc_manager`, `perf_manager` غير موجودين في `users.role` — يُستخدم `hr_manager` أو `operations_manager` كبديل).
7. **`user_permission_overrides`** موجود لكن لا شاشة إدارة تفصيلية.
8. **RLS يعتمد على `current_app_role()` وليس Supabase JWT:** يعني الحماية تفشل لو تلاعب المستخدم بـ localStorage. مخاطرة أمنية أساسية.
