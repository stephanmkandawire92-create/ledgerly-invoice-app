-- Ledgerly subscription schema. Apply to a development Supabase project first.
create table if not exists public.subscription_entitlements (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 provider text not null check (provider in ('revenuecat','paypal')),
 external_subscription_id text not null,
 product_id text,
 status text not null check (status in ('active','cancelled','expired','past_due','suspended','pending')),
 current_period_end timestamptz,
 last_event_id text,
 provider_status_updated_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provider, external_subscription_id)
);
alter table public.subscription_entitlements
 add column if not exists provider_status_updated_at timestamptz;
create index if not exists subscription_entitlements_user_status_idx on public.subscription_entitlements(user_id,status,current_period_end desc);
alter table public.subscription_entitlements enable row level security;
revoke all on public.subscription_entitlements from anon, authenticated;
grant select on public.subscription_entitlements to authenticated;
grant all on public.subscription_entitlements to service_role;
drop policy if exists "Users can read their own subscription entitlements" on public.subscription_entitlements;
create policy "Users can read their own subscription entitlements" on public.subscription_entitlements for select to authenticated using ((select auth.uid()) = user_id);

create table if not exists public.billing_webhook_events (
 provider text not null check (provider in ('revenuecat','paypal')),
 event_id text not null,
 received_at timestamptz not null default now(),
 primary key(provider,event_id)
);
alter table public.billing_webhook_events enable row level security;
revoke all on public.billing_webhook_events from anon, authenticated;
grant all on public.billing_webhook_events to service_role;

-- A user may have only one unresolved PayPal checkout. The request ID is sent
-- to PayPal as PayPal-Request-Id so a retry after a network/database failure
-- replays the same provider operation instead of creating another subscription.
create table if not exists public.paypal_checkout_attempts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id text not null unique,
 subscription_id text unique,
 approval_url text,
 status text not null check (status in ('creating','pending','active','cancelled','expired','past_due','suspended','failed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists paypal_checkout_attempts_user_status_idx
 on public.paypal_checkout_attempts(user_id,status,created_at desc);
create unique index if not exists paypal_one_open_checkout_per_user_idx
 on public.paypal_checkout_attempts(user_id) where status in ('creating','pending');
alter table public.paypal_checkout_attempts enable row level security;
revoke all on public.paypal_checkout_attempts from anon, authenticated;
grant all on public.paypal_checkout_attempts to service_role;

-- This RPC runs only on the Edge Function via service_role. Advisory locking
-- makes entitlement checks and checkout reservation atomic per Ledgerly user.
create or replace function public.claim_paypal_checkout(
 p_user_id uuid,
 p_request_id text
)
returns table (
 disposition text,
 request_id text,
 approval_url text,
 subscription_id text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 v_attempt public.paypal_checkout_attempts%rowtype;
begin
 if p_user_id is null or p_request_id is null or p_request_id !~ '^[0-9a-f-]{36}$' then
   raise exception 'Invalid checkout reservation input';
 end if;

 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

 if exists (
   select 1
   from public.subscription_entitlements e
   where e.user_id = p_user_id
     and (
       (e.status = 'active' and (e.current_period_end is null or e.current_period_end > now()))
       or (e.status = 'cancelled' and e.current_period_end > now())
     )
 ) then
   return query select 'entitled'::text, null::text, null::text, null::text;
   return;
 end if;

 select a.* into v_attempt
 from public.paypal_checkout_attempts a
 where a.user_id = p_user_id and a.status in ('creating','pending')
 order by a.created_at desc
 limit 1
 for update;

 if found then
   return query select
     case when v_attempt.approval_url is not null then 'existing' else 'resume' end,
     v_attempt.request_id,
     v_attempt.approval_url,
     v_attempt.subscription_id;
   return;
 end if;

 insert into public.paypal_checkout_attempts(user_id,request_id,status)
 values (p_user_id,p_request_id,'creating')
 returning * into v_attempt;

 return query select 'claimed'::text, v_attempt.request_id,
   v_attempt.approval_url, v_attempt.subscription_id;
end;
$$;
revoke all on function public.claim_paypal_checkout(uuid,text) from public, anon, authenticated;
grant execute on function public.claim_paypal_checkout(uuid,text) to service_role;

-- PayPal's status_update_time is the provider-side version of its canonical
-- subscription status. Reject older reads atomically if webhook deliveries race.
create or replace function public.apply_paypal_entitlement(
 p_user_id uuid,
 p_subscription_id text,
 p_product_id text,
 p_status text,
 p_period_end timestamptz,
 p_event_id text,
 p_status_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 v_applied boolean;
begin
 if p_user_id is null or p_subscription_id is null or p_status_updated_at is null then
   raise exception 'Invalid PayPal entitlement input';
 end if;

 insert into public.subscription_entitlements as current_row (
   user_id, provider, external_subscription_id, product_id, status,
   current_period_end, last_event_id, provider_status_updated_at, updated_at
 ) values (
   p_user_id, 'paypal', p_subscription_id, p_product_id, p_status,
   p_period_end, p_event_id, p_status_updated_at, now()
 )
 on conflict (provider, external_subscription_id) do update set
   user_id = excluded.user_id,
   product_id = excluded.product_id,
   status = excluded.status,
   current_period_end = coalesce(excluded.current_period_end, current_row.current_period_end),
   last_event_id = excluded.last_event_id,
   provider_status_updated_at = excluded.provider_status_updated_at,
   updated_at = now()
 where current_row.provider_status_updated_at is null
    or excluded.provider_status_updated_at >= current_row.provider_status_updated_at
 returning true into v_applied;

 return coalesce(v_applied, false);
end;
$$;
revoke all on function public.apply_paypal_entitlement(uuid,text,text,text,timestamptz,text,timestamptz)
 from public, anon, authenticated;
grant execute on function public.apply_paypal_entitlement(uuid,text,text,text,timestamptz,text,timestamptz)
 to service_role;

create or replace function public.apply_revenuecat_entitlement(
 p_user_id uuid,
 p_subscription_id text,
 p_product_id text,
 p_status text,
 p_period_end timestamptz,
 p_event_id text,
 p_status_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
 v_applied boolean;
begin
 if p_user_id is null or p_subscription_id is null or p_status_updated_at is null then
   raise exception 'Invalid RevenueCat entitlement input';
 end if;

 insert into public.subscription_entitlements as current_row (
   user_id, provider, external_subscription_id, product_id, status,
   current_period_end, last_event_id, provider_status_updated_at, updated_at
 ) values (
   p_user_id, 'revenuecat', p_subscription_id, p_product_id, p_status,
   p_period_end, p_event_id, p_status_updated_at, now()
 )
 on conflict (provider, external_subscription_id) do update set
   user_id = excluded.user_id,
   product_id = excluded.product_id,
   status = excluded.status,
   current_period_end = coalesce(excluded.current_period_end, current_row.current_period_end),
   last_event_id = excluded.last_event_id,
   provider_status_updated_at = excluded.provider_status_updated_at,
   updated_at = now()
 where current_row.provider_status_updated_at is null
    or excluded.provider_status_updated_at >= current_row.provider_status_updated_at
 returning true into v_applied;

 return coalesce(v_applied, false);
end;
$$;
revoke all on function public.apply_revenuecat_entitlement(uuid,text,text,text,timestamptz,text,timestamptz)
 from public, anon, authenticated;
grant execute on function public.apply_revenuecat_entitlement(uuid,text,text,text,timestamptz,text,timestamptz)
 to service_role;
