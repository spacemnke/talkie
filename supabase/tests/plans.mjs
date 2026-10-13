// Free vs Pro on the live project. Nobody can go Pro from the app, so this waits while you switch a
// test user over from the SQL editor (it prints the statement), then checks Pro, then waits for
// Pro to end and checks what's left.
//   node plans.mjs
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
  const me = { token: r.json.access_token, id: r.json.user.id };
  await call(me.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: name } });
  return me;
}

const plan = async (p) => (await call(p.token, "/rest/v1/rpc/my_plan", { method: "POST", body: {} })).json;
const seat = (owner, friend, jack) => call(owner.token, "/rest/v1/board", { method: "POST", body: { owner: owner.id, friend: friend.id, jack } });
const knock = async (from, to) => (await call(from.token, "/rest/v1/knocks?select=id", { method: "POST", body: { caller: from.id, callee: to.id }, prefer: "return=representation" }));
const answer = async (p, id) => (await call(p.token, "/rest/v1/rpc/answer_knock", { method: "POST", body: { knock_id: id } })).json;
const pass = (p, id) => call(p.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: id } });

async function waitFor(what, test) {
  for (let i = 0; i < 90; i++) {
    if (await test()) return true;
    await new Promise((r) => setTimeout(r, 2000));
  }
  console.log("gave up waiting: " + what);
  return false;
}

const p = await person("Pat"), f = await person("Fin"), g = await person("Gus");
check(await plan(p) === "free", "Pat starts on Free");
console.log(`WAITING: update public.profiles set pro = true where id = '${p.id}';`);
check(await waitFor("Pat on Pro", async () => await plan(p) === "pro"), "Pat is on Pro");

// Pro: all eight jacks, and no limit on a line with Pro on either end.
check((await seat(p, f, 7)).status === 201, "Pro can use jack 08");
check((await seat(f, p, 0)).status === 201, "Fin (Free) puts Pat on jack 01");
check((await seat(f, g, 1)).status === 201, "Fin puts Gus on jack 02");
check((await seat(g, f, 0)).status === 201, "Gus puts Fin on jack 01");

const k1 = await knock(p, f);
check(k1.status === 201, "Pat knocks on Fin from jack 08");
check((await answer(f, k1.json[0].id))?.status === "answered", "Fin lets Pat in");
const [p1, f1] = [await pass(p, k1.json[0].id), await pass(f, k1.json[0].id)];
check(p1.status === 200 && p1.json.limit_seconds === null && f1.json.limit_seconds === null, "no time limit when one of you has Pro (both ends)");

const k2 = await knock(f, g);
await answer(g, k2.json[0].id);
check((await pass(g, k2.json[0].id)).json.limit_seconds === 600, "two Free friends still get ten minutes");

// Pro ends: friends past jack 03 stay, but can't be knocked, and their knocks can't be let in.
console.log(`WAITING: update public.profiles set pro_until = now() - interval '1 second' where id = '${p.id}';`);
check(await waitFor("Pat's Pro to end", async () => await plan(p) === "free"), "Pat's Pro ended");
check((await call(p.token, `/rest/v1/board?owner=eq.${p.id}&select=jack`)).json[0]?.jack === 7, "Fin is still on Pat's jack 08");
check((await knock(p, f)).status >= 400, "Pat can't knock on a Pro jack any more");
const k3 = await knock(f, p);
check(k3.status === 201, "Fin can still knock (Pat is on Fin's jack 01)");
check(!(await answer(p, k3.json[0].id))?.status, "but Pat can't let in a knock from a Pro jack");
check((await call(p.token, `/rest/v1/board?owner=eq.${p.id}&friend=eq.${f.id}`, { method: "PATCH", body: { jack: 2 } })).status < 300
  && (await call(p.token, `/rest/v1/board?owner=eq.${p.id}&select=jack`)).json[0]?.jack === 2, "Pat can move Fin down to jack 03");
const k4 = await knock(p, f);
check(k4.status === 201, "and knock again from there");

for (const who of [p, f, g]) await call(who.token, `/rest/v1/board?owner=eq.${who.id}`, { method: "DELETE" });
console.log(`TEST USERS: ${[p, f, g].map((x) => `'${x.id}'`).join(", ")}`);
console.log(failures ? `${failures} FAILED` : "all good");
process.exit(failures ? 1 : 0);
