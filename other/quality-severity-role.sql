-- ═══════════════════════════════════════════════════════════
-- إضافة أعمدة "شدّة المخالفة" و "مسؤول الإصلاح" لبنود زيارات الجودة
-- تشغيل هذا الملف اختياري — لو ما اتشغّلش، البيانات تنحفظ في
-- custom_corrective_action كـ prefix ([شدة:...][مسؤول:...])
-- ═══════════════════════════════════════════════════════════

ALTER TABLE quality_visit_items
  ADD COLUMN IF NOT EXISTS severity text,
  ADD COLUMN IF NOT EXISTS responsible_role text;

COMMENT ON COLUMN quality_visit_items.severity IS 'شدّة المخالفة: critical | medium | low';
COMMENT ON COLUMN quality_visit_items.responsible_role IS 'مسؤول الإصلاح كدور: branch_manager | maintenance_dept | chef | quality_officer | quality_maint_manager';
