-- ============================================================
-- تنظيف البيانات التجريبية — نظام شؤون الغذاء
-- ============================================================
-- ⚠️⚠️ تحذير: هذا السكربت يحذف بيانات فعليًا ولا يمكن التراجع عنه.
--
-- قبل التشغيل، خُذ نسخة احتياطية:
--   Supabase Dashboard → Database → Backups (أو صدّر الجداول يدويًا)
--
-- يُبقي فقط على 3 مستخدمين (الرميح، عبدالرحمن، نايف العتيبي)
-- ويحذف كل الاجتماعات والزيارات والمهام والرسائل والإشعارات التجريبية،
-- بالإضافة إلى سجل المعدات والموردين وجداول الصيانة الوقائية.
-- لا يمس: الأقسام، الفروع، قوالب الجودة (البنود)، مصفوفة الصلاحيات، الرؤية.
-- ============================================================


-- ═══════════════════════════════════════════════════════════
-- الخطوة 1: شغّل هذا الاستعلام وحده أولًا
-- اعرف الـ id الخاص بكل من: الرميح، عبدالرحمن، نايف العتيبي
-- ═══════════════════════════════════════════════════════════
select id, username, full_name, role, is_active, created_at
from users
order by created_at;


-- ═══════════════════════════════════════════════════════════
-- الخطوة 2: بعد معرفة الأرقام من الخطوة 1،
-- ضع الـ 3 IDs الحقيقية في السطر المعلّم بـ ⚠️ ثم شغّل الكتلة كاملة
-- (كل شيء داخل transaction واحد: لو حصل أي خطأ، يتراجع كل شيء تلقائيًا)
-- ═══════════════════════════════════════════════════════════
begin;

-- المستخدمون المطلوب الإبقاء عليهم
create temporary table keep_users (id bigint) on commit drop;
insert into keep_users values
  (0),   -- ⚠️ استبدل بـ id الرميح
  (0),   -- ⚠️ استبدل بـ id عبدالرحمن
  (0);   -- ⚠️ استبدل بـ id نايف العتيبي

-- حماية: لا تكمل لو القائمة فيها صفر أو أقل من 3 (يمنع مسح الجميع بالخطأ)
do $$
begin
  if (select count(*) from keep_users where id > 0) < 3 then
    raise exception 'أدخل 3 IDs صحيحة في keep_users أولًا (لا تترك أي صفر).';
  end if;
end $$;

-- احذف الأصفار لو المستخدم نسي استبدال أحدها
delete from keep_users where id <= 0;

-- ── حذف البيانات التشغيلية (التجريبية) بالترتيب الآمن للمفاتيح الأجنبية ──

-- الاجتماعات وما يتبعها
delete from meeting_preparation_reports;
delete from meeting_agenda;
delete from meeting_attendees;
delete from meeting_requests;

-- المهام والقرارات
delete from action_items;
delete from decision_acknowledgments;
delete from decision_activity_log;
delete from decision_sub_responsibles;
delete from decision_viewers;
delete from decisions;
delete from department_tasks;

-- مشاريع التنفيذ
delete from task_project_updates;
delete from task_project_members;
delete from task_projects;

-- المحادثات والرسائل
delete from message_reads;
delete from messages;
delete from conversation_members;
delete from conversations;

-- الإشعارات والتواصل الطارئ
delete from notifications;
delete from emergency_activity_log;
delete from emergency_recipients;
delete from emergency_alerts;

-- الصيانة: المعاملات + سجل المعدات والموردين وجداول الصيانة الوقائية
delete from maintenance_timeline;
delete from maintenance_attachments;
delete from maintenance_receipts;
delete from maintenance_repairs;
delete from maintenance_finance_approvals;
delete from maintenance_quotes;
delete from maintenance_inspections;
delete from maintenance_requests;

-- سجل المعدات وجداول الصيانة الوقائية (احذف الجداول قبل المعدات التي تشير إليها)
delete from maintenance_preventive_schedule;
delete from maintenance_equipment;

-- الموردون
delete from maintenance_suppliers;

-- الجودة: الزيارات فقط — القوالب (quality_sections / quality_items) تبقى كما هي
delete from quality_attachments;
delete from quality_visit_sections;
delete from quality_visit_items;
delete from quality_visits;

-- طلبات الانضمام وسجل النشاط
delete from signup_requests;
delete from user_activity_log;

-- الاجتماعات نفسها (بعد حذف كل ما يشير إليها)
delete from meetings;

-- ── تنظيف الارتباطات قبل حذف المستخدمين ──
delete from user_permission_overrides
  where user_id not in (select id from keep_users);

-- فكّ ارتباط "المدير المباشر" لو كان يشير لمستخدم سيُحذف
update users set direct_manager_id = null
  where direct_manager_id is not null
    and direct_manager_id not in (select id from keep_users);

-- ── حذف كل المستخدمين ما عدا الثلاثة ──
delete from users where id not in (select id from keep_users);

-- عرض النتيجة النهائية للمراجعة
select id, username, full_name, role from users order by id;

commit;

-- ═══════════════════════════════════════════════════════════
-- ملاحظة: حسابات Supabase Auth (auth.users) لا تُحذف من هنا.
-- لحذف حسابات الدخول القديمة الوهمية:
--   Supabase Dashboard → Authentication → Users → احذف يدويًا
-- (غير ضروري وظيفيًا — بدون ملف مستخدم لن يستطيعوا الدخول أصلًا)
-- ═══════════════════════════════════════════════════════════
