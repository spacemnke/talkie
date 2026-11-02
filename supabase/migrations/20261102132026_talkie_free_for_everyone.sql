-- Talkie is free (decided 2 Nov): everyone gets the whole board. is_pro now answers yes for
-- everyone, so every limit built on it opens up: all eight jacks (my_jack_limit and the board and
-- knock policies), calls of five (group_limit) and no time limit (line_limit). The payment pieces
-- (subscriptions, apply_subscription, the lemon-webhook function) stay but nothing sells Pro.
create or replace function public.is_pro(person uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select true;
$$;
