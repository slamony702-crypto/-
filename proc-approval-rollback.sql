-- ═══════════════════════════════════════════════════════════
-- ROLLBACK كامل لطبقة اعتماد طلبات الشراء
-- ═══════════════════════════════════════════════════════════
-- ⚠️ يحذف كل ما أنشأته Migrations 1-5 من هذه الموجة
-- ⚠️ لا يمس أي جدول موجود مسبقًا (proc_requisitions, ...)
-- ⚠️ لا يستعيد بيانات — استخدم Backup إذا احتجت لاستعادتها
-- ═══════════════════════════════════════════════════════════
-- التنفيذ: من Supabase SQL Editor أو psql على staging
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════
-- (1) إسقاط Triggers على الجداول الأصلية (Migration 2 hardening + Migration 5)
-- ═══════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS proc_req_update_guard_trg           ON proc_requisitions;
DROP TRIGGER IF EXISTS proc_req_items_write_guard_trg      ON proc_requisition_items;
DROP TRIGGER IF EXISTS proc_po_creation_guard_trg          ON proc_purchase_orders;
DROP TRIGGER IF EXISTS proc_appr_rules_history_trg         ON proc_approval_rules;
DROP TRIGGER IF EXISTS proc_appr_rules_delete_guard_trg    ON proc_approval_rules;
DROP TRIGGER IF EXISTS proc_appr_settings_history_trg      ON proc_approval_settings;
DROP TRIGGER IF EXISTS proc_approval_rules_updated_at      ON proc_approval_rules;
DROP TRIGGER IF EXISTS proc_approval_settings_updated_at   ON proc_approval_settings;

-- ═══════════════════════════════════════════════════════════
-- (2) إسقاط الفهارس الفريدة الإضافية (Migration 5)
-- ═══════════════════════════════════════════════════════════
DROP INDEX IF EXISTS proc_po_unique_requisition;
DROP INDEX IF EXISTS proc_approval_rules_rank_idx;
DROP INDEX IF EXISTS proc_appr_rules_hist_rule_idx;
DROP INDEX IF EXISTS proc_appr_rules_hist_actor_idx;
DROP INDEX IF EXISTS proc_req_appr_source_rule_idx;

-- ═══════════════════════════════════════════════════════════
-- (3) إسقاط دوال Guards + Notification helper + RPCs
-- ═══════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS proc_req_update_guard();
DROP FUNCTION IF EXISTS proc_req_items_write_guard();
DROP FUNCTION IF EXISTS proc_po_creation_guard();
DROP FUNCTION IF EXISTS proc_appr_rules_history_trg_fn();
DROP FUNCTION IF EXISTS proc_appr_rules_delete_guard_fn();
DROP FUNCTION IF EXISTS proc_appr_settings_history_trg_fn();
DROP FUNCTION IF EXISTS proc_notify_step_assignees(BIGINT);

DROP FUNCTION IF EXISTS proc_legacy_decide_requisition(BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS proc_submit_requisition(BIGINT);
DROP FUNCTION IF EXISTS proc_approve_step(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_reject_step(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_cancel_requisition_approval(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_get_approval_chain(BIGINT);
DROP FUNCTION IF EXISTS proc_match_approval_rules(NUMERIC, BIGINT, BIGINT);
DROP FUNCTION IF EXISTS proc_requisition_total(BIGINT);

-- ═══════════════════════════════════════════════════════════
-- (4) إسقاط الجداول الجديدة (CASCADE يحذف policies/FKs الفرعية)
-- ═══════════════════════════════════════════════════════════
DROP TABLE IF EXISTS proc_approval_activity          CASCADE;
DROP TABLE IF EXISTS proc_approval_rules_history     CASCADE;
DROP TABLE IF EXISTS proc_requisition_approvals      CASCADE;
DROP TABLE IF EXISTS proc_approval_rules             CASCADE;
DROP TABLE IF EXISTS proc_approval_settings          CASCADE;

-- ═══════════════════════════════════════════════════════════
-- (5) إسقاط الأعمدة المضافة على جداول قائمة (Migration 2 + 4)
-- ═══════════════════════════════════════════════════════════
ALTER TABLE proc_requisitions
  DROP COLUMN IF EXISTS amount_at_submit,
  DROP COLUMN IF EXISTS submitted_at;

-- ملاحظة: لا يوجد أعمدة مضافة على proc_requisition_items
-- ولا على proc_purchase_orders (فقط UNIQUE index أُسقط في الخطوة 2)

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- التحقق بعد Rollback:
--   -- يجب أن تعود فارغة:
--   SELECT relname FROM pg_class
--     WHERE relname IN ('proc_approval_rules','proc_requisition_approvals',
--                       'proc_approval_activity','proc_approval_settings',
--                       'proc_approval_rules_history');
--   SELECT proname FROM pg_proc
--     WHERE proname IN ('proc_submit_requisition','proc_approve_step',
--                       'proc_reject_step','proc_cancel_requisition_approval',
--                       'proc_get_approval_chain','proc_match_approval_rules',
--                       'proc_requisition_total','proc_legacy_decide_requisition',
--                       'proc_notify_step_assignees',
--                       'proc_req_update_guard','proc_req_items_write_guard',
--                       'proc_po_creation_guard');
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'proc_requisitions'
--       AND column_name IN ('amount_at_submit','submitted_at');
-- ═══════════════════════════════════════════════════════════
-- ⚠️ ملاحظة UI: بعد Rollback، الواجهة ستفشل عند استدعاء RPCs المفقودة.
-- خيارات معالجة:
--   (أ) استرجع الفرع لـcommit قبل موجة الاعتماد (git checkout <sha> -- index.html.html)
--   (ب) اعتمد على Feature Detection في الـUI (مبنية في هذه الموجة) لعزل الأعطال
-- ═══════════════════════════════════════════════════════════
