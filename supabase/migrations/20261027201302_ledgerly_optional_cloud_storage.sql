-- Optional per-user Ledgerly cloud workspace.
-- Local-only users do not need a row in this table.
create table if not exists public.ledgerly_cloud_data (
  user_id uuid not null references auth.users(id) on delete cascade,
  data_type text not null check (data_type in ('documents', 'customers', 'items', 'payments', 'profile')),
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, data_type),
  constraint ledgerly_cloud_data_payload_shape check (
    (data_type = 'profile' and jsonb_typeof(payload) = 'object')
    or
    (data_type <> 'profile' and jsonb_typeof(payload) = 'array')
  )
);

alter table public.ledgerly_cloud_data enable row level security;

revoke all on public.ledgerly_cloud_data from anon, authenticated;
grant select, insert, update, delete on public.ledgerly_cloud_data to authenticated;

drop policy if exists "Users can read their own Ledgerly cloud data" on public.ledgerly_cloud_data;
create policy "Users can read their own Ledgerly cloud data"
  on public.ledgerly_cloud_data
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own Ledgerly cloud data" on public.ledgerly_cloud_data;
create policy "Users can insert their own Ledgerly cloud data"
  on public.ledgerly_cloud_data
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own Ledgerly cloud data" on public.ledgerly_cloud_data;
create policy "Users can update their own Ledgerly cloud data"
  on public.ledgerly_cloud_data
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own Ledgerly cloud data" on public.ledgerly_cloud_data;
create policy "Users can delete their own Ledgerly cloud data"
  on public.ledgerly_cloud_data
  for delete to authenticated
  using ((select auth.uid()) = user_id);
