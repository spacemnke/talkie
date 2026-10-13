-- Free or Pro.
-- Free: three jacks (0-2) and calls of up to ten minutes, unless the other person has Pro.
-- Pro: all eight jacks and no time limit (voice effects and knock sounds live in the app).
--
-- Nobody can make themselves Pro from the app: profiles have no update policy, and the functions
-- that write to profiles never touch these columns. Payments (later) set them from the server.
-- pro_until null with pro on means Pro with no end date (given by hand).
alter table public.profiles
  add column pro boolean not null default false,
  add column pro_until timestamptz;

-- Is this person on Pro right now? Internal: called from policies and other functions.
create function public.is_pro(person uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.pro and (p.pro_until is null or p.pro_until > now()) from public.profiles p where p.id = person),
    false);
$$;

-- How many jacks your board has.
create function public.my_jack_limit() returns integer
language sql stable security definer set search_path = '' as $$
  select case when public.is_pro(auth.uid()) then 8 else 3 end;
$$;

-- 'free' or 'pro', for the app.
create function public.my_plan() returns text
language sql stable security definer set search_path = '' as $$
  select case when public.is_pro(auth.uid()) then 'pro' else 'free' end;
$$;

-- How long a line can last, in seconds: no limit (null) if either of you has Pro, otherwise ten
-- minutes. Only the two people on the line can ask.
create function public.line_limit(knock_id uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select case when public.is_pro(k.caller) or public.is_pro(k.callee) then null else 600 end
  from public.knocks k
  where k.id = knock_id and (select auth.uid()) in (k.caller, k.callee);
$$;

revoke all on function public.is_pro(uuid), public.my_jack_limit(), public.my_plan(), public.line_limit(uuid) from public, anon, authenticated;
grant execute on function public.my_jack_limit(), public.my_plan(), public.line_limit(uuid) to authenticated;
