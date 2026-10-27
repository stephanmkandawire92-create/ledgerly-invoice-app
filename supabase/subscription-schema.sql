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
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provider, external_subscription_id)
);
create index if not exists subscription_entitlements_user_status_idx on public.subscription_entitlements(user_id,status,current_period_end desc);
alter table public.subscription_entitlements enable row level security;
revoke all on public.subscription_entitlements from anon, authenticated;
grant select on public.subscription_entitlements to authenticated;
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
