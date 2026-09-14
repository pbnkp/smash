/* smash service worker — integrity-gated, fail-closed offline cache.
   Sole author: pbnkp. MIT.
   The pinned SHA-256 map below is injected at build time. At install, every
   listed asset is fetched and hashed; ANY mismatch throws, so the service
   worker never activates and a poisoned/altered asset is never cached or
   served. Offline use cannot be silently tampered. */
"use strict";
var CACHE = "__CACHE__";
var INTEGRITY = __INTEGRITY__;

function hex(buf) {
  var v = new Uint8Array(buf), s = "", i;
  for (i = 0; i < v.length; i++) s += (v[i] < 16 ? "0" : "") + v[i].toString(16);
  return s;
}
async function sha256(buf) { return hex(await crypto.subtle.digest("SHA-256", buf)); }

self.addEventListener("install", function (e) {
  e.waitUntil((async function () {
    var cache = await caches.open(CACHE);
    var paths = Object.keys(INTEGRITY), i;
    for (i = 0; i < paths.length; i++) {
      var p = paths[i];
      var res = await fetch(p, { cache: "no-store" });
      if (!res.ok) throw new Error("sw: fetch failed " + p);
      var buf = await res.clone().arrayBuffer();
      var got = await sha256(buf);
      if (got !== INTEGRITY[p]) throw new Error("sw: integrity mismatch " + p); // FAIL CLOSED
      await cache.put(p, res);
    }
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", function (e) {
  e.waitUntil((async function () {
    var keys = await caches.keys(), i;
    for (i = 0; i < keys.length; i++) { if (keys[i] !== CACHE) await caches.delete(keys[i]); }
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", function (e) {
  var url = new URL(e.request.url);
  if (url.origin !== location.origin) return; // same-origin only
  e.respondWith((async function () {
    var cache = await caches.open(CACHE);
    var hit = await cache.match(e.request, { ignoreSearch: true });
    if (hit) return hit;
    // Not in the verified cache — go to network but never cache unverified bytes.
    try { return await fetch(e.request); } catch (_) { return new Response("offline", { status: 503 }); }
  })());
});
