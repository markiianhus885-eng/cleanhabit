import sqlite3
import json
import hashlib
import random
import string
import secrets
import smtplib
import time
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta, date
from flask import Flask, jsonify, request, g, session
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.middleware.proxy_fix import ProxyFix
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
import os

app = Flask(__name__)
# Behind the Cloudflare tunnel/cloudflared, trust one proxy hop so request.is_secure
# reflects X-Forwarded-Proto (https) and remote_addr reflects the real client IP
# (X-Forwarded-For) — needed for Secure cookies and per-IP rate limiting.
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

# Use the SECRET_KEY env var in production. If it is missing, fall back to a
# random per-process key (no secret is hard-coded in the source).
app.secret_key = os.environ.get('SECRET_KEY') or secrets.token_hex(32)

# Harden the session cookie. SESSION_COOKIE_SECURE defaults on (primary access is
# HTTPS via Cloudflare). For plain-HTTP LAN access (http://<pi>:5000) set
# COOKIE_SECURE=0 in the environment, otherwise the browser will drop the cookie.
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE='Lax',
    SESSION_COOKIE_SECURE=os.environ.get('COOKIE_SECURE', '1') == '1',
)

# Basic per-IP rate limiting (in-memory). Guards brute-force on login and abuse of
# the Claude-backed /api/voice endpoint, which spends the owner's API credits.
try:
    from flask_limiter import Limiter
    from flask_limiter.util import get_remote_address
    limiter = Limiter(key_func=get_remote_address, app=app, default_limits=[])
except Exception:  # pragma: no cover - if the package is missing, no-op decorator
    class _NoLimit:
        def limit(self, *a, **k):
            def deco(f):
                return f
            return deco
    limiter = _NoLimit()

if os.environ.get('DATABASE_PATH'):
    DB = os.environ['DATABASE_PATH']
else:
    DB = os.path.join(os.path.dirname(__file__), 'sweepy.db')

# Single-kiosk RFID scan state (see rfid_last_scan table): device posts a
# scan, a kiosk browser polls for it and performs its own login. Shared
# secret gates the device endpoint since, unlike password login, a bare UID
# is trivial to guess/replay.
RFID_SCAN_SECRET = os.environ.get('RFID_SCAN_SECRET', '')

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
        -- Single-row table holding the most recent RFID card scan. Backed by
        -- SQLite (not an in-process dict) because gunicorn runs multiple
        -- worker processes that don't share memory.
        CREATE TABLE IF NOT EXISTS rfid_last_scan (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            card_uid TEXT,
            ts REAL
        );
    ''')
    db.commit()
    for migration in [
        "ALTER TABLE tasks ADD COLUMN specific_days TEXT DEFAULT NULL",
        "ALTER TABLE history ADD COLUMN type TEXT DEFAULT 'done'",
        "ALTER TABLE tasks ADD COLUMN one_time INTEGER DEFAULT 0",
        "ALTER TABLE users ADD COLUMN email TEXT",
        """CREATE TABLE IF NOT EXISTS reset_tokens (
            token TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            expires_at TEXT NOT NULL
        )""",
        # Holds a pending registration until the email's ownership is
        # confirmed via a 6-digit code; the account itself isn't created
        # until /api/auth/verify-email succeeds.
        """CREATE TABLE IF NOT EXISTS email_verifications (
            email TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            payload TEXT NOT NULL
        )""",
        # Belt-and-suspenders for the app-level duplicate-email check in
        # register(): only non-empty emails are constrained, so legacy
        # accounts created before email collection (NULL/'') don't collide.
        """CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
            ON users(email) WHERE email IS NOT NULL AND email != ''""",
        # Tester/user feedback submitted from the public /feedback page.
        """CREATE TABLE IF NOT EXISTS feedback (
            id TEXT PRIMARY KEY,
            email TEXT,
            category TEXT,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL
        )""",
        # Physical RFID card UID linked to this account, for the RC522/ESP32
        # reader kiosk login flow (see /api/rfid/*, /api/auth/login-rfid).
        "ALTER TABLE users ADD COLUMN rfid_uid TEXT",
        """CREATE UNIQUE INDEX IF NOT EXISTS idx_users_rfid_uid_unique
            ON users(rfid_uid) WHERE rfid_uid IS NOT NULL AND rfid_uid != ''""",
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
    """Legacy unsalted SHA-256 — kept only to verify old accounts before upgrade."""
    return hashlib.sha256(pw.encode()).hexdigest()

def make_pw(pw):
    """Create a salted password hash for new/updated passwords."""
    return generate_password_hash(pw)

def verify_pw(stored, pw):
    """Verify a password against either the new salted hash or a legacy SHA-256.
    Returns (ok, needs_upgrade)."""
    if not stored:
        return False, False
    if stored.startswith(('pbkdf2:', 'scrypt:', 'argon2')):
        return check_password_hash(stored, pw), False
    # Legacy: constant-time compare of unsalted SHA-256, flag for rehash on success.
    ok = secrets.compare_digest(stored, hash_pw(pw))
    return ok, ok

def gen_token():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

# Google Sign-In: both the web (Google Identity Services) and Android
# (google_sign_in with serverClientId set to this same value) issue ID
# tokens audienced for the *web* OAuth client, so this is the only client
# ID the backend needs to verify against.
GOOGLE_WEB_CLIENT_ID = os.environ.get(
    'GOOGLE_WEB_CLIENT_ID',
    '957970436165-nddupot9otscvlm15ual30fagrkfaj5b.apps.googleusercontent.com')

MAIL_FROM    = os.environ.get('MAIL_FROM',    'cleanhabit@myroapp.org')
MAIL_USER    = os.environ.get('MAIL_USER',    'markiianhus885@gmail.com')
MAIL_PASS    = os.environ.get('MAIL_PASS',    '')
MAIL_NAME    = os.environ.get('MAIL_NAME',    'CleanHabit')

def send_email(to: str, subject: str, html: str):
    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From']    = f'{MAIL_NAME} <{MAIL_FROM}>'
    msg['To']      = to
    msg.attach(MIMEText(html, 'html', 'utf-8'))
    with smtplib.SMTP('smtp.gmail.com', 587) as s:
        s.starttls()
        s.login(MAIL_USER, MAIL_PASS)
        s.sendmail(MAIL_FROM, to, msg.as_string())

def send_reset_email(to: str, code: str):
    html = f"""
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px">
      <div style="text-align:center;margin-bottom:24px">
        <span style="font-size:48px">🏠</span>
        <h2 style="margin:8px 0;color:#6d7be6">CleanHabit</h2>
      </div>
      <h3 style="color:#1a1a2e">Reset hasła</h3>
      <p style="color:#555">Twój jednorazowy kod weryfikacyjny:</p>
      <div style="background:#f0f0ff;border:2px solid #6d7be6;border-radius:16px;
                  padding:24px;text-align:center;margin:24px 0">
        <span style="font-size:36px;font-weight:900;letter-spacing:12px;color:#6d7be6">{code}</span>
      </div>
      <p style="color:#888;font-size:13px">Kod ważny przez <strong>15 minut</strong>.
      Jeśli nie prosiłeś o reset hasła, zignoruj tę wiadomość.</p>
    </div>
    """
    send_email(to, 'CleanHabit — kod resetowania hasła', html)

def send_verification_email(to: str, code: str):
    html = f"""
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px">
      <div style="text-align:center;margin-bottom:24px">
        <span style="font-size:48px">🏠</span>
        <h2 style="margin:8px 0;color:#6d7be6">CleanHabit</h2>
      </div>
      <h3 style="color:#1a1a2e">Potwierdź adres email</h3>
      <p style="color:#555">Twój jednorazowy kod weryfikacyjny:</p>
      <div style="background:#f0f0ff;border:2px solid #6d7be6;border-radius:16px;
                  padding:24px;text-align:center;margin:24px 0">
        <span style="font-size:36px;font-weight:900;letter-spacing:12px;color:#6d7be6">{code}</span>
      </div>
      <p style="color:#888;font-size:13px">Kod ważny przez <strong>15 minut</strong>.
      Jeśli to nie Ty zakładałeś konto, zignoruj tę wiadomość.</p>
    </div>
    """
    send_email(to, 'CleanHabit — potwierdź swój adres email', html)

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
def root():
    from flask import redirect
    return redirect('/welcome')

@app.route('/welcome')
def landing():
    with open(os.path.join(os.path.dirname(__file__), 'templates', 'landing.html'), encoding='utf-8') as f:
        return f.read()

@app.route('/kiosk')
def kiosk():
    """Single-purpose page for a tablet/screen next to the RC522 reader:
    polls for scans and logs the matching account in automatically."""
    with open(os.path.join(os.path.dirname(__file__), 'templates', 'kiosk.html'), encoding='utf-8') as f:
        return f.read()

@app.route('/app')
def index():
    with open(os.path.join(os.path.dirname(__file__), 'templates', 'index.html'), encoding='utf-8') as f:
        return f.read()

@app.route('/download/app')
def download_apk():
    from flask import send_file, make_response
    apk_path = os.path.join(
        os.environ.get('APK_DIR', os.path.join(os.path.dirname(__file__), 'static_ext')),
        'cleanhabit.apk'
    )
    resp = make_response(send_file(
        apk_path,
        mimetype='application/vnd.android.package-archive',
        as_attachment=True,
        download_name='CleanHabit.apk',
        conditional=True,
    ))
    resp.headers['X-Accel-Buffering'] = 'no'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp

@app.route('/privacy')
def privacy():
    return '''<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Polityka prywatności — CleanHabit</title>
<style>body{font-family:sans-serif;max-width:680px;margin:40px auto;padding:0 20px;color:#333;line-height:1.7}
h1{color:#6d7be6}h2{color:#444;margin-top:32px}a{color:#6d7be6}</style></head>
<body>
<h1>🏠 Polityka prywatności CleanHabit</h1>
<p>Ostatnia aktualizacja: 2026-06-30</p>
<h2>1. Administrator danych</h2>
<p>Administratorem danych osobowych jest właściciel aplikacji CleanHabit. Kontakt: <a href="mailto:cleanhabit@myroapp.org">cleanhabit@myroapp.org</a></p>
<h2>2. Jakie dane zbieramy</h2>
<ul>
  <li>Nazwa użytkownika</li>
  <li>Adres email (do logowania, resetowania hasła i weryfikacji konta)</li>
  <li>Dane o aktywności w aplikacji (ukończone zadania, punkty)</li>
  <li>Nagranie głosowe i jego transkrypcja tekstowa — wyłącznie gdy dobrowolnie skorzystasz z funkcji asystenta głosowego (zob. pkt 8)</li>
</ul>
<h2>3. Cel przetwarzania danych</h2>
<p>Dane przetwarzamy wyłącznie w celu świadczenia usługi — zarządzania gospodarstwem domowym w ramach aplikacji CleanHabit.</p>
<h2>4. Podstawa prawna</h2>
<p>Przetwarzanie opiera się na zgodzie użytkownika (art. 6 ust. 1 lit. a RODO), wyrażonej podczas rejestracji.</p>
<h2>5. Przechowywanie danych i podmioty przetwarzające</h2>
<p>Dane przechowywane są na prywatnym serwerze w Polsce. Nie sprzedajemy ani nie udostępniamy danych w celach marketingowych. Transkrypcje poleceń głosowych (zob. pkt 8) są przesyłane do Anthropic PBC (dostawcy modelu AI Claude, USA) wyłącznie w celu rozpoznania polecenia — Anthropic pełni rolę podmiotu przetwarzającego dane na nasze zlecenie.</p>
<h2>6. Prawa użytkownika</h2>
<p>Masz prawo do dostępu, sprostowania, usunięcia oraz przenoszenia swoich danych. Aby je wykonać, skontaktuj się z nami mailowo.</p>
<h2>7. Pliki cookies</h2>
<p>Aplikacja używa wyłącznie niezbędnych plików cookie do utrzymania sesji logowania.</p>
<h2>8. Mikrofon i asystent głosowy (AI)</h2>
<p>Aplikacja zawiera opcjonalną funkcję asystenta głosowego, która prosi o dostęp do mikrofonu wyłącznie wtedy, gdy sam ją uruchomisz (np. dotykając ikony mikrofonu). Twoja wypowiedź jest zamieniana na tekst przez wbudowany w system Android mechanizm rozpoznawania mowy — surowe nagranie audio nie jest wysyłane na nasze serwery. Powstały tekst (transkrypcja) jest następnie przesyłany do naszego serwera, a stamtąd do API Claude (Anthropic), aby rozpoznać Twoje polecenie (np. „dodaj zadanie odkurzanie") i wykonać odpowiednią akcję w aplikacji. Transkrypcje nie są wykorzystywane do trenowania modeli AI ani do celów marketingowych. Możesz w każdej chwili cofnąć aplikacji dostęp do mikrofonu w ustawieniach systemu Android — funkcja asystenta głosowego przestanie wtedy działać, reszta aplikacji pozostanie w pełni funkcjonalna.</p>
</body></html>''', 200, {'Content-Type': 'text/html; charset=utf-8'}

@app.route('/delete-account')
def delete_account():
    return '''<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Usunięcie konta — CleanHabit</title>
<style>body{font-family:sans-serif;max-width:680px;margin:40px auto;padding:0 20px;color:#333;line-height:1.7}
h1{color:#6d7be6}h2{color:#444;margin-top:32px}a{color:#6d7be6}
.box{background:#f0f0ff;border:2px solid #6d7be6;border-radius:16px;padding:20px;margin:20px 0}</style></head>
<body>
<h1>🏠 Usunięcie konta — CleanHabit</h1>
<p>Ta strona opisuje, jak trwale usunąć swoje konto i powiązane z nim dane w aplikacji <strong>CleanHabit</strong> (wydawca: właściciel aplikacji CleanHabit).</p>
<h2>Jak złożyć wniosek o usunięcie konta</h2>
<div class="box">
<ol>
  <li>Wyślij wiadomość e-mail na adres <a href="mailto:cleanhabit@myroapp.org?subject=Usuni%C4%99cie%20konta">cleanhabit@myroapp.org</a> z tematem <strong>„Usunięcie konta"</strong>.</li>
  <li>W treści podaj adres e-mail, którym logujesz się do aplikacji CleanHabit.</li>
  <li>Twoje konto i powiązane dane zostaną usunięte w ciągu <strong>14 dni</strong> od otrzymania wniosku, a my potwierdzimy to mailowo.</li>
</ol>
</div>
<h2>Jakie dane zostaną usunięte</h2>
<ul>
  <li>Konto (nazwa użytkownika, adres email, hasło)</li>
  <li>Profil domownika przypisany do konta (imię, emoji, punkty, monety, odznaki)</li>
  <li>Historia ukończonych zadań powiązana z tym domownikiem</li>
</ul>
<h2>Jakie dane mogą zostać zachowane</h2>
<p>Jeśli usuwane konto jest jedynym kontem administratora w danym gospodarstwie domowym, pozostałe wspólne dane gospodarstwa (lista pokoi, definicje zadań współdzielone z innymi domownikami) mogą pozostać aktywne dla pozostałych członków rodziny — usuwane są wyłącznie dane powiązane bezpośrednio z Twoim kontem i Twoim profilem. Nie przechowujemy kopii zapasowych dłużej niż 30 dni od usunięcia.</p>
<p>Szczegóły dotyczące przetwarzania danych znajdziesz w <a href="/privacy">polityce prywatności</a>.</p>
</body></html>''', 200, {'Content-Type': 'text/html; charset=utf-8'}

@app.route('/feedback')
def feedback_page():
    return '''<!DOCTYPE html><html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Prześlij opinię — CleanHabit</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--indigo-a:#6D7BE6;--indigo-b:#5159D6;--ink:#2B2840;--muted:#908AA8;--faint:#B0AAC8;
  --page:#F4F2FC;--card:#FFFFFF;--border:#ECE9F7;--fill:#F4F2FC;--green:#2F8B5E;--red:#E5557A;}
body{font-family:'Plus Jakarta Sans',system-ui,sans-serif;background:
  radial-gradient(1100px 520px at 12% -10%,#E4DFFb 0%,transparent 60%),
  radial-gradient(900px 500px at 100% 0%,#E7DDF0 0%,transparent 55%),
  linear-gradient(160deg,#F4F2FC 0%,#EEEAFA 100%);
  min-height:100vh;color:var(--ink);display:flex;align-items:flex-start;justify-content:center;padding:3rem 1.2rem;-webkit-font-smoothing:antialiased}
.wrap{width:100%;max-width:560px}
.logo{display:flex;align-items:center;gap:.6rem;justify-content:center;text-decoration:none;color:var(--ink);font-weight:800;font-size:1.25rem;margin-bottom:1.6rem}
.logo-icon{width:42px;height:42px;background:linear-gradient(135deg,var(--indigo-a),var(--indigo-b));border-radius:14px;display:flex;align-items:center;justify-content:center;box-shadow:0 10px 20px -6px rgba(85,89,214,.6)}
.card{background:var(--card);border-radius:26px;padding:2.2rem;box-shadow:0 28px 60px -28px rgba(60,45,120,.5)}
h1{font-size:1.6rem;font-weight:800;letter-spacing:-.02em;margin-bottom:.5rem;text-align:center}
.sub{color:var(--muted);font-size:.95rem;line-height:1.6;text-align:center;margin-bottom:1.8rem}
label{display:block;font-size:.85rem;font-weight:700;color:var(--ink);margin:0 0 .5rem .2rem}
.inp,textarea,select{width:100%;background:var(--fill);border:1.5px solid var(--border);border-radius:14px;
  padding:.85rem 1rem;color:var(--ink);font-size:.95rem;font-family:inherit;outline:none;transition:border-color .2s,background .2s;appearance:none}
.inp:focus,textarea:focus,select:focus{border-color:var(--indigo-a);background:rgba(109,123,230,.05)}
.inp::placeholder,textarea::placeholder{color:var(--faint)}
textarea{resize:vertical;min-height:140px;line-height:1.5}
.field{margin-bottom:1.2rem}
.chips{display:flex;gap:.5rem;flex-wrap:wrap}
.chip{border:1.5px solid var(--border);background:#fff;border-radius:99px;padding:.5rem 1rem;font-size:.82rem;font-weight:700;cursor:pointer;color:var(--muted);transition:.18s}
.chip.on{background:rgba(109,123,230,.12);border-color:var(--indigo-a);color:var(--indigo-b)}
.btn{width:100%;padding:1rem;border:none;border-radius:15px;cursor:pointer;font-weight:800;font-size:1rem;
  background:linear-gradient(135deg,var(--indigo-a),var(--indigo-b));color:#fff;box-shadow:0 16px 30px -12px rgba(85,89,214,.65);transition:transform .2s}
.btn:hover{transform:translateY(-2px)}
.btn:disabled{opacity:.6;cursor:default;transform:none}
.msg{display:none;border-radius:14px;padding:.85rem 1rem;font-size:.9rem;margin-bottom:1.2rem;font-weight:600}
.msg.err{display:block;background:rgba(239,68,68,.1);border:1px solid rgba(239,68,68,.3);color:var(--red)}
.ok-screen{display:none;text-align:center;padding:1rem 0}
.ok-screen .big{font-size:3.4rem;margin-bottom:1rem}
.ok-screen h2{font-size:1.5rem;font-weight:800;margin-bottom:.6rem}
.ok-screen p{color:var(--muted);line-height:1.6;margin-bottom:1.6rem}
.back{display:inline-block;margin-top:1.6rem;text-align:center;width:100%;color:var(--muted);text-decoration:none;font-size:.88rem;font-weight:600}
.back:hover{color:var(--indigo-b)}
.lang{display:flex;gap:4px;justify-content:center;margin-bottom:1.2rem}
.lang button{border:none;background:#fff;border:1px solid var(--border);border-radius:9px;padding:.3rem .6rem;font-size:.78rem;font-weight:700;cursor:pointer;color:var(--muted)}
.lang button.on{background:linear-gradient(135deg,var(--indigo-a),var(--indigo-b));color:#fff;border-color:transparent}
</style></head>
<body>
<div class="wrap">
  <a href="/welcome" class="logo">
    <span class="logo-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/></svg></span>
    CleanHabit
  </a>
  <div class="lang">
    <button onclick="setLang('pl')" id="lng-pl" class="on">🇵🇱 PL</button>
    <button onclick="setLang('en')" id="lng-en">🇬🇧 EN</button>
    <button onclick="setLang('uk')" id="lng-uk">🇺🇦 UK</button>
  </div>
  <div class="card">
    <div id="form-view">
      <h1 id="t-title">Prześlij opinię 💬</h1>
      <p class="sub" id="t-sub">Twoja opinia pomaga nam ulepszać CleanHabit. Napisz co działa, co nie, albo co chciałbyś zobaczyć!</p>
      <div class="msg" id="err"></div>
      <div class="field">
        <label id="t-cat-label">Czego dotyczy?</label>
        <div class="chips" id="chips">
          <button type="button" class="chip on" data-cat="bug" data-pl="🐞 Błąd" data-en="🐞 Bug" data-uk="🐞 Помилка">🐞 Błąd</button>
          <button type="button" class="chip" data-cat="idea" data-pl="💡 Pomysł" data-en="💡 Idea" data-uk="💡 Ідея">💡 Pomysł</button>
          <button type="button" class="chip" data-cat="praise" data-pl="❤️ Pochwała" data-en="❤️ Praise" data-uk="❤️ Похвала">❤️ Pochwała</button>
          <button type="button" class="chip" data-cat="other" data-pl="✨ Inne" data-en="✨ Other" data-uk="✨ Інше">✨ Inne</button>
        </div>
      </div>
      <div class="field">
        <label id="t-msg-label">Twoja wiadomość</label>
        <textarea id="message" maxlength="3000" placeholder="Napisz tutaj..."></textarea>
      </div>
      <div class="field">
        <label id="t-email-label">Email (opcjonalnie — jeśli chcesz odpowiedź)</label>
        <input class="inp" id="email" type="email" placeholder="ty@example.com"/>
      </div>
      <button class="btn" id="submit-btn" onclick="submitFeedback()">Wyślij opinię</button>
    </div>
    <div class="ok-screen" id="ok-view">
      <div class="big">🎉</div>
      <h2 id="t-ok-title">Dziękujemy!</h2>
      <p id="t-ok-sub">Twoja opinia została wysłana. Bardzo nam pomaga w ulepszaniu aplikacji.</p>
      <button class="btn" onclick="resetForm()" id="t-again">Wyślij kolejną</button>
    </div>
  </div>
  <a href="/welcome" class="back" id="t-back">← Wróć do strony głównej</a>
</div>
<script>
const $ = id => document.getElementById(id);
let lang = 'pl', category = 'bug';
const TR = {
  pl:{title:'Prześlij opinię 💬',sub:'Twoja opinia pomaga nam ulepszać CleanHabit. Napisz co działa, co nie, albo co chciałbyś zobaczyć!',cat:'Czego dotyczy?',msgl:'Twoja wiadomość',msgp:'Napisz tutaj...',emaill:'Email (opcjonalnie — jeśli chcesz odpowiedź)',btn:'Wyślij opinię',sending:'Wysyłam...',empty:'Napisz wiadomość przed wysłaniem.',neterr:'Coś poszło nie tak. Spróbuj ponownie.',oktitle:'Dziękujemy!',oksub:'Twoja opinia została wysłana. Bardzo nam pomaga w ulepszaniu aplikacji.',again:'Wyślij kolejną',back:'← Wróć do strony głównej'},
  en:{title:'Send feedback 💬',sub:'Your feedback helps us improve CleanHabit. Tell us what works, what doesn\\'t, or what you\\'d love to see!',cat:'What\\'s it about?',msgl:'Your message',msgp:'Write here...',emaill:'Email (optional — if you want a reply)',btn:'Send feedback',sending:'Sending...',empty:'Please write a message first.',neterr:'Something went wrong. Try again.',oktitle:'Thank you!',oksub:'Your feedback has been sent. It really helps us improve the app.',again:'Send another',back:'← Back to homepage'},
  uk:{title:'Надіслати відгук 💬',sub:'Ваш відгук допомагає покращувати CleanHabit. Напишіть що працює, що ні, або що хотіли б побачити!',cat:'Про що це?',msgl:'Ваше повідомлення',msgp:'Напишіть тут...',emaill:'Email (необов\\'язково — якщо хочете відповідь)',btn:'Надіслати відгук',sending:'Надсилаю...',empty:'Спочатку напишіть повідомлення.',neterr:'Щось пішло не так. Спробуйте ще раз.',oktitle:'Дякуємо!',oksub:'Ваш відгук надіслано. Це дуже допомагає нам покращувати додаток.',again:'Надіслати ще',back:'← На головну'}
};
function setLang(l){
  lang=l; const t=TR[l];
  ['pl','en','uk'].forEach(x=>$('lng-'+x).classList.toggle('on',x===l));
  $('t-title').textContent=t.title; $('t-sub').textContent=t.sub; $('t-cat-label').textContent=t.cat;
  $('t-msg-label').textContent=t.msgl; $('message').placeholder=t.msgp; $('t-email-label').textContent=t.emaill;
  $('submit-btn').textContent=t.btn; $('t-ok-title').textContent=t.oktitle; $('t-ok-sub').textContent=t.oksub;
  $('t-again').textContent=t.again; $('t-back').textContent=t.back;
  document.querySelectorAll('.chip').forEach(c=>c.textContent=c.getAttribute('data-'+l));
}
document.querySelectorAll('.chip').forEach(c=>c.onclick=()=>{
  category=c.getAttribute('data-cat');
  document.querySelectorAll('.chip').forEach(x=>x.classList.remove('on'));
  c.classList.add('on');
});
async function submitFeedback(){
  const msg=$('message').value.trim(), email=$('email').value.trim(), err=$('err'), t=TR[lang];
  err.style.display='none';
  if(!msg){ err.className='msg err'; err.textContent=t.empty; return; }
  const btn=$('submit-btn'); btn.disabled=true; btn.textContent=t.sending;
  try{
    const r=await fetch('/api/feedback',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({message:msg,email:email,category:category})});
    const data=await r.json();
    if(data.error){ err.className='msg err'; err.textContent=data.error; btn.disabled=false; btn.textContent=t.btn; return; }
    $('form-view').style.display='none'; $('ok-view').style.display='block';
  }catch(e){ err.className='msg err'; err.textContent=t.neterr; btn.disabled=false; btn.textContent=t.btn; }
}
function resetForm(){
  $('message').value=''; $('email').value=''; $('err').style.display='none';
  $('ok-view').style.display='none'; $('form-view').style.display='block';
  const btn=$('submit-btn'); btn.disabled=false; btn.textContent=TR[lang].btn;
}
</script>
</body></html>''', 200, {'Content-Type': 'text/html; charset=utf-8'}

@app.route('/api/feedback', methods=['POST'])
@limiter.limit('10 per hour')
def submit_feedback():
    d = request.get_json(silent=True) or {}
    message = (d.get('message') or '').strip()
    email = (d.get('email') or '').strip()[:200]
    category = (d.get('category') or 'other').strip()[:30]
    if not message:
        return jsonify({'error': 'Wiadomość nie może być pusta'}), 400
    message = message[:3000]
    db = get_db()
    db.execute(
        "INSERT INTO feedback(id,email,category,message,created_at) VALUES (?,?,?,?,?)",
        [uid(), email, category, message, datetime.now().isoformat()])
    db.commit()
    # Best-effort email to the owner so feedback is seen without polling the DB.
    try:
        safe = message.replace('<', '&lt;').replace('>', '&gt;')
        html = f"""<div style="font-family:sans-serif;max-width:560px">
          <h3 style="color:#6d7be6">📨 Nowa opinia — CleanHabit</h3>
          <p><b>Kategoria:</b> {category}</p>
          <p><b>Od:</b> {email or '(nie podano emaila)'}</p>
          <hr style="border:none;border-top:1px solid #eee">
          <p style="white-space:pre-wrap;line-height:1.6">{safe}</p>
        </div>"""
        send_email(MAIL_FROM, 'CleanHabit — nowa opinia', html)
    except Exception:
        pass
    return jsonify({'ok': True})

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

def _create_account(db, payload):
    """Shared by verify-email: turns a validated registration payload into a
    real user (+ household/member for 'create', or claiming a member for
    'join'). Mirrors what auth_register used to do inline before email
    verification was inserted in front of it."""
    import re as _re
    email        = payload['email']
    display_name = payload['display_name']
    action       = payload['action']
    token        = payload['token']
    hname        = payload['household_name']
    chosen_emoji = payload['emoji']
    member_id    = payload['member_id']

    # Accounts log in with email now; username is just an internal handle
    # derived from the email's local part (kept unique with a numeric suffix).
    # Recomputed here (not at register time) so it can't go stale during the
    # verification window.
    base_username = _re.sub(r'[^a-z0-9_.]', '', email.split('@')[0]) or 'user'
    username = base_username
    suffix = 1
    while db.execute("SELECT 1 FROM users WHERE username=?", [username]).fetchone():
        suffix += 1
        username = f'{base_username}{suffix}'

    if action == 'join':
        household = db.execute("SELECT * FROM households WHERE token=?", [token]).fetchone()
        if not household:
            return None, (jsonify({'error': f'Nie znaleziono rodziny z kodem "{token}"'}), 404)
        household_id = household['id']
        role = 'member'
        mbr = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, household_id]).fetchone()
        if not mbr:
            return None, (jsonify({'error': 'Nie znaleziono domownika'}), 404)
        if db.execute("SELECT 1 FROM users WHERE member_id=? AND household_id=?", [member_id, household_id]).fetchone():
            return None, (jsonify({'error': 'Ten domownik ma już konto — zaloguj się'}), 400)
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
        # Auto-create member profile for the owner
        import random
        emoji = chosen_emoji if chosen_emoji else random.choice(MEMBER_EMOJIS)
        member_id = uid()
        db.execute(
            "INSERT INTO members(id,household_id,name,emoji,points,coins,streak,streak_date,owned) VALUES (?,?,?,?,0,0,0,NULL,'[]')",
            [member_id, household_id, display_name, emoji]
        )

    user_id = uid()
    db.execute("INSERT INTO users(id,username,password_hash,email,household_id,member_id,role,created_at) VALUES (?,?,?,?,?,?,?,?)",
               [user_id, username, payload['password_hash'], email, household_id, member_id, role, datetime.now().isoformat()])
    db.commit()
    session['user_id'] = user_id
    user = dict(db.execute("SELECT id,username,household_id,member_id,role FROM users WHERE id=?", [user_id]).fetchone())
    household = dict(db.execute("SELECT * FROM households WHERE id=?", [household_id]).fetchone())
    return (user, household), None

@app.route('/api/auth/register', methods=['POST'])
@limiter.limit('10 per hour')
def auth_register():
    d = request.get_json(silent=True) or {}
    password     = d.get('password', '').strip()
    email        = d.get('email', '').strip().lower()
    display_name = d.get('display_name', '').strip()
    action       = d.get('action', 'create')  # 'create' or 'join'
    token        = d.get('token', '').strip().upper()
    hname        = d.get('household_name', 'Moja Rodzina').strip()
    chosen_emoji = d.get('emoji', '').strip()
    member_id    = d.get('member_id', '').strip()  # for join: pick existing member

    if not password:
        return jsonify({'error': 'Podaj hasło'}), 400
    import re as _re
    if not email or not _re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', email):
        return jsonify({'error': 'Podaj poprawny adres email'}), 400
    if len(password) < 4:
        return jsonify({'error': 'Hasło musi mieć min. 4 znaki'}), 400

    db = get_db()
    if db.execute("SELECT 1 FROM users WHERE email=?", [email]).fetchone():
        return jsonify({'error': 'Ten adres email jest już używany przez inne konto'}), 400

    if not display_name:
        display_name = email.split('@')[0]

    if action == 'join':
        household = db.execute("SELECT * FROM households WHERE token=?", [token]).fetchone()
        if not household:
            return jsonify({'error': f'Nie znaleziono rodziny z kodem "{token}"'}), 404
        # Verify the member belongs to this household and isn't claimed yet
        if not member_id:
            return jsonify({'error': 'Wybierz swojego domownika z listy'}), 400
        mbr = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, household['id']]).fetchone()
        if not mbr:
            return jsonify({'error': 'Nie znaleziono domownika'}), 404
        if db.execute("SELECT 1 FROM users WHERE member_id=? AND household_id=?", [member_id, household['id']]).fetchone():
            return jsonify({'error': 'Ten domownik ma już konto — zaloguj się'}), 400

    # Don't create the account yet — stash everything needed to finish the
    # job in email_verifications, keyed by email, and email a 6-digit code.
    # /api/auth/verify-email does the actual INSERT once the code checks out.
    payload = {
        'password_hash': make_pw(password), 'email': email, 'display_name': display_name,
        'action': action, 'token': token, 'household_name': hname,
        'emoji': chosen_emoji, 'member_id': member_id,
    }
    code = ''.join(random.choices(string.digits, k=6))
    expires = (datetime.now() + timedelta(minutes=15)).isoformat()
    db.execute("DELETE FROM email_verifications WHERE email=?", [email])
    db.execute("INSERT INTO email_verifications(email,code,expires_at,payload) VALUES (?,?,?,?)",
               [email, code, expires, json.dumps(payload)])
    db.commit()
    try:
        send_verification_email(email, code)
    except Exception as e:
        return jsonify({'error': f'Nie udało się wysłać emaila: {e}'}), 500
    return jsonify({'ok': True, 'pending_verification': True, 'email': email})

@app.route('/api/auth/verify-email', methods=['POST'])
@limiter.limit('10 per hour')
def auth_verify_email():
    d = request.get_json(silent=True) or {}
    email = d.get('email', '').strip().lower()
    code  = d.get('code', '').strip()
    if not email or not code:
        return jsonify({'error': 'Wypełnij wszystkie pola'}), 400
    db = get_db()
    row = db.execute("SELECT * FROM email_verifications WHERE email=?", [email]).fetchone()
    if not row or row['code'] != code:
        return jsonify({'error': 'Nieprawidłowy kod weryfikacyjny'}), 400
    if datetime.fromisoformat(row['expires_at']) < datetime.now():
        return jsonify({'error': 'Kod wygasł — zarejestruj się ponownie'}), 400
    if db.execute("SELECT 1 FROM users WHERE email=?", [email]).fetchone():
        db.execute("DELETE FROM email_verifications WHERE email=?", [email])
        db.commit()
        return jsonify({'error': 'Ten adres email jest już używany przez inne konto'}), 400

    payload = json.loads(row['payload'])
    result, err = _create_account(db, payload)
    if err:
        return err
    db.execute("DELETE FROM email_verifications WHERE email=?", [email])
    db.commit()
    user, household = result
    return jsonify({'ok': True, 'user': user, 'household': household})

@app.route('/api/auth/google', methods=['POST'])
@limiter.limit('20 per hour')
def auth_google():
    """Sign in (or register) with Google.

    Single endpoint, two passes — mirrors the email-code flow but Google has
    already proven the email, so there's no separate verification step:
      1. Client sends just {id_token}. If a user with that email already
         exists, log them straight in. Otherwise respond with
         {needs_setup: true, email, suggested_name} so the client can show
         the same create/join household form used for normal registration.
      2. Client re-sends {id_token, action, ...household/join fields...}.
         The id_token is re-verified (cheap, and avoids a server-side
         pending-signup table) and the account is created via the same
         _create_account() helper email-verification uses.
    """
    d = request.get_json(silent=True) or {}
    raw_token = d.get('id_token', '').strip()
    if not raw_token:
        return jsonify({'error': 'Brak tokenu Google'}), 400
    try:
        info = google_id_token.verify_oauth2_token(
            raw_token, google_requests.Request(), GOOGLE_WEB_CLIENT_ID)
    except ValueError:
        return jsonify({'error': 'Nieprawidłowy token Google'}), 400
    if not info.get('email_verified'):
        return jsonify({'error': 'Adres email z konta Google nie jest zweryfikowany'}), 400
    email = info['email'].strip().lower()
    name = (info.get('name') or info.get('given_name') or '').strip()

    db = get_db()
    existing = db.execute("SELECT * FROM users WHERE email=?", [email]).fetchone()
    if existing:
        session['user_id'] = existing['id']
        user = dict(db.execute(
            "SELECT id,username,household_id,member_id,role FROM users WHERE id=?",
            [existing['id']]).fetchone())
        household = dict(db.execute(
            "SELECT * FROM households WHERE id=?", [existing['household_id']]).fetchone())
        return jsonify({'ok': True, 'user': user, 'household': household})

    action = d.get('action')
    if not action:
        return jsonify({'ok': True, 'needs_setup': True, 'email': email, 'suggested_name': name})

    if action == 'join':
        member_id = d.get('member_id', '').strip()
        if not member_id:
            return jsonify({'error': 'Wybierz swojego domownika z listy'}), 400
        token = d.get('token', '').strip().upper()
    else:
        token = ''
        member_id = ''

    payload = {
        # Google users sign in via Google, not a password — store an
        # unusable random hash so the NOT NULL column is satisfied; they
        # can set a real password later via "forgot password" if they ever
        # want a fallback login method.
        'password_hash': make_pw(secrets.token_hex(32)),
        'email': email,
        'display_name': d.get('display_name', '').strip() or name,
        'action': action,
        'token': token,
        'household_name': d.get('household_name', 'Moja Rodzina').strip(),
        'emoji': d.get('emoji', '').strip(),
        'member_id': member_id,
    }
    result, err = _create_account(db, payload)
    if err:
        return err
    user, household = result
    return jsonify({'ok': True, 'user': user, 'household': household})

@app.route('/api/auth/login', methods=['POST'])
@limiter.limit('10 per minute')
def auth_login():
    d = request.get_json(silent=True) or {}
    identifier = d.get('username', '').strip().lower()
    password = d.get('password', '').strip()
    db = get_db()
    # Accounts log in with the email they registered with; username is kept
    # as a fallback so legacy accounts (created before email was required)
    # still work.
    row = db.execute("SELECT * FROM users WHERE email=? OR username=?",
                      [identifier, identifier]).fetchone()
    ok, needs_upgrade = verify_pw(row['password_hash'], password) if row else (False, False)
    if not row or not ok:
        return jsonify({'error': 'Błędny email lub hasło'}), 401
    if needs_upgrade:
        # Transparently migrate the legacy SHA-256 hash to a salted one.
        db.execute("UPDATE users SET password_hash=? WHERE id=?", [make_pw(password), row['id']])
        db.commit()
    session['user_id'] = row['id']
    user = dict(db.execute("SELECT id,username,household_id,member_id,role FROM users WHERE id=?",
                            [row['id']]).fetchone())
    household = dict(db.execute("SELECT * FROM households WHERE id=?", [user['household_id']]).fetchone())
    return jsonify({'ok': True, 'user': user, 'household': household})

@app.route('/api/auth/logout', methods=['POST'])
def auth_logout():
    session.clear()
    return jsonify({'ok': True})

@app.route('/api/auth/login-rfid', methods=['POST'])
@limiter.limit('20 per minute')
def auth_login_rfid():
    """Kiosk browser calls this after /api/rfid/poll shows a fresh scan.
    Possession of the physical card is the auth factor, same trust model as
    the standalone rfid-login demo."""
    d = request.get_json(silent=True) or {}
    card_uid = str(d.get('uid', '')).strip().upper()
    if not card_uid:
        return jsonify({'ok': False, 'error': 'missing uid'}), 400
    db = get_db()
    row = db.execute("SELECT * FROM users WHERE rfid_uid=?", [card_uid]).fetchone()
    if not row:
        return jsonify({'ok': False, 'error': 'Nieznana karta'}), 404
    session['user_id'] = row['id']
    user = dict(db.execute("SELECT id,username,household_id,member_id,role FROM users WHERE id=?",
                            [row['id']]).fetchone())
    household = dict(db.execute("SELECT * FROM households WHERE id=?", [user['household_id']]).fetchone())
    return jsonify({'ok': True, 'user': user, 'household': household})

@app.route('/api/auth/link-rfid', methods=['POST'])
def auth_link_rfid():
    """Self-service: logged-in user assigns their own card's UID to their account."""
    err = require_auth()
    if err: return err
    d = request.get_json(silent=True) or {}
    card_uid = str(d.get('uid', '')).strip().upper()
    if not card_uid:
        return jsonify({'ok': False, 'error': 'missing uid'}), 400
    db = get_db()
    existing = db.execute("SELECT id FROM users WHERE rfid_uid=?", [card_uid]).fetchone()
    if existing and existing['id'] != session['user_id']:
        return jsonify({'ok': False, 'error': 'Karta jest już przypisana do innego konta'}), 409
    db.execute("UPDATE users SET rfid_uid=? WHERE id=?", [card_uid, session['user_id']])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/rfid/scan', methods=['POST'])
def rfid_scan():
    """Device endpoint: the ESP32/RC522 reader POSTs here on every card scan."""
    if RFID_SCAN_SECRET and request.headers.get('X-RFID-Secret') != RFID_SCAN_SECRET:
        return jsonify({'ok': False, 'error': 'unauthorized'}), 401
    d = request.get_json(silent=True) or {}
    card_uid = str(d.get('uid', '')).strip().upper()
    if not card_uid:
        return jsonify({'ok': False, 'error': 'missing uid'}), 400
    db = get_db()
    db.execute("""INSERT INTO rfid_last_scan (id, card_uid, ts) VALUES (1, ?, ?)
                  ON CONFLICT(id) DO UPDATE SET card_uid=excluded.card_uid, ts=excluded.ts""",
               [card_uid, time.time()])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/rfid/poll')
def rfid_poll():
    """Kiosk browser long-poll target: returns the latest scan if it's newer
    than the `since` timestamp the caller already knows about."""
    try:
        since = float(request.args.get('since', 0))
    except ValueError:
        since = 0.0
    row = get_db().execute("SELECT card_uid, ts FROM rfid_last_scan WHERE id=1").fetchone()
    if row and row['ts'] and row['ts'] > since:
        return jsonify({'uid': row['card_uid'], 'ts': row['ts']})
    return jsonify({'uid': None, 'ts': row['ts'] if row else 0})

@app.route('/api/auth/forgot-password', methods=['POST'])
@limiter.limit('5 per hour')
def auth_forgot_password():
    d = request.get_json(silent=True) or {}
    email = d.get('email', '').strip().lower()
    if not email:
        return jsonify({'error': 'Podaj adres email'}), 400
    db = get_db()
    row = db.execute("SELECT id FROM users WHERE email=?", [email]).fetchone()
    # Always return ok to avoid email enumeration
    if row:
        code = ''.join(random.choices(string.digits, k=6))
        expires = (datetime.now() + timedelta(minutes=15)).isoformat()
        tok = secrets.token_hex(32)
        db.execute("DELETE FROM reset_tokens WHERE user_id=?", [row['id']])
        db.execute("INSERT INTO reset_tokens(token,user_id,expires_at) VALUES (?,?,?)",
                   [tok, row['id'], expires])
        db.commit()
        try:
            send_reset_email(email, code)
            db.execute("UPDATE reset_tokens SET token=? WHERE user_id=?",
                       [code, row['id']])
            db.commit()
        except Exception as e:
            return jsonify({'error': f'Nie udało się wysłać emaila: {e}'}), 500
    return jsonify({'ok': True})

@app.route('/api/auth/reset-password', methods=['POST'])
@limiter.limit('10 per hour')
def auth_reset_password():
    d = request.get_json(silent=True) or {}
    email    = d.get('email', '').strip().lower()
    code     = d.get('code', '').strip()
    new_pass = d.get('password', '').strip()
    if not email or not code or not new_pass:
        return jsonify({'error': 'Wypełnij wszystkie pola'}), 400
    if len(new_pass) < 4:
        return jsonify({'error': 'Hasło musi mieć min. 4 znaki'}), 400
    db = get_db()
    row = db.execute("SELECT id FROM users WHERE email=?", [email]).fetchone()
    if not row:
        return jsonify({'error': 'Nieprawidłowy kod lub email'}), 400
    tok = db.execute(
        "SELECT * FROM reset_tokens WHERE user_id=? AND token=?",
        [row['id'], code]
    ).fetchone()
    if not tok:
        return jsonify({'error': 'Nieprawidłowy kod weryfikacyjny'}), 400
    if datetime.fromisoformat(tok['expires_at']) < datetime.now():
        return jsonify({'error': 'Kod wygasł — spróbuj ponownie'}), 400
    db.execute("UPDATE users SET password_hash=? WHERE id=?", [make_pw(new_pass), row['id']])
    db.execute("DELETE FROM reset_tokens WHERE user_id=?", [row['id']])
    db.commit()
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
    name = (request.get_json(silent=True) or {}).get('name', '').strip()
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
    d = request.get_json(silent=True) or {}
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
    d = request.get_json(silent=True) or {}
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
    d = request.get_json(silent=True) or {}
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

@app.route('/api/rooms/<rid>/stats')
def room_stats(rid):
    """Per-room breakdown for the room detail screen: open quests for this
    room (with their done-today/assignee/schedule), plus a per-member
    completion leaderboard and a 7-day total for the room."""
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    room = db.execute("SELECT * FROM rooms WHERE id=? AND household_id=?", [rid, hid]).fetchone()
    if not room: return jsonify({'error': 'not found'}), 404

    tasks = [dict(r) for r in db.execute(
        "SELECT * FROM tasks WHERE room_id=? AND household_id=?", [rid, hid])]
    members = {r['id']: dict(r) for r in db.execute(
        "SELECT id, name, emoji FROM members WHERE household_id=?", [hid])}

    today = datetime.now().strftime('%Y-%m-%d')
    done_today_ids = {r['task_id'] for r in db.execute(
        "SELECT task_id FROM history WHERE household_id=? AND completed_at LIKE ? AND (type='done' OR type IS NULL)",
        [hid, f'{today}%'])}

    quests = []
    for t in tasks:
        m = members.get(t['assigned_to'], {})
        quests.append({
            'id': t['id'], 'name': t['name'], 'diff': t['diff'], 'freq': t['freq'],
            'one_time': bool(t['one_time']),
            'member_id': t['assigned_to'], 'member_name': m.get('name'), 'member_emoji': m.get('emoji'),
            'done_today': t['id'] in done_today_ids,
        })

    task_ids = [t['id'] for t in tasks]
    member_breakdown = []
    week_total = {'count': 0, 'pts': 0}
    if task_ids:
        placeholders = ','.join('?' * len(task_ids))
        rows = db.execute(
            f"SELECT member_id, COUNT(*) cnt, SUM(pts) pts FROM history "
            f"WHERE household_id=? AND task_id IN ({placeholders}) AND (type='done' OR type IS NULL) "
            f"GROUP BY member_id ORDER BY cnt DESC",
            [hid] + task_ids).fetchall()
        for r in rows:
            m = members.get(r['member_id'], {})
            member_breakdown.append({
                'member_id': r['member_id'], 'name': m.get('name', '?'), 'emoji': m.get('emoji', '👤'),
                'count': r['cnt'], 'pts': r['pts'] or 0,
            })
        cutoff7 = (datetime.now() - timedelta(days=7)).isoformat()
        wk = db.execute(
            f"SELECT COUNT(*) cnt, SUM(pts) pts FROM history "
            f"WHERE household_id=? AND task_id IN ({placeholders}) AND (type='done' OR type IS NULL) AND completed_at>=?",
            [hid] + task_ids + [cutoff7]).fetchone()
        week_total = {'count': wk['cnt'] or 0, 'pts': wk['pts'] or 0}

    return jsonify({
        'room': {'id': room['id'], 'name': room['name'], 'emoji': room['emoji'], 'cleanliness': room['cleanliness']},
        'quests': quests,
        'done_count': sum(1 for q in quests if q['done_today']),
        'member_breakdown': member_breakdown,
        'week_total': week_total,
    })

# ── TASKS ─────────────────────────────────────────────────────
@app.route('/api/tasks', methods=['POST'])
def add_task():
    err = require_auth(); hid = get_hid()
    if err: return err
    d = request.get_json(silent=True) or {}
    if not d.get('assignedTo'):
        return jsonify({'error': 'Wybierz, kto wykonuje zadanie'}), 400
    specific_days = d.get('specificDays')  # e.g. "0,2,4" = Mon,Wed,Fri or None
    if specific_days and not isinstance(specific_days, str):
        specific_days = ','.join(str(x) for x in specific_days)
    freq = d.get('freq', 'weekly') if not specific_days else 'custom'
    one_time = 1 if d.get('oneTime') else 0
    due_date = d.get('dueDate')  # optional 'YYYY-MM-DD' - schedules the task's first occurrence
    if due_date:
        created_at = f"{due_date}T{datetime.now().strftime('%H:%M:%S')}"
    else:
        created_at = datetime.now().isoformat()
    db = get_db()
    db.execute(
        "INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at,specific_days,one_time) VALUES (?,?,?,?,?,?,?,NULL,?,?,?,?)",
        [uid(), hid, d['name'], d['roomId'], d['assignedTo'], freq, d['diff'],
         1 if d.get('approvalNeeded') else 0, created_at, specific_days, one_time])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>', methods=['PUT'])
def edit_task(tid):
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    d = request.get_json(silent=True) or {}
    if not d.get('assignedTo'):
        return jsonify({'error': 'Wybierz, kto wykonuje zadanie'}), 400
    specific_days = d.get('specificDays')
    if specific_days and not isinstance(specific_days, str):
        specific_days = ','.join(str(x) for x in specific_days)
    freq = d.get('freq', 'weekly') if not specific_days else 'custom'
    one_time = 1 if d.get('oneTime') else 0
    db.execute(
        "UPDATE tasks SET name=?, room_id=?, assigned_to=?, freq=?, diff=?, approval_needed=?, specific_days=?, one_time=? "
        "WHERE id=? AND household_id=?",
        [d['name'], d['roomId'], d['assignedTo'], freq, d['diff'],
         1 if d.get('approvalNeeded') else 0, specific_days, one_time, tid, hid])
    db.commit()
    return jsonify({'ok': True})

@app.route('/api/tasks/<tid>/expire', methods=['POST'])
def expire_task(tid):
    """Mark a task as missed/expired — advance cycle without awarding points.

    Accepts an optional {"date": "YYYY-MM-DD"} body to skip a *specific*
    calendar occurrence rather than always anchoring on "now". Without it
    the anchor lands on today, which only correctly skips the occurrence
    that's actually due today — for a future-dated occurrence clicked from
    the calendar, anchoring on "now" can leave that same future day still
    matching the recurrence cycle (looks like nothing happened).
    """
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)
    data = request.get_json(silent=True) or {}
    target_date = data.get('date')
    now_iso = datetime.now().isoformat()
    if target_date:
        try:
            now_iso = datetime.combine(date.fromisoformat(target_date), datetime.now().time()).isoformat()
        except ValueError:
            pass

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
    data = request.get_json(silent=True) or {}
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)
    u = current_user()
    if task['assigned_to'] and not is_admin(hid):
        if not u or u.get('member_id') != task['assigned_to']:
            return jsonify({'error': 'Tylko przypisana osoba lub admin może wykonać to zadanie'}), 403
    member_id = data.get('memberId') or task['assigned_to'] or (u.get('member_id') if u else None)
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if not member:
        # fallback: first member of household
        member = db.execute("SELECT * FROM members WHERE household_id=? ORDER BY rowid ASC LIMIT 1", [hid]).fetchone()
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

@app.route('/api/tasks/<tid>/uncomplete', methods=['POST'])
def uncomplete_task(tid):
    """Undo today's most recent completion of a task: removes the history
    row and reverses the points/coins/cleanliness it granted. Best-effort —
    streak is decremented but its prior streak_date isn't reconstructable,
    and badges already awarded are not revoked."""
    err = require_auth(); hid = get_hid()
    if err: return err
    db = get_db()
    task = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?", [tid, hid]).fetchone()
    if not task: return jsonify({'error': 'not found'}), 404
    task = dict(task)
    today = datetime.now().strftime('%Y-%m-%d')
    row = db.execute(
        "SELECT * FROM history WHERE household_id=? AND task_id=? AND type='done' AND completed_at LIKE ? "
        "ORDER BY completed_at DESC LIMIT 1",
        [hid, tid, f'{today}%']).fetchone()
    if not row:
        return jsonify({'error': 'Brak dzisiejszego ukończenia do cofnięcia'}), 400
    row = dict(row)
    pts = row['pts'] or 0
    coins = row['coins_earned'] or 0
    member_id = row['member_id']

    db.execute("DELETE FROM history WHERE id=? AND household_id=?", [row['id'], hid])
    db.execute(
        "UPDATE members SET points=MAX(0,points-?), coins=MAX(0,coins-?) WHERE id=? AND household_id=?",
        [pts, coins, member_id, hid])
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if member and member['streak_date'] == today and member['streak'] > 0:
        db.execute("UPDATE members SET streak=streak-1, streak_date=NULL WHERE id=? AND household_id=?",
                   [member_id, hid])
    db.execute("UPDATE rooms SET cleanliness=MAX(0,cleanliness-?) WHERE id=? AND household_id=?",
               [min(pts*8, 22), task['room_id'], hid])

    # Re-anchor the task on whatever completion (done or missed) precedes
    # the one we just deleted, so the recurrence cycle resets correctly.
    prev = db.execute(
        "SELECT completed_at FROM history WHERE household_id=? AND task_id=? ORDER BY completed_at DESC LIMIT 1",
        [hid, tid]).fetchone()
    db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?",
               [prev['completed_at'] if prev else None, tid, hid])
    db.commit()
    return jsonify({'ok': True})

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
    if (request.get_json(silent=True) or {}).get('approved', True):
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
    d = request.get_json(silent=True) or {}
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
    filter_member = request.args.get('memberId') or None  # None/'all' = everyone

    tasks   = [dict(r) for r in db.execute("SELECT * FROM tasks WHERE household_id=?", [hid])]
    if filter_member and filter_member != 'all':
        tasks = [t for t in tasks if not t['assigned_to'] or t['assigned_to'] == filter_member]
    members = {r['id']: dict(r) for r in db.execute("SELECT * FROM members WHERE household_id=?", [hid])}
    rooms   = {r['id']: dict(r) for r in db.execute("SELECT * FROM rooms WHERE household_id=?", [hid])}
    history = [dict(r) for r in db.execute(
        "SELECT task_id, completed_at, type FROM history WHERE household_id=? AND completed_at LIKE ?",
        [hid, f'{year}-{month:02d}%'])]
    done_dates = {}
    missed_dates = {}
    for h in history:
        d = h['completed_at'][:10]
        if h['type'] == 'missed':
            missed_dates.setdefault(d, set()).add(h['task_id'])
        else:
            done_dates.setdefault(d, set()).add(h['task_id'])

    # Full completion history (not just this month) is needed to know, for any
    # given day, which cycle the task is on - both real completions and
    # expire_task() "missed" entries advance last_completed, so every row here
    # is a valid cycle anchor.
    all_anchors = {}
    for r in db.execute("SELECT task_id, completed_at FROM history WHERE household_id=?", [hid]):
        all_anchors.setdefault(r['task_id'], []).append(datetime.fromisoformat(r['completed_at']).date())
    for k in all_anchors:
        all_anchors[k].sort()

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
            anchors_before = [a for a in all_anchors.get(t['id'], []) if a <= day.date()]

            # "Skip only this occurrence" (expire_task with a target date)
            # lands its anchor exactly on the skipped day, which would
            # otherwise still satisfy the cycle-day check below (diff=0).
            # Hide the task from that specific day entirely instead of
            # showing it as done — it was skipped, not completed.
            if not t.get('one_time') and t['id'] in missed_dates.get(day_iso, set()):
                continue

            if t.get('one_time'):
                # One-time tasks have no recurrence at all: show only on the day
                # they were created, never smeared across every following day.
                if day.date() != created.date():
                    continue
            elif t.get('specific_days'):
                # show only on the chosen weekdays
                chosen = [int(x) for x in t['specific_days'].split(',') if x.strip().isdigit()]
                if day_dow not in chosen:
                    continue
            else:
                # Discrete recurring schedule: mark exactly the cycle days (the
                # anchor itself, then every freq_days after it), not every day
                # from the anchor onward - a sticky "still due" window tiled the
                # whole month with no gaps and looked like a daily task no
                # matter what the actual frequency was.
                freq_days = FREQ_DAYS.get(t['freq'], 7)
                anchor = anchors_before[-1] if anchors_before else created.date()
                diff = (day.date() - anchor).days
                if diff < 0 or diff % freq_days != 0:
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
    d = request.get_json(silent=True) or {}
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
    member_id = (request.get_json(silent=True) or {}).get('memberId') or u.get('member_id')
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

# ── CLAUDE (smart parsing for the voice assistant; optional) ──
def claude_intent(transcript, rooms, members, tasks):
    """Turn a free-form voice command into a structured intent via Claude.
    Uses ANTHROPIC_API_KEY; model overridable with CLAUDE_MODEL (default
    claude-haiku-4-5-20251001). Returns a dict or None → caller falls back to keywords."""
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        return None
    try:
        import anthropic
    except Exception:
        return None
    rooms_txt   = "\n".join(f"- id={r['id']} | {r['name']}" for r in rooms) or "(none)"
    members_txt = "\n".join(f"- id={m['id']} | {m['name']}" for m in members) or "(none)"
    tasks_txt   = "\n".join(f"- id={t['id']} | {t['name']} | room_id={t['room_id']}" for t in tasks) or "(none)"
    system = (
        "You are the voice assistant of a family chore app. The user speaks English, Polish or "
        "Ukrainian. Decide what to do and reply with a JSON object ONLY — no prose, no markdown. "
        'Schema: {"action":"add_task|complete_task|unknown","task_id":"","task_name":"",'
        '"room_id":"","member_id":"","diff":"easy|medium|hard",'
        '"freq":"daily|weekly|biweekly|monthly","approval":false,"one_time":false}. '
        "If the user reports they DID/finished a chore → action complete_task and set task_id to the "
        "closest existing task id. If they WANT/need to add a chore → action add_task with a "
        "short task_name in the user's language. Otherwise action unknown. "
        "member_id = the household member the chore is ASSIGNED to — match by name or role word "
        "('mom/mama/mamie'→a member named Mama, 'dad/tata'→Tata, a child's name→that member); "
        "leave empty if the user did not say who. "
        "approval = true only if the user says it must be approved/checked/confirmed by a parent. "
        "one_time = true if the user says it is a one-off / only once / just today. "
        "freq = a sensible recurrence for the chore when recurring (dishes/trash→daily, "
        "vacuum/floors→weekly, windows→monthly); use 'weekly' if unsure. "
        "Use empty strings / false when not applicable."
    )
    prompt = (f"ROOMS:\n{rooms_txt}\n\nMEMBERS:\n{members_txt}\n\nEXISTING TASKS:\n{tasks_txt}\n\n"
              f'USER SAID: "{transcript}"\n\nReturn only the JSON object.')
    try:
        client = anthropic.Anthropic(api_key=api_key)
        msg = client.messages.create(
            model=os.environ.get('CLAUDE_MODEL', 'claude-haiku-4-5-20251001'),
            max_tokens=400,
            system=system,
            messages=[{"role": "user", "content": prompt}],
        )
        text = "".join(b.text for b in msg.content if b.type == "text").strip()
        # Be tolerant if the model wraps the JSON in fences/prose.
        start, end = text.find('{'), text.rfind('}')
        if start != -1 and end != -1:
            text = text[start:end + 1]
        intent = json.loads(text)
        return intent if isinstance(intent, dict) else None
    except Exception:
        return None

def _voice_complete(db, hid, task, member_id):
    """Award a completion (points/coins/streak/history/cleanliness/badges)."""
    pts = DIFF_PTS.get(task['diff'], 1)
    now_iso = datetime.now().isoformat()
    today = datetime.now().strftime('%Y-%m-%d')
    member = db.execute("SELECT * FROM members WHERE id=? AND household_id=?", [member_id, hid]).fetchone()
    if member:
        m = dict(member)
        streak = m['streak'] + 1 if m['streak_date'] != today else m['streak']
        db.execute("UPDATE members SET points=points+?,coins=coins+?,streak=?,streak_date=? WHERE id=? AND household_id=?",
                   [pts, pts, streak, today, member_id, hid])
    db.execute("UPDATE tasks SET last_completed=? WHERE id=? AND household_id=?", [now_iso, task['id'], hid])
    db.execute("UPDATE rooms SET cleanliness=MIN(100,cleanliness+?),last_cleaned=? WHERE id=? AND household_id=?",
               [min(pts * 8, 22), now_iso, task['room_id'], hid])
    db.execute("INSERT INTO history(id,household_id,task_id,member_id,completed_at,pts,coins_earned) VALUES (?,?,?,?,?,?,?)",
               [uid(), hid, task['id'], member_id, now_iso, pts, pts])
    db.commit()
    return pts, check_achievements(db, member_id, hid)

# ── VOICE ─────────────────────────────────────────────────────
@app.route('/api/voice', methods=['POST'])
@limiter.limit('30 per hour;6 per minute')
def voice_command():
    err = require_auth(); hid = get_hid()
    if err: return err
    body = request.get_json(silent=True) or {}
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
    FREQ_LABELS = {'daily':'codziennie','weekly':'co tydzień','biweekly':'co 2 tyg.','monthly':'co miesiąc','custom':'własne'}
    APPROVAL_WORDS = ['zatwierdz','akceptacj','do akceptacji','approval','approve','confirm','підтвердж']
    ONETIME_WORDS = ['jednorazow','tylko raz','jeden raz','one-time','one time','once','одноразов','лише раз']
    FREQ_WORDS = {
        'daily':   ['codziennie','codzienne','każdego dnia','daily','every day','щодня','щоденно'],
        'monthly': ['miesiąc','miesięcznie','co miesiąc','monthly','every month','щомісяця','kwartał','quarter'],
        'biweekly':['dwa tygodnie','2 tygodnie','co dwa tygodnie','biweekly','двотижн'],
        'weekly':  ['tydzień','tygodniowo','co tydzień','weekly','every week','щотижня'],
    }
    def detect_freq(text):
        for fk, fwords in FREQ_WORDS.items():
            if any(w in text for w in fwords): return fk
        return 'weekly'
    def add_msg(name, rname, freq, mname, one_time, approval):
        parts = [f'➕ "{name}"']
        if rname: parts.append(rname)
        parts.append(FREQ_LABELS.get(freq, freq))
        if mname: parts.append(f'dla {mname}')
        if one_time: parts.append('jednorazowe')
        if approval: parts.append('wymaga zatwierdzenia')
        return ' · '.join(parts)

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

    # ── Smart parsing via Claude (falls back to keyword logic below) ──
    intent = claude_intent(transcript, rooms, members, tasks)
    if intent and intent.get('action') in ('add_task', 'complete_task'):
        gm = next((m for m in members if m['id'] == intent.get('member_id')), None) or find_member(transcript)
        if intent['action'] == 'complete_task':
            trow = db.execute("SELECT * FROM tasks WHERE id=? AND household_id=?",
                              [intent.get('task_id', ''), hid]).fetchone()
            if trow:
                task = dict(trow)
                member_id = (gm or {}).get('id') or task['assigned_to'] or ''
                if member_id:
                    pts, new_badges = _voice_complete(db, hid, task, member_id)
                    who = (gm or {}).get('name', '?')
                    return jsonify({'action': 'complete_task',
                                    'message': f'✅ {who}: "{task["name"]}" +{pts}',
                                    'new_badges': new_badges})
            # no matching task → fall through to keyword logic
        else:  # add_task
            room_id = intent.get('room_id') or ''
            if not any(r['id'] == room_id for r in rooms):
                room_id = rooms[0]['id'] if rooms else ''
            member_id = (gm or {}).get('id') or (members[0]['id'] if members else '')
            diff = intent.get('diff') if intent.get('diff') in ('easy', 'medium', 'hard') else 'medium'
            freq = intent.get('freq') if intent.get('freq') in ('daily','weekly','biweekly','monthly') else detect_freq(transcript)
            approval = 1 if (intent.get('approval') or any(w in transcript for w in APPROVAL_WORDS)) else 0
            one_time = 1 if (intent.get('one_time') or any(w in transcript for w in ONETIME_WORDS)) else 0
            name = (intent.get('task_name') or '').strip()[:60] or 'Sprzątanie'
            db.execute(
                "INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at,one_time) VALUES (?,?,?,?,?,?,?,NULL,?,?,?)",
                [uid(), hid, name, room_id, member_id, freq, diff, approval, datetime.now().isoformat(), one_time])
            db.commit()
            rname = next((r['name'] for r in rooms if r['id'] == room_id), '')
            mname = next((m['name'] for m in members if m['id'] == member_id), '')
            return jsonify({'action': 'add_task', 'message': add_msg(name, rname, freq, mname, one_time, approval)})

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
        freq = detect_freq(transcript)
        approval = 1 if any(w in transcript for w in APPROVAL_WORDS) else 0
        one_time = 1 if any(w in transcript for w in ONETIME_WORDS) else 0
        db.execute("INSERT INTO tasks(id,household_id,name,room_id,assigned_to,freq,diff,last_completed,approval_needed,created_at,one_time) VALUES (?,?,?,?,?,?,?,NULL,?,?,?)",
                   [uid(), hid, task_name, room_id, member_id, freq, 'medium', approval, datetime.now().isoformat(), one_time])
        db.commit()
        mname = next((m['name'] for m in members if m['id']==member_id), '')
        return jsonify({'action':'add_task',
                        'message': add_msg(task_name, room['name'] if room else '', freq, mname, one_time, approval)})

    return jsonify({'action':'unknown','message':'Nie rozumiem. Powiedz np. "Chcę odkurzyć salon".'})

if __name__ == '__main__':
    _ensure_db()
    # Debug is OFF by default — the Werkzeug debugger is a remote-code-execution
    # risk if ever exposed. Enable explicitly with FLASK_DEBUG=1 for local dev.
    debug = os.environ.get('FLASK_DEBUG', '0') == '1'
    app.run(debug=debug, host='0.0.0.0', port=5000, use_reloader=False)
