# Talkie's operator (Supabase)

The project is **talkie** (`xakscsouugwlyefaieyl`, London). The app signs in anonymously, so
**Authentication → Sign In / Providers → Allow anonymous sign-ins** must be on.

- `migrations/` — the schema: profiles (your code and name), board (your eight jacks), knocks,
  row-level security, and the functions the app calls (`ensure_profile`, `lookup_code`,
  `answer_knock`, `cancel_knock`, `check_in`, `sign_off`, `friends_here`). Applied in order.
- Who's around: each Talkie checks in every 30 seconds (with its do-not-disturb state) and signs
  off on quit; friends hear check-ins live through Realtime, and 75 seconds of silence means away.
  Realtime Presence dropped or crashed too often on this project to rely on.
- `functions/line-token/` — hands out LiveKit tokens for a knock that was let in. Needs the secrets
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` (Edge Functions → Secrets). Deployed with
  JWT verification off, because it checks the caller against Supabase Auth itself.

Deploy the function with the CLI: `supabase functions deploy line-token --no-verify-jwt --project-ref xakscsouugwlyefaieyl`.

## Checking it

`node supabase/tests/backend.mjs` and `node supabase/tests/live.mjs` (Node 22) sign up throwaway
anonymous users and check the whole path: codes, boards and their privacy, knocks and who can see
them, answering, line passes, knocks and presence arriving live, and LiveKit accepting a pass. They
leave anonymous test users named Ada, Bo and Cy behind; delete them from Authentication → Users.
