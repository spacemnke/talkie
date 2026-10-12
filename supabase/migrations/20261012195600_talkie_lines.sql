-- Talkie: who you are (a code and a name), who's on your board, and knocks between boards.
-- Everyone signs in anonymously from the app; their auth id is their profile id.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique check (code ~ '^TLK-[A-Z0-9]{4}$'),
  name text not null check (char_length(name) between 1 and 24),
  created_at timestamptz not null default now()
);

-- Your eight jacks. Being on someone's board is what lets your knock ring there.
create table public.board (
  owner uuid not null references public.profiles (id) on delete cascade,
  friend uuid not null references public.profiles (id) on delete cascade,
  jack smallint not null check (jack between 0 and 7),
  added_at timestamptz not null default now(),
  primary key (owner, friend),
  unique (owner, jack),
  check (owner <> friend)
);
create index board_friend_idx on public.board (friend);

-- A knock. The callee answers it or ignores it; declining is never written down, so the caller
-- can't tell a decline from no answer.
create table public.knocks (
  id uuid primary key default gen_random_uuid(),
  caller uuid not null references public.profiles (id) on delete cascade,
  callee uuid not null references public.profiles (id) on delete cascade,
  caller_name text not null default '',
  caller_code text not null default '',
  status text not null default 'knocking' check (status in ('knocking', 'answered', 'cancelled')),
  created_at timestamptz not null default now(),
  answered_at timestamptz
);
create index knocks_callee_idx on public.knocks (callee, created_at desc);
create index knocks_caller_idx on public.knocks (caller, created_at desc);

-- The caller's name and code come from their profile, not from what the app sends.
create function public.stamp_knock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select p.name, p.code into new.caller_name, new.caller_code from public.profiles p where p.id = new.caller;
  new.status := 'knocking';
  new.created_at := now();
  new.answered_at := null;
  return new;
end $$;
create trigger knocks_stamp before insert on public.knocks for each row execute function public.stamp_knock();

alter table public.profiles enable row level security;
alter table public.board enable row level security;
alter table public.knocks enable row level security;

-- You can read your own profile and the profiles of the people on your board.
create policy "read own and board profiles" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or exists (
    select 1 from public.board b where b.owner = (select auth.uid()) and b.friend = profiles.id));

-- Your board is yours alone.
create policy "read own board" on public.board for select to authenticated using (owner = (select auth.uid()));
create policy "add to own board" on public.board for insert to authenticated with check (owner = (select auth.uid()));
create policy "move on own board" on public.board for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "eject from own board" on public.board for delete to authenticated using (owner = (select auth.uid()));

-- Knocks are seen by the two people in them. You can only knock on someone on your board.
create policy "read own knocks" on public.knocks for select to authenticated
  using (caller = (select auth.uid()) or callee = (select auth.uid()));
create policy "knock on your board" on public.knocks for insert to authenticated
  with check (caller = (select auth.uid()) and exists (
    select 1 from public.board b where b.owner = (select auth.uid()) and b.friend = knocks.callee));

-- First launch: make (or fetch) your profile with a fresh code. Later launches can update the name.
create function public.ensure_profile(display_name text) returns public.profiles
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  p public.profiles;
  c text;
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  clean text := nullif(left(btrim(coalesce(display_name, '')), 24), '');
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into p from public.profiles where id = me;
  if found then
    if clean is not null and clean <> p.name then
      update public.profiles set name = clean where id = me returning * into p;
    end if;
    return p;
  end if;
  loop
    c := 'TLK-';
    for i in 1..4 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    begin
      insert into public.profiles (id, code, name) values (me, c, coalesce(clean, 'TALKIE')) returning * into p;
      return p;
    exception when unique_violation then
      -- That code is taken: roll another.
    end;
  end loop;
end $$;

-- Who a code belongs to, for the ADD panel. Only the name and id, nothing else.
create function public.lookup_code(friend_code text) returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.name from public.profiles p
  where auth.uid() is not null and p.code = upper(btrim(friend_code));
$$;

-- Let a knock in. Only the person being knocked on can, and only while it's still knocking.
create function public.answer_knock(knock_id uuid) returns public.knocks
language plpgsql security definer set search_path = '' as $$
declare k public.knocks;
begin
  update public.knocks set status = 'answered', answered_at = now()
  where id = knock_id and callee = auth.uid() and status = 'knocking' and created_at > now() - interval '60 seconds'
  returning * into k;
  return k;
end $$;

-- The caller gives up (pulled the cord, or nobody answered).
create function public.cancel_knock(knock_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.knocks set status = 'cancelled' where id = knock_id and caller = auth.uid() and status = 'knocking';
$$;

revoke all on function public.ensure_profile(text), public.lookup_code(text), public.answer_knock(uuid), public.cancel_knock(uuid), public.stamp_knock() from public, anon;
grant execute on function public.ensure_profile(text), public.lookup_code(text), public.answer_knock(uuid), public.cancel_knock(uuid) to authenticated;

-- Knocks arrive live.
alter publication supabase_realtime add table public.knocks;
