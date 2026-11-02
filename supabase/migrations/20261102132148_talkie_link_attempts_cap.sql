-- Wrong link codes are also capped for everyone together: 300 in an hour and every address waits
-- until the hour has passed. An address a caller makes up doesn't buy more guesses.
create or replace function public.use_link(link_code text, from_ip text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  who text := coalesce(nullif(from_ip, ''), 'unknown');
  found_person uuid;
begin
  if (select count(*) from public.link_attempts a where a.ip = who and a.at > now() - interval '1 hour') >= 10
     or (select count(*) from public.link_attempts a where a.at > now() - interval '1 hour') >= 300 then
    raise exception 'too many tries';
  end if;
  update public.link_codes c set used_at = now()
  where c.code = upper(regexp_replace(coalesce(link_code, ''), '[^A-Za-z0-9]', '', 'g'))
    and c.used_at is null and c.expires_at > now()
  returning c.person into found_person;
  if found_person is null then
    insert into public.link_attempts (ip) values (who);
    delete from public.link_attempts where at < now() - interval '1 day';
  end if;
  return found_person;
end $$;
