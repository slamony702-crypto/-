-- اختبارات القرارات — ✅ EXECUTED LOCALLY, PASS
--  D1 new->executed مباشرة                → PASS (رُفض)
--  D2 new->in_progress->executed          → PASS
--  D3 تعديل معتمد كـbranch_manager        → PASS (رُفض)، updated_at مضبوط
-- RLS: NOT EXECUTED — REQUIRES SUPABASE STAGING
--  (المُنشئ/المسؤول/المشاهدون/نطاق القسم؛ حذف المعتمد ممنوع؛ INSERT بـcreated_by=self.)
\set ON_ERROR_STOP 0
set session pilot.uid='20'; set session pilot.role='branch_manager';
insert into decisions(id,decision_text,status,created_by) values (972,'قرار','new',20);
update decisions set status='executed' where id=972;       -- D1 ERROR
update decisions set status='in_progress' where id=972;    -- D2a OK
update decisions set status='executed' where id=972;       -- D2b OK
update decisions set notes='x' where id=972;               -- D3 ERROR
select 'verify' t, status, (updated_at is not null) ua from decisions where id=972;  -- executed / t
delete from decisions where id=972; delete from pilot_audit_log where record_id='972';
