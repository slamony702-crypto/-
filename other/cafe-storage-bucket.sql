-- ═══════════════════════════════════════════════════════════
-- إنشاء bucket خاص لصور الكافيه — public read، authenticated write
-- ═══════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public)
values ('cafe', 'cafe', true)
on conflict (id) do nothing;

-- سياسات: قراءة عامة (للعرض)، رفع/تعديل/حذف للمصادَقين فقط
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'cafe_obj_select') then
    create policy "cafe_obj_select" on storage.objects for select
      to public using (bucket_id = 'cafe');
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_obj_insert') then
    create policy "cafe_obj_insert" on storage.objects for insert
      to authenticated with check (bucket_id = 'cafe');
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_obj_update') then
    create policy "cafe_obj_update" on storage.objects for update
      to authenticated using (bucket_id = 'cafe') with check (bucket_id = 'cafe');
  end if;
  if not exists (select 1 from pg_policies where policyname = 'cafe_obj_delete') then
    create policy "cafe_obj_delete" on storage.objects for delete
      to authenticated using (bucket_id = 'cafe');
  end if;
end $$;
