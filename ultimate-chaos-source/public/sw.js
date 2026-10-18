const CACHE='ultimate-chaos-static-v2';
const SHELL=['/offline.html','/icons/icon-192.png','/icons/icon-512.png','/favicon.svg'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)));});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('ultimate-chaos-static-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));});
self.addEventListener('message',event=>{if(event.data?.type==='SKIP_WAITING')void self.skipWaiting();});
async function remember(request,response){if(response.status!==200||response.type==='opaque')return response;const cache=await caches.open(CACHE);await cache.put(request,response.clone());const keys=await cache.keys();const reusable=keys.filter(key=>!SHELL.includes(new URL(key.url).pathname));await Promise.all(reusable.slice(0,Math.max(0,reusable.length-60)).map(key=>cache.delete(key)));return response;}
self.addEventListener('fetch',event=>{
 const request=event.request,url=new URL(request.url);
 // Never intercept Supabase, API calls, writes, auth or media range requests.
 if(request.method!=='GET'||url.origin!==self.location.origin||request.headers.has('range'))return;
 if(request.mode==='navigate'){
  // Online documents and match routes are never cached. Offline always gets an honest connection screen.
  event.respondWith(fetch(request).catch(async()=>await caches.match('/offline.html')||Response.error()));return;
 }
 if(/^\/assets\/[^/]+-[\w-]+\.(js|css)$/.test(url.pathname))event.respondWith(caches.match(request).then(hit=>hit||fetch(request).then(response=>remember(request,response))));
 else if(/^\/(art|fonts|icons)\//.test(url.pathname)){const update=fetch(request).then(response=>remember(request,response));event.waitUntil(update.catch(()=>{}));event.respondWith(caches.match(request).then(hit=>hit||update).catch(()=>Response.error()));}
});
