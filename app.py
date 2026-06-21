import sqlite3
import json
import hashlib
import random
import string
import secrets
from datetime import datetime, timedelta
from flask import Flask, jsonify, request, g, session
import os

app = Flask(__name__)
# Use the SECRET_KEY env var in production. If it is missing, fall back to a
# random per-process key (no secret is hard-coded in the source).
app.secret_key = os.environ.get('SECRET_KEY') or secrets.token_hex(32)

if os.environ.get('RAILWAY_ENVIRONMENT') or os.environ.get('RENDER'):
    # Use persistent volume if available, fallback to /tmp
    _data_dir = os.environ.get('RAILWAY_VOLUME_MOUNT_PATH', '/tmp')
    DB = os.path.join(_data_dir, 'sweepy.db')
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
            last_completed TEXT, approval_needed INTEGER DEFAULT 0, created_at TEXT,
            specific_days TEXT DEFAULT NULL
        );
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            task_id TEXT, member_id TEXT,
            completed_at TEXT, pts INTEGER, coins_earned INTEGER,
            type TEXT DEFAULT 'done'
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
        CREATE TABLE IF NOT EXISTS goals (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            emoji TEXT DEFAULT '🎯',
            price INTEGER NOT NULL,
            created_by TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS goal_purchases (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL,
            goal_id TEXT NOT NULL,
            member_id TEXT NOT NULL,
            purchased_at TEXT,
            fulfilled INTEGER DEFAULT 0
        );
    ''')
    db.commit()
    for migration in [
        "ALTER TABLE tasks ADD COLUMN specific_days TEXT DEFAULT NULL",
        "ALTER TABLE history ADD COLUMN type TEXT DEFAULT 'done'",
        "ALTER TABLE tasks ADD COLUMN one_time INTEGER DEFAULT 0",
    ]:
        try:
            db.execute(migration)
            db.commit()
        except Exception:
            pass
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
def cleanup_one_time(db, household_id):
    """Remove one-time tasks completed on a previous day. They remain visible in
    'Done' on their completion day, then disappear. last_completed is stored as a
    naive ISO string (YYYY-MM-DD...), so a date-prefix string compare is safe."""
    today = datetime.now().strftime('%Y-%m-%d')
    db.execute(
        "DELETE FROM tasks WHERE household_id=? AND COALESCE(one_time,0)=1 "
        "AND last_completed IS NOT NULL AND substr(last_completed,1,10) < ?",
        [household_id, today])
    db.commit()

def get_all_data(household_id):
    db = get_db()
    cleanup_one_time(db, household_id)
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

    goals = [dict(r) for r in db.execute(
        "SELECT * FROM goals WHERE household_id=? ORDER BY created_at DESC", [household_id])]
    goal_purchases = [dict(r) for r in db.execute(
        "SELECT gp.*, m.name as member_name, m.emoji as member_emoji "
        "FROM goal_purchases gp JOIN members m ON gp.member_id=m.id "
        "WHERE gp.household_id=? ORDER BY gp.purchased_at DESC", [household_id])]

    # Attach purchases to each goal
    for g in goals:
        g['purchases'] = [p for p in goal_purchases if p['goal_id'] == g['id']]

    # Get original creator (earliest admin)
    admin_user = db.execute(
        "SELECT member_id FROM users WHERE household_id=? AND role='admin' ORDER BY created_at ASC LIMIT 1",
        [household_id]).fetchone()

    # Get roles for all members who have accounts
    member_users = db.execute(
        "SELECT member_id, role FROM users WHERE household_id=?", [household_id]).fetchall()
    members_roles = {r['member_id']: r['role'] for r in member_users}

    return {
        'household': config.get('household', household['name'] if household else 'Moja Rodzina'),
        'household_token': household['token'] if household else '',
        'household_admin_member': admin_user['member_id'] if admin_user else None,
        'members_roles': members_roles,
        'members': members, 'rooms': rooms, 'tasks': tasks,
        'history': history, 'approvals': approvals, 'goals': goals,
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

# ── HOUSEHOLD LOOKUP (public, no auth needed) ─────────────────
@app.route('/api/household/lookup')
def household_lookup():
    token = request.args.get('token', '').strip().upper()
    if len(token) != 6:
        return jsonify({'error': 'invalid token'}), 400
    db = get_db()
    hh = db.execute("SELECT * FROM households WHERE token=?", [token]).fetchone()
    if not hh:
        return jsonify({'error': 'Nie znaleziono rodziny z tym kodem'}), 404
    hh = dict(hh)
    members = [{'id': r['id'], 'name': r['name'], 'emoji': r['emoji']}
               for r in db.execute("SELECT id,name,emoji FROM members WHERE household_id=?", [hh['id']])]
    return jsonify({'name': hh['name'], 'token': hh['token'], 'members': members})

# ── AUTH ──────────────────────────────────────────────────────
MEMBER_EMOJIS = ['😊','😎','🤩','🥳','😄','🦸','🧑','👦','👧','👨','👩','🧔','👴','👵','🐱','🐶','🦊','🐸','🐼','🦁']

@app.route('/api/auth/register', methods=['POST'])
def auth_register():
    d = request.json or {}
    username     = d.get('username', '').strip().lower()
    password     = d.get('password', '').strip()
    display_name = d.get('display_name', '').strip()
    action       = d.get('action', 'create')  # 'create' or 'join'
    token        = d.get('token', '').strip().upper()
    hname        = d.get('household_name', 'Moja Rodzina').strip()
    chosen_emoji = d.get('emoji', '').strip()
    member_id    = d.get('member_id', '').strip()  # for join: pick existing member

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
        # Verify the member belongs to this household and isn't claimed yet
        if not member_id:
            return jsonify({'error': 'Wybierz swojego domownika z listy'}), 400
        mbr = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, household_id]).fetchone()
        if not mbr:
            return jsonify({'error': 'Nie znaleziono domownika'}), 404
        if db.execute("SELECT 1 FROM users WHERE member_id=? AND household_id=?", [member_id, household_id]).fetchone():
            return jsonify({'error': 'Ten domownik ma już konto — zaloguj się'}), 400
    else:
        # Create new household
        if not display_name:
            display_name = username
        household_id = uid()
        new_token = gen_token()
        while db.execute("SELECT 1 FROM households WHERE token=?", [new_token]).fetchone():
            new_token = gen_token()
        db.execute("INSERT INTO households(id,name,token,created_at) VALUES (?,?,?,?)",
                   [household_id, hname, new_token, datetime.now().isoformat()])
        db.execute("INSERT OR REPLACE INTO config(key,household_id,value) VALUES ('household',?,?)",
                   [household_id, hname])
        role = 'admin'
        # Auto-create member profile for the owner
        import random
        emoji = chosen_emoji if chosen_emoji else random.choice(MEMBER_EMOJIS)
        member_id = uid()
        db.execute(
            "INSERT INTO members(id,household_id,name,emoji,points,coins,streak,streak_date,owned) VALUES (?,?,?,?,0,0,0,NULL,'[]')",
            [member_id, household_id, display_name, emoji]
        )

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
    u = current_user()
    data = get_all_data(get_hid())
    data['current_user'] = {k: u[k] for k in ('id','username','household_id','member_id','role') if k in u} if u else {}
    return jsonify(data)

@app.route('/api/household', methods=['PUT'])
def api_household():
    err = require_auth(); hid = get_hid()
    if err: return err
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel może zmienić nazwę rodziny'}), 403
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
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel może dodawać domowników'}), 403
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
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel może usuwać domowników'}), 403
    db = get_db()
    # Find original creator member_id
    creator = db.execute(
        "SELECT member_id FROM users WHERE household_id=? AND role='admin' ORDER BY created_at ASC LIMIT 1",
        [hid]).fetchone()
    if creator and creator['member_id'] == mid:
        return jsonify({'error': 'Nie można usunąć twórcy rodziny'}), 403
    db.execute("DELETE FROM members WHERE id=? AND household_id=?", [mid, hid])
    db.execute("UPDATE tasks SET assigned_to='' WHERE assigned_to=? AND household_id=?", [mid, hid])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/members/<mid>/role', methods=['PUT'])
def set_member_role(mid):
    err = require_auth(); hid = get_hid()
    if err: return err
    if not is_owner(hid):
        return jsonify({'error': 'Tylko właściciel może zmieniać role'}), 403
    db = get_db()
    # Prevent changing original creator's role
    creator = db.execute(
        "SELECT member_id FROM users WHERE household_id=? AND role='admin' ORDER BY created_at ASC LIMIT 1",
        [hid]).fetchone()
    d = request.json or {}
    new_role = d.get('role', 'member')
    if new_role not in ('admin', 'member'):
        return jsonify({'error': 'Nieprawidłowa rola'}), 400
    # Find user linked to this member
    target_user = db.execute(
        "SELECT id FROM users WHERE member_id=? AND household_id=?", [mid, hid]).fetchone()
    if not target_user:
        return jsonify({'error': 'Ten domownik nie ma konta'}), 404
    # Cannot demote original creator
    if creator and creator['member_id'] == mid and new_role != 'admin':
        return jsonify({'error': 'Nie można zmienić roli twórcy rodziny'}), 403
    db.execute("UPDATE users SET role=? WHERE id=?", [new_role, target_user['id']])
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
    specific_days = d.get('specificDays')  # e.g. "0,2,4" = Mon,Wed,Fri or None
    if specific_days and not isinstance(specific_days, str):
        specific_days = ','.join(str(x) for x in specific_days)
    freq = d.get('freq', 'weekly') if not specific_days else 'custom'
    one_time = 1 if d.get('oneTime') else 0
    db = get_db()
    db.execute(
        "INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at,specific_days,one_time) VALUES (?,?,?,?,?,?,?,NULL,?,?,?,?)",
        [uid(), hid, d['name'], d['roomId'], d['assignedTo'], freq, d['diff'],
         1 if d.get('approvalNeeded') else 0, datetime.now().isoformat(), specific_days, one_time])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>/expire', methods=['POST'])
def expire_task(tid):
    """Mark a task as missed/expired — advance cycle without awarding points."""
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)
    now_iso = datetime.now().isoformat()

    # Advance last_completed so the task resets to the next cycle
    db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?", [now_iso, tid, hid])
    # Log as missed (type='missed', 0 pts)
    member_id = task['assigned_to'] or ''
    db.execute(
        "INSERT INTO history(id,household_id,task_id,member_id,completed_at,pts,coins_earned,type) VALUES (?,?,?,?,?,0,0,'missed')",
        [uid(), hid, tid, member_id, now_iso])
    db.commit()
    return jsonify({'ok': True, 'missed': True})

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
    u = current_user()
    member_id = data.get('memberId') or task['assigned_to'] or (u.get('member_id') if u else None)
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if not member:
        # fallback: first member of household
        member = db.execute("SELECT * FROM members WHERE household_id=? ORDER BY created_at ASC LIMIT 1", [hid]).fetchone()
    if not member: return jsonify({'error': 'member not found'}), 404
    member_id = member['id']

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
    # One-time tasks stay visible in "Done" for the rest of the day; they are
    # swept the next day by cleanup_one_time() (called from get_all_data).
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
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel lub admin może zatwierdzać'}), 403
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
        admin_row = db.execute("SELECT 1 FROM users WHERE household_id=? AND member_id=? AND role='admin'", [hid, m['id']]).fetchone()
        m['is_admin'] = bool(admin_row)
        result.append(m)
    result.sort(key=lambda x: x['period_pts'], reverse=True)
    return jsonify(result)

# ── STATS ─────────────────────────────────────────────────────
@app.route('/api/stats')
def api_stats():
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()

    # Last 28 days activity heatmap (per day count of completed tasks)
    cutoff28 = (datetime.now() - timedelta(days=28)).isoformat()
    rows = db.execute(
        "SELECT DATE(completed_at) as day, COUNT(*) as cnt FROM history "
        "WHERE household_id=? AND completed_at>? AND type='done' GROUP BY day",
        [hid, cutoff28]).fetchall()
    heatmap = {r['day']: r['cnt'] for r in rows}

    # This week stats
    cutoff7 = (datetime.now() - timedelta(days=7)).isoformat()
    week_done = db.execute(
        "SELECT COUNT(*) FROM history WHERE household_id=? AND completed_at>? AND type='done'",
        [hid, cutoff7]).fetchone()[0]
    week_pts = db.execute(
        "SELECT COALESCE(SUM(pts),0) FROM history WHERE household_id=? AND completed_at>? AND type='done'",
        [hid, cutoff7]).fetchone()[0]

    # Most active member this week
    top_row = db.execute(
        "SELECT member_id, COUNT(*) as cnt FROM history "
        "WHERE household_id=? AND completed_at>? AND type='done' GROUP BY member_id ORDER BY cnt DESC LIMIT 1",
        [hid, cutoff7]).fetchone()
    top_member = None
    if top_row:
        m = db.execute("SELECT name, emoji FROM members WHERE id=? AND household_id=?",
                       [top_row['member_id'], hid]).fetchone()
        if m:
            top_member = {'name': m['name'], 'emoji': m['emoji'], 'count': top_row['cnt']}

    # Family streak — consecutive days with at least one task done
    streak = 0
    check_day = datetime.now().date()
    for _ in range(365):
        day_str = check_day.strftime('%Y-%m-%d')
        cnt = db.execute(
            "SELECT COUNT(*) FROM history WHERE household_id=? AND DATE(completed_at)=? AND type='done'",
            [hid, day_str]).fetchone()[0]
        if cnt == 0:
            break
        streak += 1
        check_day -= timedelta(days=1)

    # Per-member activity (last 28 days) for member profile
    member_activity = {}
    for r in db.execute(
        "SELECT member_id, DATE(completed_at) as day, COUNT(*) as cnt FROM history "
        "WHERE household_id=? AND completed_at>? AND type='done' GROUP BY member_id, day",
        [hid, cutoff28]).fetchall():
        member_activity.setdefault(r['member_id'], {})[r['day']] = r['cnt']

    return jsonify({
        'heatmap': heatmap,
        'week_done': week_done,
        'week_pts': week_pts,
        'top_member': top_member,
        'family_streak': streak,
        'member_activity': member_activity,
    })

# ── CALENDAR ──────────────────────────────────────────────────
@app.route('/api/calendar')
def calendar_view():
    import calendar as cal_mod
    err = require_auth(); hid = get_hid()
    if err: return err
    db  = get_db()
    now = datetime.now()
    year  = int(request.args.get('year',  now.year))
    month = int(request.args.get('month', now.month))

    tasks   = [dict(r) for r in db.execute("SELECT * FROM tasks WHERE household_id=?", [hid])]
    members = {r['id']: dict(r) for r in db.execute("SELECT * FROM members WHERE household_id=?", [hid])}
    rooms   = {r['id']: dict(r) for r in db.execute("SELECT * FROM rooms WHERE household_id=?", [hid])}
    history = [dict(r) for r in db.execute(
        "SELECT task_id, completed_at FROM history WHERE household_id=? AND completed_at LIKE ?",
        [hid, f'{year}-{month:02d}%'])]
    done_dates = {}
    for h in history:
        d = h['completed_at'][:10]
        done_dates.setdefault(d, set()).add(h['task_id'])

    days_in_month = cal_mod.monthrange(year, month)[1]
    result = []
    for day_num in range(1, days_in_month + 1):
        day = datetime(year, month, day_num)
        day_iso = day.strftime('%Y-%m-%d')
        # weekday: Mon=0 .. Sun=6
        day_dow = day.weekday()
        day_tasks = []
        for t in tasks:
            created = datetime.fromisoformat(t['created_at']) if t['created_at'] else now
            if created.date() > day.date():
                continue
            member = members.get(t['assigned_to'], {})
            room   = rooms.get(t['room_id'], {})

            if t.get('specific_days'):
                # show only on the chosen weekdays
                chosen = [int(x) for x in t['specific_days'].split(',') if x.strip().isdigit()]
                if day_dow not in chosen:
                    continue
            else:
                freq_days = FREQ_DAYS.get(t['freq'], 7)
                if t['last_completed']:
                    last = datetime.fromisoformat(t['last_completed'])
                    next_due = last + timedelta(days=freq_days)
                else:
                    next_due = created
                diff = (day.date() - next_due.date()).days
                if not (0 <= diff < freq_days or freq_days == 1):
                    continue

            day_tasks.append({
                'id': t['id'], 'name': t['name'], 'diff': t['diff'], 'freq': t['freq'],
                'specific_days': t.get('specific_days'),
                'member_name': member.get('name', '?'), 'member_emoji': member.get('emoji', '👤'),
                'room_name': room.get('name', '?'),
                'done': t['id'] in done_dates.get(day_iso, set()),
            })
        result.append({'date': day_iso, 'is_today': day.date() == now.date(), 'tasks': day_tasks})
    return jsonify(result)

# ── GOALS ─────────────────────────────────────────────────────
def is_admin(hid):
    u = current_user()
    return u and u['role'] == 'admin' and u['household_id'] == hid

def is_owner(hid):
    """True only for the household creator (earliest admin). Owner-only powers:
    delete goals, assign/change the admin role."""
    u = current_user()
    if not u or not u.get('member_id'):
        return False
    creator = get_db().execute(
        "SELECT member_id FROM users WHERE household_id=? AND role='admin' "
        "ORDER BY created_at ASC LIMIT 1", [hid]).fetchone()
    return bool(creator) and creator['member_id'] == u['member_id']

@app.route('/api/goals', methods=['POST'])
def create_goal():
    err = require_auth(); hid = get_hid()
    if err: return err
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel może tworzyć cele'}), 403
    d = request.json or {}
    name  = d.get('name', '').strip()
    price = int(d.get('price', 0))
    if not name or price < 1:
        return jsonify({'error': 'Podaj nazwę i cenę'}), 400
    u = current_user()
    db = get_db()
    db.execute(
        "INSERT INTO goals(id,household_id,name,description,emoji,price,created_by,created_at) VALUES (?,?,?,?,?,?,?,?)",
        [uid(), hid, name, d.get('description',''), d.get('emoji','🎯'), price,
         u['member_id'] or '', datetime.now().isoformat()])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/goals/<gid>', methods=['DELETE'])
def delete_goal(gid):
    err = require_auth(); hid = get_hid()
    if err: return err
    if not is_owner(hid):
        return jsonify({'error': 'Tylko właściciel może usuwać cele'}), 403
    db = get_db()
    db.execute("DELETE FROM goal_purchases WHERE goal_id=? AND household_id=?", [gid, hid])
    db.execute("DELETE FROM goals WHERE id=? AND household_id=?", [gid, hid])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/goals/<gid>/buy', methods=['POST'])
def buy_goal(gid):
    err = require_auth(); hid = get_hid()
    if err: return err
    u = current_user()
    member_id = (request.json or {}).get('memberId') or u.get('member_id')
    if not member_id:
        return jsonify({'error': 'Nie jesteś połączony z profilem domownika'}), 400
    db = get_db()
    goal = db.execute("SELECT * FROM goals WHERE id=? AND household_id=?", [gid, hid]).fetchone()
    if not goal: return jsonify({'error': 'Nie znaleziono celu'}), 404
    goal = dict(goal)
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if not member: return jsonify({'error': 'Nie znaleziono profilu'}), 404
    member = dict(member)
    if member['coins'] < goal['price']:
        return jsonify({'error': f'Za mało monet! Masz {member["coins"]}🪙, potrzebujesz {goal["price"]}🪙'}), 400
    db.execute("UPDATE members SET coins=coins-? WHERE id=? AND household_id=?",
               [goal['price'], member_id, hid])
    db.execute("INSERT INTO goal_purchases(id,household_id,goal_id,member_id,purchased_at,fulfilled) VALUES (?,?,?,?,?,0)",
               [uid(), hid, gid, member_id, datetime.now().isoformat()])
    db.commit()
    return jsonify({'ok': True, 'coins_left': member['coins'] - goal['price']})

@app.route('/api/goal-purchases/<pid>/fulfill', methods=['POST'])
def fulfill_purchase(pid):
    err = require_auth(); hid = get_hid()
    if err: return err
    if not is_admin(hid):
        return jsonify({'error': 'Tylko właściciel może oznaczać jako zrealizowane'}), 403
    db = get_db()
    db.execute("UPDATE goal_purchases SET fulfilled=1 WHERE id=? AND household_id=?", [pid, hid])
    db.commit()
    return jsonify({'ok': True})

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
        # English
        'cleaned','washed','vacuumed','wiped','did','finished','done','completed',
        'tidied','mopped','swept','took out','i have',
    ]
    WANT_WORDS = [
        'chcę','chce','chciałbym','chciałabym','muszę','musze','powinienem','powinnam',
        'zamierzam','planuję','będę','trzeba','należy','dodaj',
        'хочу','маю','треба','потрібно','збираюся','планую','додай',
        # English
        'want','need','should','will','add','have to','gonna','going to',"i'll",
    ]
    ROOM_MAP = {
        'salon':['salon','salonie','вітальня','living room','living','lounge'],
        'kuchnia':['kuchni','kuchnia','кухня','kitchen'],
        'łazienka':['łazienka','łazienki','ванна','bathroom','bath'],
        'sypialnia':['sypialnia','sypialni','спальня','bedroom'],
        'toaleta':['toaleta','toalety','туалет','toilet'],
    }
    TASK_MAP = {
        'odkurzanie':['odkurzyć','odkurz','пилосос','vacuum','hoover'],
        'zmywanie naczyń':['zmyć','naczynia','посуд','dishes','wash dishes','dishwasher'],
        'mycie podłóg':['podłogi','podłogę','підлогу','floor','floors','mop'],
        'wycieranie kurzu':['kurz','пил','dust'],
        'wyniesienie śmieci':['śmieci','сміття','trash','garbage','rubbish','bin'],
        'pranie':['pranie','прання','laundry','washing'],
        'mycie okien':['okna','вікна','window','windows'],
        'sprzątanie':['posprzątać','спrzątać','прибирання','clean','tidy','tidy up'],
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
