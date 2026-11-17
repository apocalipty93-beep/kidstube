/* Интерфейс: лента, плеер, родительский режим, управление пультом (D-pad). ES5. */
(function () {
  var S = KT.S;
  var root = document.getElementById('app');
  var view = 'home';        // home | player | parent
  var filter = 'all';       // all | ru | en | cat:<id> | ch:<id>
  var newCat = 'cartoons';  // категория для вручную добавляемого канала
  var newText = '';
  var cur = null;           // текущее видео
  var queue = [];           // видео того же канала (для автовоспроизведения)
  var pool = [];            // вся текущая лента (для рекомендаций)
  var player = null;
  var fs = false;
  var errCount = 0;
  var modal = null;
  var apiRequested = false;
  var pendingVideo = null;
  var moved = false;        // пользователь уже двигал фокус пультом/мышью

  /* ---------- helpers ---------- */
  function h(tag, attrs, kids) {
    var e = document.createElement(tag);
    attrs = attrs || {};
    for (var k in attrs) {
      if (k === 'class') { e.className = attrs[k]; }
      else if (k === 'text') { e.textContent = attrs[k]; }
      else if (k.indexOf('on') === 0) { e.addEventListener(k.slice(2), attrs[k]); }
      else { e.setAttribute(k, attrs[k]); }
    }
    (kids || []).forEach(function (c) { if (c) { e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c); } });
    return e;
  }
  function foc(e, key, fn) {
    e.setAttribute('tabindex', '0');
    e.setAttribute('data-f', '1');
    if (key) { e.setAttribute('data-key', key); }
    if (fn) { e.addEventListener('click', fn); }
    return e;
  }
  function btn(label, key, fn, cls) { return foc(h('div', { class: 'btn ' + (cls || ''), text: label }), key, fn); }
  function toast(msg) {
    var t = h('div', { class: 'toast', text: msg });
    document.body.appendChild(t);
    setTimeout(function () { if (t.parentNode) { t.parentNode.removeChild(t); } }, 2600);
  }
  function currentKey() { var a = document.activeElement; return a && a.getAttribute ? a.getAttribute('data-key') : null; }
  function focusKey(key) {
    var el = key ? root.querySelector('[data-key="' + key + '"]') : null;
    if (!el) { el = (modal || root).querySelector('[data-f]'); }
    if (el) { el.focus(); }
  }
  function clear() { root.innerHTML = ''; }

  /* ---------- главная ---------- */
  function applyFilter(all) {
    if (filter === 'ru' || filter === 'en') { return all.filter(function (v) { return v.lang === filter; }); }
    if (filter.indexOf('cat:') === 0) {
      var cid = filter.slice(4), on = {};
      S.channels.forEach(function (c) { if (c.cat === cid && c.enabled && c.id) { on[c.id] = true; } });
      return all.filter(function (v) { return on[v.channelId]; });
    }
    if (filter.indexOf('ch:') === 0) { var id = filter.slice(3); return all.filter(function (v) { return v.channelId === id; }); }
    return all;
  }

  function card(v, list) {
    var thumb = h('div', { class: 'thumb' }, [
      h('img', { src: 'https://i.ytimg.com/vi/' + v.id + '/mqdefault.jpg', alt: '' }),
      h('div', { class: 'play' }),
      h('div', { class: 'dur', text: KT.fmtDur(v.seconds) })
    ]);
    var c = h('div', { class: 'card' }, [thumb, h('div', { class: 't', text: v.title }), h('div', { class: 'c', text: v.channelTitle })]);
    return foc(c, 'v-' + v.id, function () { openPlayer(v, list); });
  }

  function renderHome(keepKey) {
    leavePlayer();
    view = 'home';
    var key = keepKey || currentKey();
    clear();
    var all = KT.visible();
    if (filter.indexOf('ch:') === 0) {
      var fid = filter.slice(3);
      if (!S.channels.some(function (c) { return c.id === fid && c.enabled; }) || !all.some(function (v) { return v.channelId === fid; })) { filter = 'all'; }
    }
    if (filter.indexOf('cat:') === 0) {
      var fcat = filter.slice(4);
      if (!S.channels.some(function (c) { return c.cat === fcat && c.enabled && c.id; })) { filter = 'all'; }
    }
    var list = applyFilter(all);
    if (!keepKey && !moved && list.length) { key = 'v-' + list[0].id; }

    root.appendChild(h('div', { class: 'head' }, [
      h('div', { class: 'logo' }, [h('i'), 'Мультики']),
      h('div', { class: 'spacer' }),
      btn('Обновить', 'refresh', function () { KT.refresh(); }),
      btn('Родителям', 'parent', function () { askPin(function () { renderParent(); }); })
    ]));

    var chips = h('div', { class: 'chips' });
    [['all', 'Все'], ['ru', 'Русские'], ['en', 'English']].forEach(function (p) {
      chips.appendChild(foc(h('div', { class: 'chip' + (filter === p[0] ? ' sel' : ''), text: p[1] }), 'chip-' + p[0], function () { filter = p[0]; renderHome('chip-' + p[0]); }));
    });
    var present = {}, chOf = {};
    S.channels.forEach(function (c) { chOf[c.id] = c; });
    all.forEach(function (v) { var c = chOf[v.channelId]; if (c) { present[c.cat || 'cartoons'] = true; } });
    (KT.cfg.cats || []).forEach(function (p) {
      if (!present[p.id]) { return; }
      chips.appendChild(foc(h('div', { class: 'chip' + (filter === 'cat:' + p.id ? ' sel' : ''), text: p.name }), 'chip-cat-' + p.id, function () { filter = 'cat:' + p.id; renderHome('chip-cat-' + p.id); }));
    });
    root.appendChild(chips);

    var av = h('div', { class: 'avatars' });
    var hasVid = {};
    all.forEach(function (v) { hasVid[v.channelId] = true; });
    S.channels.filter(function (c) { return c.enabled && c.id && hasVid[c.id]; }).forEach(function (c) {
      var sel = filter === 'ch:' + c.id;
      var pic = h('div', { class: 'pic', text: c.thumb ? '' : c.title.charAt(0) });
      if (c.thumb) { pic.style.backgroundImage = 'url(' + c.thumb + ')'; }
      var a = h('div', { class: 'avatar' + (sel ? ' sel' : '') }, [pic, h('div', { class: 'nm', text: c.title })]);
      foc(a, 'ch-' + c.id, function () { filter = sel ? 'all' : 'ch:' + c.id; renderHome('ch-' + c.id); });
      av.appendChild(a);
    });
    root.appendChild(av);

    if (KT.st.loading && !all.length) {
      root.appendChild(h('div', { class: 'msg', text: 'Загружаю мультики…' }));
    } else if (!all.length) {
      root.appendChild(h('div', { class: 'msg', text: KT.st.error || 'Пока нет мультиков. Нажмите «Обновить».' }));
    } else if (!list.length) {
      root.appendChild(h('div', { class: 'msg', text: 'Ничего не найдено' }));
    } else {
      var grid = h('div', { class: 'grid' });
      list.forEach(function (v) { grid.appendChild(card(v, list)); });
      root.appendChild(grid);
    }
    focusKey(key || (list.length ? 'v-' + list[0].id : 'refresh'));
  }

  /* ---------- плеер ---------- */
  function loadYtApi(cb) {
    if (window.YT && window.YT.Player) { cb(); return; }
    pendingVideo = cb;
    if (apiRequested) { return; }
    apiRequested = true;
    window.onYouTubeIframeAPIReady = function () { if (pendingVideo) { var f = pendingVideo; pendingVideo = null; f(); } };
    var s = document.createElement('script');
    s.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(s);
  }

  function makePlayer() {
    if (!cur || !document.getElementById('yt')) { return; }
    player = new YT.Player('yt', {
      width: '100%', height: '100%', videoId: cur.id,
      playerVars: { autoplay: 1, rel: 0, fs: 0, playsinline: 1, modestbranding: 1, controls: 1, cc_load_policy: 0, origin: location.origin },
      events: {
        onReady: function (e) {
          try { e.target.getIframe().setAttribute('tabindex', '-1'); } catch (x) {}
          try { e.target.playVideo(); } catch (x2) {}
        },
        onStateChange: function (e) {
          if (e.data === 1) { errCount = 0; }
          if (e.data === 0) { nextVideo(false); }
        },
        onError: function () { errCount++; if (errCount <= 3) { nextVideo(true); } }
      }
    });
  }

  function leavePlayer() {
    if (player) { try { player.destroy(); } catch (e) {} player = null; }
    fs = false;
  }

  function playVideo(v) {
    KT.markWatched(v.id);
    cur = v;
    if (player && player.loadVideoById) { player.loadVideoById(v.id); }
    renderPlayerInfo();
  }

  function nextVideo(force) {
    if (!force && !S.autoNext) { return; }
    var i = -1;
    queue.forEach(function (v, n) { if (v.id === cur.id) { i = n; } });
    if (!queue.length) { return; }
    var nx = queue[(i + 1) % queue.length];
    if (nx.id !== cur.id) { playVideo(nx); }
  }

  function togglePause() {
    if (!player || !player.getPlayerState) { return; }
    try { if (player.getPlayerState() === 1) { player.pauseVideo(); } else { player.playVideo(); } } catch (e) {}
  }
  function seek(d) {
    if (!player || !player.getCurrentTime) { return; }
    try { player.seekTo(Math.max(0, player.getCurrentTime() + d), true); } catch (e) {}
  }

  function setFs(on) {
    fs = on;
    var w = document.getElementById('pwrap');
    if (!w) { return; }
    if (on) {
      w.className = 'pwrap fs';
      var hint = w.querySelector('.fshint');
      if (hint) { hint.className = 'fshint show'; setTimeout(function () { hint.className = 'fshint'; }, 4000); }
      var x = w.querySelector('.fsx'); if (x) { x.focus(); }
    } else {
      w.className = 'pwrap';
      focusKey('fsbtn');
    }
  }

  function renderPlayerInfo() {
    var t = document.getElementById('ptitle');
    var c = document.getElementById('pchan');
    if (t) { t.textContent = cur.title; }
    if (c) { c.textContent = cur.channelTitle; }
    var q = document.getElementById('pqueue');
    if (q) {
      q.innerHTML = '';
      var same = queue.filter(function (v) { return v.id !== cur.id; });
      var others = pool.filter(function (v) { return v.channelId !== cur.channelId; });
      var rel = [];
      for (var i = 0; i < same.length || i < others.length; i++) {
        if (i < same.length) { rel.push(same[i]); }
        if (i < others.length) { rel.push(others[i]); }
      }
      rel.forEach(function (v) {
        q.appendChild(foc(h('div', { class: 'q' }, [h('div', { class: 'thumb' }, [h('img', { src: 'https://i.ytimg.com/vi/' + v.id + '/mqdefault.jpg', alt: '' }), h('div', { class: 'dur', text: KT.fmtDur(v.seconds) })]), h('div', { class: 't', text: v.title, style: 'margin:.4rem .3rem 0;font-weight:700' })]), 'q-' + v.id, function () { playVideo(v); }));
      });
    }
  }

  function openPlayer(v, list) {
    view = 'player';
    KT.markWatched(v.id);
    cur = v; errCount = 0;
    pool = list;
    queue = list.filter(function (x) { return x.channelId === v.channelId; });
    if (!queue.length) { queue = list; }
    clear();
    var wrap = h('div', { class: 'pwrap', id: 'pwrap' }, [
      h('div', { id: 'yt' }),
      foc(h('div', { class: 'btn main fsx', text: 'Выйти' }), 'fsx', function () { setFs(false); }),
      h('div', { class: 'fshint', text: 'OK — пауза · ← → — перемотка · Назад — выход' })
    ]);
    var left = h('div', { class: 'pleft' }, [
      wrap,
      h('div', { class: 'ptitle', id: 'ptitle', text: v.title }),
      h('div', { class: 'pchan', id: 'pchan', text: v.channelTitle }),
      h('div', { class: 'prow' }, [
        btn('Назад', 'back', function () { renderHome(); }),
        btn('Пауза / Играть', 'pp', togglePause, 'main'),
        btn('На весь экран', 'fsbtn', function () { setFs(true); }),
        btn('Родителям', 'pmenu', function () { askPin(blockMenu); })
      ])
    ]);
    var right = h('div', { class: 'pright' }, [h('div', { class: 'qh', text: 'Ещё мультики' }), h('div', { id: 'pqueue' })]);
    root.appendChild(h('div', { class: 'pview' }, [left, right]));
    renderPlayerInfo();
    loadYtApi(makePlayer);
    focusKey('fsbtn');
  }

  function blockMenu() {
    openModal('Родительское меню', [
      btn('Заблокировать это видео', 'm1', function () { KT.blockVideo(cur.id); closeModal(); toast('Видео заблокировано'); renderHome(); }, 'main'),
      btn('Отключить канал «' + cur.channelTitle + '»', 'm2', function () {
        S.channels.forEach(function (c) { if (c.id === cur.channelId) { KT.setEnabled(c, false); } });
        closeModal(); renderHome();
      }),
      btn('Отмена', 'm3', closeModal, 'off')
    ]);
  }

  /* ---------- модальные окна и PIN ---------- */
  function openModal(title, kids) {
    closeModal();
    var d = h('div', { class: 'dlg' }, [h('h2', { text: title })].concat(kids));
    modal = h('div', { class: 'modal' }, [d]);
    document.body.appendChild(modal);
    var f = modal.querySelector('[data-f]'); if (f) { f.focus(); }
  }
  function closeModal() {
    if (modal && modal.parentNode) { modal.parentNode.removeChild(modal); }
    modal = null;
    focusKey(null);
  }

  function pinDialog(title, done) {
    var val = '';
    var dots = h('div', { class: 'dots', text: '' });
    var pad = h('div', { class: 'pad' });
    function upd() { var s = ''; for (var i = 0; i < 4; i++) { s += i < val.length ? '●' : '○'; } dots.textContent = s; }
    function press(d) {
      if (val.length >= 4) { return; }
      val += d; upd();
      if (val.length === 4) { var v = val; setTimeout(function () { closeModal(); done(v); }, 120); }
    }
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', 'X'].forEach(function (k) {
      pad.appendChild(foc(h('div', { class: 'k', text: k === 'C' ? '⌫' : (k === 'X' ? '✕' : k) }), 'pin-' + k, function () {
        if (k === 'C') { val = val.slice(0, -1); upd(); }
        else if (k === 'X') { closeModal(); }
        else { press(k); }
      }));
    });
    upd();
    openModal(title, [dots, pad]);
    var f = modal.querySelector('[data-key="pin-5"]'); if (f) { f.focus(); }
    modal.setAttribute('data-pin', '1');
  }

  function askPin(ok) {
    if (!S.pin) {
      pinDialog('Придумайте PIN для родителей', function (p) { KT.setPin(p); toast('PIN сохранён'); ok(); });
    } else {
      pinDialog('Введите PIN', function (p) { if (p === S.pin) { ok(); } else { toast('Неверный PIN'); } });
    }
  }

  function catName(id) {
    var l = KT.cfg.cats || [];
    for (var i = 0; i < l.length; i++) { if (l[i].id === id) { return l[i].name; } }
    return 'Мультики';
  }

  /* ---------- родительский режим ---------- */
  function renderParent(keepKey) {
    leavePlayer();
    view = 'parent';
    var key = keepKey || currentKey();
    clear();
    var p = h('div', { class: 'parent' });
    p.appendChild(h('div', { class: 'head', style: 'padding-left:0' }, [h('div', { class: 'logo', text: 'Для родителей' }), h('div', { class: 'spacer' }), btn('Готово', 'done', function () { renderHome(); }, 'main')]));

    p.appendChild(h('h2', { text: 'Разрешённые каналы' }));
    S.channels.forEach(function (c, i) {
      var row = h('div', { class: 'row' }, [h('div', { class: 'nm' }, [c.title, h('div', { class: 'sub', text: '@' + c.handle + ' · ' + (c.lang === 'ru' ? 'русский' : 'English') + ' · ' + catName(c.cat) + (c.id ? (S.videos.length && !S.videos.some(function (v) { return v.channelId === c.id; }) ? ' · нет видео: канал запретил встраивание' : ' · ' + S.videos.filter(function (v) { return v.channelId === c.id; }).length + ' видео') : ' · не найден на YouTube') })])]);
      if (c.id) { row.appendChild(btn(c.enabled ? 'Включён' : 'Выключен', 'tg-' + i, function () { KT.setEnabled(c, !c.enabled); renderParent('tg-' + i); }, c.enabled ? 'main' : 'off')); }
      if (c.custom || !c.id) { row.appendChild(btn('Удалить', 'rm-' + i, function () { KT.removeChannel(c); renderParent('done'); })); }
      p.appendChild(row);
    });

    p.appendChild(h('h2', { text: 'Добавить канал' }));
    var inp = h('input', { type: 'text', id: 'newch', value: newText, placeholder: '@handle или ссылка youtube.com/@handle' });
    inp.setAttribute('data-f', '1'); inp.setAttribute('data-key', 'newch');
    function addCh(lang) {
      var s = inp.value.trim();
      var m = /@([^\/?#\s]+)/.exec(s);
      var handle = m ? m[1] : (s.indexOf('/') === -1 ? s : '');
      if (!handle) { toast('Нужен @handle канала, например @Bluey'); return; }
      toast('Ищу канал…');
      KT.addChannelByHandle(handle, lang, newCat).then(function (ch) {
        if (!ch) { toast('Канал не найден'); return; }
        toast('Добавлен: ' + ch.title);
        KT.refresh().then(function () { renderParent('done'); });
      })['catch'](function (e) { toast('Ошибка: ' + e.message); });
    }
    p.appendChild(h('div', { class: 'row' }, [inp, btn('Категория: ' + catName(newCat), 'addcat', function () {
      var l = KT.cfg.cats || [], i = 0;
      l.forEach(function (x, n) { if (x.id === newCat) { i = n; } });
      newCat = l[(i + 1) % l.length].id; newText = inp.value; renderParent('addcat');
    }), btn('Русский', 'addru', function () { addCh('ru'); }), btn('English', 'adden', function () { addCh('en'); })]));

    p.appendChild(h('h2', { text: 'Настройки' }));
    p.appendChild(h('div', { class: 'row' }, [h('div', { class: 'nm', text: 'Автоматически включать следующее видео' }), btn(S.autoNext ? 'Да' : 'Нет', 'auto', function () { KT.setAutoNext(!S.autoNext); renderParent('auto'); }, S.autoNext ? 'main' : 'off')]));

    var wi = h('input', { type: 'text', id: 'words', value: (S.extra || []).join(', '), placeholder: 'слово1, слово2' });
    wi.setAttribute('data-f', '1'); wi.setAttribute('data-key', 'words');
    p.appendChild(h('div', { class: 'row' }, [h('div', { class: 'nm' }, ['Свои стоп-слова', h('div', { class: 'sub', text: 'Встроенных: ' + (KT.words().length - (S.extra || []).length) })]), wi, btn('Сохранить', 'wsave', function () {
      var arr = wi.value.split(',').map(function (x) { return x.trim().toLowerCase(); }).filter(function (x) { return x; });
      KT.setExtra(arr); toast('Сохранено'); renderParent('wsave');
    })]));

    p.appendChild(h('div', { class: 'row' }, [h('div', { class: 'nm', text: 'Заблокированные видео: ' + S.blocked.length }), S.blocked.length ? btn('Сбросить', 'unblock', function () { KT.clearBlocked(); renderParent('unblock'); }) : null]));
    p.appendChild(h('div', { class: 'row' }, [h('div', { class: 'nm', text: 'Сменить PIN' }), btn('Сменить', 'chpin', function () { pinDialog('Новый PIN (4 цифры)', function (np) { KT.setPin(np); toast('PIN изменён'); }); })]));
    p.appendChild(h('div', { class: 'row' }, [h('div', { class: 'nm' }, ['Обновить ленту сейчас', KT.st.error ? h('div', { class: 'sub', text: KT.st.error }) : null]), btn(KT.st.loading ? 'Загрузка…' : 'Обновить', 'rf', function () { KT.refresh(); })]));
    root.appendChild(p);
    focusKey(key || 'done');
  }

  /* ---------- пульт и клавиатура ---------- */
  function visibleEl(el) { return el.getClientRects().length > 0; }

  function moveFocus(dir) {
    var scope = modal || root;
    var els = Array.prototype.slice.call(scope.querySelectorAll('[data-f]')).filter(visibleEl);
    var cur0 = document.activeElement;
    if (!cur0 || !cur0.hasAttribute || !cur0.hasAttribute('data-f') || els.indexOf(cur0) === -1) { if (els[0]) { els[0].focus(); } return; }
    var r = cur0.getBoundingClientRect();
    var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    var best = null, bestScore = 1e12;
    els.forEach(function (el) {
      if (el === cur0) { return; }
      var b = el.getBoundingClientRect();
      var dx = (b.left + b.width / 2) - cx, dy = (b.top + b.height / 2) - cy;
      var ok = dir === 'left' ? dx < -4 : dir === 'right' ? dx > 4 : dir === 'up' ? dy < -4 : dy > 4;
      if (!ok) { return; }
      var horiz = (dir === 'left' || dir === 'right');
      var main = horiz ? Math.abs(dx) : Math.abs(dy);
      var cross = horiz ? Math.abs(dy) : Math.abs(dx);
      var score = main + cross * 2.5;
      if (score < bestScore) { bestScore = score; best = el; }
    });
    if (best) { best.focus(); }
  }

  function goBack() {
    if (modal) { closeModal(); return true; }
    if (view === 'player') { if (fs) { setFs(false); } else { renderHome(); } return true; }
    if (view === 'parent') { renderHome(); return true; }
    return false; // на главной — пусть ТВ закроет приложение
  }

  document.addEventListener('mousedown', function () { moved = true; });
  document.addEventListener('keydown', function (e) {
    var k = e.keyCode;
    if (k >= 37 && k <= 40) { moved = true; }
    var tag = e.target && e.target.tagName;
    var typing = tag === 'INPUT' || tag === 'TEXTAREA';

    if (k === 461 || k === 27 || k === 10009 || (k === 8 && !typing)) {
      if (goBack()) { e.preventDefault(); }
      return;
    }
    if (view === 'player' && fs && !modal) {
      if (k === 13) { togglePause(); e.preventDefault(); return; }
      if (k === 37) { seek(-10); e.preventDefault(); return; }
      if (k === 39) { seek(10); e.preventDefault(); return; }
    }
    if (k === 415 || k === 19 || k === 179) { togglePause(); e.preventDefault(); return; }
    if (k === 417) { seek(10); return; }
    if (k === 412) { seek(-10); return; }
    if (k === 413) { if (view === 'player') { renderHome(); } return; }

    if (typing && (k === 37 || k === 39)) { return; }
    if (k === 37) { moveFocus('left'); e.preventDefault(); }
    else if (k === 39) { moveFocus('right'); e.preventDefault(); }
    else if (k === 38) { moveFocus('up'); e.preventDefault(); }
    else if (k === 40) { moveFocus('down'); e.preventDefault(); }
    else if (k === 13 && !typing) {
      var a = document.activeElement;
      if (a && a.hasAttribute && a.hasAttribute('data-f')) { a.click(); e.preventDefault(); }
    }
  });

  // Если пульт-указка кликнул по плееру, фокус уходит в iframe и кнопки пульта «пропадают» — возвращаем.
  window.addEventListener('blur', function () {
    setTimeout(function () {
      var a = document.activeElement;
      if (a && a.tagName === 'IFRAME') { try { a.blur(); window.focus(); } catch (e) {} }
    }, 0);
  });

  /* ---------- старт ---------- */
  KT.onChange(function () {
    if (modal) { return; }
    if (view === 'home') { renderHome(); }
    else if (view === 'parent') { renderParent(); }
  });
  renderHome();
  KT.init();
})();
