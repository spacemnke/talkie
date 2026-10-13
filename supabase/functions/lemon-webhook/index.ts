// Payments. Lemon Squeezy calls this whenever a Talkie Pro subscription starts, renews, changes or
// ends. Each call is signed with the webhook's signing secret; anything unsigned is turned away.
// The subscription is recorded and the buyer's Pro set from it (apply_subscription). The buyer's
// Talkie account comes from the checkout: Talkie opens it with checkout[custom][user_id].
//
// Secret (Supabase → Edge Functions → Secrets): LEMON_SQUEEZY_WEBHOOK_SECRET, the same signing
// secret as the webhook in Lemon Squeezy. Lemon Squeezy doesn't send a Supabase JWT, so the
// gateway's JWT check is off; the signature is the check.
import { createClient } from "npm:@supabase/supabase-js@2";

// Trimmed: pasted secrets often carry a stray space or newline.
const SECRET = (Deno.env.get("LEMON_SQUEEZY_WEBHOOK_SECRET") ?? "").trim();

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** The body's HMAC-SHA256 under the signing secret, in hex, which is what X-Signature carries. */
async function signature(body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  return Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Compares in the same time whatever the input, so the signature can't be guessed a byte at a time. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!SECRET) return json({ error: "Payments aren't set up: add LEMON_SQUEEZY_WEBHOOK_SECRET to the function secrets." }, 503);

  const body = await req.text();
  const given = (req.headers.get("X-Signature") ?? "").trim().toLowerCase();
  if (!same(given, await signature(body))) return json({ error: "Bad signature" }, 401);

  let event;
  try {
    event = JSON.parse(body);
  } catch {
    return json({ error: "Not JSON" }, 400);
  }
  const name: string = event?.meta?.event_name ?? "";
  const data = event?.data;
  // Only subscription events change Pro. Invoices, orders and the rest are acknowledged and let go
  // (a renewal also sends subscription_updated with the new date).
  if (data?.type !== "subscriptions") return json({ ignored: name });

  const a = data.attributes ?? {};
  const account = String(event.meta?.custom_data?.user_id ?? "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: person, error } = await admin.rpc("apply_subscription", {
    sub_id: String(data.id),
    account: UUID.test(account) ? account : null,
    sub_status: String(a.status ?? ""),
    sub_variant: String(a.variant_name ?? ""),
    buyer_email: String(a.user_email ?? ""),
    renews: a.renews_at ?? null,
    ends: a.ends_at ?? null,
    test: a.test_mode === true,
    changed: a.updated_at ?? new Date().toISOString(),
  });
  // A failure here makes Lemon Squeezy try again later.
  if (error) {
    console.error(`${name} ${data.id}: ${error.message}`);
    return json({ error: "Couldn't record the subscription" }, 500);
  }
  if (!person) console.warn(`${name} ${data.id}: no Talkie account on this purchase (${a.status})`);
  return json({ ok: true, event: name, status: a.status, linked: Boolean(person) });
});
