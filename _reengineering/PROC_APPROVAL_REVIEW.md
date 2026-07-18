# مراجعة أمن طبقة اعتماد طلبات الشراء (Procurement Approval)

**الفرع:** `feature/purchase-orders-wave1`
**التاريخ:** 2026-07-18
**الحالة:** مراجعة داخلية بعد جولة التصلّب — قبل الدمج مع master

---

## 1) الجداول الجديدة (السطح والغرض)

| الجدول | الغرض | ملاحظات أمنية |
|--------|-------|----------------|
| **`proc_approval_rules`** | مصفوفة القواعد التي يعرّفها المالك: `min_amount`, `max_amount`, `branch_id`, `department_id`, `required_role`, `step_order`. | لا تُحذف عند حذف الفرع/القسم (ON DELETE CASCADE مقصود لتجنّب قواعد يتيمة). RLS: قراءة للمرتبطين بالمشتريات/المالية، كتابة للمدراء. |
| **`proc_requisition_approvals`** | نسخة من الخطوات لكل طلب. حقول: `step_no`, `required_role`, `assigned_to`, `status` ∈ {pending, approved, rejected, skipped, cancelled}, `decided_by`, `decided_at`, `comment`, `rule_snapshot` (JSONB). | `UNIQUE (requisition_id, step_no)` يمنع تكرار الخطوات. الكتابة عبر RPCs فقط بحكم الأمر الواقع (RLS للـauthenticated يقبل admin فقط). |
| **`proc_approval_activity`** | سجل تدقيق شامل (submitted/approved/rejected/cancelled/legacy_*). `metadata` JSONB لأي بيانات إضافية. | Append-only بشكل فعلي (لا سياسة UPDATE للـauthenticated). القراءة مربوطة بصاحب الطلب أو مدير مشتريات/مالية. |
| **`proc_approval_settings`** (جولة التصلّب) | صف واحد فقط (PK Boolean = TRUE). يحمل flag `allow_legacy_approval` (افتراضيًا `FALSE`). | قراءة للجميع authenticated. كتابة لمدراء المشتريات/المالية/الشركة فقط. |

**تعديلات على `proc_requisitions` (جولة التصلّب — عمودان جديدان فقط، لا تعديل عمود قائم):**
- `amount_at_submit NUMERIC(14,2)` — snapshot لإجمالي الطلب وقت التقديم (يبقى حتى لو تغيرت الأسعار).
- `submitted_at TIMESTAMPTZ` — وقت التقديم الفعلي (يبقى محفوظًا حتى إن تغيرت `updated_at`).

---

## 2) الـ RPCs الست (بعد التصلّب) — الأسماء والوظائف

| # | الاسم | الوظيفة | الحماية |
|---|------|--------|---------|
| 1 | `proc_match_approval_rules(amount, branch_id, dept_id)` | يُرجِع القواعد المطابقة مرتبةً حسب `step_order`، مع اختيار الأكثر تخصيصًا عند التعادل. | STABLE، SECURITY DEFINER، `SET search_path=public`. |
| 2 | `proc_requisition_total(req_id)` | إجمالي `quantity * estimated_price` لبنود الطلب. | STABLE، SECURITY DEFINER. |
| 3 | `proc_submit_requisition(req_id)` | التقديم للاعتماد. **بعد التصلّب:** يفشل بـ`APPROVAL_CONFIGURATION_MISSING` عندما لا تنطبق قاعدة وإعداد legacy مُعطَّل. | Auth check + active user + advisory lock + FOR UPDATE + snapshot المبلغ. |
| 4 | `proc_approve_step(step_id, comment)` | اعتماد خطوة واحدة. لو كانت الأخيرة → الطلب يصبح `approved`. | Auth + active + advisory lock على الطلب + FOR UPDATE + منع self-approval + فحص الدور + فحص assigned_to + فحص ترتيب الخطوات. |
| 5 | `proc_reject_step(step_id, reason)` | رفض خطوة → رفض الطلب كامل + إلغاء الخطوات اللاحقة. سبب إلزامي. | كل ما سبق. |
| 6 | `proc_cancel_requisition_approval(req_id, reason)` | إلغاء مسار الاعتماد (المالك أو مدير المشتريات) عندما `status='submitted'`. | Auth + active + advisory lock + FOR UPDATE. |
| 7 | `proc_get_approval_chain(req_id)` | يُرجِع الخطوات + سجل النشاط كـJSON للواجهة. | STABLE، SECURITY DEFINER. |
| 8 | `proc_legacy_decide_requisition(req_id, decision, reason)` | (جولة التصلّب) البديل الآمن للـUPDATE المباشر في النمط القديم. يعمل فقط عندما flag ON ولا سلسلة. | Auth + active + advisory lock + is_procurement_manager + فحص عدم وجود chain + سبب رفض إلزامي. |

---

## 3) RLS Policies بالتفصيل

### `proc_approval_rules`
| السياسة | العملية | الشرط |
|---------|---------|--------|
| `proc_appr_rules_sel` | SELECT | مدير مشتريات، أو المالية/AP/GL، أو مدير فرع/نائبه (للاطلاع فقط) |
| `proc_appr_rules_wr` | ALL | admin, company_manager, procurement_manager, finance_manager |

### `proc_requisition_approvals`
| السياسة | العملية | الشرط |
|---------|---------|--------|
| `proc_req_appr_sel` | SELECT | مدير مشتريات، أو صاحب الطلب، أو المُخصَّص له، أو حامل الدور المطلوب في القاعدة |
| `proc_req_appr_wr` | ALL | **admin فقط** — كتابات الاعتماد تمر عبر SECURITY DEFINER RPCs، ليس بحاجة لسياسة كتابة عامة |

### `proc_approval_activity`
| السياسة | العملية | الشرط |
|---------|---------|--------|
| `proc_appr_act_sel` | SELECT | مدير مشتريات، أو صاحب الطلب، أو حاملي الأدوار المالية |
| `proc_appr_act_wr` | INSERT | admin فقط — كل الإدراج يتم داخل RPCs |

### `proc_approval_settings`
| السياسة | العملية | الشرط |
|---------|---------|--------|
| `proc_appr_settings_sel` | SELECT | كل authenticated (لتقرأ الواجهات الحالة) |
| `proc_appr_settings_wr` | UPDATE | admin, company_manager, procurement_manager, finance_manager |

---

## 4) اختيار قاعدة الاعتماد (خوارزمية `proc_match_approval_rules`)

المدخلات: `p_amount`, `p_branch_id`, `p_dept_id` من الطلب.

الخطوات (SQL — CTE داخل الدالة):

1. **candidates**: كل قاعدة `is_active=TRUE` + `entity_type='requisition'` + المبلغ داخل `[min_amount, max_amount]` + الفرع والقسم إما NULL في القاعدة (شامل) أو مطابق.
2. لكل قاعدة، احسب **درجة التخصيص** (`specificity`):
   - `+2` لو `branch_id` محدد في القاعدة (وطابق).
   - `+1` لو `department_id` محدد في القاعدة (وطابق).
   - Global (بلا فرع/قسم) = `0`.
3. **ranked**: لكل `step_order`، رتّب المرشحين تنازليًا حسب `specificity`، ثم تصاعديًا حسب `rule_id` (fallback ثابت).
4. أرجِع الصف الأول لكل `step_order` (`rn = 1`) مرتبًا بـ`step_order ASC`.

**النتيجة:** خطوة واحدة لكل مستوى، مع تفضيل القاعدة الأكثر تخصيصًا.

---

## 5) ماذا يحدث عند تطابق أكثر من قاعدة؟

في **نفس الـ`step_order`**: تُختار القاعدة **الأكثر تخصيصًا** (`branch+dept` > `branch` > `dept` > `global`). لو التساوي كامل، يُختار الأصغر `rule_id`.

في **`step_order`ات مختلفة**: كل مستوى يحصل على خطوته المستقلة، والطلب يمر بها بالترتيب.

**سبب هذا التصميم:** يسمح بقواعد عامة (global) كـfallback، ثم استثناءات لفروع/أقسام معينة، بدون تضارب.

---

## 6) ماذا يحدث عند عدم وجود قاعدة؟

### قبل التصلّب (الخطأ الأصلي)
كانت `proc_submit_requisition` تعود بـ`mode='legacy'` بصمت ويشتغل النظام كأنه بدون طبقة اعتماد — **فجوة أمن كبيرة** لو مدير أضاف طبقة الاعتماد ولم يُحدد قواعد بعد.

### بعد التصلّب (الحل)
- `proc_submit_requisition` تفحص `proc_approval_settings.allow_legacy_approval`.
- **إذا FALSE (الافتراضي)**: تُرفع `APPROVAL_CONFIGURATION_MISSING` مع تفاصيل المبلغ والفرع والقسم. الطلب يبقى في `draft`.
- **إذا TRUE**: يُسمح باستخدام النمط القديم مؤقتًا، ويُسجَّل في `proc_approval_activity` كـ`legacy_submit`. الاعتماد اللاحق يتم عبر `proc_legacy_decide_requisition` (RPC مخصصة، ليس UPDATE مباشر).

**الواجهة:** عند رفع الخطأ، يعرض tooltip بالإنجليزية `APPROVAL_CONFIGURATION_MISSING` ورسالة عربية للمستخدم. لو المستخدم مسؤول (procurement_manager أو أعلى)، يُعرض له تأكيد للانتقال إلى شاشة القواعد.

---

## 7) كيف يتم منع تجاوز الخطوات؟

طبقتان:

**الطبقة الأولى — تحقُّق داخل RPC:**
```sql
SELECT COUNT(*) INTO v_prev_pending FROM proc_requisition_approvals
  WHERE requisition_id = v_step.requisition_id
    AND step_no < v_step.step_no
    AND status <> 'approved';
IF v_prev_pending > 0 THEN
  RAISE EXCEPTION 'STEP_ORDER_VIOLATED: توجد % خطوات سابقة لم تُعتمَد', v_prev_pending;
END IF;
```

**الطبقة الثانية — التزامن (Advisory Lock):**
كل من `proc_approve_step` و `proc_reject_step` و `proc_cancel_requisition_approval` تبدأ بـ:
```sql
PERFORM pg_advisory_xact_lock(hashtext('proc_requisitions')::BIGINT, v_req_id);
```
هذا يضمن أن قرارين متزامنين على نفس الطلب يُنفَّذان بالتتابع، فلا يمر شرط "الخطوات السابقة مُعتمَدة" بشكل خاطئ في حالة السباق.

**الطبقة الثالثة — Trigger على `proc_requisitions`:**
حتى لو حاول عميل ما تجاوز الاعتماد عبر UPDATE مباشر لتغيير `status='approved'`، الـtrigger `proc_req_update_guard_trg` يفشل بـ`APPROVAL_MULTI_LEVEL_ACTIVE` عندما توجد سلسلة اعتماد.

---

## 8) منع الاعتماد المكرر (Idempotency + Concurrency)

- **قيد وحيد:** `UNIQUE (requisition_id, step_no)` يمنع بنية بيانات مكررة أصلاً.
- **`status <> 'pending'` check:** أول اعتماد يضع `status='approved'`، وأي محاولة ثانية تراه `approved` وتُرفع `STEP_NOT_PENDING`.
- **`FOR UPDATE`** على الخطوة + الطلب داخل RPC = يسلسل التنفيذ.
- **Advisory Lock** على `req_id` = يسلسل حتى قرارات مختلفة على نفس الطلب (لتجنّب سباقات على "hint" الخطوات السابقة).

**النتيجة:** أي محاولتين متزامنتين للاعتماد على نفس الخطوة → واحدة تنجح، الثانية تُرفع `STEP_NOT_PENDING`.

---

## 9) تعديل الطلب بعد بدء الاعتماد

**الحماية:**
- Trigger `proc_req_update_guard_trg` على `proc_requisitions`:
  - يرفض تغيير `branch_id` أو `department_id` عندما `status IN ('submitted','approved')` بخطأ `REQ_LOCKED_FIELDS`.
  - يرفض العودة من `submitted` إلى `draft` بخطأ `REQ_INVALID_TRANSITION`.
- Trigger `proc_req_items_write_guard_trg` على `proc_requisition_items`:
  - يرفض أي `INSERT/UPDATE/DELETE` عندما الطلب ليس `draft` بخطأ `REQ_ITEMS_LOCKED`.

**المسار الوحيد لتعديل طلب في الاعتماد:**
1. المالك أو مدير المشتريات يستدعي `proc_cancel_requisition_approval(req_id, reason)` → status → `cancelled`.
2. الطلب المُلغى يبقى في التاريخ.
3. المستخدم يفتح طلبًا جديدًا (لن يُسمح بإعادة `cancelled → draft`).

---

## 10) رفض الطلب وإعادة تقديمه

**الرفض:**
- سبب إلزامي (فحص في RPC وTrigger).
- الخطوة الحالية → `rejected`.
- الخطوات اللاحقة → `cancelled`.
- الطلب → `rejected` مع `rejection_reason`.
- الرفض حالة نهائية (Trigger `proc_req_update_guard_trg` يمنع الخروج منها).

**إعادة التقديم:**
- **الطلب المرفوض يبقى مرفوضًا** — لا يمكن إعادته إلى `draft` أو `submitted`.
- المستخدم يفتح طلبًا جديدًا. البنود الأصلية تُنسخ من الواجهة (خارج نطاق الليلة، إن اقتضت الحاجة).

**سبب هذا التصميم:** تدقيق أوضح، وسجل تدقيق مستقر (كل طلب له مصير محدد لا يُعاد كتابته).

---

## 11) مستخدم معتمد غير نشط

- عند كل `approve/reject/cancel/submit/legacyDecide`، الـRPC تفحص:
  ```sql
  SELECT COALESCE(is_active, TRUE) INTO v_caller_ok FROM users WHERE id = v_caller;
  IF NOT v_caller_ok THEN RAISE EXCEPTION 'USER_INACTIVE'; END IF;
  ```
- **الخطوات المفتوحة على مستخدم معطَّل:** لا تحصل تلقائيًا — `assigned_to` عمود اختياري. إذا كانت الخطوة عامة (`assigned_to IS NULL`)، أي حامل للدور المطلوب يمكنه اعتمادها.
- **لو `assigned_to` معطَّل:** لا يقدر يعتمد. الحلول:
  - admin يعيد التخصيص عبر UPDATE مباشر على السطر (RLS يسمح لـadmin فقط).
  - أو يُلغَى الطلب ويُعاد تقديمه.
- **مقترح للتصلّب المستقبلي:** RPC جديدة `proc_reassign_step(step_id, new_user_id)` مربوطة بصلاحية `procurement.reassign_approval`. لم تُنفَّذ ليلة اليوم.

---

## 12) تعطيل قاعدة مستخدمة في طلب قائم

**السلوك المُعتمد:**
- الخطوات الموجودة **لا تتأثر** — تحتفظ بـ`required_role` و `rule_snapshot` كنسخة مجمّدة.
- القاعدة المُعطَّلة (`is_active=FALSE`) لا تُطبَّق على **طلبات جديدة**، لكن لا تحذف الخطوات القائمة.
- **حذف** القاعدة بالكامل يعمل نفس الشيء (`rule_snapshot` محفوظ في JSONB، والخطوات مستقلة).

**النتيجة:** يمكن تحديث السياسة بأمان بدون كسر طلبات جارية.

---

## 13) Snapshot vs Live rule

**التصميم المُعتمد: Snapshot.**

- `proc_requisition_approvals.rule_snapshot` (JSONB) يحفظ عند إنشاء الخطوة: `rule_id`, `rule_name`, `specificity`, `amount_at_submit`.
- الخطوة تحمل `required_role` منسوخًا (ليس FK للقاعدة).
- تغيير القاعدة بعد التقديم لا يؤثر على الخطوة الجارية.

**سبب هذا القرار:** الشفافية القانونية والمحاسبية — كل طلب يحفظ القاعدة التي طُبقت عليه، حتى لو تغيّرت السياسة لاحقًا.

**مقارنة:** لو استخدمنا Live rule (FK للـrule)، تغيير القاعدة يعبث بسجل التدقيق التاريخي، وقد يعيد ترتيب أو نوع الاعتماد فجأة على طلب مفتوح.

---

## 14) اختبارات القبول (Test Matrix)

راجع الملف `proc-approval-tests.sql` للسيناريوهات الاثنى عشر:

| # | السيناريو | ملف الاختبار |
|---|-----------|-------------|
| 1 | no matching rule + flag off → APPROVAL_CONFIGURATION_MISSING | `TEST 1` |
| 2 | one level approval → approved after 1 step | `TEST 2` |
| 3 | three level approval → sequential | `TEST 3` |
| 4 | out of order approval → STEP_ORDER_VIOLATED | `TEST 4` |
| 5 | unauthorized approver → ROLE_MISMATCH | `TEST 5` |
| 6 | duplicate approval → STEP_NOT_PENDING | `TEST 6` |
| 7 | concurrent approval → (يدوي/manual) | `TEST 7` |
| 8 | rejection without reason → REJECTION_REASON_REQUIRED | `TEST 8` |
| 9 | resubmission after rejection → REQ_TERMINAL_STATE | `TEST 9` |
| 10 | modification after submission → REQ_LOCKED_FIELDS + REQ_ITEMS_LOCKED | `TEST 10` |
| 11 | conversion to PO before final approval → PO_BEFORE_APPROVAL | `TEST 11` |
| 12 | conversion to PO after final approval → success | `TEST 12` |

---

## 15) الفجوات المعروفة (لم تُنفَّذ ليلة اليوم)

| # | الفجوة | التوصية | الأولوية |
|---|--------|---------|----------|
| G1 | **تفويض المعتمدين (Delegation)** — عند إجازة المعتمد، لا مسار بديل تلقائي. | إضافة `proc_delegations (user_id, delegate_to, from_date, to_date)` + تعديل `proc_approve_step` ليقبل ممن يمتلك تفويضًا نشطًا. | متوسط |
| G2 | **إشعارات (Notifications)** — لا تنبيه للمعتمد التالي عند نجاح خطوة. | داخل RPCs، بعد كل تحديث، إدراج في `notifications` بمُستهدف `assigned_to` أو حاملي الدور المطلوب. | عالٍ للتجربة |
| G3 | **Approval لأوامر الشراء (PO)** — `entity_type` يقبل `purchase_order` لكن RPCs لم تُبنَ. | نسخ نفس نمط الـPR لأوامر الشراء لو احتُيج. | مؤجَّل (خارج نطاق الموجة) |
| G4 | **إعادة تخصيص خطوة (Reassign)** لخطوة معينة لمستخدم بديل. | RPC جديدة `proc_reassign_step` مربوطة بـ`procurement.reassign_approval`. | متوسط |
| G5 | **`current_app_role()`/`current_app_user_id()`** — تُستدعى في trigger `is_procurement_manager()` وأخوته من RPC، وهي تعتمد على `auth.uid()` (JWT). إن لم يكن Supabase Auth مفعّلًا كامل السلسلة، فقد ترجع NULL. | ضمن مسار "Security Foundation" في المرحلة 1 من البرومت الكبير — إلزامي قبل إطلاق Preview. | حرج |
| G6 | **audit للتغييرات على `proc_approval_rules`** — لا سجل من غيّر أي قاعدة ومتى. | جدول `proc_approval_rules_history` + trigger AFTER UPDATE/DELETE. | متوسط |
| G7 | **حد لحجم `comment` و `reason`** — لا حد أعلى فعلي (TEXT). | إضافة CHECK على الطول (مثلًا ≤ 500 حرف). | منخفض |
| G8 | **legacy submit طلب فيه chain قديمة** — إذا فُعِّل flag ثم شخص حاول تقديم طلب فيه سلسلة قديمة (من قاعدة سابقة)، `proc_legacy_decide_requisition` سيرفض لكن `proc_submit_requisition` تحذف الـchain القديمة أولًا. مقصود، لكن يستحق التوثيق. | مُوثَّق هنا. لا تغيير كود. | منخفض |

---

## 16) قرارات المهندس المؤقتة (يمكن للمالك تجاوزها)

| القرار | القيمة الحالية | البديل |
|--------|---------------|--------|
| Self-approval | ممنوع إلا لدور `admin` | يمكن تخفيفها بـflag إضافي لو المالك أراد |
| Rejection حالة نهائية (لا resubmit) | نعم | يمكن السماح بـresubmit عبر RPC مخصصة لاحقًا |
| Snapshot vs Live rule | Snapshot | (Live rule خطر — لا يُوصى به) |
| Delegation | غير مبني | ينفَّذ عند الطلب |
| Legacy flag default | OFF | مُقدَّس — لا يُشغَّل تلقائيًا في الإنتاج |

---

## 17) خلاصة الالتزام بالنقاط الثمان الأمنية

| النقطة | الحل المُنفَّذ | ملف/دالة |
|--------|---------------|-----------|
| 1 — لا تجاوز للخطوات إذا وُجدت سلسلة | Trigger `proc_req_update_guard_trg` + فحص `STEP_ORDER_VIOLATED` داخل RPC | `proc-approval-2-hardening.sql` |
| 2 — APPROVAL_CONFIGURATION_MISSING عند عدم تطابق قاعدة | Raise مع رمز صريح داخل `proc_submit_requisition` | `proc-approval-2-hardening.sql` |
| 3 — Feature flag واضح للـfallback | `proc_approval_settings.allow_legacy_approval` (Default FALSE) + UI toggle مع تحذير | `proc-approval-2-hardening.sql` + `index.html.html` |
| 4 — لا تحويل لـPO قبل الاعتماد | Trigger `proc_po_creation_guard_trg` (BEFORE INSERT) | `proc-approval-2-hardening.sql` |
| 5 — لا تعديل الحقول المؤثرة على القاعدة بعد بدء المسار | Trigger `proc_req_update_guard_trg` + `proc_req_items_write_guard_trg` | `proc-approval-2-hardening.sql` |
| 6 — رفض إلزامي بسبب | فحص داخل RPCs (`proc_reject_step`, `proc_legacy_decide_requisition`) + Trigger + UI validation | متعدد الطبقات |
| 7 — auth.uid + role + step check من DB | كل RPC تتحقق: `current_app_user_id()` NULL → AUTH_REQUIRED، `is_active` → USER_INACTIVE، دور → ROLE_MISMATCH، ترتيب → STEP_ORDER_VIOLATED | كل RPC |
| 8 — منع الاعتماد المكرر والتزامن | `UNIQUE(requisition_id, step_no)` + `FOR UPDATE` + `pg_advisory_xact_lock` + `status <> 'pending'` check | كل RPC |

---

**التوصية:** الفرع جاهز للـPreview بعد تطبيق الملفين `proc-approval-1.sql` ثم `proc-approval-2-hardening.sql` على قاعدة اختبار وتنفيذ `proc-approval-tests.sql` للتحقق. **لا Push إلى main حتى تكتمل الاختبارات اليدوية على Preview.**
