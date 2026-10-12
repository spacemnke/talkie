-- The knock trigger only runs as a trigger; nobody calls it.
revoke execute on function public.stamp_knock() from authenticated;
