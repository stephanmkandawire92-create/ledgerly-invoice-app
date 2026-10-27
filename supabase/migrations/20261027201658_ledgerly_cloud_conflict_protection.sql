-- Compare-and-swap writes prevent one device from silently replacing a
-- newer cloud section written by another device.
drop function if exists public.ledgerly_replace_cloud_workspace(jsonb, jsonb, jsonb, jsonb, jsonb, boolean);

create function public.ledgerly_replace_cloud_workspace(
  p_documents jsonb,
  p_customers jsonb,
  p_items jsonb,
  p_payments jsonb,
  p_profile jsonb,
  p_allow_overwrite boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_updated_at timestamptz := clock_timestamp();
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
  if exists (select 1 from public.ledgerly_cloud_data where user_id = v_user_id)
    and not coalesce(p_allow_overwrite, false) then
    raise exception 'Cloud workspace already contains records; explicit overwrite confirmation is required';
  end if;

  insert into public.ledgerly_cloud_data (user_id, data_type, payload, updated_at)
  values
    (v_user_id, 'documents', p_documents, v_updated_at),
    (v_user_id, 'customers', p_customers, v_updated_at),
    (v_user_id, 'items', p_items, v_updated_at),
    (v_user_id, 'payments', p_payments, v_updated_at),
    (v_user_id, 'profile', p_profile, v_updated_at)
  on conflict (user_id, data_type)
  do update set payload = excluded.payload, updated_at = excluded.updated_at;

  return jsonb_build_object(
    'documents', v_updated_at,
    'customers', v_updated_at,
    'items', v_updated_at,
    'payments', v_updated_at,
    'profile', v_updated_at
  );
end;
$$;

create or replace function public.ledgerly_save_cloud_section(
  p_data_type text,
  p_payload jsonb,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_existing_updated_at timestamptz;
  v_updated_at timestamptz := clock_timestamp();
begin
  if v_user_id is null then
    raise exception 'Sign in is required to save Ledgerly cloud data';
  end if;
  if p_data_type not in ('documents', 'customers', 'items', 'payments', 'profile') then
    raise exception 'Unknown Ledgerly workspace section';
  end if;
  if (p_data_type = 'profile' and jsonb_typeof(p_payload) <> 'object')
    or (p_data_type <> 'profile' and jsonb_typeof(p_payload) <> 'array') then
    raise exception 'Invalid payload for Ledgerly workspace section';
  end if;

  select updated_at into v_existing_updated_at
  from public.ledgerly_cloud_data
  where user_id = v_user_id and data_type = p_data_type
  for update;

  if found then
    if p_expected_updated_at is null or v_existing_updated_at <> p_expected_updated_at then
      raise exception 'Cloud data changed on another device. Reload the workspace before saving again';
    end if;
    update public.ledgerly_cloud_data
    set payload = p_payload, updated_at = v_updated_at
    where user_id = v_user_id and data_type = p_data_type;
  else
    if p_expected_updated_at is not null then
      raise exception 'Cloud data was removed on another device. Reload the workspace before saving again';
    end if;
    -- A concurrent first insert can only fail the unique constraint; it never
    -- overwrites the other device's newly created row.
    insert into public.ledgerly_cloud_data (user_id, data_type, payload, updated_at)
    values (v_user_id, p_data_type, p_payload, v_updated_at);
  end if;

  return v_updated_at;
end;
$$;

revoke all on function public.ledgerly_replace_cloud_workspace(jsonb, jsonb, jsonb, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.ledgerly_replace_cloud_workspace(jsonb, jsonb, jsonb, jsonb, jsonb, boolean) to authenticated;
revoke all on function public.ledgerly_save_cloud_section(text, jsonb, timestamptz) from public, anon;
grant execute on function public.ledgerly_save_cloud_section(text, jsonb, timestamptz) to authenticated;
