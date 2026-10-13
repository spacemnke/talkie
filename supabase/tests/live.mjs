// Live checks against the real project: knocks arrive over Realtime (with row-level security), LiveKit
// accepts the pass, and check-ins show who is around.
const URL_ = "https://xakscsouugwlyefaieyl.supabase.co";
const WS = "wss://xakscsouugwlyefaieyl.supabase.co/realtime/v1/websocket";
const KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhha3Njc291dWd3bHllZmFpZXlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4Mjk2ODEsImV4cCI6MjEwNzQwNTY4MX0.TXm0gnDiNHm3On8pV5zSZ4Fjot7qq-_8uCNqVb9lnZQ";
let failures = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) failures++; };
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function call(token, path, { method = "GET", body, prefer } = {}) {
  const headers = { apikey: KEY, Authorization: `Bearer ${token ?? KEY}`, "Content-Type": "application/json" };
  if (prefer) headers.Prefer = prefer;
  const r = await fetch(URL_ + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
}
async function user(name) {
  const r = await call(null, "/auth/v1/signup", { method: "POST", body: { data: {} } });
  const u = { token: r.json.access_token, id: r.json.user.id };
  u.profile = (await call(u.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: name } })).json;
  return u;
}

/** A tiny Phoenix client for one channel. */
function channel(topic, config, token) {
  const ws = new WebSocket(`${WS}?apikey=${KEY}&vsn=1.0.0`);
  const events = [];
  let ref = 1;
  const send = (event, payload) => ws.send(JSON.stringify({ topic: `realtime:${topic}`, event, payload, ref: String(ref++), join_ref: "1" }));
  const ready = new Promise((resolve, reject) => {
    ws.onopen = () => send("phx_join", { config, access_token: token });
    ws.onmessage = m => {
      const msg = JSON.parse(m.data);
      events.push(msg);
      if (msg.event === "phx_reply" && msg.ref === "1") msg.payload.status === "ok" ? resolve() : reject(new Error(JSON.stringify(msg.payload)));
    };
    ws.onerror = e => reject(e);
  });
  const heartbeat = setInterval(() => ws.readyState === 1 && ws.send(JSON.stringify({ topic: "phoenix", event: "heartbeat", payload: {}, ref: String(ref++) })), 20000);
  return { ready, events, send, close: () => { clearInterval(heartbeat); ws.close(); } };
}

const a = await user("Ada"), b = await user("Bo");
await call(a.token, "/rest/v1/board", { method: "POST", body: { owner: a.id, friend: b.id, jack: 0 } });
await call(b.token, "/rest/v1/board", { method: "POST", body: { owner: b.id, friend: a.id, jack: 0 } });


// B listens for knocks the way the app does: inserts and updates where B is the callee.
const knocks = channel(`knocks-${b.id}`, {
  broadcast: { self: false }, presence: { key: "" },
  postgres_changes: [
    { event: "INSERT", schema: "public", table: "knocks", filter: `callee=eq.${b.id}` },
    { event: "UPDATE", schema: "public", table: "knocks", filter: `callee=eq.${b.id}` },
  ],
}, b.token);
await knocks.ready;
check(true, "B is listening for knocks");
// A listens for answers to A's knocks.
const answers = channel(`knocks-${a.id}`, {
  broadcast: { self: false }, presence: { key: "" },
  postgres_changes: [{ event: "UPDATE", schema: "public", table: "knocks", filter: `caller=eq.${a.id}` }],
}, a.token);
await answers.ready;
await sleep(1500);

const knock = await call(a.token, "/rest/v1/knocks?select=id", { method: "POST", body: { caller: a.id, callee: b.id }, prefer: "return=representation" });
const knockId = knock.json[0].id;
let got = null;
for (let i = 0; i < 40 && !got; i++) {
  await sleep(250);
  got = knocks.events.find(e => e.event === "postgres_changes" && e.payload?.data?.record?.id === knockId);
}
check(!!got, "B hears A's knock live" + (got ? ` (from ${got.payload.data.record.caller_name})` : ""));

await call(b.token, "/rest/v1/rpc/let_in", { method: "POST", body: { knock_id: knockId } });
let answered = null;
for (let i = 0; i < 40 && !answered; i++) {
  await sleep(250);
  answered = answers.events.find(e => e.event === "postgres_changes" && e.payload?.data?.record?.id === knockId && e.payload.data.record.status === "answered");
}
check(!!answered, "A hears that B let them in");
knocks.close(); answers.close();

// LiveKit takes the pass.
const pass = (await call(a.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: knockId } })).json;
const host = pass.url.replace(/^wss:/, "https:").replace(/\/$/, "");
const v = await fetch(`${host}/rtc/validate?access_token=${pass.token}`);
const vtext = (await v.text()).trim();
check(v.status === 200, `LiveKit accepts the pass (${v.status} ${vtext.slice(0, 60)})`);
const bad = await fetch(`${host}/rtc/validate?access_token=${pass.token.slice(0, -4)}AAAA`);
check(bad.status !== 200, `LiveKit refuses a forged pass (${bad.status})`);

// Who's around: A checks in on DND; B (who has A on their board) hears it live, C doesn't.
const c = await user("Cy");
const cfg = { broadcast: { self: false }, presence: { key: "" }, postgres_changes: [{ event: "UPDATE", schema: "public", table: "profiles" }] };
const bw = channel(`talkie-${b.id}`, cfg, b.token), cw = channel(`talkie-${c.id}`, cfg, c.token);
await bw.ready; await cw.ready; await sleep(1200);
await call(a.token, "/rest/v1/rpc/check_in", { method: "POST", body: { do_not_disturb: true } });
const heard = async (w, test) => { for (let i = 0; i < 24; i++) { const e = w.events.find(e => e.event === "postgres_changes" && e.payload?.data?.record?.id === a.id && test(e.payload.data.record)); if (e) return e; await sleep(250); } return null; };
check(!!(await heard(bw, r => r.last_seen && r.dnd === true)), "B hears A check in, on do not disturb");
const here = (await call(b.token, "/rest/v1/rpc/friends_here", { method: "POST" })).json;
check(here.length === 1 && here[0].id === a.id && here[0].here && here[0].dnd, "B's list of who's here has A");
await call(a.token, "/rest/v1/rpc/sign_off", { method: "POST" });
check(!!(await heard(bw, r => r.last_seen === null)), "B hears A sign off");
check(!cw.events.some(e => e.event === "postgres_changes" && e.payload?.data?.record?.id === a.id), "C hears none of it");
check((await call(b.token, "/rest/v1/rpc/friends_here", { method: "POST" })).json[0]?.here === false, "after signing off, A isn't here");
bw.close(); cw.close();

await call(a.token, `/rest/v1/board?owner=eq.${a.id}`, { method: "DELETE" });
await call(b.token, `/rest/v1/board?owner=eq.${b.id}`, { method: "DELETE" });
console.log(failures ? `${failures} FAILED` : "all good");
process.exit(failures ? 1 : 0);
