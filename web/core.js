/* Ядро: данные, фильтры, лента. Чистый ES5 + Promise (без async/await) — для старых webOS. */
var KT = (function () {
  var CFG = (typeof KT_CONFIG !== 'undefined') ? KT_CONFIG : {};
  var API = 'https://www.googleapis.com/youtube/v3/';
  var STORE = 'kt_state_v1';
  var DAY6 = 6 * 3600 * 1000;

  var S = { channels: [], videos: [], blocked: [], extra: [], pin: '', autoNext: true, last: 0, seedsSeen: [], catStop: [], catBlocked: [], watched: [], family: '', famChosen: false,
    limit: 0, bed: '', name: '', favs: [], extraUntil: 0, catLimit: null, catBed: null, catName: '',
    usage: { day: '', sec: 0, by: {} } };
  var st = { loading: false, error: null };
  var listeners = [];

  function lsGet() { try { return (typeof localStorage !== 'undefined') ? localStorage : null; } catch (e) { return null; } }
  function save() { var l = lsGet(); if (l) { try { l.setItem(STORE, JSON.stringify(S)); } catch (e) {} } }
  function load() {
    var l = lsGet(); if (!l) return;
    try { var raw = l.getItem(STORE); if (raw) { var o = JSON.parse(raw); for (var k in o) { S[k] = o[k]; } } } catch (e) {}
  }
  function catOfSeed(handle) {
    var seeds = CFG.seeds || [], h = String(handle || '').toLowerCase();
    for (var i = 0; i < seeds.length; i++) { if (String(seeds[i].handle).toLowerCase() === h) { return seeds[i].cat; } }
    return null;
  }
  function addSeeds() {
    var seen = S.seedsSeen || (S.seedsSeen = []);
    if (!seen.length) { S.channels.forEach(function (c) { seen.push(String(c.handle).toLowerCase()); }); }
    (CFG.seeds || []).forEach(function (s) {
      var k = String(s.handle).toLowerCase();
      if (seen.indexOf(k) !== -1) { return; }
      seen.push(k);
      S.channels.push({ id: '', title: s.name, handle: s.handle, lang: s.lang, cat: s.cat || 'cartoons', uploads: '', thumb: '', enabled: true, custom: false });
    });
    S.channels.forEach(function (c) { if (!c.cat) { c.cat = catOfSeed(c.handle) || 'cartoons'; } });
  }
  // SHA-256 (ES5): каталог семьи лежит в папке с хэшем кода, чтобы сам код нигде не был виден в репозитории.
  function sha256hex(msg) {
    var K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    var H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    var b = [], i, j;
    for (i = 0; i < msg.length; i++) { b.push(msg.charCodeAt(i) & 0xff); }
    var bits = b.length * 8;
    b.push(0x80);
    while (b.length % 64 !== 56) { b.push(0); }
    b.push(0, 0, 0, 0, (bits >>> 24) & 255, (bits >>> 16) & 255, (bits >>> 8) & 255, bits & 255);
    function rr(x, n) { return (x >>> n) | (x << (32 - n)); }
    for (i = 0; i < b.length; i += 64) {
      var w = [];
      for (j = 0; j < 16; j++) { w[j] = (b[i + j * 4] << 24) | (b[i + j * 4 + 1] << 16) | (b[i + j * 4 + 2] << 8) | b[i + j * 4 + 3]; }
      for (j = 16; j < 64; j++) {
        var s0 = rr(w[j - 15], 7) ^ rr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
        var s1 = rr(w[j - 2], 17) ^ rr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0;
      }
      var a = H[0], bb = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], hh = H[7];
      for (j = 0; j < 64; j++) {
        var S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25);
        var ch = (e & f) ^ (~e & g);
        var t1 = (hh + S1 + ch + K[j] + w[j]) | 0;
        var S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22);
        var mj = (a & bb) ^ (a & c) ^ (bb & c);
        var t2 = (S0 + mj) | 0;
        hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = bb; bb = a; a = (t1 + t2) | 0;
      }
      H[0] = (H[0] + a) | 0; H[1] = (H[1] + bb) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
      H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + hh) | 0;
    }
    var out = '';
    for (i = 0; i < 8; i++) { out += ('00000000' + (H[i] >>> 0).toString(16)).slice(-8); }
    return out;
  }
  function normCode(code) { return String(code || '').toLowerCase().replace(/[^a-z0-9]/g, ''); }
  function familyId(code) { return sha256hex('kt1:' + normCode(code)).slice(0, 16); }
  function catalogUrl(code) {
    var u = CFG.catalogUrl;
    if (!u || u.indexOf('__') !== -1) { return ''; }
    code = (code === undefined) ? S.family : code;
    if (code && code !== 'main') { u = u.replace(/data\/catalog\.json$/, 'data/families/' + familyId(code) + '/catalog.json'); }
    return u;
  }
  function validCode(code) { return /^[a-z0-9]{4,12}$/.test(code || ''); }
  // Проверяем, что семья с таким кодом существует (бот создал для неё каталог).
  function checkFamily(code) {
    code = normCode(code);
    if (code !== 'main' && !validCode(code)) { return Promise.reject(new Error('Код — это 10 букв и цифр из Telegram')); }
    var u = catalogUrl(code);
    if (!u) { return Promise.reject(new Error('Каталог не настроен')); }
    return net.http(u + '?t=' + Date.now()).then(function () { return code; }, function () { throw new Error('Такого кода нет. Проверьте код или напишите боту /newcode'); });
  }
  // Переключение на каталог другой семьи: прежние каналы из каталога убираем, стартовые остаются.
  function setFamily(code) {
    code = normCode(code);
    S.family = (code === 'main') ? '' : code;
    S.famChosen = true;
    var seedHandles = {};
    (CFG.seeds || []).forEach(function (s) { seedHandles[String(s.handle).toLowerCase()] = true; });
    S.channels = S.channels.filter(function (c) { return c.custom || (!c.fromCat && seedHandles[String(c.handle).toLowerCase()]); });
    S.channels.forEach(function (c) { if (!c.custom) { c.enabled = true; } });
    S.catStop = []; S.catBlocked = []; S.videos = []; S.last = 0;
    save(); emit();
    return syncCatalog().then(function () { return refresh(); });
  }
  // Каталог, который наполняет Telegram-бот (одобренные/заблокированные каналы).
  function syncCatalog() {
    var u = catalogUrl();
    if (!u) { return Promise.resolve(false); }
    return net.http(u + '?t=' + Math.floor(Date.now() / 300000)).then(function (j) {
      var changed = false, list = (j && j.channels) || [];
      list.forEach(function (e) {
        if (!e || !e.id) { return; }
        var ex = null;
        S.channels.forEach(function (c) {
          if (c.id === e.id || (!c.id && e.handle && String(c.handle).toLowerCase() === String(e.handle).toLowerCase())) { ex = c; }
        });
        if (e.status === 'blocked') {
          if (ex) {
            S.channels = S.channels.filter(function (c) { return c !== ex; });
            S.videos = S.videos.filter(function (v) { return v.channelId !== e.id; });
            changed = true;
          }
          return;
        }
        if (e.status !== 'approved') { return; }
        if (ex) {
          if (!ex.id) { ex.id = e.id; ex.uploads = 'UU' + e.id.substring(2); changed = true; }
          if (e.cat && ex.cat !== e.cat) { ex.cat = e.cat; changed = true; }
          if (typeof e.enabled === 'boolean' && ex.enabled !== e.enabled) { ex.enabled = e.enabled; changed = true; }
          return;
        }
        S.channels.push({ id: e.id, title: e.title || e.handle || e.id, handle: e.handle || '', lang: e.lang || 'ru', cat: e.cat || 'cartoons', uploads: 'UU' + e.id.substring(2), thumb: e.thumb || '', enabled: e.enabled !== false, custom: false, fromCat: true });
        changed = true;
      });
      var sw = (j && j.stopWords) || [], bv = (j && j.blockedVideos) || [];
      if (JSON.stringify(sw) !== JSON.stringify(S.catStop || [])) { S.catStop = sw; changed = true; }
      if (JSON.stringify(bv) !== JSON.stringify(S.catBlocked || [])) { S.catBlocked = bv; changed = true; }
      var lim = (j && typeof j.limitMinutes === 'number') ? j.limitMinutes : null;
      var bed = (j && typeof j.bedtime === 'string') ? j.bedtime : '';
      var nm = (j && typeof j.childName === 'string') ? j.childName : '';
      if (lim !== S.catLimit) { S.catLimit = lim; changed = true; }
      if (bed !== (S.catBed || '')) { S.catBed = bed; changed = true; }
      if (nm !== (S.catName || '')) { S.catName = nm; changed = true; }
      if (changed) { save(); emit(); }
      return changed;
    })['catch'](function () { return false; });
  }
  /* ---------- время просмотра, сон, любимое ---------- */
  function dayKey(d) { d = d || new Date(); return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate(); }
  function usageToday() {
    var u = S.usage || (S.usage = { day: '', sec: 0, by: {} });
    if (u.day !== dayKey()) { u.day = dayKey(); u.sec = 0; u.by = {}; }
    return u;
  }
  var tickN = 0;
  function addWatch(sec, chId) {
    var u = usageToday();
    u.sec += sec;
    if (chId) { u.by[chId] = (u.by[chId] || 0) + sec; }
    tickN++;
    if (tickN % 10 === 0) { save(); }
  }
  function effLimit() { return (S.catLimit !== null && S.catLimit !== undefined) ? S.catLimit : (S.limit || 0); }
  function effBed() { return S.catBed ? S.catBed : (S.bed || ''); }
  function effName() { return S.catName || S.name || ''; }
  function parseHM(s) { var m = /^(\d{1,2}):(\d{2})$/.exec(s || ''); return m ? (+m[1]) * 60 + (+m[2]) : -1; }
  var WAKE = 7 * 60;
  function lockState(now) {
    var d = now || new Date();
    if ((S.extraUntil || 0) > d.getTime()) { return { locked: false }; }
    var lim = effLimit();
    if (lim > 0 && usageToday().sec >= lim * 60) { return { locked: true, reason: 'limit' }; }
    var b = parseHM(effBed());
    if (b > WAKE) {
      var m = d.getHours() * 60 + d.getMinutes();
      if (m >= b || m < WAKE) { return { locked: true, reason: 'bed' }; }
    }
    return { locked: false };
  }
  function extend(min) { S.extraUntil = Date.now() + min * 60000; save(); emit(); }
  function setLimit(n) { S.limit = n; S.extraUntil = 0; save(); emit(); }
  function setBed(s) { S.bed = s; S.extraUntil = 0; save(); emit(); }
  function setName(s) { S.name = s; save(); emit(); }
  function isFav(id) { return (S.favs || []).indexOf(id) !== -1; }
  function toggleFav(id) {
    var f = S.favs || (S.favs = []), i = f.indexOf(id);
    if (i === -1) { f.unshift(id); } else { f.splice(i, 1); }
    save(); emit();
    return i === -1;
  }

  function emit() { for (var i = 0; i < listeners.length; i++) { try { listeners[i](); } catch (e) {} } }
  function onChange(fn) { listeners.push(fn); }

  function qs(o) { var a = []; for (var k in o) { a.push(encodeURIComponent(k) + '=' + encodeURIComponent(o[k])); } return a.join('&'); }

  function defaultHttp(url) {
    return new Promise(function (res, rej) {
      var x = new XMLHttpRequest();
      x.open('GET', url);
      x.timeout = 25000;
      x.onload = function () {
        if (x.status === 200) {
          try { res(JSON.parse(x.responseText)); } catch (e) { rej(e); }
        } else {
          var m = 'HTTP ' + x.status;
          try { var j = JSON.parse(x.responseText); if (j.error && j.error.message) { m += ': ' + j.error.message; } } catch (e) {}
          rej(new Error(m));
        }
      };
      x.onerror = function () { rej(new Error('Нет сети')); };
      x.ontimeout = function () { rej(new Error('Таймаут')); };
      x.send();
    });
  }
  var net = { http: defaultHttp };
  function get(path, q) { q.key = CFG.apiKey; return net.http(API + path + '?' + qs(q)); }

  function words() { return (CFG.stopWords || []).concat(S.extra || [], S.catStop || []); }
  function isBlockedText(text, ws) {
    var t = String(text).toLowerCase();
    for (var i = 0; i < ws.length; i++) {
      var w = String(ws[i]).trim().toLowerCase();
      if (w && t.indexOf(w) !== -1) { return true; }
    }
    return false;
  }
  function parseDuration(iso) {
    var m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso || '');
    if (!m) { return 0; }
    return (parseInt(m[1] || '0', 10) * 3600) + (parseInt(m[2] || '0', 10) * 60) + parseInt(m[3] || '0', 10);
  }
  function fmtDur(s) {
    function two(n) { return (n < 10 ? '0' : '') + n; }
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return h > 0 ? (h + ':' + two(m) + ':' + two(sec)) : (m + ':' + two(sec));
  }
  function thumbOf(sn) {
    var t = (sn && sn.thumbnails) || {};
    var x = t.medium || t['default'];
    return (x && x.url) || '';
  }

  function resolveHandle(handle, lang, custom) {
    var hh = handle.charAt(0) === '@' ? handle : '@' + handle;
    return get('channels', { part: 'snippet,contentDetails', forHandle: hh }).then(function (j) {
      var items = j.items || [];
      if (!items.length) { return null; }
      var it = items[0];
      var rp = (it.contentDetails && it.contentDetails.relatedPlaylists) || {};
      return {
        id: it.id,
        title: (it.snippet && it.snippet.title) || handle,
        handle: handle.replace('@', ''),
        lang: lang || 'ru',
        uploads: rp.uploads || ('UU' + it.id.substring(2)),
        thumb: thumbOf(it.snippet),
        enabled: true,
        custom: !!custom
      };
    });
  }

  function channelThumbs(ids) {
    if (!ids.length) { return Promise.resolve({}); }
    return get('channels', { part: 'snippet', id: ids.join(','), maxResults: '50' }).then(function (j) {
      var out = {};
      (j.items || []).forEach(function (it) { var u = thumbOf(it.snippet); if (u) { out[it.id] = u; } });
      return out;
    });
  }

  // До 3 страниц загрузок канала (до 150 видео), чтобы лента была разнообразной.
  function fetchUploads(ch, token, acc, page) {
    var q = { part: 'snippet,contentDetails', playlistId: ch.uploads || ('UU' + ch.id.substring(2)), maxResults: '50' };
    if (token) { q.pageToken = token; }
    return get('playlistItems', q).then(function (pl) {
      acc = acc.concat(pl.items || []);
      if (pl.nextPageToken && page < 3) { return fetchUploads(ch, pl.nextPageToken, acc, page + 1); }
      return acc;
    });
  }

  function fetchVideos(ch, ws) {
    return fetchUploads(ch, '', [], 1).then(function (items) {
      var pl = { items: items };
      var ids = [], titles = {}, dates = {};
      (pl.items || []).forEach(function (it) {
        var cd = it.contentDetails || {}, sn = it.snippet || {};
        var id = cd.videoId;
        if (!id) { return; }
        var title = sn.title || '';
        if (title === 'Private video' || title === 'Deleted video') { return; }
        if (isBlockedText(title, ws)) { return; }
        ids.push(id);
        titles[id] = title;
        var d = Date.parse(cd.videoPublishedAt || sn.publishedAt || '');
        dates[id] = isNaN(d) ? 0 : d;
      });
      if (!ids.length) { return []; }
      var chunks = [];
      for (var c0 = 0; c0 < ids.length; c0 += 50) { chunks.push(ids.slice(c0, c0 + 50)); }
      return Promise.all(chunks.map(function (part) {
        return get('videos', { part: 'contentDetails,status', id: part.join(','), maxResults: '50' });
      })).then(function (res) {
        var out = [];
        res.forEach(function (vj) {
          (vj.items || []).forEach(function (it) {
            var s = it.status || {}, cd = it.contentDetails || {};
            if (s.embeddable !== true || s.privacyStatus !== 'public') { return; }
            var secs = parseDuration(cd.duration);
            if (secs < 30) { return; }
            out.push({ id: it.id, title: titles[it.id] || '', channelId: ch.id, channelTitle: ch.title, lang: ch.lang, seconds: secs, published: dates[it.id] || 0 });
          });
        });
        return out;
      });
    });
  }

  // Если среди последних загрузок почти нет проигрываемых видео (владелец запретил встраивание
  // новинок), берём разрешённые для встраивания через поиск по каналу (100 ед. квоты).
  function fetchEmbeddable(ch, ws) {
    return get('search', { part: 'snippet', channelId: ch.id, type: 'video', videoEmbeddable: 'true', safeSearch: 'strict', maxResults: '50', order: 'viewCount' }).then(function (sj) {
      var ids = [], titles = {}, dates = {};
      (sj.items || []).forEach(function (it) {
        var id = it.id && it.id.videoId, sn = it.snippet || {}, title = sn.title || '';
        if (!id || isBlockedText(title, ws)) { return; }
        ids.push(id); titles[id] = title;
        var d = Date.parse(sn.publishedAt || '');
        dates[id] = isNaN(d) ? 0 : d;
      });
      if (!ids.length) { return []; }
      return get('videos', { part: 'contentDetails,status', id: ids.join(','), maxResults: '50' }).then(function (vj) {
        var out = [];
        (vj.items || []).forEach(function (it) {
          var s = it.status || {}, cd = it.contentDetails || {};
          if (s.embeddable !== true || s.privacyStatus !== 'public') { return; }
          var secs = parseDuration(cd.duration);
          if (secs < 30) { return; }
          out.push({ id: it.id, title: titles[it.id] || '', channelId: ch.id, channelTitle: ch.title, lang: ch.lang, seconds: secs, published: dates[it.id] || 0 });
        });
        return out;
      });
    });
  }

  function fetchChannel(ch, ws) {
    return fetchVideos(ch, ws).then(function (list) {
      if (list.length >= 10) { return list; }
      return fetchEmbeddable(ch, ws).then(function (extra) {
        var have = {};
        list.forEach(function (v) { have[v.id] = true; });
        return list.concat(extra.filter(function (v) { return !have[v.id]; }));
      })['catch'](function () { return list; });
    });
  }

  function refresh() {
    if (st.loading) { return Promise.resolve(); }
    if (!CFG.apiKey || CFG.apiKey === '__YT_KEY__') {
      st.error = 'В сайт не подставлен ключ YouTube API (секрет YT_WEB_KEY).';
      emit();
      return Promise.resolve();
    }
    st.loading = true; st.error = null; emit();
    var firstErr = null;
    function note(e) { if (!firstErr) { firstErr = (e && e.message) ? e.message : String(e); } }
    addSeeds();
    return syncCatalog().then(function () {
      var resolving = S.channels.filter(function (c) { return !c.id; }).map(function (c) {
        return resolveHandle(c.handle, c.lang, c.custom).then(function (r) {
          if (r) { c.id = r.id; c.title = r.title; c.uploads = r.uploads; c.thumb = r.thumb; }
        })['catch'](note);
      });
      return Promise.all(resolving);
    }).then(function () {
      var noThumb = S.channels.filter(function (c) { return c.id && !c.thumb; });
      return channelThumbs(noThumb.map(function (c) { return c.id; })).then(function (m) {
        noThumb.forEach(function (c) { c.thumb = m[c.id] || ''; });
      })['catch'](note);
    }).then(function () {
      var ws = words();
      var jobs = S.channels.filter(function (c) { return c.id && c.enabled; }).map(function (c) {
        return fetchChannel(c, ws)['catch'](function (e) { note(e); return []; });
      });
      return Promise.all(jobs);
    }).then(function (lists) {
      lists.forEach(function (l) { l.sort(function (a, b) { return b.published - a.published; }); });
      var merged = [], i = 0, added = true;
      while (added) {
        added = false;
        for (var k = 0; k < lists.length; k++) {
          if (i < lists[k].length) { merged.push(lists[k][i]); added = true; }
        }
        i++;
      }
      if (merged.length) { S.videos = merged; S.ver = 2; S.last = Date.now(); }
      else if (firstErr) { st.error = 'Не удалось загрузить: ' + firstErr; }
      save();
    })['catch'](function (e) {
      st.error = 'Ошибка: ' + (e && e.message ? e.message : e);
    }).then(function () {
      st.loading = false; emit();
    });
  }

  // Порядок ленты: новый при каждом запуске (стабилен, пока приложение открыто),
  // непросмотренные идут раньше просмотренных, каналы чередуются.
  var SEED = String(Math.random());
  function hash(s) {
    var h = 2166136261;
    for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = (h * 16777619) >>> 0; }
    return h;
  }
  function markWatched(id) {
    var w = S.watched || (S.watched = []);
    var i = w.indexOf(id);
    if (i !== -1) { w.splice(i, 1); }
    w.push(id);
    if (w.length > 600) { w.splice(0, w.length - 600); }
    save();
  }
  function mix(list) {
    var seen = {}, by = {}, order = [];
    (S.watched || []).forEach(function (id) { seen[id] = true; });
    list.forEach(function (v) {
      if (!by[v.channelId]) { by[v.channelId] = []; order.push(v.channelId); }
      by[v.channelId].push(v);
    });
    order.sort(function (a, b) { return hash(a + SEED) - hash(b + SEED); });
    order.forEach(function (cid) {
      by[cid].sort(function (a, b) {
        var wa = seen[a.id] ? 1 : 0, wb = seen[b.id] ? 1 : 0;
        if (wa !== wb) { return wa - wb; }
        return hash(a.id + SEED) - hash(b.id + SEED);
      });
    });
    var out = [], i = 0, added = true;
    while (added) {
      added = false;
      for (var k = 0; k < order.length; k++) {
        if (i < by[order[k]].length) { out.push(by[order[k]][i]); added = true; }
      }
      i++;
    }
    return out;
  }

  function visible() {
    var on = {};
    S.channels.forEach(function (c) { if (c.enabled && c.id) { on[c.id] = true; } });
    var ws = words();
    var list = mix(S.videos.filter(function (v) {
      return on[v.channelId] && S.blocked.indexOf(v.id) === -1 && (S.catBlocked || []).indexOf(v.id) === -1 && !isBlockedText(v.title, ws);
    }));
    var favs = S.favs || [];
    if (!favs.length) { return list; }
    var fv = [], rest = [];
    list.forEach(function (v) { (favs.indexOf(v.id) !== -1 ? fv : rest).push(v); });
    return fv.concat(rest);
  }

  function init() {
    load();
    addSeeds();
    emit();
    return syncCatalog().then(function (changed) {
      var stale = !S.last || S.ver !== 2 || (Date.now() - S.last) > DAY6;
      if (changed || !S.videos.length || stale) { return refresh(); }
    });
  }

  function setEnabled(c, on) { c.enabled = on; save(); emit(); }
  function removeChannel(c) {
    S.channels = S.channels.filter(function (x) { return x !== c; });
    S.videos = S.videos.filter(function (v) { return v.channelId !== c.id; });
    save(); emit();
  }
  function addChannelByHandle(handle, lang, cat) {
    return resolveHandle(handle, lang, true).then(function (ch) {
      if (!ch) { return null; }
      ch.cat = cat || 'cartoons';
      var dup = S.channels.some(function (x) { return x.id && x.id === ch.id; });
      if (!dup) { S.channels.push(ch); save(); emit(); }
      return ch;
    });
  }
  function blockVideo(id) { if (S.blocked.indexOf(id) === -1) { S.blocked.push(id); } save(); emit(); }
  function clearBlocked() { S.blocked = []; save(); emit(); }
  function setExtra(arr) { S.extra = arr; save(); emit(); }
  function setPin(p) { S.pin = p; save(); emit(); }
  function setAutoNext(v) { S.autoNext = !!v; save(); emit(); }

  return {
    S: S, st: st, cfg: CFG, markWatched: markWatched, init: init, syncCatalog: syncCatalog, addWatch: addWatch, usageToday: usageToday, lockState: lockState, extend: extend, setLimit: setLimit, setBed: setBed, setName: setName, isFav: isFav, toggleFav: toggleFav, effLimit: effLimit, effBed: effBed, effName: effName, setFamily: setFamily, checkFamily: checkFamily, familyId: familyId, refresh: refresh, visible: visible, onChange: onChange, words: words,
    setEnabled: setEnabled, removeChannel: removeChannel, addChannelByHandle: addChannelByHandle,
    blockVideo: blockVideo, clearBlocked: clearBlocked, setExtra: setExtra, setPin: setPin, setAutoNext: setAutoNext,
    isBlockedText: isBlockedText, parseDuration: parseDuration, fmtDur: fmtDur, _net: net
  };
})();
if (typeof module !== 'undefined' && module.exports) { module.exports = KT; }
