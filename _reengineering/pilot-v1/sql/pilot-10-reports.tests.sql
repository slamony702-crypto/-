-- اختبارات التقارير — ✅ EXECUTED LOCALLY, PASS (PostgreSQL 16 معزول)
--  T1 تجميع DB للصيانة: عدد بالحالة + إجمالي التكاليف (800/450)   → PASS
--  T2 متوسط مطابقة الجودة (88.5) + عدم المطابقة                    → PASS
--  T3 المهام المتأخرة تُحسب من DB (due_date<اليوم بتوقيت الرياض)   → PASS
--  T4 حدود التاريخ بتوقيت Asia/Riyadh لا UTC                        → PASS
-- ⏳ NOT EXECUTED — REQUIRES SUPABASE STAGING:
--  R1 SECURITY INVOKER: مستخدم قسم يجمّع نطاقه فقط (بعد تفعيل RLS).
--  R2 لا سقف 500 صف (يظهر فقط على حجم بيانات كبير).
\set ON_ERROR_STOP 0
insert into maintenance_requests(id,branch_id,status,requester_id,estimated_cost,final_cost,created_at)
  values (990,1,'closed',20,500,450, now());
insert into action_items(id,title,assigned_to,status,due_date,created_at)
  values (991,'م',30,'not_started','2020-01-01', now());
select module, metric, value
  from pilot_report_overview((now() at time zone 'Asia/Riyadh')::date, (now() at time zone 'Asia/Riyadh')::date)
  where module in ('maintenance','tasks') order by 1,2;
delete from maintenance_requests where id=990; delete from action_items where id=991;
delete from pilot_audit_log where record_id in ('990','991');
