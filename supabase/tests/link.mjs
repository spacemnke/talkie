// One account on two devices, and Talkie being free, on the live project:
//   node supabase/tests/link.mjs
// A throwaway account ("Link Test") checks it has the whole board, makes a link code, and a second
// "device" uses the code to sign in to the same account. Then: a used code fails, and ten wrong
// codes in an hour are refused (this machine's address is then refused for an hour). Leaves the
// test account behind (it gets a private @link.switchtalkie.com address); the script prints its id.
const URL_ = "https://xakscsouugwlyefaieyl.supabase.co";
const KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhha3Njc291dWd3bHllZmFpZXlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4Mjk2ODEsImV4cCI6MjEwNzQwNTY4MX0.TXm0gnDiNHm3On8pV5zSZ4Fjot7qq-_8uCNqVb9lnZQ";
let failures = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) failures++; };

async function call(token, path, { method = "GET", body } = {}) {
  const r = await fetch(URL_ + path, {
    method,
    headers: { apikey: KEY, Authorization: `Bearer ${token ?? KEY}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
}
const rpc = (token, name, body = {}) => call(token, `/rest/v1/rpc/${name}`, { method: "POST", body });
const link = (code) => call(null, "/functions/v1/link-device", { method: "POST", body: { code } });

// The Mac: a new account.
const signup = await call(null, "/auth/v1/signup", { method: "POST", body: { data: {} } });
check(signup.status === 200, "sign up the Mac's account");
const mac = { token: signup.json.access_token, id: signup.json.user.id };
const profile = (await rpc(mac.token, "ensure_profile", { display_name: "LINK TEST" })).json;
check(/^TLK-/.test(profile.code ?? ""), `the Mac has a code (${profile.code})`);
console.log("     test account:", mac.id);

// Free for everyone: the whole board.
check((await rpc(mac.token, "my_plan")).json === "pro", "every account has the whole board (my_plan)");
check((await rpc(mac.token, "my_jack_limit")).json === 8, "eight jacks");

// A link code, used by a second device.
const started = await rpc(mac.token, "start_link");
const code = started.json;
check(started.status === 200 && /^[A-Z2-9]{8}$/.test(code ?? ""), `the Mac gets a link code (${code})`);
const linked = await link(`${code.slice(0, 4)}-${code.slice(4)}`.toLowerCase());
check(linked.status === 200 && !!linked.json.token_hash, "the code (typed in lower case, with a dash) is accepted");
check(linked.json.code === profile.code && linked.json.name === "LINK TEST", "it names the Mac's account");
const verified = await call(null, "/auth/v1/verify", { method: "POST", body: { type: "magiclink", token_hash: linked.json.token_hash } });
check(verified.status === 200 && verified.json.user?.id === mac.id, "the iPhone is signed in to the same account");
const phone = { token: verified.json.access_token };
const phoneProfile = (await rpc(phone.token, "ensure_profile", { display_name: "" })).json;
check(phoneProfile.code === profile.code && phoneProfile.name === "LINK TEST", "same code and name on the iPhone (an empty name doesn't rename)");
check((await rpc(mac.token, "my_plan")).status === 200, "the Mac is still signed in too");

// A code works once.
check((await link(code)).status === 404, "a used code is refused");

// Ten wrong codes in an hour, then refused.
let statuses = [];
for (let i = 0; i < 11; i++) statuses.push((await link("ZZZZZZZZ")).status);
check(statuses.slice(0, 10).every((s) => s === 404 || s === 429), "wrong codes are refused");
check(statuses.includes(429), `after enough wrong codes: too many tries (statuses ${statuses.join(" ")})`);
check((await link("short")).status === 400, "a code that isn't 8 characters is turned away");

console.log(failures ? `\n${failures} failed` : "\nall good");
process.exit(failures ? 1 : 0);
