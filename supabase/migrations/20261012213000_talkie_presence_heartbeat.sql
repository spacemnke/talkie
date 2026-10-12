-- Who's around, kept in the database: each Talkie checks in every 30 seconds with its do-not-disturb
-- state, and friends see the change live. Silent for long enough means away. Signing off on quit
-- clears it at once. (Realtime Presence dropped or crashed too often on this project to rely on.)
alter table public.profiles
  add column last_seen timestamptz,
  add column dnd boolean not null default false;

create function public.check_in(do_not_disturb boolean) returns timestamptz
language sql security definer set search_path = '' as $$
  update public.profiles set last_seen = now(), dnd = coalesce(do_not_disturb, false)
  where id = auth.uid()
  returning last_seen;
$$;

create function public.sign_off() returns void
language sql security definer set search_path = '' as $$
  update public.profiles set last_seen = null where id = auth.uid();
$$;

revoke all on function public.check_in(boolean), public.sign_off() from public, anon;
grant execute on function public.check_in(boolean), public.sign_off() to authenticated;

-- Friends' check-ins arrive live (row-level security limits each person to their own board).
alter publication supabase_realtime add table public.profiles;
