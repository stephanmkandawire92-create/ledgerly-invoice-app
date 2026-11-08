-- Ledgerly PayPal integration hardening.
--
-- Additive and idempotent: safe to re-run against the existing project.
-- Apply before deploying the repaired Edge Functions.
--
-- 1. `apply_paypal_entitlement` may never move a subscription to a different
--    Ledgerly account. Previously `on conflict ... do update set user_id =
--    excluded.user_id` would silently re-bind a subscription id, which is an
--    account-takeover primitive if a custom_id is ever forged or reused.
-- 2. The same function now rejects statuses outside the documented set.
-- 3. `claim_paypal_checkout` refuses to start a second subscription while an
--    existing subscription has an unresolved payment problem. Without this a
--    customer with a failed renewal could pay twice.
-- 4. Adds the index used by the reconciliation endpoint.

-- ---------------------------------------------------------------------------
-- Entitlement writer
-- ---------------------------------------------------------------------------
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
 v_owner uuid;
begin
 if p_user_id is null or p_subscription_id is null or p_status_updated_at is null then
   raise exception 'Invalid PayPal entitlement input';
 end if;
 if p_status not in ('active','cancelled','expired','past_due','suspended','pending') then
   raise exception 'Invalid PayPal entitlement status: %', p_status;
 end if;

 select e.user_id into v_owner
 from public.subscription_entitlements e
 where e.provider = 'paypal' and e.external_subscription_id = p_subscription_id;

 if v_owner is not null and v_owner <> p_user_id then
   raise exception 'PayPal subscription % is already bound to another account', p_subscription_id
     using errcode = '42501';
 end if;

 insert into public.subscription_entitlements as current_row (
   user_id, provider, external_subscription_id, product_id, status,
   current_period_end, last_event_id, provider_status_updated_at, updated_at
 ) values (
   p_user_id, 'paypal', p_subscription_id, p_product_id, p_status,
   p_period_end, p_event_id, p_status_updated_at, now()
 )
 on conflict (provider, external_subscription_id) do update set
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

-- Keep the RevenueCat writer consistent: an entitlement row is never re-bound.
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
 v_owner uuid;
begin
 if p_user_id is null or p_subscription_id is null or p_status_updated_at is null then
   raise exception 'Invalid RevenueCat entitlement input';
 end if;
 if p_status not in ('active','cancelled','expired','past_due','suspended','pending') then
   raise exception 'Invalid RevenueCat entitlement status: %', p_status;
 end if;

 select e.user_id into v_owner
 from public.subscription_entitlements e
 where e.provider = 'revenuecat' and e.external_subscription_id = p_subscription_id;

 if v_owner is not null and v_owner <> p_user_id then
   raise exception 'RevenueCat subscription % is already bound to another account', p_subscription_id
     using errcode = '42501';
 end if;

 insert into public.subscription_entitlements as current_row (
   user_id, provider, external_subscription_id, product_id, status,
   current_period_end, last_event_id, provider_status_updated_at, updated_at
 ) values (
   p_user_id, 'revenuecat', p_subscription_id, p_product_id, p_status,
   p_period_end, p_event_id, p_status_updated_at, now()
 )
 on conflict (provider, external_subscription_id) do update set
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

-- ---------------------------------------------------------------------------
-- Checkout reservation
-- ---------------------------------------------------------------------------
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
 v_status text;
 v_period_end timestamptz;
begin
 if p_user_id is null or p_request_id is null or p_request_id !~ '^[0-9a-f-]{36}$' then
   raise exception 'Invalid checkout reservation input';
 end if;

 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

 -- Already entitled: paying again would be a duplicate charge.
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

 -- A subscription with an unresolved payment problem must be repaired in
 -- PayPal, not replaced by a second subscription.
 select e.status, e.current_period_end into v_status, v_period_end
 from public.subscription_entitlements e
 where e.user_id = p_user_id
   and e.provider = 'paypal'
   and e.status in ('past_due','suspended')
   and (e.current_period_end is null or e.current_period_end > now())
 order by e.updated_at desc
 limit 1;

 if v_status is not null then
   return query select 'payment_issue'::text, null::text, null::text, null::text;
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

-- Reconciliation reads the newest attempt for one account.
create index if not exists paypal_checkout_attempts_user_updated_idx
 on public.paypal_checkout_attempts(user_id, updated_at desc);

-- Entitlement lookups by account are used by both the app and the sync function.
create index if not exists subscription_entitlements_user_provider_idx
 on public.subscription_entitlements(user_id, provider, updated_at desc);
