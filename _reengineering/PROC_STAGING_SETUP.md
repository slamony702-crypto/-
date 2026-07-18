# إعداد بيئة Staging لاختبار طبقة اعتماد طلبات الشراء

**الفرع:** `feature/purchase-orders-wave1`
**السبب:** لم يُعثَر على أي بيئة اختبار مؤكدة في المشروع (لا `.env`، لا `SUPABASE_TEST_*`، لا `STAGING_*`، لا `TEST_DATABASE_URL`). Vercel project واحد فقط باسم `shouon-al-ghithaa` وهو Production.

**المطلوب منك:** إنشاء بيئة Supabase منفصلة (اختيار (أ) أو (ب) أدناه) وتزويدنا بمعلومات الاتصال غير الحساسة. **لا تلصق أي key هنا** — فقط **Project Ref** (`abcxyz123`) واسم البيئة.

---

## الخيار (أ) — Supabase Branch (الأسرع — من داخل Dashboard)

مناسب لو تريد بيئة سريعة مربوطة تلقائيًا بـproject الإنتاج (تنسخ Schema، لكن البيانات فارغة).

### الخطوات
1. افتح Supabase Dashboard → مشروع `shouon-al-ghithaa` → **Branching** من القائمة اليسرى.
2. لو Branching غير مفعّل، فعّله (يحتاج خطة Pro أو أعلى). لو خطتك Free، اذهب للخيار (ب).
3. اضغط **Create branch** → اسمها `staging-proc-approval`.
4. انتظر حتى يصبح الـstatus `READY` (عادة 1-2 دقيقة).
5. من صفحة الـbranch، انسخ:
   - **Project Ref** الجديد (شكله `xxxx.supabase.co` — الجزء قبل `.supabase.co`)
   - رابط SQL Editor للـbranch
6. **لا تنسخ الـService Role Key هنا.** يبقى في Dashboard.

### التحقق من العزل
```sh
# افتح SQL Editor للـbranch وشغّل:
SELECT current_database(), current_setting('server_version');
# يجب أن تكون قاعدة بيانات مختلفة عن الإنتاج.
```

---

## الخيار (ب) — مشروع Supabase منفصل تمامًا

مناسب لو خطتك Free أو تريد عزلًا كاملًا.

### الخطوات
1. https://supabase.com/dashboard/projects → **New project**
2. الاسم: `shouon-al-ghithaa-staging`
3. اختر **Region** قريبة من الإنتاج (مثلًا `eu-central-1` أو `me-south-1`)
4. أنشئ **database password** جديد قوي — احفظه في password manager (لا هنا)
5. بعد الإنشاء، من `Project Settings` → `API`:
   - انسخ **Project Ref** (شكله `abcxyz123`)
   - **Project URL** = `https://abcxyz123.supabase.co`
6. سيكون لديك:
   - `anon` key (publishable — للواجهة)
   - `service_role` key (سري — للـmigrations)
   - كلاهما **لا يُنسخ إلى Git ولا رسائل شات**

### الجداول الأساسية المطلوبة قبل تشغيل الاختبارات
بيئة اختبار جديدة تحتاج نسخ Schema الأساسي من الإنتاج. الترتيب:
1. `hr-schema.sql` (يعرّف `users`، `current_app_user_id()`، `current_app_role()`)
2. `acct-schema.sql` + `acct-schema-2b-ap.sql` + `acct-schema-2c-ar.sql` (لـ`acct_vendors`، `acct_bills`)
3. `branches-seed.sql` (فرع واحد على الأقل)
4. `permissions-and-test-users.sql` (يزرع مستخدمين تجريبيين)
5. **ثم** `proc-schema-1.sql` (طلبات الشراء الأصلية)

بعد ذلك، migrations هذه الموجة:
6. `proc-approval-1.sql`
7. `proc-approval-2-hardening.sql`
8. `proc-approval-3-matching-priority.sql` (سيُنشأ في هذه الجولة)

---

## بعد الإعداد — ما تحتاج تشاركه معي

**افتح ملف نصي محلي (خارج Git) واكتب:**
```
STAGING_ENV_NAME=shouon-al-ghithaa-staging   ← أو staging-proc-approval
STAGING_PROJECT_REF=abcxyz123                 ← Project Ref فقط (غير حساس)
STAGING_URL=https://abcxyz123.supabase.co     ← معلوم للعموم
STAGING_CREATED_AT=YYYY-MM-DD
STAGING_IS_PRODUCTION=false                    ← تأكيد صريح
```
شارك محتوى هذا الملف معي في رسالة الشات.

**لا تشارك أبدًا:**
- ❌ `service_role` key
- ❌ database password
- ❌ `anon` key حتى (يفضّل عدم نشرها في محادثات دائمة)

---

## الأدوات الجاهزة في الفرع (تنتظر تشغيلًا عندك)

بعد اكتمال Setup، شغّل بالترتيب من Supabase SQL Editor:

| # | الملف | الغرض | مدة |
|---|-------|-------|-----|
| 1 | `proc-approval-preflight.sql` | تحقق قراءة فقط: هل الجداول الأصلية موجودة؟ الـstatus الحالي؟ Conflict names؟ | ~1 ثانية |
| 2 | `proc-approval-1.sql` | إنشاء الجداول والدوال الأساسية | ~3 ثواني |
| 3 | `proc-approval-2-hardening.sql` | Triggers + Advisory locks + Legacy RPC | ~2 ثانية |
| 4 | `proc-approval-3-matching-priority.sql` | Priority + AMBIGUOUS detection | ~1 ثانية |
| 5 | `proc-approval-tests.sql` | 20 اختبار (BEGIN…ROLLBACK — لا يحفظ شيئًا) | ~5 ثواني |
| 6 | جلستان `proc-concurrency-session-a.sql` + `proc-concurrency-session-b.sql` | اختبار التزامن بجلستي psql | يدوي |

**كل الملفات جاهزة الآن على الفرع `feature/purchase-orders-wave1`.**

---

## تأكيد آلي قبل تشغيل migrations

قبل تطبيق `proc-approval-1/2/3.sql` على بيئتك، شغّل هذا التحقق أولًا:

```sql
-- تأكيد أن الاتصال ليس Production
DO $$
BEGIN
  -- تحذير: الـProject Ref للإنتاج هو "shouon-al-ghithaa" (أو URL انتاجي معروف)
  -- لو current_database يطابق الإنتاج، أوقف
  RAISE NOTICE 'DB name: %', current_database();
  RAISE NOTICE 'Confirm this is STAGING before proceeding.';
  -- لو ما زلت غير متأكد، لا تكمل.
END $$;
```

---

## قواعد الأمان أثناء العمل

- ✅ لن أطلب أي key منك في أي رسالة
- ✅ لن أضع أي URL أو ref في `git` أبدًا
- ✅ ستنفذ SQL بنفسك من Supabase Dashboard — لن أتصل بأي DB
- ✅ تقارير Runtime ترسلها لي كنص (مخرجات NOTICE، عدد صفوف، أخطاء)
- ❌ لا نشغّل شيئًا على Production حتى بعد اكتمال الاختبارات — يظل قرارك النهائي

---

## الحكم الحالي

**`BLOCKED NO STAGING ENVIRONMENT`** — الفرع جاهز من ناحية الكود والاختبارات، لكن لا يمكن التقدّم دون بيئة staging مؤكدة. أرسل التفاصيل المطلوبة أعلاه وأشغّل بنفسك، وأرسل لي مخرجات كل مرحلة نصيًا.
