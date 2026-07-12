-- ==========================================
-- Security Migration — Phase B: Lock down RLS
-- ⚠️ لا تشغّل هذا الملف حتى يسجّل جميع المستخدمين النشطين
-- ⚠️ دخولهم مرة واحدة على الأقل بعد نشر مرحلة أ.
--
-- تحقق أولًا:
--   select count(*) filter (where auth_id is null) as pending
--   from users where is_active = true;
--   -- pending يجب أن يكون 0
-- ==========================================

do $$
declare pending int;
begin
  select count(*) into pending from users where is_active = true and auth_id is null;
  if pending > 0 then
    raise exception 'لا يمكن قفل RLS: يوجد % مستخدم نشط لم يترحّل بعد. اطلب منهم تسجيل الدخول أولًا.', pending;
  end if;
end $$;

-- 1) استبدال السياسات المفتوحة بسياسات authenticated
do $$
declare
  tbl text;
  tables text[] := array[
    'users','departments','meetings','meeting_attendees','meeting_agenda','meeting_preparation_reports','meeting_requests',
    'action_items','decisions','decision_acknowledgments','decision_activity_log','decision_sub_responsibles','decision_viewers',
    'department_tasks','department_goals','task_projects','task_project_members','task_project_updates',
    'conversations','conversation_members','messages','message_reads',
    'notifications','emergency_alerts','emergency_recipients','emergency_activity_log',
    'company_vision','user_activity_log','role_permissions','user_permission_overrides',
    'branches','maintenance_requests','maintenance_suppliers','maintenance_inspections','maintenance_quotes',
    'maintenance_finance_approvals','maintenance_repairs','maintenance_receipts','maintenance_attachments','maintenance_timeline',
    'quality_sections','quality_items','quality_visits','quality_visit_items','quality_visit_sections','quality_attachments'
  ];
  pol record;
begin
  foreach tbl in array tables loop
    -- تأكد إن RLS مفعّلة
    execute format('alter table %I enable row level security', tbl);
    -- امسح كل السياسات المفتوحة
    for pol in select policyname from pg_policies where schemaname = 'public' and tablename = tbl loop
      execute format('drop policy if exists %I on %I', pol.policyname, tbl);
    end loop;
    -- سياسات جديدة: مصادَق فقط
    execute format('create policy %I on %I for select to authenticated using (true)', tbl || '_auth_select', tbl);
    execute format('create policy %I on %I for insert to authenticated with check (true)', tbl || '_auth_insert', tbl);
    execute format('create policy %I on %I for update to authenticated using (true) with check (true)', tbl || '_auth_update', tbl);
    execute format('create policy %I on %I for delete to authenticated using (true)', tbl || '_auth_delete', tbl);
  end loop;
end $$;

-- 2) اختياري: امسح كلمات المرور نصًا صريحًا (بعد التأكد من الترحيل)
--    ⚠️ لا تعود ولا يمكن استرجاعها. شغّلها فقط بعد التأكد.
-- alter table users drop column if exists password_plain;

-- 3) سياسات Storage: قصر maintenance bucket على المصادَقين فقط
--    (إن أردت السماح للجميع بالقراءة، احذف السطر التالي)
-- do $$ begin
--   drop policy if exists "maint_obj_select" on storage.objects;
--   create policy "maint_obj_select" on storage.objects for select to authenticated using (bucket_id = 'maintenance');
--   drop policy if exists "maint_obj_insert" on storage.objects;
--   create policy "maint_obj_insert" on storage.objects for insert to authenticated with check (bucket_id = 'maintenance');
--   drop policy if exists "maint_obj_delete" on storage.objects;
--   create policy "maint_obj_delete" on storage.objects for delete to authenticated using (bucket_id = 'maintenance');
-- end $$;
