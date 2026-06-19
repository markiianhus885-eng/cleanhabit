import sqlite3
import json
import hashlib
import math
from datetime import datetime, timedelta
from flask import Flask, jsonify, request, g, session
import os

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'cleanhouse-secret-2026-xK9mP')

if os.environ.get('RAILWAY_ENVIRONMENT') or os.environ.get('RENDER'):
    DB = '/tmp/sweepy.db'
else:
    DB = os.path.join(os.path.dirname(__file__), 'sweepy.db')

# ─── DB INIT ──────────────────────────────────────────────────
def _ensure_db():
    db = sqlite3.connect(DB)
    db.executescript('''
        CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS members (
            id TEXT PRIMARY KEY, name TEXT, emoji TEXT,
            points INTEGER DEFAULT 0, coins INTEGER DEFAULT 0,
            streak INTEGER DEFAULT 0, streak_date TEXT, owned TEXT DEFAULT '[]'
        );
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY, name TEXT, emoji TEXT,
            cleanliness INTEGER DEFAULT 100, last_cleaned TEXT, color TEXT DEFAULT '#38BDF8'
        );
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY, name TEXT, room_id TEXT, assigned_to TEXT,
            freq TEXT DEFAULT 'weekly', diff TEXT DEFAULT 'medium',
            last_completed TEXT, approval_needed INTEGER DEFAULT 0, created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY, task_id TEXT, member_id TEXT,
            completed_at TEXT, pts INTEGER, coins_earned INTEGER
        );
        CREATE TABLE IF NOT EXISTS approvals (
            id TEXT PRIMARY KEY, task_id TEXT, member_id TEXT, requested_at TEXT
        );
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            member_id TEXT,
            role TEXT DEFAULT 'member',
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS achievements (
            id TEXT PRIMARY KEY,
            member_id TEXT NOT NULL,
            badge_key TEXT NOT NULL,
            earned_at TEXT,
            UNIQUE(member_id, badge_key)
        );
    ''')
    db.commit()
    db.close()

_ensure_db()

# ─── DB HELPERS ───────────────────────────────────────────────
def get_db():
    if 'db' not in g:
        g.db = sqlite3.connect(DB, detect_types=sqlite3.PARSE_DECLTYPES)
        g.db.row_factory = sqlite3.Row
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    db = g.pop('db', None)
    if db: db.close()

def uid():
    import uuid
    return str(uuid.uuid4())[:8]

def hash_pw(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

# ─── CONSTANTS ────────────────────────────────────────────────
FREQ_DAYS = {'daily':1,'every2':2,'weekly':7,'biweekly':14,'monthly':30}
DIFF_PTS  = {'easy':1,'medium':2,'hard':3}

BADGES = {
    'first_step':   {'name':'Pierwszy Krok',      'emoji':'👟', 'desc':'Wykonaj swoje pierwsze zadanie'},
    'streak_3':     {'name':'Seria 3 dni',         'emoji':'🔥', 'desc':'3 dni z rzędu'},
    'streak_7':     {'name':'Seria 7 dni',         'emoji':'🔥🔥','desc':'7 dni z rzędu'},
    'streak_30':    {'name':'Niezniszczalny',      'emoji':'💎', 'desc':'30 dni z rzędu'},
    'tasks_10':     {'name':'Pracowity',           'emoji':'⚡', 'desc':'10 wykonanych zadań'},
    'tasks_50':     {'name':'Superbohater',        'emoji':'🦸', 'desc':'50 wykonanych zadań'},
    'tasks_100':    {'name':'Legenda',             'emoji':'👑', 'desc':'100 wykonanych zadań'},
    'daily_5':      {'name':'Błyskawica',          'emoji':'⚡', 'desc':'5 zadań w jeden dzień'},
    'perfect_room': {'name':'Perfekcjonista',      'emoji':'✨', 'desc':'Doprowadź pokój do 100%'},
    'week_champ':   {'name':'Sprzątacz Tygodnia',  'emoji':'🏆', 'desc':'Najwięcej punktów w tygodniu'},
    'month_champ':  {'name':'Mistrz Miesiąca',     'emoji':'🥇', 'desc':'Najwięcej punktów w miesiącu'},
    'hard_worker':  {'name':'Twardziel',           'emoji':'💪', 'desc':'Wykonaj 5 trudnych zadań'},
    'early_bird':   {'name':'Ranny Ptaszek',       'emoji':'🐦', 'desc':'Wykonaj zadanie przed 9:00'},
    'night_owl':    {'name':'Nocna Sowa',          'emoji':'🦉', 'desc':'Wykonaj zadanie po 22:00'},
}

# ─── ACHIEVEMENTS ─────────────────────────────────────────────
def check_achievements(db, member_id):
    """Check and award new achievements after task completion."""
    new_badges = []
    existing = {r['badge_key'] for r in db.execute(
        "SELECT badge_key FROM achievements WHERE member_id=?", [member_id])}

    member = dict(db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone() or {})
    if not member: return []

    total_tasks = db.execute(
        "SELECT COUNT(*) FROM history WHERE member_id=?", [member_id]).fetchone()[0]
    today = datetime.now().strftime('%Y-%m-%d')
    today_tasks = db.execute(
        "SELECT COUNT(*) FROM history WHERE member_id=? AND completed_at LIKE ?",
        [member_id, today+'%']).fetchone()[0]
    hard_tasks = db.execute(
        "SELECT COUNT(*) FROM history h JOIN tasks t ON h.task_id=t.id WHERE h.member_id=? AND t.diff='hard'",
        [member_id]).fetchone()[0]
    hour = datetime.now().hour
    streak = member.get('streak', 0)

    checks = {
        'first_step':   total_tasks >= 1,
        'streak_3':     streak >= 3,
        'streak_7':     streak >= 7,
        'streak_30':    streak >= 30,
        'tasks_10':     total_tasks >= 10,
        'tasks_50':     total_tasks >= 50,
        'tasks_100':    total_tasks >= 100,
        'daily_5':      today_tasks >= 5,
        'hard_worker':  hard_tasks >= 5,
        'early_bird':   hour < 9,
        'night_owl':    hour >= 22,
    }

    for key, earned in checks.items():
        if earned and key not in existing:
            db.execute("INSERT OR IGNORE INTO achievements(id,member_id,badge_key,earned_at) VALUES (?,?,?,?)",
                       [uid(), member_id, key, datetime.now().isoformat()])
            new_badges.append(key)

    # Week/month champ — check if this member has most pts
    cutoff_week = (datetime.now() - timedelta(days=7)).isoformat()
    cutoff_month = (datetime.now() - timedelta(days=30)).isoformat()
    for badge, cutoff in [('week_champ', cutoff_week), ('month_champ', cutoff_month)]:
        if badge in existing: continue
        rows = db.execute(
            "SELECT member_id, SUM(pts) as s FROM history WHERE completed_at>? GROUP BY member_id ORDER BY s DESC LIMIT 1",
            [cutoff]).fetchone()
        if rows and rows['member_id'] == member_id and rows['s'] >= 10:
            db.execute("INSERT OR IGNORE INTO achievements(id,member_id,badge_key,earned_at) VALUES (?,?,?,?)",
                       [uid(), member_id, badge, datetime.now().isoformat()])
            new_badges.append(badge)

    db.commit()
    return new_badges

def get_member_achievements(db, member_id):
    rows = db.execute("SELECT badge_key, earned_at FROM achievements WHERE member_id=? ORDER BY earned_at",
                      [member_id]).fetchall()
    result = []
    for r in rows:
        key = r['badge_key']
        if key in BADGES:
            b = dict(BADGES[key])
            b['key'] = key
            b['earned_at'] = r['earned_at']
            result.append(b)
    return result

# ─── CLEANLINESS ──────────────────────────────────────────────
def is_due(task):
    if not task['last_completed']: return True
    last = datetime.fromisoformat(task['last_completed'])
    return (datetime.now() - last).total_seconds() >= FREQ_DAYS.get(task['freq'], 7) * 86400

def calc_cleanliness(room, tasks):
    base = room['cleanliness']
    now = datetime.now()
    for t in [t for t in tasks if t['room_id'] == room['id']]:
        freq_days = FREQ_DAYS.get(t['freq'], 7)
        pts = DIFF_PTS.get(t['diff'], 1)
        days_since = (now - datetime.fromisoformat(t['last_completed'])).days if t['last_completed'] else freq_days * 2
        if days_since > freq_days:
            overdue = min(days_since - freq_days, freq_days * 2)
            base = max(0, base - (overdue / freq_days) * pts * 4)
    return round(min(100, max(0, base)))

# ─── DATA ─────────────────────────────────────────────────────
def get_all_data():
    db = get_db()
    config   = {r['key']: r['value'] for r in db.execute("SELECT * FROM config")}
    members  = [dict(r) for r in db.execute("SELECT * FROM members ORDER BY points DESC")]
    rooms    = [dict(r) for r in db.execute("SELECT * FROM rooms")]
    tasks    = [dict(r) for r in db.execute("SELECT * FROM tasks ORDER BY created_at")]
    history  = [dict(r) for r in db.execute("SELECT * FROM history ORDER BY completed_at DESC")]
    approvals= [dict(r) for r in db.execute("SELECT * FROM approvals ORDER BY requested_at DESC")]

    for m in members:
        m['owned'] = json.loads(m['owned'] or '[]')
        m['achievements'] = get_member_achievements(db, m['id'])
    for room in rooms:
        room['cleanliness'] = calc_cleanliness(room, tasks)

    return {
        'household': config.get('household', 'Moja Rodzina'),
        'members': members, 'rooms': rooms, 'tasks': tasks,
        'history': history, 'approvals': approvals,
        'badge_defs': BADGES,
    }

# ─── AUTH HELPERS ─────────────────────────────────────────────
def current_user():
    uid_val = session.get('user_id')
    if not uid_val: return None
    row = get_db().execute("SELECT * FROM users WHERE id=?", [uid_val]).fetchone()
    return dict(row) if row else None

# ─── ROUTES ───────────────────────────────────────────────────
@app.route('/')
def index():
    with open(os.path.join(os.path.dirname(__file__), 'templates', 'index.html'), encoding='utf-8') as f:
        return f.read()

@app.route('/.well-known/assetlinks.json')
def assetlinks():
    from flask import send_from_directory
    return send_from_directory(
        os.path.join(os.path.dirname(__file__), 'static', '.well-known'), 'assetlinks.json')

# ── AUTH ──────────────────────────────────────────────────────
@app.route('/api/auth/register', methods=['POST'])
def auth_register():
    d = request.json or {}
    username = d.get('username', '').strip().lower()
    password = d.get('password', '').strip()
    member_id = d.get('member_id', '')
    if not username or not password:
        return jsonify({'error': 'Podaj nazwę użytkownika i hasło'}), 400
    if len(password) < 4:
        return jsonify({'error': 'Hasło musi mieć min. 4 znaki'}), 400
    db = get_db()
    if db.execute("SELECT 1 FROM users WHERE username=?", [username]).fetchone():
        return jsonify({'error': 'Ta nazwa użytkownika jest zajęta'}), 400
    # First user = admin
    is_admin = not db.execute("SELECT 1 FROM users").fetchone()
    user_id = uid()
    db.execute("INSERT INTO users(id,username,password_hash,member_id,role,created_at) VALUES (?,?,?,?,?,?)",
               [user_id, username, hash_pw(password), member_id,
                'admin' if is_admin else 'member', datetime.now().isoformat()])
    db.commit()
    session['user_id'] = user_id
    user = dict(db.execute("SELECT * FROM users WHERE id=?", [user_id]).fetchone())
    user.pop('password_hash', None)
    return jsonify({'ok': True, 'user': user})

@app.route('/api/auth/login', methods=['POST'])
def auth_login():
    d = request.json or {}
    username = d.get('username', '').strip().lower()
    password = d.get('password', '').strip()
    db = get_db()
    row = db.execute("SELECT * FROM users WHERE username=? AND password_hash=?",
                     [username, hash_pw(password)]).fetchone()
    if not row:
        return jsonify({'error': 'Błędna nazwa użytkownika lub hasło'}), 401
    session['user_id'] = row['id']
    user = dict(row)
    user.pop('password_hash', None)
    return jsonify({'ok': True, 'user': user})

@app.route('/api/auth/logout', methods=['POST'])
def auth_logout():
    session.clear()
    return jsonify({'ok': True})

@app.route('/api/auth/me')
def auth_me():
    user = current_user()
    if not user:
        return jsonify({'user': None})
    user.pop('password_hash', None)
    return jsonify({'user': user})

@app.route('/api/auth/users')
def auth_users():
    """List all users (admin only, for linking members)."""
    rows = get_db().execute("SELECT id, username, member_id, role FROM users").fetchall()
    return jsonify([dict(r) for r in rows])

# ── DATA ──────────────────────────────────────────────────────
@app.route('/api/data')
def api_data():
    return jsonify(get_all_data())

@app.route('/api/household', methods=['PUT'])
def api_household():
    name = (request.json or {}).get('name', '').strip()
    if name:
        get_db().execute("INSERT OR REPLACE INTO config VALUES ('household',?)", [name])
        get_db().commit()
    return jsonify({'ok': True})

# ── MEMBERS ───────────────────────────────────────────────────
@app.route('/api/members', methods=['POST'])
def add_member():
    d = request.json or {}
    get_db().execute(
        "INSERT INTO members(id,name,emoji,points,coins,streak,streak_date,owned) VALUES (?,?,?,0,0,0,NULL,'[]')",
        [uid(), d['name'], d['emoji']])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/members/<mid>', methods=['DELETE'])
def del_member(mid):
    db = get_db()
    db.execute("DELETE FROM members WHERE id=?", [mid])
    db.execute("UPDATE tasks SET assigned_to='' WHERE assigned_to=?", [mid])
    db.commit()
    return jsonify({'ok': True})

# ── ROOMS ─────────────────────────────────────────────────────
@app.route('/api/rooms', methods=['POST'])
def add_room():
    d = request.json or {}
    get_db().execute(
        "INSERT INTO rooms(id,name,emoji,cleanliness,last_cleaned,color) VALUES (?,?,?,100,NULL,'#38BDF8')",
        [uid(), d['name'], d['emoji']])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/rooms/<rid>', methods=['DELETE'])
def del_room(rid):
    db = get_db()
    db.execute("DELETE FROM rooms WHERE id=?", [rid])
    db.execute("DELETE FROM tasks WHERE room_id=?", [rid])
    db.commit()
    return jsonify({'ok': True})

# ── TASKS ─────────────────────────────────────────────────────
@app.route('/api/tasks', methods=['POST'])
def add_task():
    d = request.json or {}
    get_db().execute(
        "INSERT INTO tasks(id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,NULL,?,?)",
        [uid(), d['name'], d['roomId'], d['assignedTo'], d['freq'], d['diff'],
         1 if d.get('approvalNeeded') else 0, datetime.now().isoformat()])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>', methods=['DELETE'])
def del_task(tid):
    get_db().execute("DELETE FROM tasks WHERE id=?", [tid])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>/complete', methods=['POST'])
def complete_task(tid):
    db = get_db()
    data = request.json or {}
    task = db.execute("SELECT * FROM tasks WHERE id=?", [tid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)

    member_id = data.get('memberId') or task['assigned_to']
    member = db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone()
    if not member: return jsonify({'error': 'member not found'}), 404

    if task['approval_needed']:
        if not db.execute("SELECT 1 FROM approvals WHERE task_id=?", [tid]).fetchone():
            db.execute("INSERT INTO approvals(id,task_id,member_id,requested_at) VALUES (?,?,?,?)",
                       [uid(), tid, member_id, datetime.now().isoformat()])
            db.commit()
        return jsonify({'ok': True, 'pending_approval': True})

    pts = DIFF_PTS.get(task['diff'], 1)
    now_iso = datetime.now().isoformat()
    today = datetime.now().strftime('%Y-%m-%d')
    member = dict(member)
    streak = member['streak'] + 1 if member['streak_date'] != today else member['streak']

    db.execute("UPDATE members SET points=points+?, coins=coins+?, streak=?, streak_date=? WHERE id=?",
               [pts, pts, streak, today, member_id])
    db.execute("UPDATE tasks SET last_completed=? WHERE id=?", [now_iso, tid])
    db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?), last_cleaned=? WHERE id=?",
               [min(pts*8, 22), now_iso, task['room_id']])
    db.execute("INSERT INTO history(id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?)",
               [uid(), tid, member_id, now_iso, pts, pts])
    db.commit()

    # Check room for perfect achievement
    room = db.execute("SELECT * FROM rooms WHERE id=?", [task['room_id']]).fetchone()
    all_tasks = [dict(r) for r in db.execute("SELECT * FROM tasks")]
    if room:
        cl = calc_cleanliness(dict(room), all_tasks)
        if cl >= 100:
            db.execute("INSERT OR IGNORE INTO achievements(id,member_id,badge_key,earned_at) VALUES (?,?,?,?)",
                       [uid(), member_id, 'perfect_room', now_iso])
            db.commit()

    new_badges = check_achievements(db, member_id)
    return jsonify({'ok': True, 'pts': pts, 'coins': pts, 'new_badges': new_badges})

@app.route('/api/approvals/<aid>/approve', methods=['POST'])
def approve_task(aid):
    db = get_db()
    approval = db.execute("SELECT * FROM approvals WHERE id=?", [aid]).fetchone()
    if not approval: return jsonify({'error': 'not found'}), 404
    approval = dict(approval)

    if request.json.get('approved', True):
        task = db.execute("SELECT * FROM tasks WHERE id=?", [approval['task_id']]).fetchone()
        member = db.execute("SELECT * FROM members WHERE id=?", [approval['member_id']]).fetchone()
        if task and member:
            task, member = dict(task), dict(member)
            pts = DIFF_PTS.get(task['diff'], 1)
            today = datetime.now().strftime('%Y-%m-%d')
            streak = member['streak'] if member['streak_date'] == today else member['streak'] + 1
            now_iso = datetime.now().isoformat()
            db.execute("UPDATE members SET points=points+?, coins=coins+?, streak=?, streak_date=? WHERE id=?",
                       [pts, pts, streak, today, approval['member_id']])
            db.execute("UPDATE tasks SET last_completed=? WHERE id=?", [now_iso, approval['task_id']])
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?), last_cleaned=? WHERE id=?",
                       [min(pts*8, 22), now_iso, task['room_id']])
            db.execute("INSERT INTO history VALUES (?,?,?,?,?,?)",
                       [uid(), approval['task_id'], approval['member_id'], now_iso, pts, pts])
            check_achievements(db, approval['member_id'])

    db.execute("DELETE FROM approvals WHERE id=?", [aid])
    db.commit()
    return jsonify({'ok': True})

# ── SHOP ──────────────────────────────────────────────────────
@app.route('/api/shop/buy', methods=['POST'])
def buy_item():
    db = get_db()
    d = request.json or {}
    member_id, item_id, price = d['memberId'], d['itemId'], d['price']
    member = db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone()
    if not member: return jsonify({'error': 'not found'}), 404
    member = dict(member)
    owned = json.loads(member['owned'] or '[]')
    if item_id in owned: return jsonify({'error': 'already owned'}), 400
    if member['coins'] < price: return jsonify({'error': 'insufficient coins'}), 400
    owned.append(item_id)
    db.execute("UPDATE members SET coins=coins-?, owned=? WHERE id=?",
               [price, json.dumps(owned), member_id])
    db.commit()
    return jsonify({'ok': True})

# ── LEADERBOARD ───────────────────────────────────────────────
@app.route('/api/leaderboard')
def leaderboard():
    period = request.args.get('period', 'week')
    days = {'week': 7, 'month': 30, 'all': 36500}.get(period, 7)
    cutoff = (datetime.now() - timedelta(days=days)).isoformat()
    db = get_db()
    members = [dict(r) for r in db.execute("SELECT * FROM members")]
    result = []
    for m in members:
        pts = m['points'] if period == 'all' else db.execute(
            "SELECT COALESCE(SUM(pts),0) FROM history WHERE member_id=? AND completed_at>?",
            [m['id'], cutoff]).fetchone()[0]
        m['period_pts'] = pts
        m['owned'] = json.loads(m['owned'] or '[]')
        m['achievements'] = get_member_achievements(db, m['id'])
        result.append(m)
    result.sort(key=lambda x: x['period_pts'], reverse=True)
    return jsonify(result)

# ── ACHIEVEMENTS ──────────────────────────────────────────────
@app.route('/api/achievements/<mid>')
def member_achievements(mid):
    db = get_db()
    earned = get_member_achievements(db, mid)
    all_badges = []
    for key, info in BADGES.items():
        b = dict(info)
        b['key'] = key
        b['earned'] = any(e['key'] == key for e in earned)
        b['earned_at'] = next((e['earned_at'] for e in earned if e['key'] == key), None)
        all_badges.append(b)
    return jsonify(all_badges)

# ── CALENDAR ──────────────────────────────────────────────────
@app.route('/api/calendar')
def calendar_view():
    """Return tasks mapped to days of current week."""
    db = get_db()
    tasks = [dict(r) for r in db.execute("SELECT * FROM tasks")]
    members = {r['id']: dict(r) for r in db.execute("SELECT * FROM members")}
    rooms   = {r['id']: dict(r) for r in db.execute("SELECT * FROM rooms")}
    now = datetime.now()
    week_start = now - timedelta(days=now.weekday())  # Monday

    week = []
    for i in range(7):
        day = week_start + timedelta(days=i)
        day_tasks = []
        for t in tasks:
            freq_days = FREQ_DAYS.get(t['freq'], 7)
            if t['last_completed']:
                last = datetime.fromisoformat(t['last_completed'])
                next_due = last + timedelta(days=freq_days)
            else:
                next_due = datetime.fromisoformat(t['created_at']) if t['created_at'] else now

            # Task is due on this day if next_due falls on this day ± 0.5 days
            diff_days = (day.date() - next_due.date()).days
            if -1 <= diff_days <= 0 or (freq_days == 1):  # daily always shows
                member = members.get(t['assigned_to'], {})
                room = rooms.get(t['room_id'], {})
                day_tasks.append({
                    'id': t['id'], 'name': t['name'],
                    'diff': t['diff'], 'freq': t['freq'],
                    'member_name': member.get('name','?'),
                    'member_emoji': member.get('emoji','👤'),
                    'room_name': room.get('name','?'),
                    'done': t['last_completed'] and
                            datetime.fromisoformat(t['last_completed']).date() == day.date(),
                })
        week.append({
            'date': day.strftime('%Y-%m-%d'),
            'weekday': ['Pon','Wt','Śr','Czw','Pt','Sob','Nd'][i],
            'is_today': day.date() == now.date(),
            'tasks': day_tasks,
        })
    return jsonify(week)

# ── VOICE ─────────────────────────────────────────────────────
@app.route('/api/voice', methods=['POST'])
def voice_command():
    body = request.json or {}
    transcript = body.get('transcript', '').strip().lower()
    if not transcript:
        return jsonify({'error': 'empty transcript'}), 400

    db = get_db()
    rooms   = [dict(r) for r in db.execute("SELECT id, name FROM rooms")]
    members = [dict(r) for r in db.execute("SELECT id, name FROM members")]
    tasks   = [dict(r) for r in db.execute("SELECT id, name, room_id, assigned_to FROM tasks")]

    DONE_WORDS = [
        'posprzątałem','posprzątałam','odkurzyłem','odkurzyłam','umyłem','umyłam',
        'wyczyściłem','wyczyściłam','zrobiłem','zrobiłam','skończyłem','skończyłam',
        'gotowe','zrobione','wykonałem','wykonałam','wyprałem','wyprałam',
        'pozmywałem','pozmywałam','wyniósłem','wyniosłam',
        'прибрав','прибрала','помив','помила','почистив','почистила',
        'зробив','зробила','закінчив','закінчила','пропилососив','пропилососила',
    ]
    WANT_WORDS = [
        'chcę','chce','chciałbym','chciałabym','muszę','musze','powinienem','powinnam',
        'zamierzam','planuję','planuje','będę','bede','trzeba','należy','dodaj',
        'хочу','маю','треба','потрібно','збираюся','планую','додай',
    ]
    ROOM_MAP = {
        'salon':['salon','salonie','salonu','вітальня','вітальні'],
        'kuchnia':['kuchni','kuchnia','kuchnię','кухня','кухні'],
        'łazienka':['łazienka','łazienki','łazience','ванна','ванній','ванну'],
        'sypialnia':['sypialnia','sypialni','спальня','спальні'],
        'toaleta':['toaleta','toalety','toalecie','туалет','туалеті'],
        'balkon':['balkon','balkonie','балкон'],
    }
    TASK_MAP = {
        'odkurzanie':['odkurzyć','odkurz','пилосос','пилососити'],
        'zmywanie naczyń':['zmyć','zmywanie','naczynia','помити посуд'],
        'mycie podłóg':['podłogi','podłogę','mop','помити підлогу'],
        'mycie toalety':['toaletę','umyć toaletę','туалет помити'],
        'wycieranie kurzu':['kurz','wytrzeć','витерти пил'],
        'wyniesienie śmieci':['śmieci','śmietnik','wynieść','винести сміття'],
        'pranie':['pranie','prać','wypra','постирати'],
        'mycie okien':['okna','okien','помити вікна'],
        'sprzątanie':['posprzątać','sprzątać','прибирання','прибрати'],
    }

    def find_member(text):
        """Find member by name mention in text."""
        for m in members:
            if m['name'].lower() in text:
                return m
        # Check logged-in user
        user = current_user()
        if user and user.get('member_id'):
            for m in members:
                if m['id'] == user['member_id']:
                    return m
        return members[0] if members else None

    def find_room(text):
        for room in rooms:
            if room['name'].lower() in text: return room
        for key, aliases in ROOM_MAP.items():
            if any(a in text for a in aliases):
                for room in rooms:
                    if key in room['name'].lower(): return room
                return rooms[0] if rooms else None
        return rooms[0] if rooms else None

    def find_task(text):
        best, score = None, 0
        for t in tasks:
            s = sum(1 for w in t['name'].lower().split() if w in text)
            for aliases in TASK_MAP.values():
                s += sum(1 for a in aliases if a in text)
            if s > score: score, best = s, t
        return best

    def guess_task_name(text):
        for name, aliases in TASK_MAP.items():
            if any(a in text for a in aliases):
                return name.capitalize()
        return 'Sprzątanie'

    is_done = any(w in transcript for w in DONE_WORDS)
    is_want = any(w in transcript for w in WANT_WORDS)
    actor = find_member(transcript)

    if is_done:
        matched = find_task(transcript)
        if matched:
            task = dict(db.execute("SELECT * FROM tasks WHERE id=?", [matched['id']]).fetchone())
            member_id = actor['id'] if actor else task['assigned_to']
            pts = DIFF_PTS.get(task['diff'], 1)
            today = datetime.now().strftime('%Y-%m-%d')
            now_iso = datetime.now().isoformat()
            member = db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone()
            if member:
                m = dict(member)
                streak = m['streak'] + 1 if m['streak_date'] != today else m['streak']
                db.execute("UPDATE members SET points=points+?,coins=coins+?,streak=?,streak_date=? WHERE id=?",
                           [pts, pts, streak, today, member_id])
            db.execute("UPDATE tasks SET last_completed=? WHERE id=?", [now_iso, matched['id']])
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?),last_cleaned=? WHERE id=?",
                       [min(pts*8, 22), now_iso, task['room_id']])
            db.execute("INSERT INTO history(id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?)",
                       [uid(), matched['id'], member_id, now_iso, pts, pts])
            db.commit()
            new_badges = check_achievements(db, member_id)
            who = actor['name'] if actor else '?'
            return jsonify({'action':'complete_task',
                            'message':f'✅ {who} wykonał(a) "{matched["name"]}"! +{pts} pkt',
                            'new_badges': new_badges})
        return jsonify({'action':'unknown','message':'Nie znalazłem pasującego zadania. Dodaj je najpierw.'})

    elif is_want:
        room = find_room(transcript)
        task_name = guess_task_name(transcript)
        member_id = actor['id'] if actor else (members[0]['id'] if members else '')
        room_id = room['id'] if room else (rooms[0]['id'] if rooms else '')
        db.execute("INSERT INTO tasks(id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,NULL,0,?)",
                   [uid(), task_name, room_id, member_id, 'weekly', 'medium', datetime.now().isoformat()])
        db.commit()
        return jsonify({'action':'add_task',
                        'message':f'➕ Dodano "{task_name}" w pokoju {room["name"] if room else ""}!'})

    return jsonify({'action':'unknown','message':'Nie rozumiem. Powiedz np. "Chcę odkurzyć salon" lub "Posprzątałem kuchnię".'})

# ── CONFIG ────────────────────────────────────────────────────
@app.route('/api/config/apikey', methods=['POST'])
def set_api_key():
    key = (request.json or {}).get('key', '').strip()
    get_db().execute("INSERT OR REPLACE INTO config VALUES ('api_key',?)", [key])
    get_db().commit()
    return jsonify({'ok': True})

if __name__ == '__main__':
    _ensure_db()
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
