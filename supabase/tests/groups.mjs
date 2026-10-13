// Group calls on the live project: knocking someone into a call, letting someone into yours, who
// can and can't, the room and time each person gets, and the room filling up at three on Free.
//   node groups.mjs
const URL_ = "https://xakscsouugwlyefaieyl.supabase.co";
const KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhha3Njc291dWd3bHllZmFpZXlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4Mjk2ODEsImV4cCI6MjEwNzQwNTY4MX0.TXm0gnDiNHm3On8pV5zSZ4Fjot7qq-_8uCNqVb9lnZQ";
let failures = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) failures++; };

async function call(token, path, { method = "GET", body, prefer } = {}) {
  const headers = { apikey: KEY, Authorization: `Bearer ${token ?? KEY}`, "Content-Type": "application/json" };
  if (prefer) headers.Prefer = prefer;
  const r = await fetch(URL_ + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
}

async function person(name) {
  const r = await call(null, "/auth/v1/signup", { method: "POST", body: { data: {} } });
  if (r.status !== 200) throw new Error("sign-up failed: " + JSON.stringify(r.json));
  const me = { name, token: r.json.access_token, id: r.json.user.id };
  await call(me.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: name } });
  return me;
}

const seat = (owner, friend, jack) => call(owner.token, "/rest/v1/board", { method: "POST", body: { owner: owner.id, friend: friend.id, jack } });
const knock = (from, to, group) => call(from.token, "/rest/v1/knocks?select=id,group_id,added_by", {
  method: "POST", body: { caller: from.id, callee: to.id, ...(group ? { group_id: group } : {}) }, prefer: "return=representation" });
const letIn = async (p, id, into) => (await call(p.token, "/rest/v1/rpc/let_in", { method: "POST", body: { knock_id: id, into_group: into ?? null } })).json;
const pass = (p, id) => call(p.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: id } });

/** Holds LiveKit's signalling connection open, which is enough to count as in the room. */
function enter(p) {
  return new Promise((resolve) => {
    const ws = new WebSocket(`${p.url.replace(/\/+$/, "")}/rtc?access_token=${p.token}&auto_subscribe=1&sdk=js&version=2.9.0&protocol=15`);
    ws.binaryType = "arraybuffer";
    let done = false;
    const finish = (ok) => { if (!done) { done = true; resolve({ ok, ws }); } };
    ws.onmessage = () => finish(true);
    ws.onerror = () => finish(false);
    setTimeout(() => finish(false), 8000);
  });
}

const h = await person("Hal"), a = await person("Ann"), b = await person("Ben"), c = await person("Cat");
for (const [jack, f] of [a, b, c].entries()) await seat(h, f, jack);
for (const f of [a, b, c]) await seat(f, h, 0);

// Hal knocks Ann: a call of two, named after that knock.
const root = (await knock(h, a)).json[0];
check(root.group_id === null && root.added_by === h.id, "a first knock starts a call (added by the caller)");
check((await letIn(a, root.id))?.status === "answered", "Ann lets Hal in");
const passA = await pass(a, root.id), passH = await pass(h, root.id);
check(passA.json.room === `line-${root.id}` && passH.json.room === passA.json.room, "both get the call's room");
check(passA.json.limit_seconds >= 595 && passA.json.limit_seconds <= 600, `a free call gets ten minutes (${passA.json.limit_seconds})`);

// Hal brings Ben in: same room, the time that's left.
const second = await knock(h, b, root.id);
check(second.status === 201 && second.json[0].group_id === root.id, "Hal knocks Ben into the call");
check((await knock(c, h, root.id)).status >= 400, "Cat can't knock into a call she isn't on");
await letIn(b, second.json[0].id);
const passB = await pass(b, second.json[0].id);
check(passB.json.room === passA.json.room, "Ben gets the same room");
check(passB.json.limit_seconds <= passA.json.limit_seconds, "and what's left of the ten minutes");

// Cat knocks Hal (not from a call); Hal lets her into his call.
const third = (await knock(c, h)).json[0];
const merged = await letIn(h, third.id, root.id);
check(merged?.status === "answered" && merged.group_id === root.id && merged.added_by === h.id, "Hal lets Cat into his call");

// The room fills up: Hal, Ann and Ben are in, and Hal is on Free.
const inside = [];
for (const p of [passH.json, passA.json, passB.json]) inside.push(await enter(p));
check(inside.every((x) => x.ok), "Hal, Ann and Ben are in the room");
await new Promise((r) => setTimeout(r, 1500));
const passC = await pass(c, third.id);
check(passC.status === 409, `the call is full at three on Free (${passC.status} ${JSON.stringify(passC.json.error ?? "")})`);
inside[2].ws.close();
await new Promise((r) => setTimeout(r, 4000));
const again = await pass(c, third.id);
check(again.status === 200 && again.json.room === passA.json.room, `when Ben leaves, Cat gets in (${again.status})`);
check((await pass(h, root.id)).status === 200, "someone already in the room always gets a pass");
for (const x of inside) x.ws.close();

for (const who of [h, a, b, c]) await call(who.token, `/rest/v1/board?owner=eq.${who.id}`, { method: "DELETE" });
console.log(failures ? `${failures} FAILED` : "all good");
process.exit(failures ? 1 : 0);
