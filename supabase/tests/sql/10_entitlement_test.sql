-- Behavioural tests for the Ledgerly billing schema and RPCs.
-- Run with: supabase/tests/run_sql_tests.sh
-- Each test prints PASS; any failure raises and stops the script.

\set ON_ERROR_STOP on
set client_min_messages to notice;

create or replace function public.test_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if condition is not true then
    raise exception 'ASSERTION FAILED: %', message;
  end if;
  raise notice 'PASS: %', message;
end;
$$;

-- Fixtures -------------------------------------------------------------------
delete from public.subscription_entitlements;
delete from public.paypal_checkout_attempts;
delete from public.billing_webhook_events;
delete from auth.users;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'one@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'two@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'three@example.test');

-- 1. Checkout reservation dispositions ---------------------------------------
do $$
declare
  v_first record;
  v_second record;
begin
  select * into v_first from public.claim_paypal_checkout(
    '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  perform public.test_assert(v_first.disposition = 'claimed', 'first checkout is claimed');

  select * into v_second from public.claim_paypal_checkout(
    '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  perform public.test_assert(v_second.disposition = 'resume', 'in-flight checkout is resumed');
  perform public.test_assert(
    v_second.request_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'resumed checkout keeps the original PayPal request id');
end
$$;

-- 2. An entitled account cannot start a second subscription -------------------
do $$
declare
  v_result record;
begin
  perform public.apply_paypal_entitlement(
    '11111111-1111-1111-1111-111111111111', 'I-ACTIVE', 'P-PLAN', 'active',
    now() + interval '30 days', 'evt-1', now());

  select * into v_result from public.claim_paypal_checkout(
    '11111111-1111-1111-1111-111111111111', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  perform public.test_assert(v_result.disposition = 'entitled', 'active subscriber is not charged twice');
end
$$;

-- 3. An unresolved payment problem blocks a new subscription ------------------
do $$
declare
  v_result record;
begin
  perform public.apply_paypal_entitlement(
    '22222222-2222-2222-2222-222222222222', 'I-PASTDUE', 'P-PLAN', 'past_due',
    now() + interval '5 days', 'evt-2', now());

  select * into v_result from public.claim_paypal_checkout(
    '22222222-2222-2222-2222-222222222222', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
  perform public.test_assert(v_result.disposition = 'payment_issue', 'failed renewal blocks a duplicate subscription');
end
$$;

-- 4. A paid-through cancellation still blocks a second subscription ----------
do $$
declare
  v_result record;
begin
  perform public.apply_paypal_entitlement(
    '33333333-3333-3333-3333-333333333333', 'I-PAIDTHROUGH', 'P-PLAN', 'cancelled',
    now() + interval '10 days', 'evt-3', now());

  select * into v_result from public.claim_paypal_checkout(
    '33333333-3333-3333-3333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
  perform public.test_assert(v_result.disposition = 'entitled', 'paid-through cancellation blocks a new charge');
end
$$;

-- 5. Versioned writes ignore older provider states ---------------------------
do $$
declare
  v_applied boolean;
  v_status text;
  v_count integer;
begin
  perform public.apply_paypal_entitlement(
    '11111111-1111-1111-1111-111111111111', 'I-VERSIONED', 'P-PLAN', 'active',
    now() + interval '30 days', 'evt-10', '2026-11-01T10:00:00Z');

  perform public.apply_paypal_entitlement(
    '11111111-1111-1111-1111-111111111111', 'I-VERSIONED', 'P-PLAN', 'active',
    now() + interval '30 days', 'evt-11', '2026-11-01T10:00:00Z');
  select count(*) into v_count from public.subscription_entitlements
   where external_subscription_id = 'I-VERSIONED';
  perform public.test_assert(v_count = 1,
    'a repeated event updates one row instead of creating a duplicate entitlement');

  v_applied := public.apply_paypal_entitlement(
    '11111111-1111-1111-1111-111111111111', 'I-VERSIONED', 'P-PLAN', 'expired',
    null, 'evt-12', '2026-10-01T10:00:00Z');
  select status into v_status from public.subscription_entitlements
   where external_subscription_id = 'I-VERSIONED';
  perform public.test_assert(v_applied is false and v_status = 'active',
    'older provider state cannot roll an entitlement back');

  v_applied := public.apply_paypal_entitlement(
    '11111111-1111-1111-1111-111111111111', 'I-VERSIONED', 'P-PLAN', 'expired',
    null, 'evt-13', '2026-12-01T10:00:00Z');
  select status into v_status from public.subscription_entitlements
   where external_subscription_id = 'I-VERSIONED';
  perform public.test_assert(v_applied is true and v_status = 'expired',
    'newer provider state is applied');
end
$$;

-- 6. A subscription can never be rebound to another account ------------------
do $$
declare
  v_blocked boolean := false;
begin
  begin
    perform public.apply_paypal_entitlement(
      '22222222-2222-2222-2222-222222222222', 'I-VERSIONED', 'P-PLAN', 'active',
      now() + interval '30 days', 'evt-14', '2027-01-01T10:00:00Z');
  exception when others then
    v_blocked := true;
  end;
  perform public.test_assert(v_blocked, 'rebinding a subscription to another account is rejected');
end
$$;

-- 7. Unknown statuses are rejected -------------------------------------------
do $$
declare
  v_blocked boolean := false;
begin
  begin
    perform public.apply_paypal_entitlement(
      '33333333-3333-3333-3333-333333333333', 'I-BADSTATUS', 'P-PLAN', 'unlimited',
      now(), 'evt-15', now());
  exception when others then
    v_blocked := true;
  end;
  perform public.test_assert(v_blocked, 'undocumented entitlement status is rejected');
end
$$;

-- 8. Row level security exposes only the caller's rows ------------------------
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
  select count(*) into v_count from public.subscription_entitlements;
  perform public.test_assert(v_count = 2, 'a customer sees only their own entitlement rows');
  reset role;
end
$$;

-- 9. A signed-in customer cannot write entitlements directly ------------------
do $$
declare
  v_blocked boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
  begin
    insert into public.subscription_entitlements (
      user_id, provider, external_subscription_id, status
    ) values (
      '11111111-1111-1111-1111-111111111111', 'paypal', 'I-FORGED', 'active'
    );
  exception when others then
    v_blocked := true;
  end;
  reset role;
  perform public.test_assert(v_blocked, 'client-side entitlement writes are denied');
end
$$;

-- 10. The entitlement RPC is not callable by a signed-in customer ------------
do $$
declare
  v_blocked boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
  begin
    perform public.apply_paypal_entitlement(
      '11111111-1111-1111-1111-111111111111', 'I-CLIENT', 'P-PLAN', 'active',
      now() + interval '30 days', 'evt-16', now());
  exception when others then
    v_blocked := true;
  end;
  reset role;
  perform public.test_assert(v_blocked, 'apply_paypal_entitlement requires service_role');
end
$$;

-- 11. One open checkout per account ------------------------------------------
do $$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.paypal_checkout_attempts (user_id, request_id, status)
    values ('22222222-2222-2222-2222-222222222222', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'pending'),
           ('22222222-2222-2222-2222-222222222222', '99999999-9999-4999-8999-999999999999', 'pending');
  exception when unique_violation then
    v_blocked := true;
  end;
  perform public.test_assert(v_blocked, 'a customer can have only one open PayPal checkout');
end
$$;

-- 12. Webhook events are unique per provider ---------------------------------
do $$
declare
  v_blocked boolean := false;
begin
  insert into public.billing_webhook_events (provider, event_id) values ('paypal', 'WH-1');
  begin
    insert into public.billing_webhook_events (provider, event_id) values ('paypal', 'WH-1');
  exception when unique_violation then
    v_blocked := true;
  end;
  perform public.test_assert(v_blocked, 'duplicate webhook events are rejected by the primary key');
end
$$;

-- 13. The service role can write entitlements --------------------------------
do $$
declare
  v_count integer;
begin
  set local role service_role;
  perform public.apply_paypal_entitlement(
    '33333333-3333-3333-3333-333333333333', 'I-SERVICE', 'P-PLAN', 'active',
    now() + interval '30 days', 'evt-17', now());
  reset role;
  select count(*) into v_count from public.subscription_entitlements
   where external_subscription_id = 'I-SERVICE';
  perform public.test_assert(v_count = 1, 'service_role can write entitlements');
end
$$;

drop function if exists public.test_assert(boolean, text);
