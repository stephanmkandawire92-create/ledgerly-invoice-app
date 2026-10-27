-- Atomic workspace replacement for first-time migration or an explicitly
-- confirmed overwrite. SECURITY INVOKER preserves RLS enforcement.
create or replace function public.ledgerly_replace_cloud_workspace(
  p_documents jsonb,
  p_customers jsonb,
  p_items jsonb,
  p_payments jsonb,
  p_profile jsonb,
  p_allow_overwrite boolean default false
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Sign in is required to update the Ledgerly cloud workspace';
  end if;

  if jsonb_typeof(p_documents) <> 'array'
    or jsonb_typeof(p_customers) <> 'array'
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_typeof(p_payments) <> 'array'
    or jsonb_typeof(p_profile) <> 'object' then
    raise exception 'Invalid Ledgerly workspace payload';
  end if;

  if exists (
    select 1 from public.ledgerly_cloud_data
    where user_id = v_user_id
  ) and not coalesce(p_allow_overwrite, false) then
    raise exception 'Cloud workspace already contains records; explicit overwrite confirmation is required';
  end if;

  insert into public.ledgerly_cloud_data (user_id, data_type, payload, updated_at)
  values
    (v_user_id, 'documents', p_documents, now()),
    (v_user_id, 'customers', p_customers, now()),
    (v_user_id, 'items', p_items, now()),
    (v_user_id, 'payments', p_payments, now()),
    (v_user_id, 'profile', p_profile, now())
  on conflict (user_id, data_type)
  do update set payload = excluded.payload, updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.ledgerly_replace_cloud_workspace(jsonb, jsonb, jsonb, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.ledgerly_replace_cloud_workspace(jsonb, jsonb, jsonb, jsonb, jsonb, boolean) to authenticated;
