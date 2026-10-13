-- Paying for Pro, through Lemon Squeezy. Go Pro in Talkie opens a checkout tagged with your account
-- id. Lemon Squeezy tells the lemon-webhook function whenever a subscription starts, renews, changes
-- or ends, and the function records it here with apply_subscription, which sets your Pro.
--
-- Private: no policies, so the app can neither read nor write it; only the webhook function
-- (service role) does. It's kept apart from profiles because friends can read your profile.
create table public.subscriptions (
  -- Lemon Squeezy's subscription id.
  id text primary key,
  person uuid references public.profiles (id) on delete set null,
  -- on_trial, active, paused, past_due, unpaid, cancelled or expired.
  status text not null,
  -- Monthly or Yearly.
  variant text not null default '',
  -- The buyer's email, to sort out a purchase that didn't come with a Talkie account.
  email text not null default '',
  renews_at timestamptz,
  ends_at timestamptz,
  -- Pro lasts until then.
  paid_until timestamptz not null,
  test_mode boolean not null default false,
  -- Lemon Squeezy's updated_at, so an older event arriving late never wins.
  changed_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create index subscriptions_person_idx on public.subscriptions (person);
alter table public.subscriptions enable row level security;
revoke all on table public.subscriptions from anon, authenticated;

-- Sets someone's Pro from their subscriptions: Pro until the latest of them runs out. Pro given by
-- hand (on, with no end date) is left alone.
create function public.refresh_paid_pro(who uuid) returns void
language sql security definer set search_path = '' as $$
  update public.profiles p
  set pro = s.until > now(), pro_until = s.until
  from (select max(paid_until) as until from public.subscriptions where person = who) s
  where p.id = who and s.until is not null and not (p.pro and p.pro_until is null);
$$;

-- Records one subscription event and updates the person's Pro. Returns whose it is, or null when
-- the purchase didn't name a Talkie account (it's kept, with the email, to link up by hand).
--
-- How long Pro lasts: an active subscription until it renews, plus three days in case the renewal
-- is late; a cancelled one until the end of what was paid for; paused, unpaid or expired, not at all.
create function public.apply_subscription(
  sub_id text, account uuid, sub_status text, sub_variant text, buyer_email text,
  renews timestamptz, ends timestamptz, test boolean, changed timestamptz
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  until timestamptz := case
    when sub_status in ('on_trial', 'active', 'past_due') then greatest(coalesce(renews, now()), now()) + interval '3 days'
    when sub_status = 'cancelled' then coalesce(ends, now())
    else now()
  end;
  owner_id uuid;
begin
  if account is not null and not exists (select 1 from public.profiles where id = account) then
    account := null;
  end if;
  insert into public.subscriptions as s
    (id, person, status, variant, email, renews_at, ends_at, paid_until, test_mode, changed_at)
  values (sub_id, account, sub_status, sub_variant, buyer_email, renews, ends, until, test, changed)
  on conflict (id) do update set
    person = coalesce(excluded.person, s.person),
    status = excluded.status,
    variant = excluded.variant,
    email = excluded.email,
    renews_at = excluded.renews_at,
    ends_at = excluded.ends_at,
    paid_until = excluded.paid_until,
    test_mode = excluded.test_mode,
    changed_at = excluded.changed_at,
    updated_at = now()
  where s.changed_at <= excluded.changed_at;
  select s.person into owner_id from public.subscriptions s where s.id = sub_id;
  if owner_id is not null then
    perform public.refresh_paid_pro(owner_id);
  end if;
  return owner_id;
end $$;

revoke all on function public.refresh_paid_pro(uuid) from public, anon, authenticated;
revoke all on function public.apply_subscription(text, uuid, text, text, text, timestamptz, timestamptz, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.apply_subscription(text, uuid, text, text, text, timestamptz, timestamptz, boolean, timestamptz) to service_role;
