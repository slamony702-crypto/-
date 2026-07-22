# 40 — فجوات قاعدة البيانات الشاملة

> **المرجع:** `_system_discovery/DATABASE_OVERVIEW.md`.

## أ) الأرقام

- 121 جدول SQL versioned (Waves 0-4).
- 75+ جدول بلا SQL versioned (الأصل قبل Wave 0).
- 175 اسم جدول unique في `sb.from(...)`.
- 90+ RPC / SQL function.

## ب) الفجوات

### ب-1) جداول بلا SQL versioned (R-07 عالية)
```
meetings, meeting_attendees, meeting_agenda, meeting_tasks,
meeting_requests, meeting_preparation_reports,
action_items,
decisions, decision_sub_responsibles, decision_viewers, decision_acknowledgments, decision_activity_log,
department_tasks, task_projects, task_project_members, task_project_updates,
conversations, conversation_members, messages, message_reads,
emergency_alerts, emergency_recipients, emergency_activity_log,
maintenance_* (11 جدول),
quality_* (6 جداول),
cafe_* (4 جداول),
company_vision, department_goals,
users, role_permissions, user_permission_overrides, user_activity_log, signup_requests,
branches, departments, branch_assets,
notifications
```

**الحل:** dump كل schemas من Supabase (`pg_dump --schema-only`) إلى SQL versioned files.

### ب-2) عدم توحيد بين الجداول
- `crm_customers` مقابل `acct_customers` (R-08).
- `departments` مقابل `hr_departments`.
- `branch_assets` مقابل `maintenance_equipment` مقابل `maintenance_assets`.
- `acct_purchase_orders` مقابل `proc_purchase_orders`.
- `meeting_tasks` مقابل `action_items`.

### ب-3) عمود بلا أمان
- `users.password_plain` (R-01 حرجة).
- `int_webhook_endpoints.secret_token` (R-05 عالية).

### ب-4) ترقيم COUNT+1
15+ دالة ترقيم تستخدم COUNT+1 (R-18 منخفضة، race condition تحت حمل عالي).

### ب-5) Indexes / Performance
- تم إضافة (v121): `pos_txn_completed_date_idx`.
- **مطلوب:** indexes على `notifications(user_id, is_read)`, `action_items(assigned_to, status)`, ...

### ب-6) FKs مفقودة أو ضعيفة
- `Franchise sales_reports.contract_id` — verify.
- `crm_customers.acct_customer_id` — غير موجود (R-08).
- `haccp_health_certificates.user_id` — قد تربط بـ HR.
- POS transaction ↔ delivery order (اختياري فقط).
- Documents polymorphic (بلا FK صارم).

### ب-7) Triggers مطلوبة
- `notification_on_status_change` (موحد بدل insert manual).
- `audit_log_on_state_transition` (كل حالة تسجل).
- `franchise_auto_create_ar_invoice` (لو المالك يقرر).

### ب-8) RLS بحاجة توحيد
- كل schema Wave 1-4 له سياساته الخاصة.
- توصية: نقل RLS إلى Supabase JWT (R-02) + توحيد الأنماط.

## ج) دوال Auto Journal (10 كاملة)

كل الدوال موجودة وشغالة. لكن:
- **بعضها بلا شاشة اعتماد** (`close_fiscal_year`, `run_monthly_depreciation`).
- **CASH_FLOW RPC غير موجود** (R-16).

## د) Triggers

100+ trigger من نوع `updated_at`. Auto-numbering triggers. Validation triggers (`acct_validate_*`).

## هـ) Views

- المرجع لم يذكر Views كثيرة — قد تكون فرصة لإضافة materialized views لتسريع BI.

## و) توصيات

1. **HIGH:** dump SQL versioned لكل جدول (R-07).
2. **HIGH:** توحيد `crm_customers` و `acct_customers` (R-08).
3. **HIGH:** إزالة `password_plain` (R-01).
4. **MEDIUM:** إضافة indexes للأداء.
5. **MEDIUM:** توحيد patterns RLS + الانتقال لـ JWT (R-02).
6. **LOW:** انتقال ترقيم إلى SEQUENCE.
