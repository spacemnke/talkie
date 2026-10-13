-- Free or Pro, enforced: friends only go on jacks your plan has, and only they can knock and be let in.
-- Friends already past your jacks (after Pro ends) stay put: they can be ejected or moved down,
-- but not knocked, and their knocks can't be answered.
alter policy "add to own board" on public.board
  with check (owner = (select auth.uid()) and jack < (select public.my_jack_limit()));

alter policy "move on own board" on public.board
  using (owner = (select auth.uid()))
  with check (owner = (select auth.uid()) and jack < (select public.my_jack_limit()));

-- You can only knock on someone on one of your jacks.
alter policy "knock on your board" on public.knocks
  with check (caller = (select auth.uid()) and exists (
    select 1 from public.board b
    where b.owner = (select auth.uid()) and b.friend = knocks.callee and b.jack < (select public.my_jack_limit())));

-- Letting a knock in: only from someone on one of your jacks (an off-board or Pro-jack knock never
-- rings in the app, and can't be answered around it either).
create or replace function public.answer_knock(knock_id uuid) returns public.knocks
language plpgsql security definer set search_path = '' as $$
declare k public.knocks;
begin
  update public.knocks set status = 'answered', answered_at = now()
  where id = knock_id and callee = auth.uid() and status = 'knocking' and created_at > now() - interval '60 seconds'
    and exists (
      select 1 from public.board b
      where b.owner = auth.uid() and b.friend = knocks.caller and b.jack < public.my_jack_limit())
  returning * into k;
  return k;
end $$;
