-- ============================================================
-- تشغيل سريع — نسخة مقاومة للأخطاء (تتخطى الجداول غير الموجودة)
-- ============================================================
-- خطوة واحدة قبل الضغط على Run:
--   1) شغّل الاستعلام الأول (SELECT) وحده لمعرفة id المستخدمين المطلوب إبقاؤهم
--   2) استبدل الأرقام في السطر المُعلَّم بـ ⬇️
--   3) اضغط Run على الكتلة كاملة (من begin لـ commit)
-- ============================================================


-- ═══ الاستعلام 1: هات أرقام المستخدمين ═══
select id, username, full_name, role
from users
order by role, full_name;


-- ═══ الاستعلام 2: التنظيف الآمن ═══
begin;

-- ⬇️ ⬇️ ⬇️ استبدل الأصفار بأرقام الرميح وعبدالرحمن ونايف ⬇️ ⬇️ ⬇️
create temporary table keep_users (id bigint) on commit drop;
insert into keep_users values
  (1),   -- ⚠️ id الرميح
  (5),   -- ⚠️ id عبدالرحمن
  (12);  -- ⚠️ id نايف العتيبي
-- ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️ ⬆️

-- حماية: لو نسيت تحط الأرقام، السكربت يوقف
do $$ begin
  if (select count(*) from keep_users where id > 0) < 3 then
    raise exception 'خطأ: لم تُدخل الأرقام الثلاثة بعد. راجع السطور المعلّمة أعلاه.';
  end if;
end $$;
delete from keep_users where id <= 0;

-- ═══ حذف آمن: يتخطى أي جدول غير موجود بدون خطأ ═══
do $$
declare
  tbl text;
  drop_list text[] := array[
    -- الاجتماعات وما يتبعها
    'meeting_preparation_reports', 'meeting_agenda', 'meeting_attendees', 'meeting_requests',
    -- المهام والقرارات
    'action_items',
    'decision_acknowledgments', 'decision_activity_log', 'decision_sub_responsibles',
    'decision_viewers', 'decisions',
    'department_tasks', 'department_goals',
    -- مشاريع التنفيذ
    'task_project_updates', 'task_project_members', 'task_projects',
    -- المحادثات والرسائل
    'message_reads', 'messages', 'conversation_members', 'conversations',
    -- الإشعارات والتواصل الطارئ
    'notifications',
    'emergency_activity_log', 'emergency_recipients', 'emergency_alerts',
    -- الصيانة
    'maintenance_timeline', 'maintenance_attachments', 'maintenance_receipts',
    'maintenance_repairs', 'maintenance_finance_approvals', 'maintenance_quotes',
    'maintenance_inspections', 'maintenance_requests',
    'maintenance_preventive_schedule', 'maintenance_equipment', 'maintenance_suppliers',
    -- الجودة (الزيارات فقط — القوالب quality_sections/quality_items تبقى)
    'quality_attachments', 'quality_visit_sections', 'quality_visit_items', 'quality_visits',
    -- طلبات الانضمام وسجل النشاط
    'signup_requests', 'user_activity_log',
    -- الاجتماعات نفسها (في الآخر بعد حذف كل ما يشير إليها)
    'meetings'
  ];
begin
  foreach tbl in array drop_list loop
    if to_regclass('public.' || tbl) is not null then
      execute format('delete from %I', tbl);
      raise notice 'تم مسح: %', tbl;
    else
      raise notice 'تم تجاوز (غير موجود): %', tbl;
    end if;
  end loop;
end $$;

-- ═══ تنظيف ارتباطات المستخدمين قبل حذفهم ═══
do $$ begin
  if to_regclass('public.user_permission_overrides') is not null then
    delete from user_permission_overrides where user_id not in (select id from keep_users);
  end if;
end $$;

update users set direct_manager_id = null
  where direct_manager_id is not null
    and direct_manager_id not in (select id from keep_users);

-- ═══ حذف كل المستخدمين ما عدا الثلاثة ═══
delete from users where id not in (select id from keep_users);

-- ═══ المراجعة النهائية: لازم يظهر 3 صفوف بس ═══
select id, username, full_name, role from users order by id;

commit;
