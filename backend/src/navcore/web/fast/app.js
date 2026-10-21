// NAVI fast mode, all on the phone (onnxruntime-web), no server, no route data:
// metric depth (Depth Anything V2 indoor) finds ANY obstacle + the free side; YOLO26s only names it.
import * as ort from '/fast/ort.wasm.min.mjs';

const $ = (id) => document.getElementById(id);
const video = $('video'), overlay = $('overlay'), caption = $('caption');
const home = $('home'), startBtn = $('startBtn'), homeText = $('homeText');
const menuBtn = $('menuBtn'), sheet = $('sheet'), sheetBg = $('sheetBg'), perf = $('perf');

const SIZE = 320, DW = 196, DH = 350, MIN_GAP_MS = 40;
const LABELS = ['person','bicycle','car','motorcycle','airplane','bus','train','truck','boat','traffic light','fire hydrant','stop sign','parking meter','bench','bird','cat','dog','horse','sheep','cow','elephant','bear','zebra','giraffe','backpack','umbrella','handbag','tie','suitcase','frisbee','skis','snowboard','sports ball','kite','baseball bat','baseball glove','skateboard','surfboard','tennis racket','bottle','wine glass','cup','fork','knife','spoon','bowl','banana','apple','sandwich','orange','broccoli','carrot','hot dog','pizza','donut','cake','chair','couch','potted plant','bed','dining table','toilet','tv','laptop','mouse','remote','keyboard','cell phone','microwave','oven','toaster','sink','refrigerator','book','clock','vase','scissors','teddy bear','hair drier','toothbrush'];
// Only things a walking person can bump into; small handheld classes are dropped (main source of wrong labels).
const VI = {
  person: 'người', bicycle: 'xe đạp', car: 'ô tô', motorcycle: 'xe máy', bus: 'xe buýt', truck: 'xe tải',
  train: 'tàu', bench: 'ghế băng', chair: 'ghế', couch: 'ghế sofa', 'potted plant': 'chậu cây', bed: 'giường',
  'dining table': 'bàn', toilet: 'bồn cầu', dog: 'con chó', cat: 'con mèo', horse: 'con ngựa', cow: 'con bò',
  suitcase: 'vali', 'fire hydrant': 'trụ nước', 'stop sign': 'biển báo', 'traffic light': 'đèn giao thông',
  'parking meter': 'cột trụ', refrigerator: 'tủ lạnh', sink: 'bồn rửa', oven: 'lò',
};
// stop/warn are in the depth model's own scale (it reads indoor distances a bit long).
// Shown on screen only (not spoken): small things people want to see but can't walk into.
const SHOW = {
  laptop: 'laptop', tv: 'màn hình', 'cell phone': 'điện thoại', cup: 'cốc', bottle: 'chai', bowl: 'bát',
  book: 'sách', keyboard: 'bàn phím', mouse: 'chuột', remote: 'điều khiển', backpack: 'ba lô', handbag: 'túi xách',
  umbrella: 'ô', clock: 'đồng hồ', vase: 'bình hoa', microwave: 'lò vi sóng', toaster: 'máy nướng', scissors: 'kéo',
  'teddy bear': 'gấu bông', 'wine glass': 'ly', knife: 'dao', 'sports ball': 'quả bóng', skateboard: 'ván trượt',
  bird: 'con chim', kite: 'diều', tie: 'cà vạt',
};
const SENS = {
  low: { conf: 0.5, area: 0.02, hits: 3, stop: 1.4, warn: 2.0 },
  mid: { conf: 0.4, area: 0.012, hits: 2, stop: 1.7, warn: 2.4 },
  high: { conf: 0.3, area: 0.006, hits: 2, stop: 2.0, warn: 2.8 },
};
const ZONE_VI = { left: 'bên trái', center: 'phía trước', right: 'bên phải' };

// ---------- settings ----------
const opts = Object.assign({ voice: true, vibrate: true, boxes: true, sens: 'mid', rate: '1.1' },
  JSON.parse(localStorage.getItem('navi-opts') || '{}'));
const save = () => localStorage.setItem('navi-opts', JSON.stringify(opts));
for (const [id, key] of [['optVoice', 'voice'], ['optVibrate', 'vibrate'], ['optBoxes', 'boxes']]) {
  $(id).checked = opts[key];
  $(id).addEventListener('change', (e) => { opts[key] = e.target.checked; save(); if (key === 'voice' && !opts.voice) speech.cancel(); });
}
for (const [id, key] of [['optSens', 'sens'], ['optRate', 'rate']]) {
  const seg = $(id);
  const paint = () => seg.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.v === opts[key]));
  seg.addEventListener('click', (e) => { const v = e.target.dataset?.v; if (v) { opts[key] = v; save(); paint(); } });
  paint();
}

// ---------- speech: one voice at a time, only danger may interrupt ----------
const speech = {
  voice: null, busy: false, level: null, endAt: 0, timer: 0,
  pick() { this.voice = speechSynthesis.getVoices().find((v) => v.lang?.toLowerCase().startsWith('vi')) || null; },
  done() { clearTimeout(this.timer); this.busy = false; this.level = null; this.endAt = performance.now(); },
  cancel() { window.speechSynthesis?.cancel(); this.done(); },
  idleFor() { return this.busy ? -1 : performance.now() - this.endAt; },
  say(text, level) {
    showCaption(text, level);
    if (!opts.voice || !window.speechSynthesis) { this.endAt = performance.now() + 1500; return; }
    if (this.busy) {
      if (level !== 'stop' || this.level === 'stop') return;
      speechSynthesis.cancel();
    }
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'vi-VN'; if (this.voice) u.voice = this.voice; u.rate = Number(opts.rate);
    u.onend = u.onerror = () => this.done();
    this.busy = true; this.level = level;
    // Some phones never fire onend; release the lock after an estimated duration.
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.done(), 1200 + (text.length * 85) / Number(opts.rate));
    speechSynthesis.speak(u);
  },
};
if (window.speechSynthesis) { speech.pick(); speechSynthesis.onvoiceschanged = () => speech.pick(); }

let captionTimer = 0;
function showCaption(text, level) {
  caption.textContent = text; caption.className = `caption show ${level || ''}`;
  clearTimeout(captionTimer); captionTimer = setTimeout(() => caption.classList.remove('show'), 2800);
}
const buzz = (p) => { if (opts.vibrate) navigator.vibrate?.(p); };

// ---------- detection ----------
const grab = document.createElement('canvas');
grab.width = grab.height = SIZE;
const gctx = grab.getContext('2d', { willReadFrequently: true });
const input = new Float32Array(3 * SIZE * SIZE);

function preprocess() {
  const vw = video.videoWidth, vh = video.videoHeight;
  const scale = Math.min(SIZE / vw, SIZE / vh);
  const w = Math.round(vw * scale), h = Math.round(vh * scale);
  const left = Math.floor((SIZE - w) / 2), top = Math.floor((SIZE - h) / 2);
  gctx.fillStyle = 'rgb(114,114,114)'; gctx.fillRect(0, 0, SIZE, SIZE);
  gctx.drawImage(video, left, top, w, h);
  const px = gctx.getImageData(0, 0, SIZE, SIZE).data, n = SIZE * SIZE;
  for (let i = 0, j = 0; i < n; i++, j += 4) {
    input[i] = px[j] / 255; input[i + n] = px[j + 1] / 255; input[i + 2 * n] = px[j + 2] / 255;
  }
  return { left, top, scale, vw, vh };
}

function parse(out, t) {
  const s = SENS[opts.sens], dets = [];
  const clamp = (v) => Math.min(Math.max(v, 0), 1);
  for (let r = 0; r < 300; r++) {
    const o = r * 6, conf = out[o + 4], label = LABELS[out[o + 5] | 0];
    if (!(conf >= s.conf) || !(VI[label] || SHOW[label])) continue;
    const x1 = clamp((out[o] - t.left) / t.scale / t.vw), x2 = clamp((out[o + 2] - t.left) / t.scale / t.vw);
    const y1 = clamp((out[o + 1] - t.top) / t.scale / t.vh), y2 = clamp((out[o + 3] - t.top) / t.scale / t.vh);
    if ((x2 - x1) * (y2 - y1) < s.area) continue;
    dets.push({ label, conf, box: [x1, y1, x2, y2] });
  }
  return dets;
}

// ---------- depth: nearest surface per region, regardless of what it is ----------
const dgrab = document.createElement('canvas');
dgrab.width = DW; dgrab.height = DH;
const dctx = dgrab.getContext('2d', { willReadFrequently: true });
const dinput = new Float32Array(3 * DW * DH);
const MEAN = [0.485, 0.456, 0.406], STD = [0.229, 0.224, 0.225];
let depth = null; // Float32Array DH*DW, metres (model scale)

function preprocessDepth() {
  dctx.drawImage(video, 0, 0, DW, DH);
  const px = dctx.getImageData(0, 0, DW, DH).data, n = DW * DH;
  for (let i = 0, j = 0; i < n; i++, j += 4) {
    for (let c = 0; c < 3; c++) dinput[i + c * n] = (px[j + c] / 255 - MEAN[c]) / STD[c];
  }
}

// Low percentile of depth inside a normalized rectangle = distance to the nearest real surface there.
function nearIn(x1, x2, y1, y2, q = 0.1) {
  const c0 = Math.floor(x1 * DW), c1 = Math.max(c0 + 1, Math.floor(x2 * DW));
  const r0 = Math.floor(y1 * DH), r1 = Math.max(r0 + 1, Math.floor(y2 * DH));
  const v = [];
  for (let r = r0; r < r1; r += 2) for (let c = c0; c < c1; c += 2) v.push(depth[r * DW + c]);
  v.sort((a, b) => a - b);
  return v[Math.floor(q * (v.length - 1))] ?? 99;
}

// Rows 20–75%: body height when the phone is held at the chest; floor and ceiling stay out of it.
let clear = null;
function analyzeDepth() {
  // Each side = its most open lane, so one close thing at the edge doesn't hide a free gap.
  const lane = (x1, x2) => nearIn(x1, x2, 0.2, 0.75);
  const raw = { left: Math.max(lane(0, 0.2), lane(0.15, 0.35)), center: lane(0.3, 0.7), right: Math.max(lane(0.65, 0.85), lane(0.8, 1)) };
  if (!clear) clear = raw;
  else for (const k in raw) clear[k] = clear[k] * 0.4 + raw[k] * 0.6;
  return clear;
}

// Obstacle regions straight from depth: near pixels grouped into boxes, for things YOLO can't name.
const GS = 4, GW = Math.floor(DW / GS), GH = Math.floor(DH / GS);
let blobs = [];
function depthBlobs(named) {
  const s = SENS[opts.sens], g0 = Math.floor(GH * 0.12), g1 = Math.floor(GH * 0.88);
  const near = new Uint8Array(GW * GH), seen = new Uint8Array(GW * GH);
  // "Near" = within warn range AND clearly closer than the rest of the scene,
  // so a small room's walls don't merge into one giant box.
  const vals = [];
  for (let gy = g0; gy < g1; gy++) for (let gx = 0; gx < GW; gx++) vals.push(depth[(gy * GS) * DW + gx * GS]);
  vals.sort((a, b) => a - b);
  const lim = Math.min(s.warn, vals[vals.length >> 1] * 0.8);
  for (let gy = g0; gy < g1; gy++) for (let gx = 0; gx < GW; gx++) {
    if (depth[(gy * GS) * DW + gx * GS] < lim) near[gy * GW + gx] = 1;
  }
  const found = [];
  for (let i = 0; i < near.length; i++) {
    if (!near[i] || seen[i]) continue;
    const stack = [i]; seen[i] = 1;
    let n = 0, minX = GW, minY = GH, maxX = 0, maxY = 0, dmin = 99;
    while (stack.length) {
      const k = stack.pop(), x = k % GW, y = (k / GW) | 0;
      n++; minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      dmin = Math.min(dmin, depth[(y * GS) * DW + x * GS]);
      for (const j of [k - 1, k + 1, k - GW, k + GW]) {
        if (j < 0 || j >= near.length || seen[j] || !near[j] || Math.abs((j % GW) - x) > 1) continue;
        seen[j] = 1; stack.push(j);
      }
    }
    if (n < GW * GH * 0.015 || maxY - minY < 5) continue;
    const box = [minX / GW, minY / GH, (maxX + 1) / GW, (maxY + 1) / GH];
    // Skip regions that are really a YOLO object we already show with its name.
    if (named.some((o) => iou(o.box, box) > 0.35)) continue;
    found.push({ box, dist: dmin });
  }
  // Light smoothing so boxes don't jump frame to frame.
  blobs = found.map((b) => {
    const prev = blobs.find((p) => iou(p.box, b.box) > 0.3);
    return prev ? { box: prev.box.map((v, k) => v * 0.5 + b.box[k] * 0.5), dist: b.dist } : b;
  });
  return blobs;
}

// ---------- tracker: smooths boxes, votes labels, needs N hits before an object is "real" ----------
let tracks = [], nextId = 1;
function iou(a, b) {
  const w = Math.max(0, Math.min(a[2], b[2]) - Math.max(a[0], b[0])), h = Math.max(0, Math.min(a[3], b[3]) - Math.max(a[1], b[1]));
  const i = w * h; return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9);
}
function updateTracks(dets, now) {
  const pairs = [];
  tracks.forEach((t, ti) => dets.forEach((d, di) => {
    const v = iou(t.box, d.box) + (t.votes[d.label] ? 0.15 : 0);
    if (v > 0.3) pairs.push([v, ti, di]);
  }));
  pairs.sort((a, b) => b[0] - a[0]);
  const usedT = new Set(), usedD = new Set();
  for (const [, ti, di] of pairs) {
    if (usedT.has(ti) || usedD.has(di)) continue;
    usedT.add(ti); usedD.add(di);
    const t = tracks[ti], d = dets[di];
    t.box = t.box.map((v, k) => v * 0.45 + d.box[k] * 0.55);
    t.votes[d.label] = (t.votes[d.label] || 0) + d.conf;
    t.hits++; t.misses = 0; t.seen = now;
    t.hist.push([now, t.box[3] - t.box[1]]); if (t.hist.length > 12) t.hist.shift();
  }
  tracks = tracks.filter((t, ti) => usedT.has(ti) || ++t.misses <= 3);
  dets.forEach((d, di) => {
    if (!usedD.has(di)) tracks.push({ id: nextId++, box: d.box, votes: { [d.label]: d.conf }, hits: 1, misses: 0, seen: now, hist: [[now, d.box[3] - d.box[1]]] });
  });
  const need = SENS[opts.sens].hits;
  return tracks.filter((t) => t.hits >= need && t.misses === 0).map(describe);
}
function describe(t) {
  const label = Object.entries(t.votes).sort((a, b) => b[1] - a[1])[0][0];
  const [x1, y1, x2, y2] = t.box, area = (x2 - x1) * (y2 - y1);
  const overlap = Math.max(0, Math.min(x2, 0.7) - Math.max(x1, 0.3)) / 0.4;
  const zone = overlap >= 0.4 ? 'center' : (x1 + x2) / 2 < 0.5 ? 'left' : 'right';
  const dist = depth ? nearIn(x1, x2, y1, y2, 0.25) : 99;
  t.dh = (t.dh || []).concat([[performance.now(), dist]]).slice(-10);
  const first = t.dh[0], approaching = t.dh.length >= 6 && dist < first[1] * 0.78 && dist < SENS[opts.sens].warn * 1.3;
  return { id: t.id, label, name: VI[label] || SHOW[label], obstacle: !!VI[label], box: t.box, zone, area, dist, approaching };
}

// ---------- announcer: what to say, and when ----------
const said = new Map(); // track id -> 'seen' | 'center' | 'approach'
let danger = null, dangerClearSince = 0;
const cap = (s) => s[0].toUpperCase() + s.slice(1);

function listText(objs) {
  const count = {};
  for (const o of objs) count[o.name] = (count[o.name] || 0) + 1;
  return Object.entries(count).map(([n, c]) => (c > 1 ? `${c} ${n}` : n)).join(', ');
}

const sideVi = (s) => (s === 'left' ? 'trái' : 'phải');
let warnAt = 0, dangerHits = 0;

function announce(all, c, now) {
  const s = SENS[opts.sens], objs = all.filter((o) => o.obstacle);
  // Name the thing in the path if YOLO recognises it, otherwise it is just "vật cản".
  const inPath = objs.filter((o) => o.zone === 'center' && o.dist < s.warn).sort((a, b) => a.dist - b.dist)[0];
  const what = inPath ? cap(inPath.name) : 'Vật cản';

  // Free side from depth, sticky: switch only when the other side is clearly more open.
  let free = c.left >= c.right ? 'left' : 'right';
  if (danger?.free && free !== danger.free && c[danger.free] * 1.2 > c[free]) free = danger.free;
  const sideOpen = c[free] > Math.max(s.stop * 1.15, c.center * 1.2);

  // 1) Danger: something very close straight ahead (2 frames in a row), repeat every 4s.
  dangerHits = c.center < s.stop ? dangerHits + 1 : 0;
  if (dangerHits >= 2) {
    dangerClearSince = 0;
    if (!danger || now - danger.at > 4000) {
      const text = sideOpen ? `Dừng lại. ${what} rất gần phía trước. Đi sang ${sideVi(free)}.`
        : `Dừng lại. ${what} chắn phía trước, hai bên cũng gần.`;
      speech.say(text, 'stop'); buzz([250, 80, 250]);
      danger = { free, at: now };
    } else danger.free = free;
    if (inPath) said.set(inPath.id, 'center');
    return;
  }
  if (danger) {
    if (c.center >= s.stop * 1.1) {
      if (!dangerClearSince) dangerClearSince = now;
      if (now - dangerClearSince > 1500 && speech.idleFor() > 300) { speech.say('Phía trước đã thông.', 'info'); danger = null; }
    } else dangerClearSince = 0;
    return;
  }
  if (speech.idleFor() < 700) return; // let the last sentence breathe; nothing piles up

  // 2) Getting close ahead: one heads-up, at most every 6s.
  if (c.center < s.warn && now - warnAt > 6000) {
    const hint = sideOpen && c[free] > s.warn ? ` Nên lệch sang ${sideVi(free)}.` : '';
    speech.say(`${what} phía trước, đang gần.${hint}`, 'warn'); buzz(100);
    warnAt = now; if (inPath) said.set(inPath.id, 'center');
    return;
  }

  // 3) Something closing in fast (e.g. a person walking towards you).
  const coming = objs.find((o) => o.zone === 'center' && o.approaching && said.get(o.id) !== 'approach');
  if (coming) { speech.say(`${cap(coming.name)} đang đến gần phía trước.`, 'warn'); buzz(120); said.set(coming.id, 'approach'); return; }

  // 4) New nearby objects, grouped into one sentence. Far-away ones are not worth talking about.
  const fresh = objs.filter((o) => o.dist < s.warn * 1.5 && (!said.has(o.id) || (o.zone === 'center' && said.get(o.id) === 'seen')));
  if (!fresh.length) return;
  const parts = [];
  for (const z of ['center', 'left', 'right']) {
    const inZone = fresh.filter((o) => o.zone === z);
    if (inZone.length) parts.push(`${cap(ZONE_VI[z])} có ${listText(inZone)}`);
  }
  speech.say(parts.join('. ') + '.', 'info');
  for (const o of fresh) said.set(o.id, o.zone === 'center' ? 'center' : 'seen');
}

// ---------- drawing ----------
function draw(objs, c, regions) {
  const W = innerWidth, H = innerHeight, dpr = devicePixelRatio || 1;
  if (overlay.width !== W * dpr) { overlay.width = W * dpr; overlay.height = H * dpr; }
  const g = overlay.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, W, H);
  if (!opts.boxes) return;
  const s = SENS[opts.sens];
  const tone = (d) => (d < s.stop ? '#ff4d4f' : d < s.warn ? '#ffb020' : '#3ddc97');
  // Path bar: left / ahead / right clearance from depth.
  if (c) {
    const top = menuBtn.getBoundingClientRect().top + 18; // aligned with the menu button, below the notch
    ['left', 'center', 'right'].forEach((k, i) => {
      g.fillStyle = tone(c[k]); g.globalAlpha = 0.9;
      g.beginPath(); g.roundRect(W / 2 - 50 + i * 34, top, 28, 8, 4); g.fill();
    });
    g.globalAlpha = 1;
  }
  const sc = Math.max(W / video.videoWidth, H / video.videoHeight);
  const ox = (W - video.videoWidth * sc) / 2, oy = (H - video.videoHeight * sc) / 2;
  const fx = (x) => ox + x * video.videoWidth * sc, fy = (y) => oy + y * video.videoHeight * sc;
  g.font = '600 14px system-ui,sans-serif'; g.lineWidth = 3;
  const pill = (x, y, text, bg, fg) => {
    const tw = g.measureText(text).width + 16, ly = Math.max(y - 26, 0);
    g.fillStyle = bg; g.beginPath(); g.roundRect(x, ly, tw, 22, 11); g.fill();
    g.fillStyle = fg; g.fillText(text, x + 8, ly + 15.5);
  };
  for (const r of regions) {
    const color = tone(r.dist);
    const x = fx(r.box[0]), y = fy(r.box[1]), w = fx(r.box[2]) - x, h = fy(r.box[3]) - y;
    g.strokeStyle = color; g.setLineDash([10, 7]); g.beginPath(); g.roundRect(x, y, w, h, 14); g.stroke(); g.setLineDash([]);
    g.fillStyle = color; g.globalAlpha = 0.12; g.fill(); g.globalAlpha = 1;
    pill(x, y, r.dist < s.stop ? 'Vật cản · rất gần' : 'Vật cản · gần', color, '#081410');
  }
  for (const o of objs) {
    if (!o.obstacle) {
      const x = fx(o.box[0]), y = fy(o.box[1]), w = fx(o.box[2]) - x, h = fy(o.box[3]) - y;
      g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineWidth = 2; g.beginPath(); g.roundRect(x, y, w, h, 12); g.stroke(); g.lineWidth = 3;
      pill(x, y, o.name, 'rgba(255,255,255,.9)', '#081410');
      continue;
    }
    const color = tone(o.dist);
    const x = fx(o.box[0]), y = fy(o.box[1]), w = fx(o.box[2]) - x, h = fy(o.box[3]) - y;
    g.strokeStyle = color; g.beginPath(); g.roundRect(x, y, w, h, 14); g.stroke();
    pill(x, y, o.name, color, '#081410');
  }
}

// ---------- main loop ----------
let frameNo = 0, objs = [];
let session = null, dsession = null, running = false, stream = null, wakeLock = null, avgMs = 0, threads = 1;
async function loop() {
  while (running) {
    const t0 = performance.now();
    if (video.readyState >= 2 && video.videoWidth) {
      preprocessDepth();
      const dres = await dsession.run({ pixel_values: new ort.Tensor('float32', dinput, [1, 3, DH, DW]) });
      depth = dres.depth.data;
      // Depth (safety) runs every frame; YOLO only names things, so every other frame is enough.
      let dets = null;
      if (frameNo++ % 2 === 0) {
        const t = preprocess();
        const res = await session.run({ images: new ort.Tensor('float32', input, [1, 3, SIZE, SIZE]) });
        dets = parse(res.output0.data, t);
      }
      if (!running) break;
      const now = performance.now();
      const c = analyzeDepth();
      if (dets) objs = updateTracks(dets, now);
      else objs = objs.map((o) => ({ ...o, dist: nearIn(o.box[0], o.box[2], o.box[1], o.box[3], 0.25) }));
      draw(objs, c, depthBlobs(objs)); announce(objs, c, now);
      avgMs = avgMs ? avgMs * 0.9 + (now - t0) * 0.1 : now - t0;
    }
    await new Promise((r) => setTimeout(r, Math.max(MIN_GAP_MS - (performance.now() - t0), 0)));
  }
}

async function start() {
  speech.cancel(); speech.say('Bắt đầu.', 'info'); // inside the tap: unlocks audio on iPhone
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: false,
      video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } } });
  } catch (e) { homeText.textContent = 'Hãy cho phép quyền camera'; speech.say('Không mở được camera. Hãy cho phép quyền camera.', 'stop'); return; }
  video.srcObject = stream; await video.play();
  try { wakeLock = await navigator.wakeLock?.request('screen'); } catch (e) { /* unsupported */ }
  tracks = []; objs = []; blobs = []; said.clear(); danger = null; clear = null; dangerHits = 0; warnAt = 0;
  running = true; home.hidden = true; menuBtn.hidden = false;
  loop();
}

function pause(silent = false) {
  if (!running) return;
  running = false; closeMenu();
  stream?.getTracks().forEach((t) => t.stop()); stream = null; video.srcObject = null;
  wakeLock?.release().catch(() => {}); wakeLock = null;
  overlay.getContext('2d').clearRect(0, 0, overlay.width, overlay.height);
  menuBtn.hidden = true; home.hidden = false; home.classList.add('over');
  homeText.textContent = 'Đã tạm dừng'; startBtn.setAttribute('aria-label', 'Tiếp tục');
  speech.cancel(); if (!silent) speech.say('Đã tạm dừng.', 'info');
  clearTimeout(captionTimer); caption.className = 'caption';
}

function openMenu() {
  perf.textContent = `Độ sâu + YOLO26s · ${Math.round(avgMs)} ms/khung · ${threads} luồng`;
  sheet.hidden = sheetBg.hidden = false;
}
function closeMenu() { sheet.hidden = sheetBg.hidden = true; }

startBtn.addEventListener('click', start);
home.addEventListener('click', (e) => { if (e.target === home && !startBtn.disabled) start(); });
menuBtn.addEventListener('click', openMenu);
sheetBg.addEventListener('click', closeMenu);
$('closeBtn').addEventListener('click', closeMenu);
$('pauseBtn').addEventListener('click', () => pause());

// Long-press anywhere on the camera = pause (blind-friendly, no button to find).
let pressTimer = 0;
const cam = $('cam');
cam.addEventListener('pointerdown', () => { if (running) pressTimer = setTimeout(() => { buzz(60); pause(); }, 700); });
for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) cam.addEventListener(ev, () => clearTimeout(pressTimer));
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(true); });
document.addEventListener('contextmenu', (e) => e.preventDefault());

// ---------- boot ----------
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/fast/sw.js', { scope: '/fast/' }).catch(() => {});
ort.env.wasm.wasmPaths = '/fast/';
threads = self.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 2) : 1;
ort.env.wasm.numThreads = threads;
try {
  const o = { executionProviders: ['wasm'], graphOptimizationLevel: 'all' };
  dsession = await ort.InferenceSession.create('/fast/depth.onnx', o);
  session = await ort.InferenceSession.create('/fast/model.onnx', o);
  startBtn.disabled = false; homeText.textContent = 'Chạm để bắt đầu';
} catch (e) {
  homeText.textContent = 'Lỗi tải mô hình'; console.error(e);
}
