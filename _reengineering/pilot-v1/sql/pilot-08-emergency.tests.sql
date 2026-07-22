-- اختبارات الطوارئ — ✅ EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول)
--  E1 new->closed مباشرة              → PASS (رُفض)
--  E2 new->in_progress                → PASS (first_response_at مضبوط)
--  E3 إغلاق بلا تقرير                  → PASS (رُفض)
--  E4 إغلاق بتقرير                     → PASS (closed + status=resolved + closed_at)
--  E5 حذف حالة طوارئ                   → PASS (رُفض: لا تُحذف)
-- RLS: NOT EXECUTED — REQUIRES SUPABASE STAGING
--  (المرسِل/المستقبِل/المستلمون/نطاق القسم؛ INSERT بـsender_id=self.)
\set ON_ERROR_STOP 0
set session pilot.uid='20'; set session pilot.role='branch_manager';
insert into emergency_alerts(id,title,message,sender_id,processing_status) values (980,'حريق','بلاغ',20,'new');
update emergency_alerts set processing_status='closed' where id=980;                            -- E1 ERROR
update emergency_alerts set processing_status='in_progress' where id=980;                       -- E2 OK
update emergency_alerts set processing_status='closed' where id=980;                            -- E3 ERROR
update emergency_alerts set processing_status='closed', closure_report='تمت السيطرة' where id=980; -- E4 OK
select 'verify' t, processing_status, status, (first_response_at is not null) fr, (closed_at is not null) ca from emergency_alerts where id=980;
delete from emergency_alerts where id=980;                                                      -- E5 ERROR (no delete)
-- تنظيف (يتطلب تعطيل تريجر المنع مؤقتًا):
-- alter table emergency_alerts disable trigger trg_em_nodelete;
-- delete from emergency_alerts where id=980; delete from pilot_audit_log where record_id='980';
-- alter table emergency_alerts enable trigger trg_em_nodelete;
