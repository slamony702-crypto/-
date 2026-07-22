-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — اختبارات موديول الجودة
-- ═══════════════════════════════════════════════════════════════════════
-- ✅ منطق الحرّاس وفصل المهام — EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول).
-- ⏳ RLS لكل دور — NOT EXECUTED — REQUIRES SUPABASE STAGING.
--
-- النتائج (كما نُفِّذت):
--   Q1 draft→completed                                → PASS
--   Q2 completed→closed مباشرة (بلا تحقق)             → PASS (رُفض)
--   Q3 المفتِّش يعتمد زيارته (verified_by=inspector)   → PASS (رُفض: فصل مهام)
--   Q4 صاحب الإجراء يعتمد (verified_by=item owner)    → PASS (رُفض: فصل مهام)
--   Q5 طرف مستقل يعتمد                                → PASS (نجح، verified_at مضبوط)
--   Q6 تعديل عناصر بعد التحقق                          → PASS (رُفض)
--   Q7 إغلاق بلا نتيجة accepted                        → PASS (رُفض)
--   Q8 ضبط accepted ثم الإغلاق                         → PASS (نجح، closed_at مضبوط)
--   Q9 تعديل زيارة مغلقة                               → PASS (رُفض)
--
-- طريقة التشغيل: بعد baseline + pilot-01 + pilot-04، كـ superuser مع
-- set session pilot.uid='30'; set session pilot.role='employee';
-- ═══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP 0
set session pilot.uid='30'; set session pilot.role='employee';

insert into quality_visits(id,branch_id,inspector_id,status) values (950,1,30,'draft');
insert into quality_visit_items(visit_id,status,responsible_user_id) values (950,'non_conform',20);

update quality_visits set status='completed' where id=950;                       -- Q1 OK
update quality_visits set status='closed' where id=950;                          -- Q2 ERROR
update quality_visits set status='verified', verified_by=30 where id=950;        -- Q3 ERROR (inspector)
update quality_visits set status='verified', verified_by=20 where id=950;        -- Q4 ERROR (action owner)
update quality_visits set status='verified', verified_by=40 where id=950;        -- Q5 OK
insert into quality_visit_items(visit_id,status) values (950,'conform');         -- Q6 ERROR (post-verify)
update quality_visits set status='closed' where id=950;                          -- Q7 ERROR (not accepted)
update quality_visits set verification_result='accepted' where id=950;          -- set result
update quality_visits set status='closed' where id=950;                          -- Q8 OK
update quality_visits set notes='x' where id=950;                                -- Q9 ERROR (closed)

select 'verify' as t, status, verified_by, verification_result,
       verified_at is not null as vt, closed_at is not null as ct
from quality_visits where id=950;   -- expect closed / 40 / accepted / t / t

delete from quality_visit_items where visit_id=950;
delete from quality_visits where id=950;
delete from pilot_audit_log where record_id='950';

-- ═══ RLS (REQUIRES SUPABASE STAGING) ═══
-- R1 مفتّش فرع1 لا يرى زيارات فرع2.
-- R2 موظف لا يُنشئ زيارة بـ inspector_id ≠ نفسه.
-- R3 القوالب (sections/items) تُعدَّل من إدارة الجودة فقط.
-- R4 الجداول الفرعية ترث رؤية/إدارة الزيارة الأم.
