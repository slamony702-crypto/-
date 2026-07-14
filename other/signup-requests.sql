-- ==========================================
-- Signup Requests: طلبات انضمام من زوار غير مسجّلين
-- Safe to re-run.
-- ==========================================
create table if not exists signup_requests (
  id bigserial primary key,
  full_name text not null,
  mobile_number text not null,
  email text not null,
  job_title text not null,
  region text not null,
  notes text,
  status text default 'pending', -- pending | approved | rejected
  created_at timestamptz default now(),
  reviewed_by bigint references users(id) on delete set null,
  reviewed_at timestamptz
);
create index if not exists idx_signup_requests_status on signup_requests(status);

alter table signup_requests enable row level security;

-- زائر غير مسجّل (anon) يقدر يرسل طلب بس — مفيش قراءة ولا تعديل
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'signup_requests_anon_insert') then
    create policy signup_requests_anon_insert on signup_requests for insert to anon with check (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'signup_requests_auth_select') then
    create policy signup_requests_auth_select on signup_requests for select to authenticated using (true);
    create policy signup_requests_auth_update on signup_requests for update to authenticated using (true) with check (true);
    create policy signup_requests_auth_delete on signup_requests for delete to authenticated using (true);
  end if;
end $$;
