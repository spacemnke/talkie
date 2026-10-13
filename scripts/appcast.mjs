// Writes the update feed Talkie checks (Sparkle's appcast) for one build, signed so Talkie only
// installs updates that really came from this repository.
//
//   SPARKLE_PRIVATE_KEY=<base64 Ed25519 seed> node scripts/appcast.mjs <archive> <build> <version> <url> <out.xml>
//
// The archive is signed whole with Ed25519, which is what Sparkle checks against SUPublicEDKey in
// Info.plist. The key lives in the repository's Actions secrets, never in the repository.
import { createPrivateKey, createPublicKey, sign } from "node:crypto";
import { readFileSync, writeFileSync, statSync } from "node:fs";

const [archive, build, version, url, out] = process.argv.slice(2);
if (!out) {
  console.error("usage: node scripts/appcast.mjs <archive> <build> <version> <url> <out.xml>");
  process.exit(2);
}
const seed = Buffer.from((process.env.SPARKLE_PRIVATE_KEY ?? "").trim(), "base64");
if (seed.length !== 32) {
  console.error("SPARKLE_PRIVATE_KEY must be a base64 Ed25519 seed (32 bytes)");
  process.exit(1);
}

// An Ed25519 private key is its 32-byte seed behind a fixed PKCS#8 header.
const key = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
  format: "der",
  type: "pkcs8",
});
const data = readFileSync(archive);
const signature = sign(null, data, key).toString("base64");
const publicKey = createPublicKey(key).export({ format: "der", type: "spki" }).subarray(12).toString("base64");

const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Talkie</title>
    <link>https://switchtalkie.com</link>
    <item>
      <title>Talkie ${version}</title>
      <pubDate>${new Date().toUTCString()}</pubDate>
      <sparkle:version>${build}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${url}" length="${statSync(archive).size}" type="application/octet-stream" sparkle:edSignature="${signature}"/>
    </item>
  </channel>
</rss>
`;
writeFileSync(out, xml);
console.log(`${out}: build ${build} (${version}), signed for public key ${publicKey}`);
