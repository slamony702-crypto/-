# 01 — المستخدمون والصلاحيات (Users & Permissions)

## 1) هوية الموديول

| الحقل | القيمة |
|---|---|
| الاسم العربي | المستخدمون والصلاحيات |
| الاسم الإنجليزي | Users & Permissions Management |
| Routes | `#users`, `#my_profile`, `#invite`, `#settings` (`index.html.html:17317, 17320-17323`) |
| DAL | لا DAL مستقل — الاستعلامات مباشرة (`sb.from('users')`) |
| الجداول | `users`, `role_permissions`, `user_permission_overrides`, `user_activity_log`, `signup_requests`, `notifications` |
| الغرض التجاري | إدارة الهوية والوصول لكل المنصة — الأساس الأمني |
| الكيان المركزي | `users` (سجل الموظف الأمني) |
| نقطة البداية | Signup / Invite / Admin create user |
| نقطة النهاية | Deactivation (`is_active = false`) — لا حذف حقيقي |
| المدخلات | بيانات الموظف، صور هوية، دور مبدئي |
| المخرجات | حساب مصادق + صلاحيات فعلية + سجل نشاط |
| هل مستقل؟ | نعم — هو الأساس، لا يعتمد على غيره |
| هل الاسم واضح؟ | نعم |
| هل مكانه منطقي؟ | موزع بين `#users`, `#invite`, `#settings` — يحتاج توحيد |

## 2) الصفحات والمسارات

| Route | نوع | مصدر | دور مسموح | Backend | Database | حالة | ملاحظات |
|---|---|---|---|---|---|---|---|
| `#users` | قائمة | جدول | admin, company_manager, hr_manager | `sb.from('users')` | `users` | COMPLETE | soft delete |
| `#my_profile` | صفحة | جدول | الجميع (self) | `sb.from('users')` + notifications | `users`, `notifications` | COMPLETE | v121 pagination |
| `#invite` | فورم | نموذج | admin, company_manager | `sb.from('signup_requests')` | `signup_requests` | COMPLETE | approve flow |
| `#settings` | صفحة | متعددة الأقسام | admin غالبًا | متعدد | متعدد | COMPLETE | يجمع users + branches + system |

## 3) تحليل كل صفحة

- **`#users`:** header + عد المستخدمين + جدول (اسم/بريد/دور/فرع/قسم/حالة). فلاتر بالدور والحالة. حالات UI: Loading skeleton، Empty state واضح، رسائل خطأ Supabase غير مؤنسنة. Responsive: جدول ينزلق أفقيًا على الموبايل بلا sticky column.
- **`#my_profile`:** hero بصورة الموظف + KPIs شخصية (اجتماعات، مهام مفتوحة، إشعارات). لا فورم تعديل واضح للحقول الأساسية.
- **`#invite`:** فورم بسيط (بريد + دور مبدئي). لا رابط دعوة قابل للنسخ — يعتمد على إدخال المدير للبيانات كاملة.
- **`#settings`:** يحتوي تبويبات — أسماء غير واضحة (users, branches, system, AI, ...).

## 4) دورة العمل التفصيلية

**Happy Path:**
1. مرشح يقدم `signup_request` (`pending_approval`).
2. Admin/HR يراجع في `#invite`.
3. يوافق → إنشاء `users` row (مع `password_plain` — R-01) + welcome email (خارج الكود الحالي).
4. أول دخول → إجبار تغيير كلمة السر (`bootApp` يفحص).
5. الاستخدام اليومي (RLS يضبط الرؤية).
6. تعديل دور/فرع → مباشرة على `users.role/branch_id`.
7. الخروج → `is_active = false`.

**Rejection Path:** `signup_requests.status = rejected` + `reject_reason` (raised in `signup-requests-reject-reason.sql`).

**Failure Paths:** فحص `bootApp` لتفعيل الاعتمادية عند نقل الموبايل — يعمل logout نظيف (HANDOFF §4.6).

## 5) الحالات والانتقالات

- `signup_requests.status`: `pending_approval → approved / rejected` (SQL: `signup-requests.sql`).
- `users.is_active`: `true → false` (soft delete).
- `users.role`: 18 قيمة (SQL: `permissions-and-test-users.sql`).

## 6) قاعدة البيانات

| الجدول | مصدر SQL | ملاحظات |
|---|---|---|
| `users` | *بلا SQL versioned* (R-07) | يحتوي `password_plain` (R-01) |
| `role_permissions` | بلا SQL versioned | نمطي |
| `user_permission_overrides` | بلا SQL versioned | لا شاشة تفصيلية (Permissions Audit §7) |
| `user_activity_log` | بلا SQL versioned | لا شاشة عرض شاملة |
| `signup_requests` | `signup-requests.sql` + `signup-requests-reject-reason.sql` | له reject reason |
| `notifications` | بلا SQL versioned | جدول عام |

**RPCs:** `current_app_user_id()`, `current_app_role()` — دوال SECURITY DEFINER (كل schemas Wave 1-4 تعتمد عليها). `login-verify-rpc.sql` موجود.

## 7) الـBackend (DAL)

لا `window.USERS` مستقل — الاستعلامات مباشرة داخل `pageUsers`, `pageMyProfile`, `pageInvite`, `bootApp`, `authLogin`.

**gap analysis:** توحيد شاشات المستخدم في DAL موحد (`window.USR`) قد يفيد الصيانة.

## 8) الصلاحيات

| Role | View Users | Edit Users | Invite | Reset Password |
|---|:---:|:---:|:---:|:---:|
| admin | ✅ | ✅ | ✅ | ✅ |
| company_manager | ✅ | ✅ | ✅ | ✅ |
| hr_manager | ✅ | ✅ (limited) | ✅ | — |
| department_manager | ✅ (dept) | — | — | — |
| employee | Self only | Self only | — | Self |

- RLS: نعم على `users`.
- Client-side: `can()` يفحص الدور قبل عرض `#users`.
- Bypassable: نعم — تلاعب `localStorage` لأن RLS يعتمد `current_app_role()` (R-02).

## 9) العلاقات

- **يستقبل من:** `signup_requests` (approved → users).
- **يرسل إلى:** كل موديول (كل جدول له `created_by` أو `assigned_to` أو RLS يفحص `current_app_user_id()`).
- **حرج:** حذف/تعطيل مستخدم يؤثر على `assigned_to` في `action_items`, `department_tasks`, `maintenance_requests`, ...

## 10) التقارير والمؤشرات

- عدد المستخدمين النشطين — قائم في dashboard.
- محاولات الدخول الفاشلة — لا يوجد report.
- سجل نشاط لكل موظف — الجدول موجود، لا شاشة عرض.

## 11) الإشعارات وسجل التدقيق

- `user_activity_log` يستقبل الأحداث المهمة (login, logout, permission change) — يعتمد على DAL manual insert.
- إشعارات: عند approval/rejection لطلب signup، عند force logout.

## 12) UI/UX Assessment

- **الاسم واضح:** نعم.
- **الموقع:** موزع بين `#users` و `#settings` و `#invite` — يحتاج hub واحد.
- **الاتساق:** ✅ لكن `#settings` مكتظ.

## 13) التكرارات

- `hr_departments` مقابل `departments` (`branch_assets`) — تكرار مقصود لكن مربك.
- `users.branch_id` مقابل `hr_employee_profile.branch_id` — احتمال تكرار.

## 14) مستوى الاكتمال (12 محور)

| المحور | الدرجة |
|---|---:|
| Backend | 85 |
| DB Schema | 60 (بلا SQL versioned) |
| RPCs | 70 |
| UI Screens | 90 |
| Permissions | 60 (R-02) |
| Workflow | 85 |
| Notifications | 75 |
| Audit | 60 (لا شاشة) |
| Reports | 40 |
| Cross-module | 90 |
| Documentation | 90 |
| Test Coverage | 20 |
| **المجموع** | **~68/100** |

**التصنيف:** 🟡 NEEDS_STABILIZATION + 🔴 NEEDS_SECURITY_REWORK (بسبب `password_plain` + RLS pattern).

## 15) FUTURE_BLUEPRINT (28 عنصر مقترح)

1. **الاسم المقترح:** إدارة المستخدمين والوصول (IAM).
2. **القسم:** الأمن والحوكمة.
3. **الصفحات:** `#iam` (dashboard), `#iam_users`, `#iam_roles`, `#iam_overrides`, `#iam_sessions`, `#iam_audit`, `#iam_signup_queue`, `#iam_password_policy`.
4. **الجداول الجديدة/المعدلة:** `iam_users` (بدون password_plain — عبر Supabase Auth), `iam_role_matrix` (توسع `role_permissions`), `iam_sessions` (heartbeat + force logout), `iam_password_history`.
5. **APIs:** `iam_force_logout(user_id)`, `iam_grant_temporary_permission(user_id, module, until)`, `iam_reset_password(user_id)`.
6. **Workflows:** تسلسل approval صريح لطلبات التوظيف (HR review → Admin approve → auto welcome email).
7. **قرار المالك:** تحديد سياسة password (طول، تعقيد، انتهاء).
8. **قرار:** إبقاء 18 دور أم دمج (`finance` قديم → حذف).
9. **قرار:** توحيد `hr_departments` و `departments`؟
10. **علاقة CRM:** حساب موظف ≠ حساب عميل (بلا خلط).
11. **RLS:** انتقال كامل لـ Supabase JWT.
12. **Audit UI:** شاشة `#iam_audit` تعرض `user_activity_log`.
13. **Reports:** تقرير محاولات فاشلة، تقرير permission overrides، تقرير sessions.
14. **Notifications:** عند approval، عند force logout، عند password change.
15. **Integrations:** WhatsApp OTP، SSO Google Workspace (اختياري).
16. **Design:** hero موحّد + KPIs (نشطون، معلقون، مؤرشفون، محاولات فاشلة).
17. **Mobile:** priority على `#my_profile` (self-service).
18. **Cross-module:** ربط أزرار "تخويل مؤقت" في كل موديول حساس.
19. **Data model:** فصل `password_plain` كليًا (R-01).
20. **Migration:** dump كل schemas الأصل إلى SQL versioned (R-07).
21. **Test:** E2E signup + login + logout + force logout.
22. **KPI:** avg time to onboard, avg session length, permission override count.
23. **Backup:** password_history 12 كلمات.
24. **Compliance:** GDPR-like data retention.
25. **AI Assistant hook:** استعلام "من دخل النظام آخر 24 ساعة".
26. **Roadmap Phase 1:** إصلاح R-01 + R-02.
27. **Roadmap Phase 2:** UI للـaudit + reports.
28. **Roadmap Phase 3:** SSO + WhatsApp OTP.

## ملاحظات نهائية

- **R-01 (password_plain):** حرجة، لا تُصعد للإنتاج بدون معالجة.
- **R-02 (RLS pattern):** حرجة كذلك.
- **test_admin bypass:** كل موديولات المعاينة تعتمد على `MODULE_PREVIEW_USERS = ['test_admin']` (السطر 12450).
