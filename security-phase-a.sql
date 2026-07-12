-- ==========================================
-- Security Migration — Phase A: Enable Supabase Auth
-- (Safe to run anytime, does NOT lock RLS yet.)
-- ==========================================

-- 1) Add auth_id + email columns on users
alter table users add column if not exists auth_id uuid;
alter table users add column if not exists email text;

-- Ensure email uniqueness (best-effort backfill)
update users
set email = coalesce(email, lower(regexp_replace(username, '[^a-zA-Z0-9]', '', 'g')) || '@shouon.internal')
where email is null and username is not null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'users_email_unique') then
    alter table users add constraint users_email_unique unique (email);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'users_auth_id_unique') then
    alter table users add constraint users_auth_id_unique unique (auth_id);
  end if;
end $$;

-- 2) Trigger: auto-confirm auth users on signup
--    (so signup can complete without email verification)
create or replace function auto_confirm_auth_user()
returns trigger language plpgsql security definer as $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end $$;

drop trigger if exists tr_auto_confirm_auth on auth.users;
create trigger tr_auto_confirm_auth
  before insert on auth.users
  for each row execute function auto_confirm_auth_user();

-- 3) Progress query — check how many users have migrated:
--    select count(*) filter (where auth_id is not null) as migrated,
--           count(*) filter (where auth_id is null) as pending,
--           count(*) as total
--    from users where is_active = true;
