// A pass onto a line. Talkie calls this once a knock has been let in: both people get a LiveKit
// token for the call's room, named after its first knock. Nobody outside the call can get one.
// A call holds three people when a Free user brings someone in and five for Pro; the room is
// checked before the pass is handed out. It also says how long the line can last: no limit if
// anyone on the call has Pro, otherwise what's left of ten minutes.
//
// Secrets (Supabase → Edge Functions → Secrets): LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
// The caller is checked against Supabase Auth here, so the gateway's JWT check is off.
import { createClient } from "npm:@supabase/supabase-js@2";

// Trimmed: pasted secrets often carry a stray space or newline, which would break the signature.
const LIVEKIT_URL = (Deno.env.get("LIVEKIT_URL") ?? "").trim();
const LIVEKIT_API_KEY = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
const LIVEKIT_API_SECRET = (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim();

/** How long a pass is good for. A line can stay open this long. */
const PASS_SECONDS = 6 * 60 * 60;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The most people LiveKit lets into any Talkie room. */
const ROOM_MAX = 5;

/** A LiveKit access token: an HS256 JWT signed with the API secret. */
async function liveKitToken(claims: Record<string, unknown>): Promise<string> {
  const enc = new TextEncoder();
  const header = base64url(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = base64url(enc.encode(JSON.stringify(claims)));
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(LIVEKIT_API_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`${header}.${payload}`)));
  return `${header}.${payload}.${base64url(signature)}`;
}

/** Calls LiveKit's room service (Twirp over HTTPS, on the same host as the WebSocket URL). */
async function roomService(method: string, room: string, body: Record<string, unknown>): Promise<Response> {
  const now = Math.floor(Date.now() / 1000);
  const token = await liveKitToken({
    iss: LIVEKIT_API_KEY,
    sub: "talkie-operator",
    nbf: now - 10,
    exp: now + 60,
    video: { room, roomAdmin: true, roomCreate: true },
  });
  const host = LIVEKIT_URL.replace(/^ws/, "http").replace(/\/+$/, "");
  return await fetch(`${host}/twirp/livekit.RoomService/${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

/** Who's in a room right now, by account id. Empty if the room isn't open yet. */
async function inRoom(room: string): Promise<string[]> {
  const r = await roomService("ListParticipants", room, { room });
  if (!r.ok) return [];
  const body = await r.json().catch(() => ({}));
  return (body.participants ?? []).map((p: { identity: string }) => p.identity);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return json({ error: "LiveKit isn't set up: add LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET to the function secrets." }, 503);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const jwt = authorization.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Not signed in" }, 401);

  // Act as the person asking, so row-level security decides which knocks they can see.
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
  const user = userData?.user;
  if (userError || !user) return json({ error: "Not signed in" }, 401);

  let knockId = "";
  try {
    knockId = String((await req.json())?.knock_id ?? "");
  } catch {
    return json({ error: "Send { knock_id }" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(knockId)) return json({ error: "Send { knock_id }" }, 400);

  const { data: knock, error: knockError } = await supabase
    .from("knocks")
    .select("id, caller, callee, status, answered_at, group_id")
    .eq("id", knockId)
    .maybeSingle();
  if (knockError) return json({ error: knockError.message }, 500);
  if (!knock || (knock.caller !== user.id && knock.callee !== user.id)) return json({ error: "No such line" }, 404);
  if (knock.status !== "answered" || !knock.answered_at) return json({ error: "Not let in" }, 403);
  if (Date.now() - Date.parse(knock.answered_at) > PASS_SECONDS * 1000) return json({ error: "That line has closed" }, 403);

  const { data: me } = await supabase.from("profiles").select("name").eq("id", user.id).maybeSingle();
  // Worked out from both plans on the server; null means no limit.
  const { data: limit, error: limitError } = await supabase.rpc("line_limit", { knock_id: knock.id });
  if (limitError) return json({ error: limitError.message }, 500);
  const room = `line-${knock.group_id ?? knock.id}`;

  // Room for one more? Counted by who's actually in the call, against the plan of whoever brought
  // this person in. Someone already in the room (the one who added them) always gets through.
  const here = await inRoom(room).catch(() => [] as string[]);
  if (!here.includes(user.id)) {
    const { data: most, error: mostError } = await supabase.rpc("group_limit", { knock_id: knock.id });
    if (mostError) return json({ error: mostError.message }, 500);
    if (here.length >= Math.min(most ?? 3, ROOM_MAX)) return json({ error: "That call is full" }, 409);
    // A new room gets LiveKit's own cap too, so nobody gets past five whatever the app does.
    if (here.length === 0) await roomService("CreateRoom", room, { name: room, max_participants: ROOM_MAX }).catch(() => {});
  }

  const now = Math.floor(Date.now() / 1000);
  const token = await liveKitToken({
    iss: LIVEKIT_API_KEY,
    sub: user.id,
    name: me?.name ?? "TALKIE",
    nbf: now - 10,
    exp: now + PASS_SECONDS,
    video: { room, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true },
  });
  return json({ url: LIVEKIT_URL, token, room, limit_seconds: limit ?? null });
});
