// End-to-end check of Talkie's operator: two anonymous users, codes, boards, a knock, an answer, line passes.
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

async function signUp() {
  const r = await call(null, "/auth/v1/signup", { method: "POST", body: { data: {} } });
  if (r.status !== 200) throw new Error("sign-up failed: " + JSON.stringify(r.json));
  return { token: r.json.access_token, id: r.json.user.id };
}

const a = await signUp(), b = await signUp(), c = await signUp();
const pa = (await call(a.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: "Ada" } })).json;
const pb = (await call(b.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: "Bo" } })).json;
const pc = (await call(c.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: "Cy" } })).json;
check(/^TLK-[A-Z0-9]{4}$/.test(pa.code) && pa.name === "Ada", `profile with a code: ${pa.code}`);
const again = (await call(a.token, "/rest/v1/rpc/ensure_profile", { method: "POST", body: { display_name: "Ada" } })).json;
check(again.code === pa.code, "the code stays the same next launch");

const found = (await call(a.token, "/rest/v1/rpc/lookup_code", { method: "POST", body: { friend_code: pb.code.toLowerCase() } })).json;
check(found.length === 1 && found[0].id === b.id && found[0].name === "Bo", "looking up a code finds the friend");
const nobody = (await call(a.token, "/rest/v1/rpc/lookup_code", { method: "POST", body: { friend_code: "TLK-0000" } })).json;
check(Array.isArray(nobody) && nobody.length === 0, "an unknown code finds nobody");

check((await call(a.token, "/rest/v1/board", { method: "POST", body: { owner: a.id, friend: b.id, jack: 0 } })).status === 201, "A puts B on jack 01");
check((await call(b.token, "/rest/v1/board", { method: "POST", body: { owner: b.id, friend: a.id, jack: 2 } })).status === 201, "B puts A on jack 03");

// Free or Pro: everyone starts on Free, with three jacks, and nobody can make themselves Pro.
const plan = async (t) => (await call(t, "/rest/v1/rpc/my_plan", { method: "POST", body: {} })).json;
check(await plan(a.token) === "free", "A starts on Free");
check((await call(a.token, "/rest/v1/board", { method: "POST", body: { owner: a.id, friend: c.id, jack: 3 } })).status >= 400, "Free has no jack 04");
check((await call(b.token, `/rest/v1/board?owner=eq.${b.id}&friend=eq.${a.id}`, { method: "PATCH", body: { jack: 6 } })).status >= 400
  || (await call(b.token, `/rest/v1/board?owner=eq.${b.id}&select=jack`)).json[0]?.jack === 2, "Free can't move a friend onto jack 07");
await call(a.token, `/rest/v1/profiles?id=eq.${a.id}`, { method: "PATCH", body: { pro: true } });
check(await plan(a.token) === "free", "A can't make themselves Pro");
check((await call(a.token, "/rest/v1/rpc/is_pro", { method: "POST", body: { person: a.id } })).status >= 400, "nobody can ask whether someone else is Pro");
check((await call(c.token, "/rest/v1/board", { method: "POST", body: { owner: a.id, friend: c.id, jack: 1 } })).status >= 400, "C can't write on A's board");
const boardA = (await call(a.token, "/rest/v1/board?select=jack,friend,profile:profiles!board_friend_fkey(name)")).json;
check(boardA.length === 1 && boardA[0].profile?.name === "Bo", "A's board shows B by name");
check((await call(c.token, `/rest/v1/board?owner=eq.${a.id}`)).json.length === 0, "C can't read A's board");
check((await call(c.token, `/rest/v1/profiles?id=eq.${a.id}`)).json.length === 0, "C can't read A's profile");

const knock = await call(a.token, "/rest/v1/knocks?select=id,caller_name,caller_code,status", { method: "POST", body: { caller: a.id, callee: b.id }, prefer: "return=representation" });
check(knock.status === 201 && knock.json[0].caller_name === "Ada" && knock.json[0].caller_code === pa.code, "A knocks on B (name and code stamped by the server)");
const knockId = knock.json[0].id;
check((await call(c.token, "/rest/v1/knocks", { method: "POST", body: { caller: c.id, callee: b.id } })).status >= 400, "C can't knock on B (B isn't on C's board)");
check((await call(c.token, `/rest/v1/knocks?id=eq.${knockId}`)).json.length === 0, "C can't see A's knock");
check((await call(b.token, `/rest/v1/knocks?id=eq.${knockId}`)).json.length === 1, "B sees A's knock");

const early = await call(a.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: knockId } });
check(early.status === 403 || early.status === 503, `no pass before B lets A in (${early.status})`);
const cheat = (await call(a.token, "/rest/v1/rpc/answer_knock", { method: "POST", body: { knock_id: knockId } })).json;
check(!cheat || cheat.status === null, "A can't answer their own knock");
const answered = (await call(b.token, "/rest/v1/rpc/answer_knock", { method: "POST", body: { knock_id: knockId } })).json;
check(answered.status === "answered", "B lets A in");

const passA = await call(a.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: knockId } });
const passB = await call(b.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: knockId } });
const passC = await call(c.token, "/functions/v1/line-token", { method: "POST", body: { knock_id: knockId } });
if (passA.status === 503) {
  console.log("note LiveKit secrets aren't set yet: " + passA.json.error);
} else {
  check(passA.status === 200 && passA.json.token && passA.json.room === `line-${knockId}`, "A gets a pass to the room");
  check(passB.status === 200 && passB.json.room === passA.json.room, "B gets a pass to the same room");
  const claims = JSON.parse(Buffer.from(passA.json.token.split(".")[1], "base64url").toString());
  check(claims.sub === a.id && claims.video?.room === passA.json.room && claims.video?.roomJoin, "A's pass is for A, in that room");
  check(passA.json.url.startsWith("wss://"), "the LiveKit URL looks right: " + passA.json.url);
  check(passA.json.limit_seconds === 600 && passB.json.limit_seconds === 600, "two Free friends get ten minutes");
}
check(passC.status === 404 || passC.status === 503, `C gets no pass (${passC.status})`);

const second = await call(a.token, "/rest/v1/knocks?select=id", { method: "POST", body: { caller: a.id, callee: b.id }, prefer: "return=representation" });
await call(a.token, "/rest/v1/rpc/cancel_knock", { method: "POST", body: { knock_id: second.json[0].id } });
check((await call(b.token, `/rest/v1/knocks?id=eq.${second.json[0].id}&select=status`)).json[0]?.status === "cancelled", "A can take a knock back");

// Tidy up the test users' rows (the auth users stay; they're anonymous and harmless).
await call(a.token, `/rest/v1/board?owner=eq.${a.id}`, { method: "DELETE" });
await call(b.token, `/rest/v1/board?owner=eq.${b.id}`, { method: "DELETE" });
console.log(failures ? `${failures} FAILED` : "all good");
process.exit(failures ? 1 : 0);
