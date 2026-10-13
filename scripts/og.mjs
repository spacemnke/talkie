// Renders the website's link preview, design/og/og.html, to site/og.png (1200 x 630).
// Needs Playwright and a Chromium: node scripts/og.mjs [path/to/chromium]
import { chromium } from "playwright";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const browser = await chromium.launch({ executablePath: process.argv[2], args: ["--headless=new"] });
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.goto("file://" + path.join(root, "design/og/og.html"));
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(root, "site/og.png") });
await browser.close();
console.log("site/og.png");
