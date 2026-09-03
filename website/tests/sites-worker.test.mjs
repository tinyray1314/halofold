import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import test from "node:test";
import { getXShareUrl } from "../src/share-intent.js";
import worker from "../worker/index.js";

test("serves existing static assets without a fallback", async () => {
  const calls = [];
  const response = await worker.fetch(new Request("https://example.test/assets/app.js"), {
    ASSETS: {
      fetch: async (request) => {
        calls.push(new URL(request.url).pathname);
        return new Response("asset", { status: 200 });
      },
    },
  });

  assert.equal(response.status, 200);
  assert.deepEqual(calls, ["/assets/app.js"]);
});

test("falls back to index.html for an unknown app route", async () => {
  const calls = [];
  const response = await worker.fetch(
    new Request("https://example.test/flow/step-two?source=share", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async (request) => {
          const url = new URL(request.url);
          calls.push(url.pathname + url.search);
          return new Response(url.pathname === "/index.html" ? "app" : "missing", {
            status: url.pathname === "/index.html" ? 200 : 404,
          });
        },
      },
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(calls, ["/flow/step-two?source=share", "/index.html"]);
});

test("does not turn missing API or write requests into the app shell", async () => {
  for (const request of [
    new Request("https://example.test/api/missing", { headers: { accept: "application/json" } }),
    new Request("https://example.test/flow", { method: "POST", headers: { accept: "text/html" } }),
  ]) {
    let calls = 0;
    const response = await worker.fetch(request, {
      ASSETS: {
        fetch: async () => {
          calls += 1;
          return new Response("missing", { status: 404 });
        },
      },
    });

    assert.equal(response.status, 404);
    assert.equal(calls, 1);
  }
});

test("emits the files required by Sites packaging", async () => {
  await access(new URL("../dist/client/index.html", import.meta.url));
  await access(new URL("../dist/server/index.js", import.meta.url));
  await access(new URL("../dist/.openai/hosting.json", import.meta.url));
});

test("ships the current DMG and no longer advertises a ZIP", async () => {
  const files = await readdir(new URL("../dist/client/assets/", import.meta.url));
  const jsName = files.find((name) => name.startsWith("index-") && name.endsWith(".js"));

  assert.ok(jsName);
  const js = await readFile(new URL(`../dist/client/assets/${jsName}`, import.meta.url), "utf8");
  assert.match(js, /\/downloads\/Halofold-1\.1\.0\.dmg/);
  assert.doesNotMatch(js, /Halofold-1\.1\.0\.zip/);
  await access(new URL("../dist/client/downloads/Halofold-1.1.0.dmg", import.meta.url));
});

test("ships complete social sharing metadata and its image", async () => {
  const html = await readFile(new URL("../dist/client/index.html", import.meta.url), "utf8");

  for (const marker of [
    'rel="canonical" href="https://halofold.aitiny.top/"',
    'property="og:title"',
    'property="og:type" content="website"',
    'property="og:url" content="https://halofold.aitiny.top/"',
    'property="og:image" content="https://halofold.aitiny.top/assets/halofold-social-card-v2.jpg"',
    'property="og:image:type" content="image/jpeg"',
    'name="twitter:card" content="summary_large_image"',
    'name="twitter:site" content="@tinyray1314"',
    'name="twitter:title"',
    'name="twitter:image" content="https://halofold.aitiny.top/assets/halofold-social-card-v2.jpg"',
    'type="application/ld+json"',
  ]) {
    assert.match(html, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  await access(new URL("../dist/client/assets/halofold-social-card-v2.jpg", import.meta.url));
});

test("builds locale-aware X share intents with the canonical site URL", () => {
  const zh = new URL(getXShareUrl("zh"));
  const en = new URL(getXShareUrl("en"));

  assert.equal(zh.origin + zh.pathname, "https://twitter.com/intent/tweet");
  assert.equal(zh.searchParams.get("url"), "https://halofold.aitiny.top/");
  assert.match(zh.searchParams.get("text"), /推荐给正在用 Codex 的朋友/);
  assert.equal(en.searchParams.get("url"), "https://halofold.aitiny.top/");
  assert.match(en.searchParams.get("text"), /If you use Codex on macOS/);
});
