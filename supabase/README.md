# Talkie's operator (Supabase)

The project is **talkie** (`xakscsouugwlyefaieyl`, London). The app signs in anonymously, so
**Authentication → Sign In / Providers → Allow anonymous sign-ins** must be on.

- `migrations/` — the schema: profiles (your code and name), board (your eight jacks), knocks,
  row-level security, and the functions the app calls (`ensure_profile`, `lookup_code`,
  `answer_knock`, `cancel_knock`). Applied in order.
- `functions/line-token/` — hands out LiveKit tokens for a knock that was let in. Needs the secrets
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` (Edge Functions → Secrets). Deployed with
  JWT verification off, because it checks the caller against Supabase Auth itself.

Deploy the function with the CLI: `supabase functions deploy line-token --no-verify-jwt --project-ref xakscsouugwlyefaieyl`.

## Checking it

`node supabase/tests/backend.mjs` and `node supabase/tests/live.mjs` (Node 22) sign up throwaway
anonymous users and check the whole path: codes, boards and their privacy, knocks and who can see
them, answering, line passes, knocks and presence arriving live, and LiveKit accepting a pass. They
leave anonymous test users named Ada, Bo and Cy behind; delete them from Authentication → Users.
