# 42 — الإشعارات وسجلات التدقيق الشاملة

## أ) نظام الإشعارات

### أ-1) جدول `notifications`
- بلا SQL versioned (R-07).
- أعمدة رئيسية: `user_id`, `title`, `body`, `type`, `link`, `is_read`, `created_at`.
- RLS: self only.

### أ-2) قنوات الإرسال
- **Push (in-app):** الأساسي — الشريط العلوي + `#notifications`.
- **Emergency channel:** موازي، بصوت مميز.
- **Email:** غير مفعّل داخل النظام (اعتماد على Supabase Auth للـ welcome/reset).
- **WhatsApp/SMS:** بنية Integrations جاهزة (Twilio, WhatsApp Cloud) — بلا workers.

### أ-3) الأحداث التي تولّد إشعارات
- meeting scheduled / cancelled / reminder (24h/1h/15m).
- action_item assigned / due_soon / overdue.
- department_task assigned / comment / due.
- decision issued.
- maintenance request assigned / escalated.
- HR leave submitted / approved / rejected.
- Accounting bill approval request.
- POS session close (variance).
- Complaint escalation.
- Franchise royalty issued.
- Integrations event failure.

### أ-4) الفجوات
- **لا "mark all as read"** واضح.
- **لا "notification preferences"** لكل مستخدم.
- **لا "silent hours"**.
- **لا "digest يومي"**.
- **لا Push notifications حقيقية** (اعتماد على Web Push غير موثق).

## ب) سجلات التدقيق (Audit Logs)

### ب-1) الجداول
- `user_activity_log` — عام (بلا شاشة عرض).
- `decision_activity_log` — خاص بالقرارات.
- `emergency_activity_log` — خاص بالطوارئ.
- `ai_audit_log` — خاص بأدوات AI.
- `doc_access_log` — خاص بالمستندات (view/download).
- `pos_sessions` — variance محفوظ.
- `int_events` — كل تفاعل خارجي.

### ب-2) Immutability
- `loyalty_transactions` — INSERT-only (v107 قرار).
- `acct_journal_entries.posted` — immutable (validate trigger).
- `delivery_tracking` — INSERT-only.

### ب-3) الفجوات

1. **لا شاشة عرض `user_activity_log`** — بيانات موجودة بلا واجهة.
2. **لا audit log على `users` role changes.**
3. **لا audit log على `role_permissions` overrides.**
4. **HR بلا audit log خاص** (تعديل راتب، تغيير قسم، إلخ).
5. **Accounting** بلا audit log كامل على التعديلات قبل posting.
6. **لا "who changed what when"** واضح لكل موديول.

### ب-4) توصيات Audit

1. **إضافة شاشة `#audit_center`** موحدة (admin only).
2. **Trigger عام `log_activity()`** — كل UPDATE يسجل.
3. **حفظ old/new values** كـ JSONB.
4. **Retention policy** (سنوات وفقًا للامتثال).

## ج) تنبيهات الاعتمادية

- **`log_change` trigger** موحد يمكن أن يحل مشكلة الـ audit gaps.
- **`before UPDATE` trigger** يعطي control كامل.

## د) توصيات عامة

1. **HIGH:** notification preferences per user.
2. **HIGH:** audit UI (admin).
3. **MEDIUM:** WhatsApp/SMS workers.
4. **MEDIUM:** digest emails.
5. **MEDIUM:** silent hours.
6. **LOW:** analytics على engagement.
