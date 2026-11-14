// Landing page globe, "live view" style: a light dot-matrix world map, points that appear where people are using the platform (example data), a card on the latest one.
// Drag or touch to turn it. The land comes from the NASA texture (public/images/earth.jpg), used only as a land/sea mask. No library.
(function () {
  var RAD = Math.PI / 180, ZOOM = 1.02, BASE0 = { lon: 27, lat: 56 };
  // Countries shown (example data): Morocco, Tunisia, Spain, Algeria, Egypt, West/Central/East Africa and South Africa, plus Costa Rica and Panama (config/carriers.yml lists only MA, TN, CR, PA). [city, lat, lon, country code]
  var CITIES = [
    ["Casablanca", 33.57, -7.59, "MA"], ["Tanger", 35.76, -5.8, "MA"], ["Rabat", 34.02, -6.84, "MA"], ["Fès", 34.03, -5.0, "MA"], ["Marrakech", 31.63, -8.0, "MA"], ["Agadir", 30.43, -9.6, "MA"], ["Oujda", 34.68, -1.9, "MA"], ["Laâyoune", 27.15, -13.2, "MA"],
    ["Tunis", 36.81, 10.18, "TN"], ["Sfax", 34.74, 10.76, "TN"], ["Sousse", 35.83, 10.64, "TN"], ["Bizerte", 37.27, 9.87, "TN"],
    ["San José", 9.93, -84.08, "CR"], ["Alajuela", 10.02, -84.21, "CR"], ["Cartago", 9.86, -83.92, "CR"], ["Liberia", 10.63, -85.44, "CR"],
    ["Panama City", 8.98, -79.52, "PA"], ["Colón", 9.36, -79.9, "PA"], ["David", 8.43, -82.43, "PA"],
    ["Madrid", 40.42, -3.7, "ES"], ["Barcelone", 41.39, 2.17, "ES"], ["Séville", 37.39, -5.98, "ES"], ["Valence", 39.47, -0.38, "ES"],
    ["Alger", 36.75, 3.06, "DZ"], ["Oran", 35.7, -0.63, "DZ"], ["Constantine", 36.37, 6.61, "DZ"], ["Ghardaïa", 32.49, 3.67, "DZ"],
    ["Le Caire", 30.04, 31.24, "EG"], ["Alexandrie", 31.2, 29.92, "EG"], ["Louxor", 25.7, 32.64, "EG"],
    ["Dakar", 14.69, -17.45, "SN"], ["Thiès", 14.79, -16.93, "SN"], ["Nouakchott", 18.09, -15.98, "MR"], ["Bamako", 12.64, -8.0, "ML"],
    ["Abidjan", 5.36, -4.01, "CI"], ["Yamoussoukro", 6.82, -5.28, "CI"], ["Accra", 5.6, -0.19, "GH"], ["Kumasi", 6.69, -1.62, "GH"],
    ["Lagos", 6.52, 3.38, "NG"], ["Abuja", 9.08, 7.4, "NG"], ["Kano", 12.0, 8.52, "NG"], ["Douala", 4.05, 9.7, "CM"], ["Yaoundé", 3.85, 11.52, "CM"],
    ["Nairobi", -1.29, 36.82, "KE"], ["Mombasa", -4.04, 39.67, "KE"], ["Johannesburg", -26.2, 28.05, "ZA"]
  ];
  var WEIGHTS = { MA: 5, TN: 3, ES: 3, DZ: 3, EG: 3, SN: 2, MR: 1, ML: 1, CI: 2, GH: 2, NG: 3, CM: 2, KE: 2, ZA: 1, CR: 1, PA: 1 };
  var GREEN = "0,128,96", LIGHT = "149,191,71";

  function vec(lat, lon) { var p = lat * RAD, l = lon * RAD; return [Math.cos(p) * Math.cos(l), Math.cos(p) * Math.sin(l), Math.sin(p)]; }
  function slerp(a, b, t) {
    var d = Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1] + a[2] * b[2])), w = Math.acos(d), s = Math.sin(w) || 1;
    var k1 = Math.sin((1 - t) * w) / s, k2 = Math.sin(t * w) / s;
    return [a[0] * k1 + b[0] * k2, a[1] * k1 + b[1] * k2, a[2] * k1 + b[2] * k2];
  }
  function round(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

  function init(box) {
    var BASE = { lon: BASE0.lon, lat: BASE0.lat };
    var canvas = box.querySelector("canvas"), ctx = canvas.getContext("2d");
    var counter = box.querySelector("[data-live-count]"), pauseBtn = box.querySelector("[data-live-pause]");
    var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var vp = null, mask = null, MW = 2048, MH = 1024;
    var panLon = 0, panLat = 0, dragging = false, last = null, visible = true, paused = reduce, size = 0, dpr = 1, raf = 0, clock = 0, prev = 0;
    var pts = CITIES.map(function (c) { return vec(c[1], c[2]); });
    var rtl = box.closest(".platform-landing") && box.closest(".platform-landing").getAttribute("dir") === "rtl" && window.matchMedia("(min-width: 1024px)").matches && box.closest(".platform-map-desktop");
    if (rtl) BASE = { lon: -24, lat: 56 };
    var lon0 = BASE.lon, lat0 = BASE.lat;
    function view(v) {
      var l = lon0 * RAD, p = lat0 * RAD, cl = Math.cos(l), sl = Math.sin(l);
      var x1 = v[0] * cl + v[1] * sl, y1 = -v[0] * sl + v[1] * cl, z1 = v[2];
      return [y1, z1 * Math.cos(p) - x1 * Math.sin(p), x1 * Math.cos(p) + z1 * Math.sin(p)];
    }
    function resize() {
      size = Math.max(200, Math.floor(box.getBoundingClientRect().width));
      dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      canvas.width = size * dpr; canvas.height = size * dpr; canvas.style.height = size + "px";
    }
    function isLand(lat, lon) {
      var u = (lon / 180 + 1) * 0.5, v = 0.5 - lat / 180;
      return mask[((v * MH) | 0) * MW + ((u * MW) | 0)] === 1;
    }
    function stamp() { var d = new Date(); return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2); }

    var pool = []; CITIES.forEach(function (c, i) { for (var k = 0; k < WEIGHTS[c[3]]; k++) pool.push(i); });
    function pick() { return pool[Math.floor(Math.random() * pool.length)]; }
    function onScreen(i) {
      var v = view(pts[i]); if (v[2] < 0.15 || !vp) return false;
      var x = vp.left + size / 2 + v[0] * size * 0.48 * ZOOM, y = vp.top + size / 2 - v[1] * size * 0.48 * ZOOM;
      return x > 20 && x < window.innerWidth - 20 && y > 90 && y < window.innerHeight - 20;
    }
    var cardEl = document.createElement("div"), cardShown = -1;
    cardEl.className = "platform-live-card"; cardEl.setAttribute("aria-hidden", "true");
    cardEl.innerHTML = '<span class="platform-live-card-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/></svg></span><span class="platform-live-card-text"><strong></strong><small></small></span>';
    box.appendChild(cardEl);
    var cardCity = 3, cardUntil = 0, nextSpawn = 0, spots = [], online = 38 + Math.floor(Math.random() * 9), nextDrift = 0;
    function draw(now) {
      raf = 0;
      if (!paused) clock += prev ? Math.min(0.1, (now - prev) / 1000) : 0;
      prev = now;
      var tt = clock, sway = 0;
      lon0 = BASE.lon + panLon;
      lat0 = Math.max(-60, Math.min(72, BASE.lat + panLat + sway * 0.8 * Math.sin(tt / 8)));
      var cx = size / 2, cy = size / 2, ra = size * 0.48, S = ra * ZOOM;
      var rect = canvas.getBoundingClientRect(); vp = rect;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size, size);

      // soft sphere
      var g = ctx.createRadialGradient(cx - ra * 0.3, cy - ra * 0.35, ra * 0.1, cx, cy, ra);
      g.addColorStop(0, "rgba(250,251,252,.9)"); g.addColorStop(0.7, "rgba(246,247,250,.6)"); g.addColorStop(1, "rgba(238,240,244,0)");
      ctx.beginPath(); ctx.arc(cx, cy, ra, 0, 7); ctx.fillStyle = g; ctx.fill();

      // dot-matrix land
      if (mask) {
        var gap = Math.max(3.6, Math.min(4.8, size / 105)), l = lon0 * RAD, p = lat0 * RAD, cl = Math.cos(l), sl = Math.sin(l), cp = Math.cos(p), sp = Math.sin(p), row = 0;
        var rh = gap * 0.866, ymin = Math.max(-ra, -rect.top - cy - gap), ymax = Math.min(ra, window.innerHeight - rect.top - cy + gap), xmin = Math.max(-ra, -rect.left - cx - gap), xmax = Math.min(ra, window.innerWidth - rect.left - cx + gap);
        for (var yi = Math.ceil((ymin + ra) / rh); -ra + yi * rh <= ymax; yi++) {
          var sy0 = -ra + yi * rh, off = yi % 2 ? gap / 2 : 0;
          for (var xi = Math.ceil((xmin + ra - off) / gap); -ra + xi * gap + off <= xmax; xi++) {
            var sx0 = -ra + xi * gap + off;
            var r2 = (sx0 * sx0 + sy0 * sy0) / (ra * ra);
            if (r2 >= 0.97) continue;
            var nx = sx0 / S, ny = -sy0 / S, nz = Math.sqrt(1 - nx * nx - ny * ny);
            var x1 = nz * cp - ny * sp, z = ny * cp + nz * sp, wx = x1 * cl - nx * sl, wy = x1 * sl + nx * cl;
            if (!isLand(Math.asin(z) / RAD, Math.atan2(wy, wx) / RAD)) continue;
            var fade = Math.min(1, (1 - r2) / 0.22);
            ctx.fillStyle = "rgba(96,102,112," + (0.6 * fade).toFixed(2) + ")";
            ctx.beginPath(); ctx.arc(cx + sx0, cy + sy0, gap * 0.17, 0, 7); ctx.fill();
          }
        }
      }

      ctx.save();
      ctx.beginPath(); ctx.arc(cx, cy, ra, 0, 7); ctx.clip();
      var X = function (q) { return cx + q[0] * S; }, Y = function (q) { return cy - q[1] * S; };
      var shown = function (q) { return q[2] > 0; };
      var moving = 0;

      // live activity: a point appears in a city, pulses, then fades (example data)
      if (!paused && now >= nextSpawn) {
        var ci = pick(), tries = 0;
        while (tries++ < 30 && !onScreen(ci)) ci = pick();
        spots.push({ city: ci, born: now });
        if (spots.length > 14) spots.shift();
        nextSpawn = now + 450 + Math.random() * 900;
        if (now > cardUntil) { cardCity = ci; cardUntil = now + 2600; }
      }
      spots = spots.filter(function (sp) { return now - sp.born < 5200; });
      spots.forEach(function (sp) {
        var v = view(pts[sp.city]), age = (now - sp.born) / 1000, fade = age < 4.2 ? 1 : Math.max(0, 1 - (age - 4.2));
        if (!shown(v)) return;
        var x = X(v), y = Y(v);
        var rp = (age % 1.6) / 1.6;
        ctx.beginPath(); ctx.arc(x, y, 2 + rp * 7, 0, 7); ctx.strokeStyle = "rgba(" + LIGHT + "," + (0.8 * (1 - rp) * fade).toFixed(2) + ")"; ctx.lineWidth = 1.5; ctx.stroke();
        ctx.globalAlpha = fade; ctx.beginPath(); ctx.arc(x, y, 1.8 * Math.min(1, age * 4), 0, 7); ctx.fillStyle = "rgb(" + LIGHT + ")"; ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = "#fff"; ctx.stroke(); ctx.globalAlpha = 1;
      });
      if (!paused && now >= nextDrift) { online = Math.max(24, Math.min(70, online + (Math.random() < 0.5 ? -1 : 1))); nextDrift = now + 1800 + Math.random() * 2200; }
      var moving = online + spots.length;

      // glass card on the latest order (a real element, so the page behind can be blurred)
      var cv = view(pts[cardCity]);
      var cardAge = spots.some(function (sp) { return sp.city === cardCity; });
      if (shown(cv) && now < cardUntil && cardAge) {
        if (cardShown !== cardCity) {
          cardShown = cardCity;
          cardEl.querySelector("strong").textContent = CITIES[cardCity][0] + ", " + CITIES[cardCity][3];
          cardEl.querySelector("small").textContent = (box.dataset.event || "New order") + " · " + stamp();
        }
        var px = X(cv), py = Y(cv), w = cardEl.offsetWidth || 190, h = cardEl.offsetHeight || 46;
        var left = px + 14 + w > size - 6 || canvas.getBoundingClientRect().left + px + 14 + w > window.innerWidth - 10;
        var bx = left ? px - 14 - w : px + 14;
        if (bx + canvas.getBoundingClientRect().left < 10) bx = px + 14;
        cardEl.style.transform = "translate(" + bx.toFixed(1) + "px," + (py - h / 2).toFixed(1) + "px)";
        cardEl.style.opacity = "1";
      } else { cardEl.style.opacity = "0"; cardShown = -1; }
      ctx.restore();
      if (counter) { var cs = String(moving); if (counter.textContent !== cs) counter.textContent = cs; }
    }

    function frame(now) { draw(now); if (visible && !paused) raf = requestAnimationFrame(frame); }
    function kick() { if (!raf) raf = requestAnimationFrame(paused ? function (n) { prev = 0; draw(n); } : frame); }

    canvas.style.cursor = "grab"; canvas.style.touchAction = "pan-y";
    canvas.addEventListener("pointerdown", function (e) { dragging = true; last = [e.clientX, e.clientY]; canvas.setPointerCapture(e.pointerId); canvas.style.cursor = "grabbing"; });
    canvas.addEventListener("pointermove", function (e) {
      if (!dragging) return;
      var dx = e.clientX - last[0], dy = e.clientY - last[1]; last = [e.clientX, e.clientY];
      var k = 90 / (size * 0.48 * ZOOM);
      panLon -= dx * k;
      if (e.pointerType === "mouse") panLat = Math.max(-50, Math.min(50, panLat + dy * k));
      if (paused) kick();
    });
    var stop = function () { dragging = false; canvas.style.cursor = "grab"; };
    canvas.addEventListener("pointerup", stop); canvas.addEventListener("pointercancel", stop);
    if (pauseBtn) {
      pauseBtn.setAttribute("aria-pressed", paused ? "true" : "false");
      pauseBtn.addEventListener("click", function () { paused = !paused; pauseBtn.setAttribute("aria-pressed", paused ? "true" : "false"); prev = 0; kick(); });
    }
    if ("IntersectionObserver" in window) new IntersectionObserver(function (en) { visible = en[0].isIntersecting; if (visible) { prev = 0; kick(); } }).observe(box);
    window.addEventListener("resize", function () { resize(); kick(); });
    resize();
    var im = new Image();
    im.onload = function () {
      var tc = document.createElement("canvas"); tc.width = MW; tc.height = MH;
      var tx = tc.getContext("2d", { willReadFrequently: true }); tx.drawImage(im, 0, 0, MW, MH);
      var d = tx.getImageData(0, 0, MW, MH).data; mask = new Uint8Array(MW * MH);
      for (var i = 0; i < MW * MH; i++) { var r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2]; mask[i] = (b > r * 1.25 && b > g * 1.05 && r + g + b < 420) ? 0 : 1; }
      kick();
    };
    im.src = box.dataset.earth;
    kick();
  }

  function boot() { document.querySelectorAll("[data-globe]").forEach(function (b) { if (!b.dataset.ready) { b.dataset.ready = "1"; init(b); } }); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})();
