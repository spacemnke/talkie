# Talkie's operator (Supabase)

The project is **talkie** (`xakscsouugwlyefaieyl`, London). The app signs in anonymously, so
**Authentication → Sign In / Providers → Allow anonymous sign-ins** must be on.

- `migrations/` — the schema: profiles (your code and name), board (your eight jacks), knocks,
  row-level security, and the functions the app calls (`ensure_profile`, `lookup_code`,
  `let_in`, `cancel_knock`, `check_in`, `sign_off`, `friends_here`, `my_plan`). Applied in order.
- Group calls: a knock's `group_id` is the call's first knock, which names the LiveKit room;
  `let_in(knock, into_group)` brings a knock into your call. `group_limit` says how many the call
  can hold for whoever brought that person in (3 Free, 5 Pro) and the line-token function checks it
  against who's in the room.
- Free or Pro: `profiles.pro` and `pro_until` (no end date when null). Nobody can set them from the
  app. Free boards use jacks 01–03, Pro all eight; you can only fill, knock from and let in knocks
  on jacks your plan has. `line_limit` says how long a line can last (600 seconds, or no limit if
  anyone on the call is Pro, otherwise what's left of the call's ten minutes) and the line pass
  carries it as `limit_seconds`. Make someone Pro by hand:
  `update public.profiles set pro = true where code = 'TLK-XXXX';`
- Payments (Lemon Squeezy): `functions/lemon-webhook/` takes Lemon Squeezy's subscription events,
  checks their signature (`X-Signature`, HMAC-SHA256 with the secret `LEMON_SQUEEZY_WEBHOOK_SECRET`)
  and calls `apply_subscription`, which keeps the subscription in the private `subscriptions` table
  (no policies: the app can't see it) and sets the buyer's `pro` and `pro_until` from it. The buyer
  is the account in the checkout's `custom_data.user_id`, which Talkie adds when it opens the
  checkout. Pro given by hand (`pro` on, `pro_until` null) is left alone. Deployed with JWT
  verification off; the signature is the check. A purchase with no account is kept with its email:
  link it with `update public.subscriptions set person = '<id>' where id = '<subscription>';` and
  then `select public.refresh_paid_pro('<id>');`.
- Who's around: each Talkie checks in every 30 seconds (with its do-not-disturb state) and signs
  off on quit; friends hear check-ins live through Realtime, and 75 seconds of silence means away.
  Realtime Presence dropped or crashed too often on this project to rely on.
- `functions/line-token/` — hands out LiveKit tokens for a knock that was let in. Needs the secrets
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` (Edge Functions → Secrets). Deployed with
  JWT verification off, because it checks the caller against Supabase Auth itself.

Deploy the functions with the CLI: `supabase functions deploy line-token --no-verify-jwt --project-ref xakscsouugwlyefaieyl`, and the same for `lemon-webhook`.

## Checking it

`node supabase/tests/backend.mjs` and `node supabase/tests/live.mjs` (Node 22) sign up throwaway
anonymous users and check the whole path: codes, boards and their privacy, knocks and who can see
them, answering, line passes, knocks and presence arriving live, and LiveKit accepting a pass.
`node supabase/tests/groups.mjs` checks group calls: knocking someone into a call, letting someone
into yours, the shared room and time, and the room filling up at three on Free (it holds LiveKit's
signalling connection open to count as being in the room). `node supabase/tests/plans.mjs` checks Free and Pro: it pauses twice and prints the SQL to run
(make a test user Pro, then end it). They leave anonymous test users named Ada, Bo, Cy, Pat, Fin,
Gus, Hal, Ann, Ben and Cat behind; delete them from Authentication → Users.
