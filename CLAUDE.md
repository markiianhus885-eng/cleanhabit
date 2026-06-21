# CleanHouse

Aplikacja webowa do zarządzania sprzątaniem dla gospodarstw domowych.

**URL produkcyjny:** https://web-production-65a7a.up.railway.app  
**Deploy:** Railway (automatyczny push do gita = deploy)

## Stack

- Backend: `app.py` — Flask 3.1.3, SQLite
- Frontend: `templates/index.html` — Vanilla JS SPA (cały UI w jednym pliku)
- AI: Anthropic SDK (asystent głosowy)
- MCP server: `mcp-package/index.js` — opublikowany na npm jako `cleanhouse-mcp@1.0.1`
- Android (stary): APK przez Bubblewrap (TWA), plik `C:\Users\Admin\app-release-signed.apk`
- Android (nowy): **Flutter** natywny klient w `flutter_app/` — konsumuje to samo API Flask. Zastępuje TWA.

## Flutter app (`flutter_app/`)

Natywny klient API (backend Flask bez zmian). `applicationId = com.cleanhouse.app`.
- Stan: `provider` + `AppState` (lib/state.dart) trzyma payload `/api/data`; mutacje → API → `refresh()`.
- Auth: sesja ciasteczkowa Flask, `dio` + `PersistCookieJar` (trwała między uruchomieniami).
- Design: redesign „Clean modern" — zielony akcent, Plus Jakarta Sans, light+dark (`lib/theme.dart`, `ChColors`). Nawigacja 5 zakładek: Today · Tasks · Rooms · Family · More.
- Logika „due today" odwzorowuje `/api/calendar` w `lib/models.dart` (`Task.isDueOn`).
- **Gotowe:** Today (+ approvals), Tasks, Rooms, auth, Family (ranking + role), Calendar, Goals, Badges, Profile, More, **i18n pl/en/uk**, **asystent głosowy**.
- **i18n:** `lib/l10n.dart` — mapa `key → [en, pl, uk]`, dostęp przez `context.t('key', {args})`. Język w `AppState.lang` (persist), zmiana w More → Język. **Plus Jakarta Sans nie ma cyrylicy** → dla `uk` używamy Manrope (`theme.dart` zależne od języka), fallback Noto Sans. Nazwy poziomów (LV_NAMES) zostają po angielsku jak w webie.
- **Asystent głosowy:** `lib/screens/assistant.dart` — `speech_to_text` + `flutter_tts` + `permission_handler`, wybór języka, POST `/api/voice`. Backend rozpoznaje słowa pl/uk/**en** (dodane). Emulator zwykle nie ma rozpoznawania mowy → działa pole tekstowe.
- **Szablony:** `lib/templates.dart` — 20 sugestii zadań + 15 szablonów celów (per język). Sugestie w arkuszu „Nowe zadanie" (przycisk 💡), szablony w „Nowy cel".
- **Role:** owner = twórca (👜 nieusuwalny). `admin` nadawany przez owner/admina. Owner+admin: zatwierdzanie zadań, zarządzanie domownikami, cele, zmiana nazwy domu (More → ołówek). Backend wymusza `is_admin` (m.in. `/api/approvals/*/approve`).
- Odznaki: `kBadgeCatalog`/`kBadgeByKey`, nazwy/opisy tłumaczone w l10n (`b_<key>_n/_d`). Zadania jednorazowe nie są usuwane od razu (`cleanup_one_time`).
- `minSdk = 24` (wymóg flutter_tts). **Backend zmiany wymagają deployu na Railway.**
- **Odłożone:** podpisany release APK (keystore `com.cleanhouse.app`).
- Build: `cd flutter_app && C:\flutter2\flutter\bin\flutter.bat build apk --debug` (emulator: `emulator-5556`).

## Struktura

```
app.py                  # Cały backend, API endpointy
templates/index.html    # Cały frontend (SPA)
static/manifest.json    # PWA manifest
static/sw.js            # Service Worker
mcp-package/index.js    # MCP server Node.js
mcp-package/package.json
requirements.txt
```

## Ważne zasady

- Frontend to jeden duży plik `templates/index.html` — nie rozbijaj na osobne pliki
- i18n: funkcje `t(key)`, `getDiff(key)`, `getFreq(key)` — zawsze dodawaj tłumaczenia dla pl/en/uk
- API zawsze zwraca `{"ok": true}` lub `{"ok": false, "error": "..."}` 
- Zadania używają camelCase w API: `roomId`, `assignedTo`, `approvalNeeded`, `oneTime`
- Twórca gospodarstwa (pierwszy user) nie może być usunięty — sprawdź `ORDER BY created_at ASC LIMIT 1`

## API endpointy

- `POST /api/auth/login` / `register`
- `GET /api/data` — wszystkie dane
- `POST /api/tasks` — dodaj zadanie
- `POST /api/tasks/<id>/complete` — oznacz jako wykonane
- `DELETE /api/tasks/<id>` — usuń zadanie
- `POST /api/rooms` — dodaj pokój
- `GET /api/leaderboard?period=week|month|all`
- `POST /api/members` — dodaj domownika
- `DELETE /api/members/<id>` — usuń (admin only, nie twórcę)
- `PUT /api/members/<id>/role` — zmień rolę

## MCP server

Opublikowany na npm: `npx -y cleanhouse-mcp`  
Narzędzia: `get_members`, `get_rooms`, `get_tasks`, `add_task`, `complete_task`, `add_room`, `get_leaderboard`

Aby zaktualizować i opublikować:
```
cd mcp-package
npm version patch
npm publish
```

## Android APK

Keystore: `C:\Users\Admin\android.keystore` (hasło lokalnie, NIE w repo).  
Package ID: `com.cleanhouse.app`  
Aby przebudować: `cd C:\Users\Admin\twa-app && bubblewrap build`
