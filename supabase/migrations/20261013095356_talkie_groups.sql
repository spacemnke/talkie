-- Group calls. A call is one LiveKit room, named after its first knock (the root). Knocking someone
-- while you're on a call (or starting one) carries the root as group_id, so they join the same room;
-- letting someone in during your call puts their knock into your call the same way.
-- How many people a call can hold depends on who brings them in: three on Free, five on Pro. The
-- line-token function checks that against who's actually in the room before handing out a pass.
alter table public.knocks
  add column group_id uuid references public.knocks (id) on delete set null,
  add column added_by uuid references public.profiles (id) on delete cascade;
create index knocks_group_idx on public.knocks (group_id);

-- Are you on this call, or starting it? (In an answered knock of the group, or the caller of a
-- knock in it that's still knocking.)
create function public.in_my_group(root uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.knocks k
    where (k.id = root or k.group_id = root)
      and k.created_at > now() - interval '6 hours'
      and ((k.status = 'answered' and (select auth.uid()) in (k.caller, k.callee))
        or (k.status = 'knocking' and k.caller = (select auth.uid()))));
$$;

-- The server stamps who's knocking, who brought them in, and which call it belongs to (always the
-- root, even if the app named another knock of the same call).
create or replace function public.stamp_knock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select p.name, p.code into new.caller_name, new.caller_code from public.profiles p where p.id = new.caller;
  new.status := 'knocking';
  new.created_at := now();
  new.answered_at := null;
  new.added_by := new.caller;
  if new.group_id is not null then
    new.group_id := coalesce((select g.group_id from public.knocks g where g.id = new.group_id), new.group_id);
  end if;
  return new;
end $$;

-- How many people the call this knock joins can hold: set by whoever brought them in.
create function public.group_limit(knock_id uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select case when public.is_pro(coalesce(k.added_by, k.caller)) then 5 else 3 end
  from public.knocks k
  where k.id = knock_id and (select auth.uid()) in (k.caller, k.callee);
$$;

-- How long a line can last, in seconds. A call's clock starts when its first knock is let in: no
-- limit if anyone who has been on it has Pro, otherwise ten minutes, and people who join later
-- get what's left.
create or replace function public.line_limit(knock_id uuid) returns integer
language sql stable security definer set search_path = '' as $$
  with mine as (
    select coalesce(k.group_id, k.id) as root from public.knocks k
    where k.id = knock_id and (select auth.uid()) in (k.caller, k.callee)
  ), call as (
    select g.caller, g.callee, g.answered_at from public.knocks g, mine
    where (g.id = mine.root or g.group_id = mine.root) and g.status = 'answered'
  )
  select case
    when exists (select 1 from call c where public.is_pro(c.caller) or public.is_pro(c.callee)) then null
    else greatest(0, 600 - floor(extract(epoch from now() - coalesce((select min(c.answered_at) from call c), now()))))::int
  end
  from mine;
$$;

-- Let a knock in. During your own call (`into_group`), they join it, unless they're building a
-- call of their own. Otherwise, a knock from someone's call brings you into theirs.
create function public.let_in(knock_id uuid, into_group uuid default null) returns public.knocks
language plpgsql security definer set search_path = '' as $$
declare
  k public.knocks;
  target uuid := into_group;
begin
  if target is not null then
    target := coalesce((select g.group_id from public.knocks g where g.id = target), target);
    if not public.in_my_group(target) then return null; end if;
  end if;
  update public.knocks set
    status = 'answered',
    answered_at = now(),
    group_id = coalesce(target, knocks.group_id),
    added_by = case when target is null then knocks.added_by else auth.uid() end
  where id = knock_id and callee = auth.uid() and status = 'knocking' and created_at > now() - interval '60 seconds'
    and exists (
      select 1 from public.board b
      where b.owner = auth.uid() and b.friend = knocks.caller and b.jack < public.my_jack_limit())
    and (target is null or (knocks.group_id is null
      and not exists (select 1 from public.knocks c where c.group_id = knocks.id)))
  returning * into k;
  return k;
end $$;

revoke all on function public.in_my_group(uuid), public.group_limit(uuid), public.let_in(uuid, uuid) from public, anon;
grant execute on function public.in_my_group(uuid), public.group_limit(uuid), public.let_in(uuid, uuid) to authenticated;
