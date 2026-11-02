-- One account on several devices. Talkie on the Mac shows a link code (start_link); Talkie on the
-- iPhone types it, and the link-device function uses it (use_link) to sign the iPhone in to the
-- same account: same code, board and plan.
--
-- Codes are 8 characters from 32 (about a trillion), good for ten minutes and once. Private: no
-- policies, so the app can't read the table; start_link makes codes for your own account only.
create table public.link_codes (
  code text primary key,
  person uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '10 minutes',
  used_at timestamptz
);
alter table public.link_codes enable row level security;
revoke all on table public.link_codes from anon, authenticated;

-- A fresh link code for your account; an earlier one stops working. The randomness comes from
-- gen_random_uuid, skipping its fixed version and variant bytes.
create function public.start_link() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea;
  c text;
  i int;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then
    raise exception 'not signed in';
  end if;
  delete from public.link_codes where person = me or expires_at < now();
  loop
    bytes := uuid_send(gen_random_uuid());
    c := '';
    foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop
      c := c || substr(alphabet, 1 + get_byte(bytes, i) % 32, 1);
    end loop;
    begin
      insert into public.link_codes (code, person) values (c, me);
      return c;
    exception when unique_violation then
      -- Taken: roll another.
    end;
  end loop;
end $$;

-- Wrong codes, by the address they came from. Ten in an hour and that address waits: on top of
-- a trillion possible codes, guessing gets nowhere. Private, like link_codes.
create table public.link_attempts (
  ip text not null,
  at timestamptz not null default now()
);
create index link_attempts_ip_at_idx on public.link_attempts (ip, at);
alter table public.link_attempts enable row level security;
revoke all on table public.link_attempts from anon, authenticated;

-- Uses a link code: the account it opens, or null if it's wrong, used or expired. Spaces and
-- dashes don't matter. Raises "too many tries" once an address has had ten wrong codes in an hour.
-- For the link-device function only.
create function public.use_link(link_code text, from_ip text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  who text := coalesce(nullif(from_ip, ''), 'unknown');
  found_person uuid;
begin
  if (select count(*) from public.link_attempts a where a.ip = who and a.at > now() - interval '1 hour') >= 10 then
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

revoke all on function public.start_link(), public.use_link(text, text) from public, anon, authenticated;
grant execute on function public.start_link() to authenticated;
grant execute on function public.use_link(text, text) to service_role;
