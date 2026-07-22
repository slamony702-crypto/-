-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — اختبارات موديول طلبات تطبيقات التوصيل
-- ═══════════════════════════════════════════════════════════════════════
-- ✅ منطق الحرّاس والتكرار — EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول).
-- ⏳ RLS لكل دور — NOT EXECUTED — REQUIRES SUPABASE STAGING.
--
-- النتائج (كما نُفِّذت):
--   D1 تكرار (تطبيق+رقم طلب+فرع)              → PASS (رُفض: unique)
--   D2 submitted→accepted                     → PASS (نجح، reviewed_by/at مضبوط)
--   D3 حسم مرتين (accepted→rejected)          → PASS (رُفض: محسوم بالفعل)
--   D4 تعديل طلب محسوم                         → PASS (رُفض)
--   D5 رفض بلا سبب                             → PASS (رُفض)
--   D6 رفض بسبب صحيح                           → PASS (نجح)
--
-- تشغيل: بعد baseline + pilot-01 + pilot-05، كـ superuser مع
-- set session pilot.uid='20'; set session pilot.role='branch_manager';
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP 0
set session pilot.uid='20'; set session pilot.role='branch_manager';

insert into branch_delivery_requests(id,branch_id,company_id,order_ref,invoice_photo_url,created_by,status)
  values (960,1,1,'ORD-960','u',20,'submitted');
insert into branch_delivery_requests(branch_id,company_id,order_ref,invoice_photo_url,created_by)
  values (1,1,'ORD-960','u2',20);                                     -- D1 ERROR (dedup)
update branch_delivery_requests set status='accepted' where id=960;   -- D2 OK
update branch_delivery_requests set status='rejected', rejection_reason='x' where id=960; -- D3 ERROR
update branch_delivery_requests set notes='y' where id=960;           -- D4 ERROR (settled)

insert into branch_delivery_requests(id,branch_id,company_id,invoice_photo_url,created_by,status)
  values (961,1,1,'u',20,'submitted');
update branch_delivery_requests set status='rejected' where id=961;   -- D5 ERROR (no reason)
update branch_delivery_requests set status='rejected', rejection_reason='فاتورة غير واضحة' where id=961; -- D6 OK

select 'verify' as t, id, status, rejection_reason from branch_delivery_requests where id in (960,961) order by id;

delete from branch_delivery_requests where id in (960,961);
delete from pilot_audit_log where table_name='branch_delivery_requests';

-- ═══ RLS (REQUIRES SUPABASE STAGING) ═══
-- R1 مدير فرع1 لا يراجع طلب فرع2.
-- R2 موظف عادي لا يُنشئ طلبًا (سياسة INSERT من delivery-requests-schema).
-- R3 الزائر غير المسجّل يرى صفرًا (مُتحقَّق سابقًا على الإنتاج).
