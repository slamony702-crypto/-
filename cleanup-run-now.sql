-- ============================================================
-- تشغيل سريع — نسخة جاهزة للصق مباشرة في Supabase SQL Editor
-- ============================================================
-- خطوة واحدة قبل الضغط على Run:
--   1) شغّل الاستعلام الأول (SELECT) وحده عشان تشوف id الرميح وعبدالرحمن ونايف
--   2) استبدل الـ 3 أرقام في السطر المُعلَّم بـ ⬇️ ⬇️ ⬇️
--   3) اضغط Run على الكتلة كلها (من begin لـ commit)
-- ============================================================


-- ═══ الاستعلام 1: هات أرقام المستخدمين ═══
select id, username, full_name, role
from users
order by role, full_name;


-- ═══ الاستعلام 2: التنظيف — بعد ما تحط الأرقام ═══
begin;

-- ⬇️ ⬇️ ⬇️ حط هنا الأرقام اللي طلعت من الاستعلام الأول ⬇️ ⬇️ ⬇️
create temporary table keep_users (id bigint) on commit drop;
insert into keep_users values
  (0),   -- ⚠️ id الرميح
  (0),   -- ⚠️ id عبدالرحمن
  (0);   -- ⚠️ id نايف العتيبي
-- ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️

-- حماية: لو نسيت تحط الأرقام، السكربت يوقف
do $$
begin
  if (select count(*) from keep_users where id > 0) < 3 then
    raise exception 'خطأ: لم تُدخل الأرقام الثلاثة بعد. راجع السطور المعلّمة أعلاه.';
  end if;
end $$;
delete from keep_users where id <= 0;

-- ═══ حذف بيانات الاجتماعات ═══
delete from meeting_preparation_reports;
delete from meeting_agenda;
delete from meeting_attendees;
delete from meeting_requests;

-- ═══ حذف المهام والقرارات ═══
delete from action_items;
delete from decision_acknowledgments;
delete from decision_activity_log;
delete from decision_sub_responsibles;
delete from decision_viewers;
delete from decisions;
delete from department_tasks;

-- ═══ حذف مشاريع التنفيذ ═══
delete from task_project_updates;
delete from task_project_members;
delete from task_projects;

-- ═══ حذف المحادثات والرسائل ═══
delete from message_reads;
delete from messages;
delete from conversation_members;
delete from conversations;

-- ═══ حذف الإشعارات والتواصل الطارئ ═══
delete from notifications;
delete from emergency_activity_log;
delete from emergency_recipients;
delete from emergency_alerts;

-- ═══ حذف بيانات الصيانة كاملة ═══
delete from maintenance_timeline;
delete from maintenance_attachments;
delete from maintenance_receipts;
delete from maintenance_repairs;
delete from maintenance_finance_approvals;
delete from maintenance_quotes;
delete from maintenance_inspections;
delete from maintenance_requests;
delete from maintenance_preventive_schedule;
delete from maintenance_equipment;
delete from maintenance_suppliers;

-- ═══ حذف الجودة (الزيارات فقط — القوالب تبقى) ═══
delete from quality_attachments;
delete from quality_visit_sections;
delete from quality_visit_items;
delete from quality_visits;

-- ═══ حذف طلبات الانضمام وسجل النشاط ═══
delete from signup_requests;
delete from user_activity_log;

-- ═══ حذف الاجتماعات نفسها ═══
delete from meetings;

-- ═══ تنظيف ارتباطات المستخدمين قبل حذفهم ═══
delete from user_permission_overrides where user_id not in (select id from keep_users);
update users set direct_manager_id = null
  where direct_manager_id is not null
    and direct_manager_id not in (select id from keep_users);

-- ═══ حذف كل المستخدمين ما عدا الثلاثة ═══
delete from users where id not in (select id from keep_users);

-- ═══ المراجعة النهائية: لازم يظهر 3 صفوف بس ═══
select id, username, full_name, role from users order by id;

commit;
