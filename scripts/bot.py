#!/usr/bin/env python3
"""Telegram-бот для «Мультиков»: ищет новые детские каналы и присылает их родителям на одобрение.

Запускается по расписанию в GitHub Actions (.github/workflows/telegram-bot.yml), только стандартная библиотека.
Секреты (переменные окружения): TG_BOT_TOKEN, TG_CHAT_ID (можно несколько через запятую), YT_KEY.
Результат: data/catalog.json (одобренные каналы с категориями) и data/state.json (служебное).
"""
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(ROOT, 'data', 'catalog.json')
STATE_PATH = os.path.join(ROOT, 'data', 'state.json')
CONFIG_PATH = os.path.join(ROOT, 'web', 'config.js')

TOKEN = os.environ.get('TG_BOT_TOKEN', '')
CHATS = [c.strip() for c in os.environ.get('TG_CHAT_ID', '').split(',') if c.strip()]
YT_KEY = os.environ.get('YT_KEY', '')
LISTEN_SECONDS = int(os.environ.get('LISTEN_SECONDS', '240'))
DISCOVER_EVERY = 20 * 3600
QUERIES_PER_RUN = 4
MAX_NEW_PER_RUN = 6

CATS = {'cartoons': 'Мультики', 'english': 'Английский', 'learn': 'Обучение', 'music': 'Музыка'}

# (запрос, язык, категория, только свежие)
QUERIES = [
    ('мультики для малышей 3-4 года', 'ru', 'cartoons', False),
    ('новые добрые мультфильмы для детей', 'ru', 'cartoons', True),
    ('cartoons for toddlers', 'en', 'cartoons', False),
    ('new kids cartoon episodes', 'en', 'cartoons', True),
    ('learn english alphabet for kids', 'en', 'english', False),
    ('phonics songs for toddlers', 'en', 'english', False),
    ('abc letters and sounds for preschool', 'en', 'english', False),
    ('развивающие мультики для малышей', 'ru', 'learn', False),
    ('учим буквы и цифры малышам', 'ru', 'learn', False),
    ('educational videos for preschoolers', 'en', 'learn', False),
    ('learn colors shapes numbers toddlers', 'en', 'learn', False),
    ('piano music for kids', 'en', 'music', False),
    ('lullabies for children', 'en', 'music', False),
    ('детские песенки для малышей', 'ru', 'music', False),
    ('классическая музыка для детей', 'ru', 'music', False),
]


# ---------------------------------------------------------------- сеть
def http_json(url, data=None, retries=3):
    """GET (или POST с JSON) -> dict. Тесты подменяют эту функцию."""
    body = None
    headers = {'User-Agent': 'kidstube-bot'}
    if data is not None:
        body = json.dumps(data).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, data=body, headers=headers)
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            txt = e.read().decode('utf-8', 'replace')
            last = RuntimeError('HTTP %s: %s' % (e.code, txt[:300]))
            if e.code in (400, 401, 403, 404):
                break
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(2 * (i + 1))
    raise last


def yt(path, **q):
    q['key'] = YT_KEY
    return http_json('https://www.googleapis.com/youtube/v3/%s?%s' % (path, urllib.parse.urlencode(q)))


def tg(method, **params):
    r = http_json('https://api.telegram.org/bot%s/%s' % (TOKEN, method), data=params)
    if not r.get('ok'):
        raise RuntimeError('telegram %s: %s' % (method, r))
    return r['result']


def tg_safe(method, **params):
    try:
        return tg(method, **params)
    except Exception as e:  # noqa: BLE001
        log('telegram error (%s): %s' % (method, str(e).replace(TOKEN, '***')))
        return None


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- данные
def load_json(path, default):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return default


def save_json(path, obj):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write('\n')


def load_config():
    t = open(CONFIG_PATH, encoding='utf-8').read()
    body = t.split('var KT_CONFIG = ', 1)[1].strip().rstrip(';')
    return json.loads(body)


def now_iso():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def has_stop(text, words):
    t = str(text).lower()
    return any(w and w in t for w in words)


def parse_duration(iso):
    m = re.match(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$', iso or '')
    if not m:
        return 0
    return int(m.group(1) or 0) * 3600 + int(m.group(2) or 0) * 60 + int(m.group(3) or 0)


def guess_lang(title):
    return 'ru' if re.search('[а-яёА-ЯЁ]', title or '') else 'en'


def thumb_of(snippet):
    t = (snippet or {}).get('thumbnails', {})
    for k in ('medium', 'default', 'high'):
        if k in t and t[k].get('url'):
            return t[k]['url']
    return ''


def channel_by_handle(handle):
    h = handle if handle.startswith('@') else '@' + handle
    r = yt('channels', part='snippet,contentDetails', forHandle=h)
    items = r.get('items') or []
    if not items:
        return None
    it = items[0]
    return {'id': it['id'], 'title': it['snippet'].get('title', handle), 'handle': handle.lstrip('@'),
            'thumb': thumb_of(it['snippet'])}


# ---------------------------------------------------------------- Telegram: карточки и ответы
def send_all(text, **kw):
    for c in CHATS:
        tg_safe('sendMessage', chat_id=c, text=text, parse_mode='HTML', disable_web_page_preview=True, **kw)


def keyboard(cid, suggested):
    others = [k for k in CATS if k != suggested]
    return {'inline_keyboard': [
        [{'text': '✅ Одобрить: ' + CATS[suggested], 'callback_data': 'a:%s:%s' % (suggested, cid)},
         {'text': '❌ Блок', 'callback_data': 'b:' + cid}],
        [{'text': '→ ' + CATS[k], 'callback_data': 'a:%s:%s' % (k, cid)} for k in others],
    ]}


def card_text(p):
    lines = ['<b>%s</b>' % html.escape(p['title']),
             '🌐 %s · предложено: %s' % ('русский' if p['lang'] == 'ru' else 'English', CATS[p['cat']])]
    if p.get('subs'):
        lines.append('👥 %s подписчиков' % format(p['subs'], ',').replace(',', ' '))
    for t in p.get('samples', [])[:3]:
        lines.append('• ' + html.escape(t))
    lines.append('<a href="https://www.youtube.com/channel/%s">Открыть канал</a>' % p['id'])
    return '\n'.join(lines)


def send_card(p):
    for c in CHATS:
        kb = keyboard(p['id'], p['cat'])
        r = None
        if p.get('thumb'):
            r = tg_safe('sendPhoto', chat_id=c, photo=p['thumb'], caption=card_text(p), parse_mode='HTML', reply_markup=kb)
        if r is None:
            tg_safe('sendMessage', chat_id=c, text=card_text(p), parse_mode='HTML', reply_markup=kb)


# ---------------------------------------------------------------- поиск кандидатов
def resolve_seeds(state, cfg):
    """Узнаём id стартовых каналов (чтобы не предлагать их заново) и сообщаем, какие handle не найдены."""
    missing = []
    for s in cfg.get('seeds', []):
        h = s['handle']
        if h in state['seedIds']:
            if not state['seedIds'][h]:
                missing.append(s)
            continue
        try:
            ch = channel_by_handle(h)
        except Exception as e:  # noqa: BLE001
            log('seed resolve error', h, e)
            continue
        state['seedIds'][h] = ch['id'] if ch else ''
        if not ch:
            missing.append(s)
    new_missing = [s for s in missing if s['handle'] not in state['missingReported']]
    if new_missing:
        send_all('⚠️ Не нашёл на YouTube эти каналы из стартового списка:\n' +
                 '\n'.join('• %s (@%s)' % (html.escape(s['name']), html.escape(s['handle'])) for s in new_missing) +
                 '\n\nИсправьте handle в web/config.js или добавьте нужный канал командой /add @handle')
        state['missingReported'] += [s['handle'] for s in new_missing]


def known_ids(state, catalog):
    ids = set(c['id'] for c in catalog['channels'])
    ids |= set(v for v in state['seedIds'].values() if v)
    ids |= set(state['seen'].keys())
    ids |= set(state['pending'].keys())
    return ids


def discover(state, catalog, cfg, force=False):
    words = [w.lower() for w in cfg.get('stopWords', [])]
    resolve_seeds(state, cfg)
    known = known_ids(state, catalog)
    picked = []
    for _ in range(QUERIES_PER_RUN):
        picked.append(QUERIES[state['qIndex'] % len(QUERIES)])
        state['qIndex'] = (state['qIndex'] + 1) % len(QUERIES)
    found = {}  # channelId -> {'cat','lang','vids':[...]}
    for q, lang, cat, recent in picked:
        params = dict(part='snippet', type='video', q=q, maxResults='25', safeSearch='strict',
                      videoEmbeddable='true', relevanceLanguage=lang)
        if recent:
            params['order'] = 'date'
            params['publishedAfter'] = datetime.fromtimestamp(time.time() - 60 * 86400, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        try:
            r = yt('search', **params)
        except Exception as e:  # noqa: BLE001
            log('search error', q, e)
            continue
        vids = [it['id']['videoId'] for it in r.get('items', []) if it.get('id', {}).get('videoId')]
        if not vids:
            continue
        try:
            vr = yt('videos', part='snippet,status,contentDetails', id=','.join(vids[:50]))
        except Exception as e:  # noqa: BLE001
            log('videos error', e)
            continue
        for v in vr.get('items', []):
            st = v.get('status', {})
            sn = v.get('snippet', {})
            if st.get('madeForKids') is not True or st.get('embeddable') is not True:
                continue
            if parse_duration(v.get('contentDetails', {}).get('duration')) < 30:
                continue
            if has_stop(sn.get('title', ''), words):
                continue
            cid = sn.get('channelId')
            if not cid or cid in known:
                continue
            e = found.setdefault(cid, {'cat': cat, 'lang': lang, 'vids': []})
            e['vids'].append(sn.get('title', ''))
    if not found:
        return 0
    cands = []
    ids = list(found.keys())
    for i in range(0, len(ids), 50):
        try:
            cr = yt('channels', part='snippet,statistics,status,contentDetails', id=','.join(ids[i:i + 50]))
        except Exception as e:  # noqa: BLE001
            log('channels error', e)
            continue
        for ch in cr.get('items', []):
            cid = ch['id']
            f = found[cid]
            stt = ch.get('status', {})
            stats = ch.get('statistics', {})
            hidden = stats.get('hiddenSubscriberCount')
            subs = int(stats.get('subscriberCount', 0) or 0)
            if stt.get('madeForKids') is False:
                state['seen'][cid] = 'auto_rejected'
                continue
            if not hidden and subs < 10000:
                state['seen'][cid] = 'auto_rejected'
                continue
            if (hidden or 'madeForKids' not in stt) and len(f['vids']) < 2:
                continue
            uploads = ((ch.get('contentDetails') or {}).get('relatedPlaylists') or {}).get('uploads') or ('UU' + cid[2:])
            try:
                pl = yt('playlistItems', part='snippet', playlistId=uploads, maxResults='25')
            except Exception as e:  # noqa: BLE001
                log('playlist error', e)
                continue
            titles = [it['snippet'].get('title', '') for it in pl.get('items', [])]
            if any(has_stop(t, words) for t in titles):
                state['seen'][cid] = 'auto_rejected'
                continue
            cands.append({'id': cid, 'title': ch['snippet'].get('title', cid), 'lang': f['lang'], 'cat': f['cat'],
                          'thumb': thumb_of(ch['snippet']), 'subs': subs,
                          'handle': (ch['snippet'].get('customUrl') or '').lstrip('@'),
                          'samples': [t for t in titles if t and t != 'Private video'][:3]})
    cands.sort(key=lambda c: -c['subs'])
    sent = 0
    for p in cands[:MAX_NEW_PER_RUN]:
        state['pending'][p['id']] = p
        send_card(p)
        sent += 1
    return sent


# ---------------------------------------------------------------- решения родителей
def decide(state, catalog, cid, action, cat=None):
    """Возвращает (текст-результат, изменился ли каталог)."""
    p = state['pending'].get(cid)
    if not p:
        for c in catalog['channels']:
            if c['id'] == cid:
                return ('Уже решено: ' + ('одобрен' if c['status'] == 'approved' else 'заблокирован'), False)
        if state['seen'].get(cid) == 'blocked':
            return ('Уже решено: заблокирован', False)
        return ('Это предложение уже неактуально', False)
    del state['pending'][cid]
    if action == 'a':
        cat = cat if cat in CATS else p['cat']
        catalog['channels'].append({'id': cid, 'title': p['title'], 'handle': p.get('handle', ''), 'lang': p['lang'],
                                    'cat': cat, 'thumb': p.get('thumb', ''), 'status': 'approved'})
        state['seen'][cid] = 'approved'
        return ('✅ Одобрено: ' + CATS[cat], True)
    state['seen'][cid] = 'blocked'
    return ('❌ Заблокировано', False)


def upsert_channel(catalog, ch, status, cat=None):
    for c in catalog['channels']:
        if c['id'] == ch['id']:
            c['status'] = status
            if cat:
                c['cat'] = cat
            return
    catalog['channels'].append({'id': ch['id'], 'title': ch['title'], 'handle': ch['handle'], 'lang': guess_lang(ch['title']),
                                'cat': cat or 'cartoons', 'thumb': ch.get('thumb', ''), 'status': status})


HELP = ('Команды:\n'
        '/find — поискать новые каналы сейчас\n'
        '/add @handle [мультики|английский|обучение|музыка] — добавить канал сразу\n'
        '/block @handle — убрать канал и больше не показывать\n'
        '/list — что сейчас разрешено\n'
        'Новые каналы приходят карточками с кнопками, нажмите ✅ или ❌.')
CAT_WORDS = {'мультики': 'cartoons', 'мульт': 'cartoons', 'английский': 'english', 'англ': 'english',
             'обучение': 'learn', 'обучалки': 'learn', 'музыка': 'music', 'песни': 'music'}


def handle_text(state, catalog, chat, text):
    """Возвращает (ответ, изменился ли каталог, запросить поиск)."""
    text = (text or '').strip()
    cmd = text.split()[0].split('@')[0].lower() if text else ''
    args = text.split()[1:]
    if cmd in ('/start', '/help'):
        return (HELP, False, False)
    if cmd == '/find':
        return ('Ищу новые каналы…', False, True)
    if cmd == '/list':
        by = {}
        for c in catalog['channels']:
            if c['status'] == 'approved':
                by.setdefault(c['cat'], []).append(c['title'])
        out = ['Через бота добавлено:']
        for k, name in CATS.items():
            if by.get(k):
                out.append('%s: %s' % (name, ', '.join(by[k])))
        if len(out) == 1:
            out.append('пока ничего (стартовые каналы живут в web/config.js)')
        out.append('Ждут решения: %d' % len(state['pending']))
        return ('\n'.join(out), False, False)
    if cmd in ('/add', '/block'):
        if not args:
            return ('Напишите так: %s @handle' % cmd, False, False)
        m = re.search(r'@([^/?#\s]+)', args[0])
        handle = m.group(1) if m else args[0].lstrip('@')
        try:
            ch = channel_by_handle(handle)
        except Exception as e:  # noqa: BLE001
            return ('Ошибка YouTube: %s' % str(e)[:200], False, False)
        if not ch:
            return ('Канал @%s не найден' % handle, False, False)
        if cmd == '/block':
            upsert_channel(catalog, ch, 'blocked')
            state['pending'].pop(ch['id'], None)
            state['seen'][ch['id']] = 'blocked'
            return ('❌ %s заблокирован' % ch['title'], True, False)
        cat = 'cartoons'
        if len(args) > 1:
            cat = CAT_WORDS.get(args[1].lower(), 'cartoons')
        upsert_channel(catalog, ch, 'approved', cat)
        state['pending'].pop(ch['id'], None)
        state['seen'][ch['id']] = 'approved'
        return ('✅ %s добавлен: %s' % (ch['title'], CATS[cat]), True, False)
    return (HELP, False, False)


def handle_update(state, catalog, u):
    """Возвращает (изменился ли каталог, запросить поиск)."""
    changed, want = False, False
    if 'callback_query' in u:
        cq = u['callback_query']
        chat = str((cq.get('message') or {}).get('chat', {}).get('id', ''))
        if chat not in CHATS:
            return (False, False)
        parts = (cq.get('data') or '').split(':')
        if parts[0] == 'a' and len(parts) == 3:
            res, changed = decide(state, catalog, parts[2], 'a', parts[1])
        elif parts[0] == 'b' and len(parts) == 2:
            res, changed = decide(state, catalog, parts[1], 'b')
        else:
            return (False, False)
        tg_safe('answerCallbackQuery', callback_query_id=cq['id'], text=res)
        msg = cq['message']
        if 'photo' in msg:
            tg_safe('editMessageCaption', chat_id=msg['chat']['id'], message_id=msg['message_id'],
                    caption=(msg.get('caption') or '') + '\n\n' + res, reply_markup={'inline_keyboard': []})
        else:
            tg_safe('editMessageText', chat_id=msg['chat']['id'], message_id=msg['message_id'],
                    text=(msg.get('text') or '') + '\n\n' + res, reply_markup={'inline_keyboard': []})
        return (changed, False)
    m = u.get('message')
    if m and str(m.get('chat', {}).get('id', '')) in CHATS:
        res, changed, want = handle_text(state, catalog, m['chat']['id'], m.get('text', ''))
        tg_safe('sendMessage', chat_id=m['chat']['id'], text=res)
    return (changed, want)


# ---------------------------------------------------------------- git
def git(*args):
    return subprocess.run(['git'] + list(args), cwd=ROOT, capture_output=True, text=True)


def publish(message='bot: update catalog'):
    if os.environ.get('NO_GIT'):
        return
    git('add', 'data')
    if git('diff', '--cached', '--quiet').returncode == 0:
        return
    git('commit', '-m', message)
    for _ in range(4):
        if git('push').returncode == 0:
            return
        git('pull', '--rebase', '-X', 'theirs')
        time.sleep(2)
    log('push failed')


# ---------------------------------------------------------------- основной цикл
def main():
    if not TOKEN or not CHATS or not YT_KEY:
        log('Нужны секреты TG_BOT_TOKEN, TG_CHAT_ID и YT_KEY')
        return 1
    cfg = load_config()
    state = load_json(STATE_PATH, {})
    for k, v in {'offset': 0, 'lastDiscover': 0, 'qIndex': 0, 'seedIds': {}, 'missingReported': [], 'seen': {}, 'pending': {}}.items():
        state.setdefault(k, v)
    catalog = load_json(CATALOG_PATH, {'updated': '', 'channels': []})
    want = time.time() - state['lastDiscover'] > DISCOVER_EVERY
    deadline = time.time() + LISTEN_SECONDS
    offset = state['offset'] or None
    dirty = False
    while True:
        if want:
            want = False
            n = discover(state, catalog, cfg)
            state['lastDiscover'] = int(time.time())
            log('discover: %d new' % n)
            if n == 0 and CHATS:
                log('no new candidates')
            save_json(STATE_PATH, state)
            publish('bot: state')
        left = deadline - time.time()
        if left < 3:
            break
        try:
            params = {'timeout': int(min(25, left - 1)), 'allowed_updates': ['message', 'callback_query']}
            if offset:
                params['offset'] = offset
            updates = tg('getUpdates', **params)
        except Exception as e:  # noqa: BLE001
            log('getUpdates error', str(e).replace(TOKEN, '***'))
            time.sleep(5)
            continue
        changed_any = False
        for u in updates:
            offset = u['update_id'] + 1
            try:
                ch, w = handle_update(state, catalog, u)
            except Exception as e:  # noqa: BLE001
                log('update error', str(e).replace(TOKEN, '***'))
                continue
            changed_any = changed_any or ch
            want = want or w
            dirty = True
        if updates:
            state['offset'] = offset or 0
            if changed_any:
                catalog['updated'] = now_iso()
                save_json(CATALOG_PATH, catalog)
            save_json(STATE_PATH, state)
            publish()
    if offset:
        tg_safe('getUpdates', offset=offset, timeout=0)
        state['offset'] = offset
    save_json(STATE_PATH, state)
    publish('bot: state')
    return 0


if __name__ == '__main__':
    sys.exit(main())
