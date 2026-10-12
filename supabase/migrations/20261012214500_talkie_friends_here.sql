-- Who on your board is around right now: checked in within the last 75 seconds. Worked out on the
-- server so the answer doesn't depend on your Mac's clock.
create function public.friends_here() returns table (id uuid, here boolean, dnd boolean)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.last_seen > now() - interval '75 seconds', false), p.dnd
  from public.board b join public.profiles p on p.id = b.friend
  where b.owner = auth.uid();
$$;

revoke all on function public.friends_here() from public, anon;
grant execute on function public.friends_here() to authenticated;
