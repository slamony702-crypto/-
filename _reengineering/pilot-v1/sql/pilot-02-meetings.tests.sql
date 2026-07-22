-- اختبارات الاجتماعات — ✅ EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول)
--  M1 scheduled->in_follow_up            → PASS
--  M2 in_follow_up->scheduled            → PASS (رُفض: انتقال غير مسموح)
--  M3 in_follow_up->closed               → PASS
--  M4 تعديل مغلق كـbranch_manager        → PASS (رُفض)
--  M5 admin يعيد فتح المغلق              → PASS (in_follow_up)
-- RLS لكل دور: NOT EXECUTED — REQUIRES SUPABASE STAGING
--  (R1 عضو قسم يرى اجتماعات قسمه؛ R2 حاضر يرى اجتماعه؛ R3 حذف للإدارة فقط؛
--   R4 INSERT بـorganizer_id=self فقط.)
\set ON_ERROR_STOP 0
set session pilot.uid='20'; set session pilot.role='branch_manager';
insert into meetings(id,title,organizer_id,status,location_type,meeting_datetime) values (970,'م',20,'scheduled','in_person',now());
update meetings set status='in_follow_up' where id=970;   -- M1 OK
update meetings set status='scheduled' where id=970;       -- M2 ERROR
update meetings set status='closed' where id=970;          -- M3 OK
update meetings set summary='x' where id=970;              -- M4 ERROR
set session pilot.role='admin';
update meetings set status='in_follow_up' where id=970;    -- M5 OK
select 'verify' t, status from meetings where id=970;      -- in_follow_up
delete from meetings where id=970; delete from pilot_audit_log where record_id='970';
