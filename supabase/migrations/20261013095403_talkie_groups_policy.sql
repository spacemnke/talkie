-- Knocking someone into a call needs you to be on it (or starting it).
alter policy "knock on your board" on public.knocks
  with check (caller = (select auth.uid())
    and exists (
      select 1 from public.board b
      where b.owner = (select auth.uid()) and b.friend = knocks.callee and b.jack < (select public.my_jack_limit()))
    and (group_id is null or public.in_my_group(group_id)));
