-- Minimal local stand-ins for the pieces Supabase provides, so the Ledgerly
-- schema and RPCs can be exercised on a plain PostgreSQL instance.
-- Never run this against a Supabase project.

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text unique,
  created_at timestamptz not null default now()
);

-- Mirrors Supabase's auth.uid(): the `sub` claim of the current JWT.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    (case
       when coalesce(current_setting('request.jwt.claims', true), '') in ('', 'null') then '{}'
       else current_setting('request.jwt.claims', true)
     end)::jsonb ->> 'sub',
    ''
  )::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;
