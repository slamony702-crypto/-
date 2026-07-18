# تدقيق مسار المصادقة الحالي — قبل ترحيل B1

**الفرع:** `security/auth-migration-phase2`
**التاريخ:** 2026-07-18
**المصدر:** فحص مباشر للكود الحالي (ليس تقارير قديمة).

---

## 0) الخلاصة المفاجئة (مهمة)

النظام **ليس** يعتمد على `password_plain` بالكامل. هو **هجين**:
- ✅ **Supabase Auth هو المسار الأساسي فعلًا** (`signInWithPassword`, `signUp`, `resetPasswordForEmail`, `getSession`, `onAuthStateChange`, `refreshSession`, `signOut`).
- ✅ عمود `auth_id UUID` موجود ويربط `users` بـ`auth.users`.
- ✅ دوال الهوية `current_app_user_id()` / `current_app_role()` **تعتمد على `auth.uid()` بالفعل** (`WHERE auth_id = auth.uid()`).
- 🔴 لكن `password_plain` + `verify_login` باقيان كـ**fallback** للمستخدمين غير المُرحَّلين، مع **ترحيل تلقائي عند الدخول**.

**المعنى:** B1 ليس إعادة بناء من الصفر — هو **إزالة الـfallback القديم** وتنظيف الواجهة. أبسط وأأمن مما كان متوقعًا.

---

## 1) مسار تسجيل الدخول الحالي (دالة `authLogin` — سطر 12377)

تدفق من 4 خطوات:

| الخطوة | ماذا يحدث | السطر |
|--------|-----------|-------|
| 1 | `signInWithPassword(derivedEmail)` — للحسابات المُرحَّلة سابقًا | 12387 |
| 2 | **fallback:** `verify_login` RPC (يقرأ `password_plain`) | 12411 |
| 3 | لو له بريد شخصي حقيقي: `signInWithPassword(realEmail)` | 12424 |
| 4 | **ترحيل تلقائي:** `signUp()` بالبريد + كلمة المرور المُدخَلة، وربط `auth_id` | 12434-12459 |

**النقطة الحرجة:** الخطوة 4 تنشئ حساب Auth باستخدام كلمة المرور النصية التي كتبها المستخدم للتو. هذا "ترحيل عند الطلب" — لكنه يعتمد على وجود `password_plain` في الخطوة 2 للتحقق أولًا.

---

## 2) استخدامات `password_plain` (7 مواضع في index.html.html)

| # | السطر | السياق | التصنيف |
|---|-------|--------|---------|
| 1 | 12338 | استرجاع كلمة المرور يكتب `password_plain` بعد `updateUser` | كتابة |
| 2 | 19694 | إضافة مستخدم جديد (add user form) | كتابة |
| 3 | 19868 | اعتماد طلب انضمام (signup approval) | كتابة |
| 4 | 20074 | تغيير كلمة المرور من الأدمن | كتابة |
| 5 | 20153 | **عرض** كلمة المرور في شاشة المستخدمين | عرض 🔴 |
| 6 | 20155 | **زر نسخ** كلمة المرور | نسخ 🔴 |
| 7 | 21517 | إدخال مستخدم بـ`TempPass...` | كتابة |

**+ في SQL:** `login-verify-rpc.sql:16` — `verify_login` تقارن `password_plain = p_password` نصًا.

---

## 3) طريقة تخزين الجلسة

| العنصر | الحالي |
|--------|--------|
| جلسة Auth | Supabase (`sb.auth` — cookies/localStorage داخلية للمكتبة) |
| cache العرض | `localStorage.food_affairs_user` (CURRENT_USER: id, username, full_name, role, department) |
| الصلاحيات | `loadPermissions()` بعد الدخول — من DB |
| onAuthStateChange | سطر 5299 + 20695 (استعادة الجلسة + refresh) |
| logout | `sb.auth.signOut()` + `localStorage.removeItem` — سطر 12487 |

**⚠️ ثغرة:** `localStorage.food_affairs_user` يحمل `role`. لو تلاعب مستخدم بقيمته، تتغير **واجهة العرض** فقط — لكن **RLS في DB يعتمد على `auth.uid()` وليس localStorage**، فالحماية الفعلية سليمة. مع ذلك يجب التأكد أن أي **قرار حماية** لا يعتمد على localStorage.

---

## 4) الدوال/الجداول المتأثرة

### دوال الهوية (تعمل على auth.uid — سليمة)
| الدالة | التعريف | الملف |
|--------|---------|-------|
| `current_app_user_id()` | `SELECT id FROM users WHERE auth_id = auth.uid()` | hr-schema.sql:27 |
| `current_app_role()` | `SELECT role FROM users WHERE auth_id = auth.uid()` | hr-schema.sql:36 |

**ملاحظة:** لا تفحص `is_active` حاليًا — سنضيفها في migration 2 (مستخدم معطّل يجب ألا يمر).

### الدالة التي ستُعطَّل
| الدالة | المشكلة | الملف |
|--------|---------|-------|
| `verify_login(username, password)` | تقارن `password_plain` نصًا، متاحة لـanon | login-verify-rpc.sql |

### الجداول
- `users` — فيه `auth_id` (نستخدمه)، `password_plain` (نحذفه لاحقًا). نضيف حقول حالة الترحيل.
- `signup_requests` — طلبات الانضمام (لا تخزن password_plain مباشرة، لكن اعتمادها ينشئ user بـpassword_plain).
- `user_activity_log` — سجل الأنشطة (يُستخدم عند تغيير كلمة المرور).

### RLS
- كل الـpolicies تعتمد على `current_app_user_id()` / `current_app_role()` — وهي مبنية على `auth.uid()`. **لا تغيير جوهري مطلوب** على RLS، فقط تحسين دوال الهوية (فحص is_active).

---

## 5) الدوال التي قد تنكسر بعد الانتقال

| العنصر | الخطر | التخفيف |
|--------|-------|---------|
| `authLogin` خطوة 2 (verify_login) | ستفشل عند تعطيل verify_login | استبدال بمسار Auth صريح + رسالة "حسابك يحتاج ترحيلًا" |
| add user / signup approval | تكتب password_plain | استبدال بـinvite flow (Auth admin createUser + دعوة) |
| admin change password | يكتب password_plain | استبدال بـ"إرسال رابط إعادة تعيين" |
| password display/copy | يعرض password_plain | حذف نهائي |
| المستخدمون بلا email صالح | لا يمكن دعوتهم | يُرصدون في preflight + تقرير ترحيل |

---

## 6) الجداول التي تحتاج auth_user_id

**لا حاجة لعمود جديد** — `users.auth_id` موجود ويؤدي الغرض. سنضيف فقط **حقول حالة الترحيل** (auth_status, auth_invited_at, auth_linked_at, auth_last_error, auth_migration_required) لتتبع العملية.

---

## 7) مخاطر الانتقال

| # | الخطر | الشدة |
|---|-------|-------|
| R1 | مستخدمون نشطون بلا email صالح → لا يمكن دعوتهم | 🔴 يحدد preflight العدد |
| R2 | عناوين email مكررة → تمنع UNIQUE على Auth | 🟠 |
| R3 | تعطيل verify_login قبل ترحيل الجميع → قفل مستخدمين | 🔴 لذا مرحلي + flag |
| R4 | localStorage role spoofing | 🟢 (RLS يحمي فعلًا) |
| R5 | حذف password_plain مبكرًا | 🟢 (مؤجّل لملف مستقل لا يُطبَّق الآن) |

---

## 8) خطة التوافق المرحلي

```
المرحلة 1: إضافة حقول حالة الترحيل (auth_id موجود)      [migration 1]
المرحلة 2: تحسين دوال الهوية (فحص is_active)            [migration 2]
المرحلة 3: RLS انتقالية (تحقق + توافق)                  [migration 3]
المرحلة 4: كود — invite/reset بدل password_plain        [frontend]
المرحلة 5: تعطيل verify_login خلف flag                   [migration 4]
المرحلة 6: فترة تحقق (الجميع مُرحَّل)                     [تشغيلي]
المرحلة 7: حذف password_plain                            [migration 5 — جاهز لا يُطبَّق]
```

**Feature flag:** `AUTH_LEGACY_LOGIN_ENABLED` (default false). Production Guard يمنع بقاءها true في الإنتاج بعد موعد الإغلاق.

---

## 9) عدد password_plain: قبل / بعد (هدف)

| | قبل | الهدف بعد B1 |
|--|-----|--------------|
| index.html.html | 7 | 0 |
| verify_login (SQL) | 1 | معطّلة ثم محذوفة |

---

## الخلاصة
الأساس (Supabase Auth + auth_id + دوال هوية على auth.uid) **موجود وسليم**. B1 = إزالة الـfallback القديم + تنظيف الواجهة + دعوات بدل كلمات مرور نصية. الخطوة التالية: **Preflight** لقياس بيانات المستخدمين (emails ناقصة/مكررة) قبل أي migration.
