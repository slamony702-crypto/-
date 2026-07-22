-- اختبارات المهام — ✅ EXECUTED LOCALLY, PASS
--  A1 not_started->completed              → PASS
--  A2 موظف يعدّل مكتملة                    → PASS (رُفض)
--  A3 مدير قسم يعيد فتحها                  → PASS (in_progress)
-- RLS: NOT EXECUTED — REQUIRES SUPABASE STAGING
--  (المكلَّف يعدّل مهمته؛ department_tasks.insert بـassigned_by=self؛ نطاق القسم.)
\set ON_ERROR_STOP 0
set session pilot.uid='20'; set session pilot.role='branch_manager';
insert into action_items(id,title,assigned_to,status) values (971,'مهمة',30,'not_started');
update action_items set status='completed' where id=971;   -- A1 OK
set session pilot.uid='30'; set session pilot.role='employee';
update action_items set progress_percent=50 where id=971;  -- A2 ERROR
set session pilot.role='department_manager';
update action_items set status='in_progress' where id=971; -- A3 OK
select 'verify' t, status from action_items where id=971;  -- in_progress
delete from action_items where id=971; delete from pilot_audit_log where record_id='971';
