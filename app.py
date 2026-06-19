import sqlite3
import json
import hashlib
import random
import string
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
        CREATE TABLE IF NOT EXISTS households (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            token TEXT UNIQUE NOT NULL,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            household_id TEXT NOT NULL,
            member_id TEXT,
            role TEXT DEFAULT 'member',
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS members (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            name TEXT, emoji TEXT,
            points INTEGER DEFAULT 0, coins INTEGER DEFAULT 0,
            streak INTEGER DEFAULT 0, streak_date TEXT, owned TEXT DEFAULT '[]'
        );
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            name TEXT, emoji TEXT,
            cleanliness INTEGER DEFAULT 100, last_cleaned TEXT, color TEXT DEFAULT '#38BDF8'
        );
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            name TEXT, room_id TEXT, assigned_to TEXT,
            freq TEXT DEFAULT 'weekly', diff TEXT DEFAULT 'medium',
            last_completed TEXT, approval_needed INTEGER DEFAULT 0, created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            task_id TEXT, member_id TEXT,
            completed_at TEXT, pts INTEGER, coins_earned INTEGER
        );
        CREATE TABLE IF NOT EXISTS approvals (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            task_id TEXT, member_id TEXT, requested_at TEXT
        );
        CREATE TABLE IF NOT EXISTS config (
            key TEXT NOT NULL, household_id TEXT NOT NULL, value TEXT,
            PRIMARY KEY (key, household_id)
        );
        CREATE TABLE IF NOT EXISTS achievements (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            member_id TEXT NOT NULL,
            badge_key TEXT NOT NULL,
            earned_at TEXT,
            UNIQUE(member_id, badge_key)
        );
    ''')
    db.commit()
    db.close()

_ensure_db()

# ─── DB ───────────────────────────────────────────────────────
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

def gen_token():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

# ─── AUTH HELPERS ─────────────────────────────────────────────
def current_user():
    uid_val = session.get('user_id')
    if not uid_val: return None
    row = get_db().execute("SELECT * FROM users WHERE id=?", [uid_val]).fetchone()
    return dict(row) if row else None

def get_hid():
    """Get current household_id, or None if not logged in."""
    u = current_user()
    return u['household_id'] if u else None

def require_auth():
    u = current_user()
    if not u:
        return jsonify({'error': 'not_logged_in'}), 401
    return None

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
def check_achievements(db, member_id, household_id):
    existing = {r['badge_key'] for r in db.execute(
        "SELECT badge_key FROM achievements WHERE member_id=? AND household_id=?",
        [member_id, household_id])}
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?",
                        [member_id, household_id]).fetchone()
    if not member: return []
    member = dict(member)
    new_badges = []
    today = datetime.now().strftime('%Y-%m-%d')
    hour = datetime.now().hour

    total_tasks = db.execute("SELECT COUNT(*) FROM history WHERE member_id=? AND household_id=?",
                             [member_id, household_id]).fetchone()[0]
    today_tasks = db.execute("SELECT COUNT(*) FROM history WHERE member_id=? AND household_id=? AND completed_at LIKE ?",
                             [member_id, household_id, today+'%']).fetchone()[0]
    hard_tasks = db.execute(
        "SELECT COUNT(*) FROM history h JOIN tasks t ON h.task_id=t.id WHERE h.member_id=? AND h.household_id=? AND t.diff='hard'",
        [member_id, household_id]).fetchone()[0]

    checks = {
        'first_step':  total_tasks >= 1,
        'streak_3':    member['streak'] >= 3,
        'streak_7':    member['streak'] >= 7,
        'streak_30':   member['streak'] >= 30,
        'tasks_10':    total_tasks >= 10,
        'tasks_50':    total_tasks >= 50,
        'tasks_100':   total_tasks >= 100,
        'daily_5':     today_tasks >= 5,
        'hard_worker': hard_tasks >= 5,
        'early_bird':  hour < 9,
        'night_owl':   hour >= 22,
    }
    for key, earned in checks.items():
        if earned and key not in existing:
            db.execute("INSERT OR IGNORE INTO achievements(id,household_id,member_id,badge_key,earned_at) VALUES (?,?,?,?,?)",
                       [uid(), household_id, member_id, key, datetime.now().isoformat()])
            new_badges.append(key)

    cutoff_week  = (datetime.now() - timedelta(days=7)).isoformat()
    cutoff_month = (datetime.now() - timedelta(days=30)).isoformat()
    for badge, cutoff in [('week_champ', cutoff_week), ('month_champ', cutoff_month)]:
        if badge in existing: continue
        row = db.execute(
            "SELECT member_id, SUM(pts) as s FROM history WHERE household_id=? AND completed_at>? GROUP BY member_id ORDER BY s DESC LIMIT 1",
            [household_id, cutoff]).fetchone()
        if row and row['member_id'] == member_id and row['s'] >= 10:
            db.execute("INSERT OR IGNORE INTO achievements(id,household_id,member_id,badge_key,earned_at) VALUES (?,?,?,?,?)",
                       [uid(), household_id, member_id, badge, datetime.now().isoformat()])
            new_badges.append(badge)

    db.commit()
    return new_badges

def get_member_achievements(db, member_id, household_id):
    rows = db.execute(
        "SELECT badge_key, earned_at FROM achievements WHERE member_id=? AND household_id=? ORDER BY earned_at",
        [member_id, household_id]).fetchall()
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
def calc_cleanliness(room, tasks):
    base = room['cleanliness']
    now = datetime.now()
    for t in [t for t in tasks if t['room_id'] == room['id']]:
        freq_days = FREQ_DAYS.get(t['freq'], 7)
        pts = DIFF_PTS.get(t['diff'], 1)
        days_since = (now - datetime.fromisoformat(t['last_completed'])).days if t['last_completed'] else freq_days * 2
        if days_since > freq_days:
            base = max(0, base - (min(days_since - freq_days, freq_days*2) / freq_days) * pts * 4)
    return round(min(100, max(0, base)))

# ─── DATA ─────────────────────────────────────────────────────
def get_all_data(household_id):
    db = get_db()
    config   = {r['key']: r['value'] for r in db.execute(
        "SELECT key, value FROM config WHERE household_id=?", [household_id])}
    members  = [dict(r) for r in db.execute(
        "SELECT * FROM members WHERE household_id=? ORDER BY points DESC", [household_id])]
    rooms    = [dict(r) for r in db.execute(
        "SELECT * FROM rooms WHERE household_id=?", [household_id])]
    tasks    = [dict(r) for r in db.execute(
        "SELECT * FROM tasks WHERE household_id=? ORDER BY created_at", [household_id])]
    history  = [dict(r) for r in db.execute(
        "SELECT * FROM history WHERE household_id=? ORDER BY completed_at DESC", [household_id])]
    approvals= [dict(r) for r in db.execute(
        "SELECT * FROM approvals WHERE household_id=? ORDER BY requested_at DESC", [household_id])]
    household = db.execute("SELECT * FROM households WHERE id=?", [household_id]).fetchone()

    for m in members:
        m['owned'] = json.loads(m['owned'] or '[]')
        m['achievements'] = get_member_achievements(db, m['id'], household_id)
    for room in rooms:
        room['cleanliness'] = calc_cleanliness(room, tasks)

    return {
        'household': config.get('household', household['name'] if household else 'Moja Rodzina'),
        'household_token': household['token'] if household else '',
        'members': members, 'rooms': rooms, 'tasks': tasks,
        'history': history, 'approvals': approvals,
    }

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
    username  = d.get('username', '').strip().lower()
    password  = d.get('password', '').strip()
    action    = d.get('action', 'create')  # 'create' or 'join'
    token     = d.get('token', '').strip().upper()
    hname     = d.get('household_name', 'Moja Rodzina').strip()
    member_id = d.get('member_id', '')

    if not username or not password:
        return jsonify({'error': 'Podaj nazwę użytkownika i hasło'}), 400
    if len(password) < 4:
        return jsonify({'error': 'Hasło musi mieć min. 4 znaki'}), 400

    db = get_db()
    if db.execute("SELECT 1 FROM users WHERE username=?", [username]).fetchone():
        return jsonify({'error': 'Ta nazwa użytkownika jest już zajęta'}), 400

    if action == 'join':
        household = db.execute("SELECT * FROM households WHERE token=?", [token]).fetchone()
        if not household:
            return jsonify({'error': f'Nie znaleziono rodziny z kodem "{token}"'}), 404
        household_id = household['id']
        role = 'member'
    else:
        # Create new household
        household_id = uid()
        new_token = gen_token()
        while db.execute("SELECT 1 FROM households WHERE token=?", [new_token]).fetchone():
            new_token = gen_token()
        db.execute("INSERT INTO households(id,name,token,created_at) VALUES (?,?,?,?)",
                   [household_id, hname, new_token, datetime.now().isoformat()])
        db.execute("INSERT OR REPLACE INTO config(key,household_id,value) VALUES ('household',?,?)",
                   [household_id, hname])
        role = 'admin'

    user_id = uid()
    db.execute("INSERT INTO users(id,username,password_hash,household_id,member_id,role,created_at) VALUES (?,?,?,?,?,?,?)",
               [user_id, username, hash_pw(password), household_id, member_id, role, datetime.now().isoformat()])
    db.commit()
    session['user_id'] = user_id
    user = dict(db.execute("SELECT id,username,household_id,member_id,role FROM users WHERE id=?", [user_id]).fetchone())
    household = dict(db.execute("SELECT * FROM households WHERE id=?", [household_id]).fetchone())
    return jsonify({'ok': True, 'user': user, 'household': household})

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
    user = dict(db.execute("SELECT id,username,household_id,member_id,role FROM users WHERE id=?",
                            [row['id']]).fetchone())
    household = dict(db.execute("SELECT * FROM households WHERE id=?", [user['household_id']]).fetchone())
    return jsonify({'ok': True, 'user': user, 'household': household})

@app.route('/api/auth/logout', methods=['POST'])
def auth_logout():
    session.clear()
    return jsonify({'ok': True})

@app.route('/api/auth/me')
def auth_me():
    user = current_user()
    if not user:
        return jsonify({'user': None})
    u = {k: v for k, v in user.items() if k != 'password_hash'}
    hh = get_db().execute("SELECT * FROM households WHERE id=?", [user['household_id']]).fetchone()
    return jsonify({'user': u, 'household': dict(hh) if hh else None})

# ── DATA ──────────────────────────────────────────────────────
@app.route('/api/data')
def api_data():
    err = require_auth()
    if err: return err
    return jsonify(get_all_data(get_hid()))

@app.route('/api/household', methods=['PUT'])
def api_household():
    err = require_auth(); hid = get_hid()
    if err: return err
    name = (request.json or {}).get('name', '').strip()
    if name:
        db = get_db()
        db.execute("INSERT OR REPLACE INTO config(key,household_id,value) VALUES ('household',?,?)", [hid, name])
        db.execute("UPDATE households SET name=? WHERE id=?", [name, hid])
        db.commit()
    return jsonify({'ok': True})

# ── MEMBERS ───────────────────────────────────────────────────
@app.route('/api/members', methods=['POST'])
def add_member():
    err = require_auth(); hid = get_hid()
    if err: return err
    d = request.json or {}
    get_db().execute(
        "INSERT INTO members(id,household_id,name,emoji,points,coins,streak,streak_date,owned) VALUES (?,?,?,?,0,0,0,NULL,'[]')",
        [uid(), hid, d['name'], d['emoji']])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/members/<mid>', methods=['DELETE'])
def del_member(mid):
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    db.execute("DELETE FROM members WHERE id=? AND household_id=?", [mid, hid])
    db.execute("UPDATE tasks SET assigned_to='' WHERE assigned_to=? AND household_id=?", [mid, hid])
    db.commit()
    return jsonify({'ok': True})

# ── ROOMS ─────────────────────────────────────────────────────
@app.route('/api/rooms', methods=['POST'])
def add_room():
    err = require_auth(); hid = get_hid()
    if err: return err
    d = request.json or {}
    get_db().execute(
        "INSERT INTO rooms(id,household_id,name,emoji,cleanliness,last_cleaned,color) VALUES (?,?,?,?,100,NULL,'#38BDF8')",
        [uid(), hid, d['name'], d['emoji']])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/rooms/<rid>', methods=['DELETE'])
def del_room(rid):
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    db.execute("DELETE FROM rooms WHERE id=? AND household_id=?", [rid, hid])
    db.execute("DELETE FROM tasks WHERE room_id=? AND household_id=?", [rid, hid])
    db.commit()
    return jsonify({'ok': True})

# ── TASKS ─────────────────────────────────────────────────────
@app.route('/api/tasks', methods=['POST'])
def add_task():
    err = require_auth(); hid = get_hid()
    if err: return err
    d = request.json or {}
    get_db().execute(
        "INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,?,NULL,?,?)",
        [uid(), hid, d['name'], d['roomId'], d['assignedTo'], d['freq'], d['diff'],
         1 if d.get('approvalNeeded') else 0, datetime.now().isoformat()])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>', methods=['DELETE'])
def del_task(tid):
    err = require_auth(); hid = get_hid()
    if err: return err
    get_db().execute("DELETE FROM tasks WHERE id=? AND household_id=?", [tid, hid])
    get_db().commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>/complete', methods=['POST'])
def complete_task(tid):
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    data = request.json or {}
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)
    member_id = data.get('memberId') or task['assigned_to']
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if not member: return jsonify({'error': 'member not found'}), 404

    if task['approval_needed']:
        if not db.execute("SELECT 1 FROM approvals WHERE task_id=? AND household_id=?", [tid, hid]).fetchone():
            db.execute("INSERT INTO approvals(id,household_id,task_id,member_id,requested_at) VALUES (?,?,?,?,?)",
                       [uid(), hid, tid, member_id, datetime.now().isoformat()])
            db.commit()
        return jsonify({'ok': True, 'pending_approval': True})

    pts = DIFF_PTS.get(task['diff'], 1)
    now_iso = datetime.now().isoformat()
    today = datetime.now().strftime('%Y-%m-%d')
    member = dict(member)
    streak = member['streak'] + 1 if member['streak_date'] != today else member['streak']

    db.execute("UPDATE members SET points=points+?, coins=coins+?, streak=?, streak_date=? WHERE id=? AND household_id=?",
               [pts, pts, streak, today, member_id, hid])
    db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?", [now_iso, tid, hid])
    db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?), last_cleaned=? WHERE id=? AND household_id=?",
               [min(pts*8, 22), now_iso, task['room_id'], hid])
    db.execute("INSERT INTO history(id,household_id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?,?)",
               [uid(), hid, tid, member_id, now_iso, pts, pts])
    db.commit()

    all_tasks = [dict(r) for r in db.execute("SELECT * FROM tasks WHERE household_id=?", [hid])]
    room = db.execute("SELECT * FROM rooms WHERE id=? AND household_id=?", [task['room_id'], hid]).fetchone()
    if room and calc_cleanliness(dict(room), all_tasks) >= 100:
        db.execute("INSERT OR IGNORE INTO achievements(id,household_id,member_id,badge_key,earned_at) VALUES (?,?,?,?,?)",
                   [uid(), hid, member_id, 'perfect_room', now_iso])
        db.commit()

    new_badges = check_achievements(db, member_id, hid)
    return jsonify({'ok': True, 'pts': pts, 'coins': pts, 'new_badges': new_badges})

@app.route('/api/approvals/<aid>/approve', methods=['POST'])
def approve_task(aid):
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    approval = db.execute("SELECT * FROM approvals WHERE id=? AND household_id=?", [aid, hid]).fetchone()
    if not approval: return jsonify({'error': 'not found'}), 404
    approval = dict(approval)
    if (request.json or {}).get('approved', True):
        task   = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [approval['task_id'], hid]).fetchone()
        member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [approval['member_id'], hid]).fetchone()
        if task and member:
            task, member = dict(task), dict(member)
            pts = DIFF_PTS.get(task['diff'], 1)
            today = datetime.now().strftime('%Y-%m-%d')
            streak = member['streak'] if member['streak_date'] == today else member['streak'] + 1
            now_iso = datetime.now().isoformat()
            db.execute("UPDATE members SET points=points+?, coins=coins+?, streak=?, streak_date=? WHERE id=? AND household_id=?",
                       [pts, pts, streak, today, approval['member_id'], hid])
            db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?", [now_iso, approval['task_id'], hid])
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?), last_cleaned=? WHERE id=? AND household_id=?",
                       [min(pts*8, 22), now_iso, task['room_id'], hid])
            db.execute("INSERT INTO history(id,household_id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?,?)",
                       [uid(), hid, approval['task_id'], approval['member_id'], now_iso, pts, pts])
            check_achievements(db, approval['member_id'], hid)
    db.execute("DELETE FROM approvals WHERE id=? AND household_id=?", [aid, hid])
    db.commit()
    return jsonify({'ok': True})

# ── SHOP ──────────────────────────────────────────────────────
@app.route('/api/shop/buy', methods=['POST'])
def buy_item():
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    d = request.json or {}
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [d['memberId'], hid]).fetchone()
    if not member: return jsonify({'error': 'not found'}), 404
    member = dict(member)
    owned = json.loads(member['owned'] or '[]')
    if d['itemId'] in owned: return jsonify({'error': 'already owned'}), 400
    if member['coins'] < d['price']: return jsonify({'error': 'insufficient coins'}), 400
    owned.append(d['itemId'])
    db.execute("UPDATE members SET coins=coins-?, owned=? WHERE id=? AND household_id=?",
               [d['price'], json.dumps(owned), d['memberId'], hid])
    db.commit()
    return jsonify({'ok': True})

# ── LEADERBOARD ───────────────────────────────────────────────
@app.route('/api/leaderboard')
def leaderboard():
    err = require_auth(); hid = get_hid()
    if err: return err
    period = request.args.get('period', 'week')
    days = {'week': 7, 'month': 30, 'all': 36500}.get(period, 7)
    cutoff = (datetime.now() - timedelta(days=days)).isoformat()
    db = get_db()
    members = [dict(r) for r in db.execute("SELECT * FROM members WHERE household_id=?", [hid])]
    result = []
    for m in members:
        pts = m['points'] if period == 'all' else db.execute(
            "SELECT COALESCE(SUM(pts),0) FROM history WHERE member_id=? AND household_id=? AND completed_at>?",
            [m['id'], hid, cutoff]).fetchone()[0]
        m['period_pts'] = pts
        m['owned'] = json.loads(m['owned'] or '[]')
        m['achievements'] = get_member_achievements(db, m['id'], hid)
        result.append(m)
    result.sort(key=lambda x: x['period_pts'], reverse=True)
    return jsonify(result)

# ── CALENDAR ──────────────────────────────────────────────────
@app.route('/api/calendar')
def calendar_view():
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    tasks   = [dict(r) for r in db.execute("SELECT * FROM tasks WHERE household_id=?", [hid])]
    members = {r['id']: dict(r) for r in db.execute("SELECT * FROM members WHERE household_id=?", [hid])}
    rooms   = {r['id']: dict(r) for r in db.execute("SELECT * FROM rooms WHERE household_id=?", [hid])}
    now = datetime.now()
    week_start = now - timedelta(days=now.weekday())
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
            diff_days = (day.date() - next_due.date()).days
            if -1 <= diff_days <= 0 or freq_days == 1:
                member = members.get(t['assigned_to'], {})
                room   = rooms.get(t['room_id'], {})
                day_tasks.append({
                    'id': t['id'], 'name': t['name'], 'diff': t['diff'], 'freq': t['freq'],
                    'member_name': member.get('name','?'), 'member_emoji': member.get('emoji','👤'),
                    'room_name': room.get('name','?'),
                    'done': bool(t['last_completed'] and
                                 datetime.fromisoformat(t['last_completed']).date() == day.date()),
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
    err = require_auth(); hid = get_hid()
    if err: return err
    body = request.json or {}
    transcript = body.get('transcript', '').strip().lower()
    if not transcript:
        return jsonify({'error': 'empty transcript'}), 400

    db = get_db()
    rooms   = [dict(r) for r in db.execute("SELECT id, name FROM rooms WHERE household_id=?", [hid])]
    members = [dict(r) for r in db.execute("SELECT id, name FROM members WHERE household_id=?", [hid])]
    tasks   = [dict(r) for r in db.execute("SELECT id, name, room_id, assigned_to FROM tasks WHERE household_id=?", [hid])]

    DONE_WORDS = [
        'posprzątałem','posprzątałam','odkurzyłem','odkurzyłam','umyłem','umyłam',
        'wyczyściłem','wyczyściłam','zrobiłem','zrobiłam','skończyłem','skończyłam',
        'gotowe','zrobione','wykonałem','wykonałam','wyprałem','wyprałam',
        'pozmywałem','pozmywałam','wyniósłem','wyniosłam',
        'прибрав','прибрала','помив','помила','почистив','почистила',
        'зробив','зробила','закінчив','закінчила',
    ]
    WANT_WORDS = [
        'chcę','chce','chciałbym','chciałabym','muszę','musze','powinienem','powinnam',
        'zamierzam','planuję','będę','trzeba','należy','dodaj',
        'хочу','маю','треба','потрібно','збираюся','планую','додай',
    ]
    ROOM_MAP = {
        'salon':['salon','salonie','вітальня'],
        'kuchnia':['kuchni','kuchnia','кухня'],
        'łazienka':['łazienka','łazienki','ванна'],
        'sypialnia':['sypialnia','sypialni','спальня'],
        'toaleta':['toaleta','toalety','туалет'],
    }
    TASK_MAP = {
        'odkurzanie':['odkurzyć','odkurz','пилосос'],
        'zmywanie naczyń':['zmyć','naczynia','посуд'],
        'mycie podłóg':['podłogi','podłogę','підлогу'],
        'wycieranie kurzu':['kurz','пил'],
        'wyniesienie śmieci':['śmieci','сміття'],
        'pranie':['pranie','прання'],
        'mycie okien':['okna','вікна'],
        'sprzątanie':['posprzątać','спrzątać','прибирання'],
    }

    def find_member(text):
        for m in members:
            if m['name'].lower() in text: return m
        u = current_user()
        if u and u.get('member_id'):
            for m in members:
                if m['id'] == u['member_id']: return m
        return members[0] if members else None

    def find_room(text):
        for room in rooms:
            if room['name'].lower() in text: return room
        for key, aliases in ROOM_MAP.items():
            if any(a in text for a in aliases):
                for room in rooms:
                    if key in room['name'].lower(): return room
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
            if any(a in text for a in aliases): return name.capitalize()
        return 'Sprzątanie'

    is_done = any(w in transcript for w in DONE_WORDS)
    is_want = any(w in transcript for w in WANT_WORDS)
    actor = find_member(transcript)

    if is_done:
        matched = find_task(transcript)
        if matched:
            task = dict(db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [matched['id'], hid]).fetchone())
            member_id = actor['id'] if actor else task['assigned_to']
            pts = DIFF_PTS.get(task['diff'], 1)
            today = datetime.now().strftime('%Y-%m-%d')
            now_iso = datetime.now().isoformat()
            member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
            if member:
                m = dict(member)
                streak = m['streak'] + 1 if m['streak_date'] != today else m['streak']
                db.execute("UPDATE members SET points=points+?,coins=coins+?,streak=?,streak_date=? WHERE id=? AND household_id=?",
                           [pts, pts, streak, today, member_id, hid])
            db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?", [now_iso, matched['id'], hid])
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?),last_cleaned=? WHERE id=? AND household_id=?",
                       [min(pts*8,22), now_iso, task['room_id'], hid])
            db.execute("INSERT INTO history(id,household_id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?,?)",
                       [uid(), hid, matched['id'], member_id, now_iso, pts, pts])
            db.commit()
            new_badges = check_achievements(db, member_id, hid)
            who = actor['name'] if actor else '?'
            return jsonify({'action':'complete_task',
                            'message':f'✅ {who} wykonał(a) "{matched["name"]}"! +{pts} pkt',
                            'new_badges': new_badges})
        return jsonify({'action':'unknown','message':'Nie znalazłem pasującego zadania.'})

    elif is_want:
        room = find_room(transcript)
        task_name = guess_task_name(transcript)
        member_id = actor['id'] if actor else (members[0]['id'] if members else '')
        room_id = room['id'] if room else (rooms[0]['id'] if rooms else '')
        db.execute("INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,?,NULL,0,?)",
                   [uid(), hid, task_name, room_id, member_id, 'weekly', 'medium', datetime.now().isoformat()])
        db.commit()
        return jsonify({'action':'add_task',
                        'message':f'➕ Dodano "{task_name}" w pokoju {room["name"] if room else ""}!'})

    return jsonify({'action':'unknown','message':'Nie rozumiem. Powiedz np. "Chcę odkurzyć salon".'})

if __name__ == '__main__':
    _ensure_db()
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
