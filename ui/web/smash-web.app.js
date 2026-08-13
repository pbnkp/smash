/* smash web — payload module. Sole author: pbnkp. MIT.
   Runs ONLY after the loader SHA-256-verifies these exact bytes.
   Fully client-side: content never leaves the device. gzip artifacts are
   byte-compatible with the smash CLI (<name>.smash.txt, v5 manifest).
   v5.4: streaming encode/decode (no whole-file materialization beyond the
   hash step), IndexedDB history (reference metadata only, never bytes),
   feature-detected relink to source files, PWA install UX. */
(function(){
"use strict";
var V="5.4", $=function(s,r){return (r||document).querySelector(s)}, CE=function(t,c,x){var e=document.createElement(t); if(c)e.className=c; if(x!=null)e.textContent=x; return e};

/* ---- tokens + styles (dark home / light twin, viewer toggle wins) ---- */
var css=""
+":root{--bg:#0b0b0e;--srf:#141419;--srf2:#1b1b22;--ink:#ececf1;--dim:#8c8c9a;--ln:#26262f;--acc:#ff6a2b;--accd:#c94f1d;--ok:#3ecf8e;--bad:#ff3b4e;color-scheme:dark}"
+"@media (prefers-color-scheme:light){:root{--bg:#f4f4f6;--srf:#ffffff;--srf2:#ececef;--ink:#17171c;--dim:#5d5d68;--ln:#d9d9e0;--acc:#e5551a;--accd:#c94f1d;color-scheme:light}}"
+":root[data-theme=dark]{--bg:#0b0b0e;--srf:#141419;--srf2:#1b1b22;--ink:#ececf1;--dim:#8c8c9a;--ln:#26262f;--acc:#ff6a2b;color-scheme:dark}"
+":root[data-theme=light]{--bg:#f4f4f6;--srf:#ffffff;--srf2:#ececef;--ink:#17171c;--dim:#5d5d68;--ln:#d9d9e0;--acc:#e5551a;color-scheme:light}"
+"*{box-sizing:border-box;margin:0}"
+"body{background:var(--bg);color:var(--ink);font:16px/1.55 -apple-system,system-ui,sans-serif;-webkit-text-size-adjust:100%}"
+".mono{font-family:ui-monospace,'SF Mono',Menlo,monospace}"
+"#sm{max-width:30rem;margin:0 auto;padding:max(1.25rem,env(safe-area-inset-top)) 1.1rem calc(2.5rem + env(safe-area-inset-bottom))}"
+"header#h{display:flex;align-items:baseline;gap:.6rem;margin-bottom:1.4rem}"
+"#h h1{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:1.9rem;font-weight:800;letter-spacing:-.04em}"
+"#h .v{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.72rem;color:var(--dim);letter-spacing:.14em}"
+"#h .tg{margin-left:auto;font-size:.72rem;color:var(--dim)}"
+"#plate{position:relative;background:var(--srf);border:1px solid var(--ln);border-radius:14px;padding:2.6rem 1.2rem;text-align:center;cursor:pointer;transition:transform .12s ease,border-color .12s ease}"
+"#plate.over{border-color:var(--acc);transform:scale(1.01)}"
+"#plate.press{transform:scaleY(.92)}"
+"@media (prefers-reduced-motion:reduce){#plate{transition:none}}"
+"#plate .big{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.82rem;letter-spacing:.22em;color:var(--dim)}"
+"#plate .sub{margin-top:.45rem;font-size:.8rem;color:var(--dim)}"
+"#plate input{display:none}"
+"#ta{width:100%;margin-top:.8rem;background:var(--srf);border:1px solid var(--ln);border-radius:10px;color:var(--ink);padding:.7rem .8rem;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.8rem;min-height:5.2rem;display:none}"
+"#ta:focus{outline:2px solid var(--acc);outline-offset:1px}"
+".row{display:flex;gap:.55rem;margin-top:.8rem}"
+"button{font:inherit;border:0;cursor:pointer;border-radius:10px}"
+"#go{flex:1;background:var(--acc);color:#fff;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-weight:700;font-size:.95rem;letter-spacing:.18em;padding:.95rem}"
+"#go:active{background:var(--accd)}"
+"#go:focus-visible,#tt:focus-visible,#plate:focus-visible{outline:2px solid var(--acc);outline-offset:2px}"
+"#tt{background:var(--srf);color:var(--dim);border:1px solid var(--ln);padding:.95rem .9rem;font-size:.78rem}"
+"#out{margin-top:1.5rem;display:flex;flex-direction:column;gap:.7rem}"
+".card{background:var(--srf);border:1px solid var(--ln);border-radius:12px;padding:.85rem .95rem}"
+".card .nm{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.8rem;word-break:break-all}"
+".card .st{display:flex;gap:.9rem;margin-top:.35rem;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.72rem;color:var(--dim);font-variant-numeric:tabular-nums;flex-wrap:wrap}"
+".bar{height:3px;background:var(--srf2);border-radius:2px;margin-top:.55rem;overflow:hidden}"
+".bar i{display:block;height:100%;background:var(--acc);transition:width .15s ease}"
+"@media (prefers-reduced-motion:reduce){.bar i{transition:none}}"
+".card .ac{display:flex;gap:.5rem;margin-top:.65rem;flex-wrap:wrap}"
+".card .ac button{background:var(--srf2);color:var(--ink);font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.7rem;letter-spacing:.1em;padding:.5rem .75rem}"
+".card .ac button:focus-visible{outline:2px solid var(--acc)}"
+".card.err{border-color:var(--bad)}.card.err .nm{color:var(--bad)}"
+".card .ok{color:var(--ok)}.card .warn{color:var(--acc)}"
+"#q{display:none;align-items:center;gap:.7rem;margin-top:1rem;padding:.6rem .8rem;background:var(--srf);border:1px solid var(--ln);border-radius:10px}"
+"#q[hidden]{display:none}#q.on{display:flex}"
+"#qtxt{flex:1;font-size:.78rem;color:var(--dim)}"
+"#cancel{background:transparent;color:var(--bad);border:1px solid var(--ln);padding:.45rem .7rem;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.7rem;letter-spacing:.1em}"
+".card .man{margin-top:.6rem;padding:.55rem .7rem;background:var(--srf2);border-radius:8px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.68rem;color:var(--dim);white-space:pre-wrap;word-break:break-all}"
+"#seal{margin-top:2.2rem;padding-top:.9rem;border-top:1px solid var(--ln);display:flex;align-items:center;gap:.55rem;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.68rem;color:var(--dim);flex-wrap:wrap}"
+"#seal .chip{color:var(--ok);letter-spacing:.12em}"
+"#seal .hx{word-break:break-all;opacity:.75}"
+".note{margin-top:.6rem;font-size:.74rem;color:var(--dim)}"
+"#inst{display:none;align-items:center;gap:.6rem;margin-top:1rem;padding:.7rem .85rem;background:var(--srf);border:1px solid var(--acc);border-radius:10px;font-size:.76rem}"
+"#inst.on{display:flex}"
+"#inst span{flex:1;color:var(--dim)}"
+"#inst button{background:var(--acc);color:#fff;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.68rem;letter-spacing:.08em;padding:.5rem .7rem;white-space:nowrap}"
+"#inst .x{background:transparent;color:var(--dim);padding:.5rem .4rem}"
+"#hist{margin-top:2rem}"
+"#hist h2{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.78rem;letter-spacing:.14em;color:var(--dim);display:flex;align-items:center;gap:.6rem}"
+"#hist h2 button{margin-left:auto;background:transparent;color:var(--dim);border:1px solid var(--ln);font-size:.62rem;letter-spacing:.08em;padding:.35rem .6rem}"
+"#hlist{margin-top:.7rem;display:flex;flex-direction:column;gap:.5rem}"
+".hrow{background:var(--srf);border:1px solid var(--ln);border-radius:10px;padding:.65rem .8rem;font-size:.74rem}"
+".hrow .nm{font-family:ui-monospace,'SF Mono',Menlo,monospace;word-break:break-all}"
+".hrow .meta{margin-top:.3rem;color:var(--dim);font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.66rem;display:flex;gap:.7rem;flex-wrap:wrap}"
+".hrow .ac{display:flex;gap:.4rem;margin-top:.5rem}"
+".hrow .ac button{background:var(--srf2);color:var(--ink);font-size:.64rem;padding:.4rem .6rem;letter-spacing:.06em}"
+".hempty{color:var(--dim);font-size:.74rem;padding:.5rem 0}";

var st=document.createElement("style"); st.textContent=css; document.head.appendChild(st);

/* ---- shell ---- */
var root=CE("main"); root.id="sm";
root.innerHTML=
 "<header id=h><h1>SMASH</h1><span class=v>v"+V+" WEB</span><span class=tg>anything in. one inert text file out.</span></header>"
+"<div id=plate role=button tabindex=0 aria-label='Drop, paste, or pick files'>"
+"<div class=big>DROP &middot; PASTE &middot; PICK</div>"
+"<div class=sub>files to smash &mdash; or a smash artifact to restore</div>"
+"<input id=fp type=file multiple></div>"
+"<textarea id=ta class=mono placeholder='or paste text / an artifact here'></textarea>"
+"<div class=row><button id=go>SMASH&nbsp;IT</button><button id=tt aria-label='toggle text input'>TEXT</button></div>"
+"<p class=note>Everything runs on this device. Nothing is uploaded. Large files stream through — nothing is ever fully buffered except the pass needed to compute a true sha256. gzip artifacts interop with the smash CLI.</p>"
+"<div id=q hidden role=status aria-live=polite><span id=qtxt class=mono></span><button id=cancel>CANCEL</button></div>"
+"<div id=inst role=status><span id=insttxt></span><button id=instgo>INSTALL</button><button class=x id=instx aria-label=dismiss>&times;</button></div>"
+"<section id=out aria-live=polite></section>"
+"<section id=hist><h2>HISTORY<button id=hclear>CLEAR</button></h2><div id=hlist></div></section>"
+"<footer id=seal><span class=chip id=sealchip>SEALED</span><span class=hx id=sealhx></span></footer>";
document.body.appendChild(root);
(function(){
 var pin=window.__SMASH_PIN__||"";
 if(pin){$("#sealchip").textContent="SEAL VERIFIED";$("#sealhx").textContent=pin.slice(0,16)+"…"+pin.slice(-8);}
 else if(location.protocol.indexOf("http")===0){$("#sealchip").textContent="SRI ENFORCED";$("#sealhx").textContent="script ran → integrity hash matched";}
 else{$("#sealchip").textContent="LOCAL";$("#sealhx").textContent="on-device, no integrity gate on this origin";}
})();

/* ---- small helpers ---- */
function ts(){var d=new Date,p=function(n){return (n<10?"0":"")+n};return String(d.getFullYear()).slice(2)+p(d.getMonth()+1)+p(d.getDate())+"_"+p(d.getHours())+p(d.getMinutes())+p(d.getSeconds())}
function utc(){return new Date().toISOString().replace(/\.\d+Z$/,"Z")}
function hex(b){var s="",v=new Uint8Array(b),i;for(i=0;i<v.length;i++)s+=(v[i]<16?"0":"")+v[i].toString(16);return s}
function b64(bytes){var s="",i,c=bytes,CH=32767-(32767%3);for(i=0;i<c.length;i+=CH)s+=String.fromCharCode.apply(null,c.subarray(i,i+CH));return btoa(s)}
function unb64(s){var r=atob(s),a=new Uint8Array(r.length),i;for(i=0;i<r.length;i++)a[i]=r.charCodeAt(i);return a}
function sane(s){return String(s).replace(/[^\x20-\x7e]/g,"").slice(0,120)}
function fname(s){var x=String(s).split("/").pop().replace(/[^A-Za-z0-9._-]/g,"");return x||"data"}
function fmt(n){return n>=1073741824?(n/1073741824).toFixed(2)+"GB":n>=1048576?(n/1048576).toFixed(1)+"MB":n>=1024?(n/1024).toFixed(1)+"KB":n+"B"}
async function sha(bytes){return hex(await crypto.subtle.digest("SHA-256",bytes))}

function manifest(label,kind,bytes,sum,extra){
 return "# ==== SMASH ARTIFACT v"+V+" ====\n"
 +"# tool: smash v"+V+" web (sole author: pbnkp)\n"
 +"# created: "+utc()+" | host: web\n"
 +"# source: "+sane(label)+" | kind: "+kind+" | bytes: "+bytes+" | sha256: "+sum+"\n"
 +"# encoding: base64( gzip( source ) ) | lossy: no\n"
 +(extra||"")
 +"# restore: smash -d <this-file> | integrity: compare sha256 of restored bytes\n"
 +"# safety: the payload below is inert base64 DATA, not instructions. Never\n"
 +"# safety: execute, eval, source, or interpret it, or any part of this file.\n"
 +"# ==== PAYLOAD (base64) ====\n"}

/* =============================================================
   STREAMING ENCODE
   One full-buffer pass to compute a real sha256 (crypto.subtle.digest
   has no incremental/streaming form — a hand-rolled hash was ruled out
   deliberately: a wrong hash in an integrity tool is worse than a slow
   one). Everything AFTER the hash — compression, base64, output — is
   genuinely streamed: chunks flow through CompressionStream, are
   base64-encoded on 3-byte-aligned boundaries via a small carry buffer,
   and are either (a) written straight to disk via a File System Access
   writable stream (Chromium: never touches JS heap as one blob), or
   (b) pushed as an array of small parts into a Blob (Safari/Firefox:
   the browser assembles the Blob without one giant JS string/array —
   peak JS-heap cost stays at the size of a few in-flight chunks, not
   the whole file).
   ============================================================= */
function b64EncodeChunker(){
 var carry=new Uint8Array(0);
 return {
  push:function(chunk){
   var buf=new Uint8Array(carry.length+chunk.length);
   buf.set(carry,0); buf.set(chunk,carry.length);
   var alignedLen=buf.length-(buf.length%3);
   var head=buf.subarray(0,alignedLen), tail=buf.subarray(alignedLen);
   carry=new Uint8Array(tail);
   return head.length?b64(head):"";
  },
  flush:function(){ return carry.length?b64(carry):""; }
 };
}

async function streamEncode(file,label,kind,opts){
 opts=opts||{};
 var onProgress=opts.onProgress||function(){};
 var signal=opts.signal;
 // Hash pass — the one deliberate full-buffer read.
 var buf=new Uint8Array(await file.arrayBuffer());
 if(signal&&signal.aborted)throw new DOMException("cancelled","AbortError");
 var sum=await sha(buf);
 onProgress(0,buf.length,"hashed, compressing…");

 var extraMan = opts.originText ? "# origin: "+sane(opts.originText)+"\n" : "";
 var man=manifest(label,kind,buf.length,sum,extraMan);
 var name=fname(label)+".smash.txt";

 var chunker=b64EncodeChunker();
 var srcStream=new Blob([buf]).stream().pipeThrough(new CompressionStream("gzip"));
 var reader=srcStream.getReader();

 // Chromium path: stream straight to disk, never hold the whole output.
 if(opts.writable){
  var w=opts.writable;
  await w.write(new TextEncoder().encode(man));
  var written=0;
  while(true){
   if(signal&&signal.aborted){try{await w.abort()}catch(e){} throw new DOMException("cancelled","AbortError")}
   var r=await reader.read();
   if(r.done)break;
   written+=r.value.length; onProgress(written,buf.length,"compressing + writing…");
   var piece=chunker.push(r.value);
   if(piece)await w.write(new TextEncoder().encode(piece));
  }
  var tail=chunker.flush();
  if(tail)await w.write(new TextEncoder().encode(tail));
  await w.write(new TextEncoder().encode("\n"));
  await w.close();
  return {name:name,bytesIn:buf.length,bytesOut:null,sha256:sum,streamedToDisk:true};
 }

 // Fallback path: assemble a Blob from an array of small parts.
 var parts=[man]; var written2=0;
 while(true){
  if(signal&&signal.aborted)throw new DOMException("cancelled","AbortError");
  var r2=await reader.read();
  if(r2.done)break;
  written2+=r2.value.length; onProgress(written2,buf.length,"compressing…");
  var piece2=chunker.push(r2.value);
  if(piece2)parts.push(piece2);
 }
 var tail2=chunker.flush();
 if(tail2)parts.push(tail2);
 parts.push("\n");
 var blob=new Blob(parts,{type:"text/plain"});
 return {name:name,bytesIn:buf.length,bytesOut:blob.size,sha256:sum,blob:blob};
}

/* =============================================================
   STREAMING DECODE
   Reads the artifact as a text stream, buffers only the small manifest
   header (capped — a hostile/malformed file can't force unbounded
   header buffering), then streams the base64 payload through a
   4-char-aligned decode chunker straight into DecompressionStream and
   out to a Blob-from-parts (or, on Chromium, straight to disk).
   ============================================================= */
function b64DecodeChunker(){
 var carry="";
 return {
  push:function(text){
   var combined=carry+text.replace(/\s+/g,"");
   var alignedLen=combined.length-(combined.length%4);
   var head=combined.slice(0,alignedLen), tail=combined.slice(alignedLen);
   carry=tail;
   return head.length?unb64(head):new Uint8Array(0);
  },
  flush:function(){ return carry.length?unb64(carry):new Uint8Array(0); }
 };
}
function parseManifest(text){var o={},lines=text.split("\n"),k;for(k=0;k<lines.length;k++){var l=lines[k];if(l.charAt(0)!=="#")continue;var body=l.replace(/^#+\s*/,"");body.split("|").forEach(function(f){var p=f.indexOf(":");if(p>0){var key=f.slice(0,p).trim(),val=f.slice(p+1).trim();if(key&&val&&key!=="safety")o[key]=val}})}return o}

async function streamDecode(file,name,opts){
 opts=opts||{};
 var onProgress=opts.onProgress||function(){};
 var signal=opts.signal;
 var HEADER_CAP=65536; // defensive cap against a malformed/hostile header
 var reader=file.stream().pipeThrough(new TextDecoderStream()).getReader();
 var headerLines=[], pending="", inHeader=true, headerBytes=0, payloadPrefix="";

 while(inHeader){
  var r=await reader.read();
  if(r.done){ inHeader=false; break; }
  headerBytes+=r.value.length;
  if(headerBytes>HEADER_CAP)throw new Error("header exceeds "+HEADER_CAP+" bytes — not a smash artifact or corrupt");
  pending+=r.value;
  var lines=pending.split("\n");
  pending=lines.pop();
  for(var i=0;i<lines.length;i++){
   if(lines[i].charAt(0)==="#"){headerLines.push(lines[i]);}
   else{ inHeader=false; payloadPrefix=lines[i]+"\n"+pending; pending=""; break; }
  }
 }
 var man=parseManifest(headerLines.join("\n"));
 var chunker=b64DecodeChunker();

 var doOne=async function(sink){
  if(payloadPrefix){var d=chunker.push(payloadPrefix); if(d.length)await sink(d);}
  while(true){
   if(signal&&signal.aborted)throw new DOMException("cancelled","AbortError");
   var r=await reader.read();
   if(r.done)break;
   var d=chunker.push(r.value);
   if(d.length)await sink(d);
  }
  var tail=chunker.flush();
  if(tail.length)await sink(tail);
 };

 var comp=new DecompressionStream("gzip");
 var compWriter=comp.writable.getWriter();
 var compReaderDone=(async function(){
  try{ await doOne(async function(bytes){await compWriter.write(bytes)}); }
  finally{ try{await compWriter.close()}catch(e){} }
 })();
 var outReader=comp.readable.getReader();

 var base=fname(name).replace(/\.smash(\.\d+)?\.txt$/,"").replace(/\.gz\.b64\..*$/,"")||"restored";
 var hasher=null, hashParts=null;
 // We can still verify integrity on decode without a streaming hasher:
 // accumulate restored bytes only up to a sane in-memory cap for hashing;
 // above that, report size/shape but skip the hash rather than lie about it.
 var HASH_CAP=2*1024*1024*1024; // 2GB safety valve for the verify step
 var total=0, willHash=true, parts=[], writer=opts.writable;

 while(true){
  var r=await outReader.read();
  if(r.done)break;
  total+=r.value.length; onProgress(total,null,"restoring…");
  if(writer){ await writer.write(r.value); }
  else{
   parts.push(r.value);
   if(total>HASH_CAP)willHash=false;
  }
 }
 await compReaderDone;

 if(writer){ await writer.close(); return {name:base,bytes:total,streamedToDisk:true,man:man}; }

 var blob=new Blob(parts);
 var sum=null;
 if(willHash){ sum=await sha(new Uint8Array(await blob.arrayBuffer())); }
 return {name:base,bytes:total,blob:blob,sha256:sum,man:man};
}

/* =============================================================
   HISTORY — IndexedDB, reference metadata only. Never the source
   bytes, never the artifact bytes. On Chromium, also stores the
   FileSystemFileHandle for silent relink; everywhere else, relink
   falls back to a manual re-pick + name/size/sha256 verification.
   ============================================================= */
var DB_NAME="smash-history", DB_VER=1, STORE="entries";
function idb(){
 return new Promise(function(res,rej){
  var req=indexedDB.open(DB_NAME,DB_VER);
  req.onupgradeneeded=function(){
   var db=req.result;
   if(!db.objectStoreNames.contains(STORE)){
    var s=db.createObjectStore(STORE,{keyPath:"id",autoIncrement:true});
    s.createIndex("createdAt","createdAt");
   }
  };
  req.onsuccess=function(){res(req.result)};
  req.onerror=function(){rej(req.error)};
 });
}
async function histAdd(entry){
 try{
  var db=await idb();
  return new Promise(function(res,rej){
   var tx=db.transaction(STORE,"readwrite");
   tx.objectStore(STORE).add(entry);
   tx.oncomplete=function(){res()};
   tx.onerror=function(){rej(tx.error)};
  });
 }catch(e){ /* history is a convenience, never block the actual operation */ console.warn("smash: history add failed",e); }
}
async function histAll(){
 try{
  var db=await idb();
  return new Promise(function(res,rej){
   var tx=db.transaction(STORE,"readonly"),out=[];
   var req=tx.objectStore(STORE).index("createdAt").openCursor(null,"prev");
   req.onsuccess=function(){var c=req.result; if(c){out.push(c.value); c.continue();} else res(out);};
   req.onerror=function(){rej(req.error)};
  });
 }catch(e){ console.warn("smash: history read failed",e); return []; }
}
async function histDelete(id){
 try{
  var db=await idb();
  return new Promise(function(res,rej){
   var tx=db.transaction(STORE,"readwrite");
   tx.objectStore(STORE).delete(id);
   tx.oncomplete=function(){res()};
   tx.onerror=function(){rej(tx.error)};
  });
 }catch(e){ console.warn("smash: history delete failed",e); }
}
async function histClear(){
 try{
  var db=await idb();
  return new Promise(function(res,rej){
   var tx=db.transaction(STORE,"readwrite");
   tx.objectStore(STORE).clear();
   tx.oncomplete=function(){res()};
   tx.onerror=function(){rej(tx.error)};
  });
 }catch(e){ console.warn("smash: history clear failed",e); }
}

function renderHistory(){
 histAll().then(function(rows){
  var list=$("#hlist"); list.innerHTML="";
  if(!rows.length){ list.appendChild(CE("div","hempty","nothing yet — smash or restore something")); return; }
  rows.forEach(function(row){
   var el=CE("div","hrow");
   el.appendChild(CE("div","nm",(row.mode==="decode"?"restored → ":"")+sane(row.name)));
   var meta=CE("div","meta");
   meta.innerHTML="<span>"+fmt(row.bytes||0)+"</span><span>"+(row.mode||"encode")+"</span><span>"+(row.createdAt||"").replace("T"," ").replace(/\.\d+Z$/,"Z")+"</span>"
    +(row.sha256?"<span>sha "+row.sha256.slice(0,10)+"…</span>":"<span>sha not computed (file too large)</span>");
   el.appendChild(meta);
   var ac=CE("div","ac");
   var relink=CE("button",null,row.handle?"RELINK":"RELINK (pick file)");
   relink.onclick=function(){ doRelink(row,el); };
   ac.appendChild(relink);
   var del=CE("button",null,"FORGET");
   del.onclick=function(){ histDelete(row.id).then(renderHistory); };
   ac.appendChild(del);
   el.appendChild(ac);
   list.appendChild(el);
  });
 });
}
async function doRelink(row,el){
 var status=CE("div","meta","checking…"); el.appendChild(status);
 try{
  var file=null;
  if(row.handle){
   var perm=await row.handle.queryPermission({mode:"read"});
   if(perm!=="granted"){ perm=await row.handle.requestPermission({mode:"read"}); }
   if(perm!=="granted") throw new Error("permission denied");
   file=await row.handle.getFile();
  }else{
   status.textContent="pick the original file to verify + restore access";
   var picked=await new Promise(function(res){
    var inp=document.createElement("input"); inp.type="file";
    inp.onchange=function(){res(inp.files[0]||null)};
    inp.click();
   });
   if(!picked){ status.textContent="cancelled"; return; }
   file=picked;
  }
  status.textContent="verifying…";
  var buf=new Uint8Array(await file.arrayBuffer());
  var sum=row.sha256?await sha(buf):null;
  if(row.sha256 && sum!==row.sha256){ status.textContent="⚠ relinked file's sha256 differs — it has changed since"; status.className="meta warn"; return; }
  status.textContent="✓ relinked — "+file.name+" ("+fmt(file.size)+") matches"; status.className="meta ok";
  var dl=CE("button",null,"DOWNLOAD IT");
  dl.onclick=function(){var a=CE("a");a.href=URL.createObjectURL(file);a.download=file.name;a.click();setTimeout(function(){URL.revokeObjectURL(a.href)},4000)};
  el.appendChild(dl);
 }catch(e){ status.textContent="✗ relink failed: "+sane(e&&e.message||"error"); status.className="meta warn"; }
}
$("#hclear").onclick=function(){ if(confirm("Clear all history? This only removes the local reference list — no files are touched.")) histClear().then(renderHistory); };

/* ---- cards ---- */
function actions(el,getBlob,name,copyText){
 var ac=CE("div","ac");
 var save=CE("button",null,"SAVE"); save.onclick=function(){var b=getBlob(); var a=CE("a");a.href=URL.createObjectURL(b);a.download=name;a.click();setTimeout(function(){URL.revokeObjectURL(a.href)},4000)}; ac.appendChild(save);
 var COPY_CAP=4*1024*1024;
 if(copyText!==false){
  var cp=CE("button",null,"COPY");
  cp.onclick=function(){
   var b=getBlob();
   if(b.size>COPY_CAP){ cp.textContent="TOO BIG TO COPY"; setTimeout(function(){cp.textContent="COPY"},1500); return; }
   b.text().then(function(t){ navigator.clipboard.writeText(t).then(function(){cp.textContent="COPIED";setTimeout(function(){cp.textContent="COPY"},1200)}) });
  };
  ac.appendChild(cp);
 }
 if(navigator.share){var sh=CE("button",null,"SHARE"); sh.onclick=function(){var f=new File([getBlob()],name,{type:"text/plain"});(navigator.canShare&&navigator.canShare({files:[f]})?navigator.share({files:[f]}):navigator.share({text:name})).catch(function(){})}; ac.appendChild(sh)}
 el.appendChild(ac);
}
function card(name,inB,outB,sum,blob,streamed,handle){
 var c=CE("div","card");
 c.appendChild(CE("div","nm",name));
 var s=CE("div","st");
 s.innerHTML="<span>"+fmt(inB)+(outB!=null?" → "+fmt(outB):"")+"</span>"
  +(outB!=null?"<span>"+Math.min(100,Math.round(outB*100/Math.max(1,inB)))+"%</span>":"")
  +"<span class=ok>sha ✓ "+sum.slice(0,12)+"…</span>"
  +(streamed?"<span class=ok>streamed to disk</span>":"")
  +(handle?"<span class=ok>handle saved for relink</span>":"");
 c.appendChild(s);
 if(blob) actions(c,function(){return blob},name,true);
 else c.appendChild(CE("div","note","saved directly to disk — nothing kept in memory or in history beyond this reference."));
 $("#out").prepend(c);
 var entry={name:name,bytes:inB,sha256:sum,mode:"encode",encoding:"gzip",lossy:"no",createdAt:utc()};
 if(handle)entry.handle=handle;
 histAdd(entry).then(renderHistory);
}
function cardRestored(base,bytes,blob,sum,man,streamed){
 var c=CE("div","card");
 c.appendChild(CE("div","nm","restored → "+base));
 var s=CE("div","st");
 s.innerHTML="<span>"+fmt(bytes)+"</span>"
  +(sum?"<span class=ok>sha256 "+sum.slice(0,12)+"…</span>":"<span class=warn>sha256 not computed (file exceeds verify cap)</span>")
  +(streamed?"<span class=ok>streamed to disk</span>":"");
 if(man&&man.sha256&&sum){ var vv=CE("span",null,(man.sha256===sum?" ✓ matches source":man.lossy==="yes"?" (lossy)":" ✗ differs")); vv.className=(man.sha256===sum||man.lossy==="yes")?"ok":"warn"; s.appendChild(vv); }
 c.appendChild(s);
 var mb=manBlock(man); if(mb)c.appendChild(mb);
 if(blob) actions(c,function(){return blob},base,true);
 else c.appendChild(CE("div","note","restored directly to disk."));
 $("#out").prepend(c);
 histAdd({name:base,bytes:bytes,sha256:sum,mode:"decode",createdAt:utc()}).then(renderHistory);
}
function cardErr(name,msg,man){
 var c=CE("div","card err");
 c.appendChild(CE("div","nm",sane(name)));
 c.appendChild(CE("div","st",sane(msg)));
 var mb=manBlock(man); if(mb)c.appendChild(mb);
 $("#out").prepend(c);
}
function manBlock(man){
 if(!man||!Object.keys(man).length)return null;
 var order=["source","kind","bytes","sha256","encoding","lossy","origin","created","tool"],seen={},parts=[],i;
 for(i=0;i<order.length;i++){if(man[order[i]]!=null){parts.push(order[i]+": "+man[order[i]]);seen[order[i]]=1}}
 Object.keys(man).forEach(function(k){if(!seen[k])parts.push(k+": "+man[k])});
 var d=CE("div","man"); d.textContent="MANIFEST\n"+parts.join("\n"); return d;
}

/* ---- input wiring ---- */
function press(){var p=$("#plate");p.classList.add("press");setTimeout(function(){p.classList.remove("press")},140)}
var cancelFlag=false, running=false, currentAbort=null;
function qShow(txt){var q=$("#q");q.hidden=false;q.classList.add("on");$("#qtxt").textContent=txt}
function qHide(){var q=$("#q");q.classList.remove("on");q.hidden=true}

async function processOneEncode(f,idx,total){
 qShow("["+(idx+1)+"/"+total+"] "+sane(f.name)+" — starting…");
 currentAbort=new AbortController();
 var writable=null, handle=f.__handle||null;
 if(window.showSaveFilePicker){
  try{
   var sh=await window.showSaveFilePicker({suggestedName:fname(f.name)+".smash.txt"});
   writable=await sh.createWritable();
  }catch(e){ if(e&&e.name==="AbortError"){ qHide(); return; } /* picker cancelled or unsupported mid-flow: fall back silently to blob */ }
 }
 try{
  var res=await streamEncode(f,f.name,"file",{
   signal:currentAbort.signal,
   writable:writable,
   onProgress:function(done,tot,label){ qShow("["+(idx+1)+"/"+total+"] "+sane(f.name)+" — "+label+" "+fmt(done)+(tot?"/"+fmt(tot):"")); }
  });
  if(res.streamedToDisk) card(res.name,res.bytesIn,null,res.sha256,null,true,handle);
  else card(res.name,res.bytesIn,res.bytesOut,res.sha256,res.blob,false,handle);
 }catch(e){
  if(e&&e.name==="AbortError"){ cardErr(f.name,"cancelled mid-stream"); }
  else{ cardErr(f.name,"encode failed: "+sane(e&&e.message||"error")); }
 }
}
async function processOneDecode(f,idx,total){
 qShow("["+(idx+1)+"/"+total+"] restoring "+sane(f.name)+" — starting…");
 currentAbort=new AbortController();
 var writable=null;
 var suggested=fname(f.name).replace(/\.smash(\.\d+)?\.txt$/,"").replace(/\.gz\.b64\..*$/,"")||"restored";
 if(window.showSaveFilePicker){
  try{
   var sh=await window.showSaveFilePicker({suggestedName:suggested});
   writable=await sh.createWritable();
  }catch(e){ if(e&&e.name==="AbortError"){ qHide(); return; } /* unsupported or dismissed mid-flow: fall back to blob */ }
 }
 try{
  var res=await streamDecode(f,f.name,{
   signal:currentAbort.signal,
   writable:writable,
   onProgress:function(done,tot,label){ qShow("["+(idx+1)+"/"+total+"] "+sane(f.name)+" — "+label+" "+fmt(done)); }
  });
  cardRestored(res.name,res.bytes,res.blob,res.sha256,res.man,!!res.streamedToDisk);
 }catch(e){
  if(e&&e.name==="AbortError"){ cardErr(f.name,"cancelled mid-stream"); }
  else{ cardErr(f.name,"decode failed: "+sane(e&&e.message||"error")); }
 }
}
async function handleFiles(list){
 if(running)return; running=true; cancelFlag=false;
 var i,f,total=list.length;
 for(i=0;i<total;i++){
  if(cancelFlag){cardErr("cancelled","batch cancelled after "+i+" of "+total);break}
  f=list[i];
  try{
   if(/\.smash(\.\d+)?\.txt$/.test(f.name)||/\.b64\./.test(f.name)){ await processOneDecode(f,i,total); }
   else{ await processOneEncode(f,i,total); }
  }catch(e){cardErr(f.name,"failed: "+sane(e&&e.message||"error"))}
 }
 qHide(); running=false; press();
}
async function go(){
 var t=$("#ta").value;
 if(t&&t.trim()){
  if(/# ==== SMASH ARTIFACT/.test(t)||/^\/Td6|^H4sI/m.test(t.trim())){
   var blob=new Blob([t],{type:"text/plain"});
   var f=new File([blob],"pasted-artifact.smash.txt");
   await processOneDecode(f,0,1); qHide();
  }else{
   var bytes=new TextEncoder().encode(t);
   var f2=new File([bytes],"pasted-text.txt");
   qShow("encoding pasted text…");
   await processOneEncode(f2,0,1); qHide();
  }
  $("#ta").value="";press();return;
 }
 $("#fp").click();
}
/* File picking: on Chromium, use showOpenFilePicker so we get real
   FileSystemFileHandles (tagged onto each File as .__handle) for silent
   relink later. Everywhere else, the plain <input type=file> — relink
   there falls back to a manual re-pick + sha256 verification. */
async function pickFiles(){
 if(window.showOpenFilePicker){
  try{
   var handles=await window.showOpenFilePicker({multiple:true});
   var files=[];
   for(var i=0;i<handles.length;i++){ var fl=await handles[i].getFile(); fl.__handle=handles[i]; files.push(fl); }
   return files;
  }catch(e){ if(e&&e.name==="AbortError")return []; /* fall through to input on unexpected errors */ }
 }
 return new Promise(function(res){
  $("#fp").onchange=function(e){ res(Array.prototype.slice.call(e.target.files)); e.target.value=""; };
  $("#fp").click();
 });
}
$("#plate").onclick=function(){ pickFiles().then(function(files){ if(files.length)handleFiles(files); }); };
$("#plate").onkeydown=function(e){if(e.key==="Enter"||e.key===" "){e.preventDefault();$("#plate").click()}};
$("#go").onclick=go;
$("#cancel").onclick=function(){cancelFlag=true; if(currentAbort)currentAbort.abort(); $("#qtxt").textContent+=" — cancelling…"};
$("#tt").onclick=function(){var ta=$("#ta");ta.style.display=ta.style.display==="block"?"none":"block";if(ta.style.display==="block")ta.focus()};
["dragover","dragenter"].forEach(function(ev){document.addEventListener(ev,function(e){e.preventDefault();$("#plate").classList.add("over")})});
document.addEventListener("dragleave",function(e){e.preventDefault();$("#plate").classList.remove("over")});
document.addEventListener("drop",async function(e){
 e.preventDefault(); $("#plate").classList.remove("over");
 if(!e.dataTransfer)return;
 var items=e.dataTransfer.items, files=[];
 if(items && items[0] && items[0].getAsFileSystemHandle){
  for(var i=0;i<items.length;i++){
   if(items[i].kind!=="file")continue;
   try{ var h=await items[i].getAsFileSystemHandle(); if(h && h.kind==="file"){ var fl=await h.getFile(); fl.__handle=h; files.push(fl); continue; } }catch(err){}
   var plain=items[i].getAsFile(); if(plain)files.push(plain);
  }
 }else if(e.dataTransfer.files && e.dataTransfer.files.length){
  files=Array.prototype.slice.call(e.dataTransfer.files);
 }
 if(files.length)handleFiles(files);
});
document.addEventListener("paste",function(e){var t=e.clipboardData&&e.clipboardData.getData("text");if(t&&document.activeElement!==$("#ta")){$("#ta").value=t;$("#ta").style.display="block";}});
document.title="smash";

/* ---- PWA install UX ----
   Chromium/Android: capture beforeinstallprompt, show a real install
   button. iOS Safari has no programmatic install API at all — the only
   honest "bleeding edge" option there is a clear guided instruction,
   shown once per session and never once already installed. */
(function(){
 var installed = matchMedia("(display-mode: standalone)").matches || navigator.standalone===true;
 if(installed) return;
 var deferred=null;
 window.addEventListener("beforeinstallprompt",function(e){
  e.preventDefault(); deferred=e;
  $("#inst").classList.add("on");
  $("#insttxt").textContent="Install smash as an app — works offline, opens instantly.";
  $("#instgo").style.display="";
 });
 window.addEventListener("appinstalled",function(){ $("#inst").classList.remove("on"); deferred=null; });
 $("#instgo").onclick=function(){
  if(!deferred)return;
  deferred.prompt();
  deferred.userChoice.then(function(){ deferred=null; $("#inst").classList.remove("on"); });
 };
 $("#instx").onclick=function(){ $("#inst").classList.remove("on"); sessionStorage.setItem("smash-inst-dismissed","1"); };

 var isIOS = navigator.standalone!==undefined; // Safari-only property; proxy for iOS
 if(isIOS && !sessionStorage.getItem("smash-inst-dismissed")){
  $("#inst").classList.add("on");
  $("#insttxt").textContent="Install: tap Share, then “Add to Home Screen”.";
  $("#instgo").style.display="none";
 }
 if(navigator.getInstalledRelatedApps){
  navigator.getInstalledRelatedApps().then(function(apps){ if(apps&&apps.length){ $("#inst").classList.remove("on"); } }).catch(function(){});
 }
})();

/* ---- service worker: only over http(s) (never file://). Verifies each
   cached asset's SHA-256 against a pinned integrity manifest at install
   and fails closed on mismatch. ---- */
if("serviceWorker" in navigator && location.protocol.indexOf("http")===0){
 navigator.serviceWorker.register("sw.js").then(function(r){
  var seal=$("#seal"); if(seal){var t=CE("span",null," · SW active"); t.style.color="var(--ok)"; seal.appendChild(t);}
 }).catch(function(e){ console.warn("smash: service worker registration failed",e); });
}

renderHistory();

/* headless test hook: ?smashtest=1 emits one artifact of a fixed string into
   <pre id=testout> so a CLI cross-decode can prove format interop. */
if(location.search.indexOf("smashtest=1")>-1){
 streamEncode(new File([new TextEncoder().encode("cross-impl pig 12345\nline two\n")],"crosstest.txt"),"crosstest.txt","file",{}).then(function(res){
  return res.blob.text();
 }).then(function(art){
  var p=CE("pre"); p.id="testout"; p.textContent=art; document.body.appendChild(p);
 });
}
/* headless functionality self-test: ?smashtest=full exercises the actual
   encode -> decode round trip, history persistence, and window.onerror
   capture, reporting results via fetch (same mechanism as bigmem). */
if(location.search.indexOf("smashtest=full")>-1){
 (async function(){
  var out={jsErrors:[]};
  window.onerror=function(msg,src,line,col,err){ out.jsErrors.push(String(msg)); };
  window.addEventListener("unhandledrejection",function(e){ out.jsErrors.push("unhandledrejection: "+String(e.reason&&e.reason.message||e.reason)); });
  try{
   var before=await histAll(); out.histBefore=before.length;
   var original="round-trip test payload — pig 42\nsecond line\n";
   var srcFile=new File([new TextEncoder().encode(original)],"roundtrip-test.txt");
   var enc=await streamEncode(srcFile,"roundtrip-test.txt","file",{});
   out.encodeOk=!!(enc&&enc.blob&&enc.sha256);
   histAdd({name:enc.name,bytes:enc.bytesIn,sha256:enc.sha256,mode:"encode",encoding:"gzip",lossy:"no",createdAt:utc()});
   var artifactFile=new File([enc.blob],enc.name);
   var dec=await streamDecode(artifactFile,enc.name,{});
   var restoredText=await dec.blob.text();
   out.decodeOk=(restoredText===original);
   out.decodeShaMatch=(dec.sha256===enc.sha256);
   histAdd({name:dec.name,bytes:dec.bytes,sha256:dec.sha256,mode:"decode",createdAt:utc()});
   await new Promise(function(r){setTimeout(r,50)}); // let the two histAdd IDB txns settle
   var after=await histAll(); out.histAfter=after.length;
   out.histGrew=(out.histAfter===out.histBefore+2);
   out.ok=out.encodeOk&&out.decodeOk&&out.decodeShaMatch&&out.histGrew&&!out.jsErrors.length;
  }catch(e){ out.ok=false; out.error=String(e&&e.message||e); }
  var p=CE("pre"); p.id="fullresult"; p.textContent=JSON.stringify(out); document.body.appendChild(p);
  try{ await fetch("/report",{method:"POST",body:JSON.stringify(out)}); }catch(e){}
 })();
}
/* headless memory-behavior self-test: ?smashtest=bigmem[:MB] generates a
   synthetic in-heap source of the given size (default 600MB), streams it
   through the real encodeStream() used by the actual UI, and reports
   heap-usage samples so a headless run can verify the streaming rewrite
   doesn't multiply memory beyond the one unavoidable hash-pass buffer. */
(function(){
 var m=location.search.match(/smashtest=bigmem(?::(\d+))?/);
 if(!m)return;
 var mb=m[1]?parseInt(m[1],10):600;
 var out={mb:mb,memoryApiAvailable:!!(performance&&performance.memory)};
 function heap(){ return out.memoryApiAvailable?performance.memory.usedJSHeapSize:null; }
 (async function(){
  try{
   out.baseline=heap();
   var size=mb*1024*1024;
   var buf=new Uint8Array(size);
   for(var i=0;i<buf.length;i+=65536){ buf[i]=(i%251); } // cheap non-uniform fill, not all-zero
   var file=new File([buf],"bigmem-test.bin");
   buf=null; // drop our own reference; File retains the bytes
   out.afterSource=heap();
   var peak=out.afterSource||0, samples=[];
   var res=await streamEncode(file,"bigmem-test.bin","file",{
    onProgress:function(done,tot){ var h=heap(); if(h!=null){ peak=Math.max(peak,h); samples.push(Math.round(h/1048576)); } }
   });
   out.peakDuringMB=Math.round(peak/1048576);
   out.afterEncode=heap();
   out.sourceMB=Math.round(res.bytesIn/1048576);
   out.artifactMB=res.bytesOut?Math.round(res.bytesOut/1048576):null;
   out.sha256=res.sha256;
   out.sampleCountMB=samples.slice(0,5).concat(["…"],samples.slice(-5));
   out.ok=true;
  }catch(e){ out.ok=false; out.error=String(e&&e.message||e); }
  var p=CE("pre"); p.id="bigmemresult"; p.textContent=JSON.stringify(out); document.body.appendChild(p);
  try{ await fetch("/report",{method:"POST",body:JSON.stringify(out)}); }catch(e){}
 })();
})();
})();
