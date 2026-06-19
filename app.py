import sqlite3
import json
import math
from datetime import datetime, timedelta
from flask import Flask, jsonify, request, g
import os
import anthropic

app = Flask(__name__)

ANTHROPIC_API_KEY = os.environ.get('ANTHROPIC_API_KEY', '')
# Use /tmp on Railway (read-only filesystem), local dir otherwise
if os.environ.get('RAILWAY_ENVIRONMENT') or os.environ.get('RENDER'):
    DB = '/tmp/sweepy.db'
else:
    DB = os.path.join(os.path.dirname(__file__), 'sweepy.db')

# Always init DB tables (works with both gunicorn and direct run)
def _ensure_db():
    db = sqlite3.connect(DB)
    db.executescript('''
        CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS members (id TEXT PRIMARY KEY, name TEXT, emoji TEXT, points INTEGER DEFAULT 0, coins INTEGER DEFAULT 0, streak INTEGER DEFAULT 0, streak_date TEXT, owned TEXT DEFAULT '[]');
        CREATE TABLE IF NOT EXISTS rooms (id TEXT PRIMARY KEY, name TEXT, emoji TEXT, cleanliness INTEGER DEFAULT 100, last_cleaned TEXT, color TEXT DEFAULT '#38BDF8');
        CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, name TEXT, room_id TEXT, assigned_to TEXT, freq TEXT DEFAULT 'weekly', diff TEXT DEFAULT 'medium', last_completed TEXT, approval_needed INTEGER DEFAULT 0, created_at TEXT);
        CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, task_id TEXT, member_id TEXT, completed_at TEXT, pts INTEGER, coins_earned INTEGER);
        CREATE TABLE IF NOT EXISTS approvals (id TEXT PRIMARY KEY, task_id TEXT, member_id TEXT, requested_at TEXT);
    ''')
    db.commit()
    db.close()

_ensure_db()

# ─── DB ───────────────────────────────────────────────────────────────────────
def get_db():
    if 'db' not in g:
        g.db = sqlite3.connect(DB, detect_types=sqlite3.PARSE_DECLTYPES)
        g.db.row_factory = sqlite3.Row
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    db = g.pop('db', None)
    if db: db.close()

def init_db():
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
    ''')
    # Seed config
    if not db.execute("SELECT 1 FROM config WHERE key='household'").fetchone():
        db.execute("INSERT INTO config VALUES ('household','Moja Rodzina')")
    # Seed members
    if not db.execute("SELECT 1 FROM members").fetchone():
        import uuid
        members = [
            ('m1','Mama','👩',340,85,5,'2024-01-10','["c8","c9"]'),
            ('m2','Tata','👨',210,52,3,'2024-01-09','["c8"]'),
            ('m3','Kasia','😊',480,120,8,'2024-01-10','["c8","c9","c10","c11"]'),
        ]
        db.executemany("INSERT INTO members VALUES (?,?,?,?,?,?,?,?)", members)
        rooms = [
            ('r1','Salon','🛋️',72,(datetime.now()-timedelta(days=2)).isoformat(),'#22C55E'),
            ('r2','Kuchnia','🍽️',48,(datetime.now()-timedelta(days=4)).isoformat(),'#F59E0B'),
            ('r3','Łazienka','🚿',30,(datetime.now()-timedelta(days=6)).isoformat(),'#EF4444'),
            ('r4','Sypialnia','🛏️',85,(datetime.now()-timedelta(days=1)).isoformat(),'#38BDF8'),
        ]
        db.executemany("INSERT INTO rooms VALUES (?,?,?,?,?,?)", rooms)
        tasks = [
            ('t1','Odkurzanie','r1','m1','weekly','medium',None,0,datetime.now().isoformat()),
            ('t2','Zmywanie naczyń','r2','m2','daily','easy',None,0,datetime.now().isoformat()),
            ('t3','Mycie toalety','r3','m3','weekly','medium',None,0,datetime.now().isoformat()),
            ('t4','Wycieranie kurzu','r4','m1','every2','easy',None,0,datetime.now().isoformat()),
            ('t5','Mycie podłóg','r2','m3','weekly','hard',None,0,datetime.now().isoformat()),
            ('t6','Mycie okien','r1','m2','monthly','hard',None,0,datetime.now().isoformat()),
        ]
        db.executemany("INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?)", tasks)
    db.commit()
    db.close()

# ─── HELPERS ──────────────────────────────────────────────────────────────────
FREQ_DAYS = {'daily':1,'every2':2,'weekly':7,'biweekly':14,'monthly':30}
DIFF_PTS  = {'easy':1,'medium':2,'hard':3}

def uid():
    import uuid
    return str(uuid.uuid4())[:8]

def is_due(task):
    if not task['last_completed']:
        return True
    last = datetime.fromisoformat(task['last_completed'])
    days = FREQ_DAYS.get(task['freq'], 7)
    return (datetime.now() - last).total_seconds() >= days * 86400

def calc_cleanliness(room, tasks):
    """Decrease cleanliness based on overdue tasks."""
    base = room['cleanliness']
    now = datetime.now()
    room_tasks = [t for t in tasks if t['room_id'] == room['id']]
    for t in room_tasks:
        freq_days = FREQ_DAYS.get(t['freq'], 7)
        pts = DIFF_PTS.get(t['diff'], 1)
        if t['last_completed']:
            days_since = (now - datetime.fromisoformat(t['last_completed'])).days
        else:
            days_since = freq_days * 2
        if days_since > freq_days:
            overdue = min(days_since - freq_days, freq_days * 2)
            decay = (overdue / freq_days) * pts * 4
            base = max(0, base - decay)
    return round(min(100, max(0, base)))

def row_to_dict(row):
    return dict(row)

def get_all_data():
    db = get_db()
    config  = {r['key']: r['value'] for r in db.execute("SELECT * FROM config")}
    members = [dict(r) for r in db.execute("SELECT * FROM members ORDER BY points DESC")]
    for m in members:
        m['owned'] = json.loads(m['owned'] or '[]')
    rooms   = [dict(r) for r in db.execute("SELECT * FROM rooms")]
    tasks   = [dict(r) for r in db.execute("SELECT * FROM tasks ORDER BY created_at")]
    history = [dict(r) for r in db.execute("SELECT * FROM history ORDER BY completed_at DESC")]
    approvals = [dict(r) for r in db.execute("SELECT * FROM approvals ORDER BY requested_at DESC")]

    # Recalc cleanliness
    for room in rooms:
        room['cleanliness'] = calc_cleanliness(room, tasks)

    return {
        'household': config.get('household', 'Moja Rodzina'),
        'members': members,
        'rooms': rooms,
        'tasks': tasks,
        'history': history,
        'approvals': approvals,
    }

# ─── ROUTES ───────────────────────────────────────────────────────────────────
@app.route('/')
def index():
    with open(os.path.join(os.path.dirname(__file__), 'templates', 'index.html'), encoding='utf-8') as f:
        return f.read()

@app.route('/.well-known/assetlinks.json')
def assetlinks():
    from flask import send_from_directory
    return send_from_directory(os.path.join(os.path.dirname(__file__), 'static', '.well-known'), 'assetlinks.json')

@app.route('/api/data')
def api_data():
    return jsonify(get_all_data())

@app.route('/api/household', methods=['PUT'])
def api_household():
    name = request.json.get('name','').strip()
    if name:
        get_db().execute("INSERT OR REPLACE INTO config VALUES ('household',?)", [name])
        get_db().commit()
    return jsonify({'ok': True})

# Members
@app.route('/api/members', methods=['POST'])
def add_member():
    d = request.json
    get_db().execute("INSERT INTO members(id,name,emoji,points,coins,streak,streak_date,owned) VALUES (?,?,?,0,0,0,NULL,'[]')",
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

# Rooms
@app.route('/api/rooms', methods=['POST'])
def add_room():
    d = request.json
    get_db().execute("INSERT INTO rooms(id,name,emoji,cleanliness,last_cleaned,color) VALUES (?,?,?,100,NULL,'#38BDF8')",
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

# Tasks
@app.route('/api/tasks', methods=['POST'])
def add_task():
    d = request.json
    get_db().execute("INSERT INTO tasks(id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,NULL,?,?)",
                     [uid(), d['name'], d['roomId'], d['assignedTo'],
                      d['freq'], d['diff'], 1 if d.get('approvalNeeded') else 0,
                      datetime.now().isoformat()])
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
    if not task:
        return jsonify({'error': 'not found'}), 404
    task = dict(task)

    member_id = data.get('memberId') or task['assigned_to']
    member = db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone()
    if not member:
        return jsonify({'error': 'member not found'}), 404

    # Approval needed?
    if task['approval_needed']:
        existing = db.execute("SELECT 1 FROM approvals WHERE task_id=?", [tid]).fetchone()
        if not existing:
            db.execute("INSERT INTO approvals(id,task_id,member_id,requested_at) VALUES (?,?,?,?)",
                       [uid(), tid, member_id, datetime.now().isoformat()])
            db.commit()
        return jsonify({'ok': True, 'pending_approval': True})

    pts = DIFF_PTS.get(task['diff'], 1)
    coins = pts
    now_iso = datetime.now().isoformat()

    # Streak
    today = datetime.now().strftime('%Y-%m-%d')
    streak = member['streak']
    if member['streak_date'] != today:
        streak = member['streak'] + 1

    # Update member
    db.execute("UPDATE members SET points=points+?, coins=coins+?, streak=?, streak_date=? WHERE id=?",
               [pts, coins, streak, today, member_id])
    # Update task
    db.execute("UPDATE tasks SET last_completed=? WHERE id=?", [now_iso, tid])
    # Update room cleanliness (boost)
    boost = min(pts * 8, 22)
    db.execute("UPDATE rooms SET cleanliness=MIN(100, cleanliness+?), last_cleaned=? WHERE id=?",
               [boost, now_iso, task['room_id']])
    # History entry
    db.execute("INSERT INTO history(id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?)",
               [uid(), tid, member_id, now_iso, pts, coins])
    db.commit()
    return jsonify({'ok': True, 'pts': pts, 'coins': coins})

@app.route('/api/approvals/<aid>/approve', methods=['POST'])
def approve_task(aid):
    db = get_db()
    approval = db.execute("SELECT * FROM approvals WHERE id=?", [aid]).fetchone()
    if not approval:
        return jsonify({'error': 'not found'}), 404
    approval = dict(approval)
    approved = request.json.get('approved', True)

    if approved:
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
            boost = min(pts * 8, 22)
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?), last_cleaned=? WHERE id=?",
                       [boost, now_iso, task['room_id']])
            db.execute("INSERT INTO history VALUES (?,?,?,?,?,?)",
                       [uid(), approval['task_id'], approval['member_id'], now_iso, pts, pts])

    db.execute("DELETE FROM approvals WHERE id=?", [aid])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/shop/buy', methods=['POST'])
def buy_item():
    db = get_db()
    d = request.json
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

@app.route('/api/leaderboard')
def leaderboard():
    period = request.args.get('period', 'week')
    days = {'week': 7, 'month': 30, 'all': 36500}.get(period, 7)
    cutoff = (datetime.now() - timedelta(days=days)).isoformat()
    db = get_db()
    members = [dict(r) for r in db.execute("SELECT * FROM members")]
    result = []
    for m in members:
        if period == 'all':
            pts = m['points']
        else:
            pts = db.execute("SELECT COALESCE(SUM(pts),0) FROM history WHERE member_id=? AND completed_at>?",
                             [m['id'], cutoff]).fetchone()[0]
        m['period_pts'] = pts
        m['owned'] = json.loads(m['owned'] or '[]')
        result.append(m)
    result.sort(key=lambda x: x['period_pts'], reverse=True)
    return jsonify(result)

@app.route('/api/voice', methods=['POST'])
def voice_command():
    """Process voice command with Claude AI and execute action."""
    body = request.json or {}
    transcript = body.get('transcript', '').strip()
    lang = body.get('lang', 'pl')
    if not transcript:
        return jsonify({'error': 'empty transcript'}), 400

    if not ANTHROPIC_API_KEY:
        return jsonify({'error': 'no_api_key', 'message': 'Brak klucza API Anthropic. Ustaw go w Ustawieniach.'}), 400

    db = get_db()
    rooms   = [dict(r) for r in db.execute("SELECT id, name FROM rooms")]
    members = [dict(r) for r in db.execute("SELECT id, name FROM members")]
    tasks   = [dict(r) for r in db.execute("SELECT id, name, room_id, assigned_to, last_completed FROM tasks")]

    rooms_list   = ', '.join([f"{r['name']} (id:{r['id']})" for r in rooms])
    members_list = ', '.join([f"{m['name']} (id:{m['id']})" for m in members])
    tasks_list   = '\n'.join([f"- {t['name']} (id:{t['id']}, pokój:{t['room_id']})" for t in tasks])

    system_prompt = """Jesteś asystentem zarządzającym listą domowych obowiązków (chores app).
Rozumiesz języki: polski i ukraiński.
Analizujesz polecenie głosowe i zwracasz JSON z akcją do wykonania.

Dostępne akcje:
1. add_task – dodaj nowe zadanie
2. complete_task – oznacz zadanie jako wykonane (gdy ktoś mówi że coś zrobił/sprzątnął/odkurzył itp.)
3. add_room – dodaj nowy pokój
4. unknown – nie rozumiem polecenia

Odpowiadaj WYŁĄCZNIE w formacie JSON, bez żadnego dodatkowego tekstu:

Dla add_task:
{"action": "add_task", "task_name": "...", "room_id": "...", "member_id": "...", "freq": "weekly", "diff": "medium", "message": "krótki opis po polsku co zrobiłeś"}

Dla complete_task:
{"action": "complete_task", "task_id": "...", "message": "..."}

Dla add_room:
{"action": "add_room", "room_name": "...", "emoji": "🏠", "message": "..."}

Dla unknown:
{"action": "unknown", "message": "Nie rozumiem polecenia. Spróbuj powiedzieć np. 'Chcę posprzątać salon' lub 'Odkurzyłem salon'."}

Zasady:
- Jeśli ktoś mówi że CHCE coś zrobić / ma zamiar / planuje → add_task
- Jeśli ktoś mówi że JUŻ zrobił / skończył / posprzątał / odkurzył / umył itp. → complete_task
- Dopasuj room_id do najbliższego pasującego pokoju z listy
- Dopasuj member_id jeśli wspomniano imię, inaczej użyj pierwszego z listy
- freq: daily/every2/weekly/biweekly/monthly
- diff: easy/medium/hard"""

    user_prompt = f"""Polecenie głosowe: "{transcript}"

Dostępne pokoje: {rooms_list}
Dostępne osoby: {members_list}
Dostępne zadania:
{tasks_list}

Zwróć JSON z akcją."""

    try:
        client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        msg = client.messages.create(
            model='claude-haiku-4-5-20251001',
            max_tokens=512,
            system=system_prompt,
            messages=[{'role': 'user', 'content': user_prompt}]
        )
        raw = msg.content[0].text.strip()
        # Extract JSON if wrapped in markdown
        if '```' in raw:
            raw = raw.split('```')[1].strip()
            if raw.startswith('json'): raw = raw[4:].strip()
        result = json.loads(raw)
    except json.JSONDecodeError:
        return jsonify({'error': 'parse_error', 'raw': raw}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

    # Execute action
    action = result.get('action')
    if action == 'add_task':
        room_id     = result.get('room_id') or (rooms[0]['id'] if rooms else '')
        member_id   = result.get('member_id') or (members[0]['id'] if members else '')
        task_name   = result.get('task_name', 'Nowe zadanie')
        freq        = result.get('freq', 'weekly')
        diff        = result.get('diff', 'medium')
        task_id = uid()
        db.execute("INSERT INTO tasks(id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at) VALUES (?,?,?,?,?,?,NULL,0,?)",
                   [task_id, task_name, room_id, member_id, freq, diff, datetime.now().isoformat()])
        db.commit()
        result['executed'] = True

    elif action == 'complete_task':
        task_id = result.get('task_id')
        task = None
        if task_id:
            task = db.execute("SELECT * FROM tasks WHERE id=?", [task_id]).fetchone()
        if task:
            task = dict(task)
            pts = DIFF_PTS.get(task['diff'], 1)
            member_id = task['assigned_to']
            member = db.execute("SELECT * FROM members WHERE id=?", [member_id]).fetchone()
            today = datetime.now().strftime('%Y-%m-%d')
            if member:
                m = dict(member)
                streak = m['streak'] if m['streak_date'] == today else m['streak'] + 1
                db.execute("UPDATE members SET points=points+?,coins=coins+?,streak=?,streak_date=? WHERE id=?",
                           [pts, pts, streak, today, member_id])
            db.execute("UPDATE tasks SET last_completed=? WHERE id=?", [datetime.now().isoformat(), task_id])
            boost = min(pts*8, 22)
            db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?),last_cleaned=? WHERE id=?",
                       [boost, datetime.now().isoformat(), task['room_id']])
            db.execute("INSERT INTO history(id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?)",
                       [uid(), task_id, member_id, datetime.now().isoformat(), pts, pts])
            db.commit()
            result['executed'] = True
            result['pts_earned'] = pts

    elif action == 'add_room':
        room_name = result.get('room_name', 'Nowy pokój')
        emoji = result.get('emoji', '🏠')
        db.execute("INSERT INTO rooms(id,name,emoji,cleanliness,last_cleaned,color) VALUES (?,?,?,100,NULL,'#38BDF8')",
                   [uid(), room_name, emoji])
        db.commit()
        result['executed'] = True

    return jsonify(result)


@app.route('/api/config/apikey', methods=['POST'])
def set_api_key():
    global ANTHROPIC_API_KEY
    key = request.json.get('key', '').strip()
    ANTHROPIC_API_KEY = key
    # Save to config table
    get_db().execute("INSERT OR REPLACE INTO config VALUES ('api_key',?)", [key])
    get_db().commit()
    return jsonify({'ok': True})


if __name__ == '__main__':
    init_db()
    # Load saved API key
    db = sqlite3.connect(DB)
    row = db.execute("SELECT value FROM config WHERE key='api_key'").fetchone()
    if row and row[0]:
        ANTHROPIC_API_KEY = row[0]
    db.close()
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
