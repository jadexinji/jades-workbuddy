const cacheName = "jade-workbuddy-v16";
const files = [
  "./index.html",
  "./manifest.webmanifest",
  "./workbuddy-icon.svg",
  "./desk-pet-cutout.webp"
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) => cache.addAll(files)));
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    fetch(event.request).then((response) => {
      const copy = response.clone();
      caches.open(cacheName).then((cache) => cache.put(event.request, copy));
      return response;
    }).catch(() => {
      return caches.match(event.request);
    })
  );
});
