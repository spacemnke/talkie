// Links another device to your account. Talkie on the Mac shows a link code (start_link); the
// iPhone sends it here and gets back a one-time sign-in (a magic-link token, never emailed) for the
// same account: same code and board. Codes are good for ten minutes and once, and an address that
// sends ten wrong codes in an hour has to wait (use_link counts them).
//
// Signing in needs an email address on the account, so an account without one gets a private
// address under link.switchtalkie.com, which never receives mail. The code is the check, so the
// gateway's JWT check is off.
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let code = "";
  try {
    code = String((await req.json())?.code ?? "");
  } catch {
    // Falls through to the check below.
  }
  if (code.replace(/[^A-Za-z0-9]/g, "").length !== 8) {
    return json({ error: "Enter the 8-character code from your other device" }, 400);
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  // The caller's address, for counting wrong codes: Cloudflare's own header when there is one
  // (callers can't set it), otherwise the first forwarded address. use_link also caps wrong codes
  // for everyone together, so a made-up address doesn't buy more guesses.
  const ip = (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0] ?? "").trim();
  const { data: person, error } = await admin.rpc("use_link", { link_code: code, from_ip: ip });
  if (error?.message?.includes("too many tries")) {
    return json({ error: "Too many wrong codes. Try again in an hour." }, 429);
  }
  if (error) {
    console.error(`use_link: ${error.message}`);
    return json({ error: "Couldn't check the code" }, 500);
  }
  if (!person) return json({ error: "That code is wrong, used or out of time" }, 404);

  const { data: found, error: userError } = await admin.auth.admin.getUserById(person);
  if (userError || !found?.user) return json({ error: "That account is gone" }, 404);
  let email = found.user.email;
  if (!email) {
    email = `${person}@link.switchtalkie.com`;
    const { error: emailError } = await admin.auth.admin.updateUserById(person, { email, email_confirm: true });
    if (emailError) {
      console.error(`updateUserById ${person}: ${emailError.message}`);
      return json({ error: "Couldn't link the account" }, 500);
    }
  }
  const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const tokenHash = link?.properties?.hashed_token;
  if (linkError || !tokenHash) {
    console.error(`generateLink ${person}: ${linkError?.message}`);
    return json({ error: "Couldn't link the account" }, 500);
  }
  const { data: profile } = await admin.from("profiles").select("code, name").eq("id", person).single();
  return json({ token_hash: tokenHash, code: profile?.code ?? null, name: profile?.name ?? null });
});
