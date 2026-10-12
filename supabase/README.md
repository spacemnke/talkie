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
