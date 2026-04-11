# Prompt maestro — Curador de contenidos personal
# Para usar en Claude Code: pega todo esto en el terminal de `claude`

---

## INSTRUCCIÓN PARA CLAUDE CODE

You are an expert engineer in self-hosting, n8n, Docker, and personal automation.
Build a complete, fully functional project. No placeholders. No TODOs. Real working code.

### LANGUAGE RULES (strict):
- All code, comments, variable names, JSON keys, workflow nodes, scripts → **English**
- Files the user reads directly → **Spanish**: README.md, AGENT.md, data/user_profile.json, all files under prompts/
- CLAUDE.md → **English** (it's for Claude Code, not the user)
- Log/error messages in scripts → English

### TOKEN EFFICIENCY (strict):
Write all prompts and agent instructions in compressed, telegraphic style.
No filler. No politeness padding. No restating context. Direct imperatives.
Bad: "Please make sure to carefully consider the user's preferences when..."
Good: "Filter by user weight. Discard score<3. Max 8 items."

---

## PROJECT DESCRIPTION

Personal content curation system with feedback loop and taste learning:

1. **Onboarding:** connect to Spotify API (free, public) → import followed podcasts + listening history → run progressive survey via Telegram (3-5 questions/day over first week) to build initial taste profile.
2. **Weekly digest:** collect new podcast episodes (RSS known feeds) + discover unknown podcasts by topic (free APIs) + YouTube videos + optional websites → Claude filters/scores/summarizes by personal profile → deliver via Telegram.
3. **Feedback on recommendations:** every digest item has Telegram inline buttons → user rates topic, host, format → profile auto-updates.
4. **Proactive user reports:** user can message the bot at any time with free-text like "me ha gustado el podcast de Huberman de hoy" or "vi este vídeo de YouTube y me encantó: {url}" → bot understands, asks 1-2 follow-up questions, updates profile. No commands needed, just natural language.
5. **Bidirectional conversation:** user adjusts preferences, asks for details, gives feedback → Claude updates profile JSON.
6. **Apple Calendar (CalDAV) read-only** → suggest when to consume content based on free slots. NEVER create/modify/delete events without explicit "sí" from user.

Stack: **n8n (Docker) + Claude API + Spotify API (free) + Telegram Bot + YouTube Data API v3 (free) + CalDAV (Apple Calendar) + RSS + free podcast discovery APIs**

Server: Linux, Docker already installed.

---

## ALL FREE APIs — NO PAID SERVICES

**Spotify (free public API):**
- OAuth2 PKCE flow for initial auth (one-time browser step)
- Scopes needed: `user-follow-read`, `user-read-recently-played`, `user-library-read`
- Endpoints: `/me/following?type=show` (followed podcasts), `/me/player/recently-played` (history)
- Token refresh: automatic via refresh_token stored in `data/spotify_token.json` (gitignored)
- Completely free, no paid tier needed

**Podcast discovery (unknown podcasts by topic):**
- **Listen Notes API** (free tier: 10k calls/month) → search by keyword/topic/trend
- **Podcast Index API** (completely free, open) → search by tag, trending, recent
- **iTunes Search API** (Apple, completely free, no key needed) → search by term
- Use all three, deduplicate, score by topic relevance

**YouTube:** YouTube Data API v3 — free (10k units/day). Search by keyword, filter by date.

**Apple Calendar:** CalDAV. PROPFIND HTTP. iCloud URL: https://caldav.icloud.com. Read-only.

**No Google Calendar.** Apple Calendar via CalDAV only.

**Email:** SMTP (user's own provider, free).

**Telegram:** Free bot API with inline keyboard buttons.

---

## SECURITY REQUIREMENTS (maximum)

Apply ALL without exception:

**Secrets:**
- All secrets in `.env` only, never hardcoded
- `.env`, `data/`, `data/spotify_token.json` in `.gitignore`
- `.env.example` no real values
- Secrets never logged, never in n8n workflow JSON exports

**Network:**
- n8n bind to `127.0.0.1:5678:5678` only
- Telegram webhook: validate `X-Telegram-Bot-Api-Secret-Token` header on every request
- n8n behind basic auth
- Webhook requires HTTPS — documented in README

**Spotify OAuth tokens:**
- Access token + refresh token stored in `data/spotify_token.json` (gitignored, chmod 600)
- Never logged, never in env vars after initial auth

**Apple Calendar (CalDAV):**
- Credentials in `.env` only, HTTPS only
- Only PROPFIND/REPORT allowed, never PUT/DELETE/POST

**Rate limiting:**
- All external API calls: retry with exponential backoff (3 attempts)
- YouTube quota guard
- Spotify: respect 429 rate limits with backoff

**Input validation:**
- Telegram: validate `chat_id` === `TELEGRAM_CHAT_ID` before any processing
- Reject unknown senders silently

**Docker:**
- n8n: `user: "1000:1000"`, no `privileged: true`

**Generated secrets:**
- `setup.sh` auto-generates `TELEGRAM_WEBHOOK_SECRET` (32 random hex chars)

---

## FEEDBACK LOOP SYSTEM — DETAILED SPEC

This is the core intelligence of the system. Implement fully.

### A. Spotify Onboarding (v0)

**Trigger:** first run, or user sends `/onboarding` to bot.

**Step 1 — Spotify import:**
- OAuth2 PKCE: generate auth URL, send to user via Telegram, user opens in browser, pastes callback URL back to bot (or bot catches redirect if webhook URL configured)
- Fetch followed podcasts (`/me/following?type=show`, paginate all)
- Fetch recently played (`/me/player/recently-played?limit=50`)
- Populate `known_podcasts` in profile with Spotify data: name, RSS URL (look up via Podcast Index by show name), language, estimated priority=5 (to be refined)

**Step 2 — Progressive survey (Telegram):**
- Do NOT send all questions at once. Schedule: 3-5 questions/day for up to 5 days.
- Store survey state in `data/onboarding_state.json`
- Question types (use Telegram inline keyboard buttons for answers):

```
Tipo 1 — Frecuencia de escucha:
"¿Con qué frecuencia escuchas [Podcast Name]?"
[Cada episodio] [A veces] [Raramente] [Ya no lo escucho]

Tipo 2 — Completitud:
"Cuando empiezas un episodio de [Podcast Name], ¿sueles terminarlo?"
[Siempre] [La mayoría] [Solo si engancha] [Suelo dejarlo]

Tipo 3 — Tema vs presentador:
"¿Qué te atrae más de [Podcast Name]?"
[El tema principal] [El presentador] [Los invitados] [Todo]

Tipo 4 — Ranking relativo:
"Entre estos dos, ¿cuál prefieres?"
[Podcast A] [Podcast B] [Los dos igual]

Tipo 5 — Tema libre:
"¿Qué temas te gustaría descubrir que aún no escuchas en podcast?"
(free text — Claude interprets and maps to interest weights)
```

- After survey completion: Claude recalculates all interest weights and podcast priorities, writes updated profile, sends summary: "He aprendido esto sobre tus gustos: ..."

### B. Inline Feedback Buttons on Digest Items

Every item in the weekly digest gets inline keyboard buttons appended:

**For podcast episodes:**
```
[👍 Bien] [👎 No era para mí] [⭐ Puntuar] [💬 Más info]
```

**For YouTube videos:**
```
[👍 Bien] [👎 No era para mí] [⭐ Puntuar] [💬 Más info]
```

When user taps **⭐ Puntuar**, bot sends follow-up message with buttons:

```
Puntúa "[Título]":

Tema:      [1] [2] [3] [4] [5]
Presentador/Canal: [1] [2] [3] [4] [5]
¿Lo recomendarías? [Sí] [No]
```

Bot stores ratings in `data/ratings_history.json` and updates the item's entry in `known_podcasts` or `youtube_channels` in profile.

When user taps **👍 Bien** or **👎 No era para mí**: quick rating (positive/negative signal), no follow-up questions. Updates implicit score.

### C. Proactive User Reports (free-text, any time)

User can send ANY natural language message reporting content they consumed on their own:

Examples the system must handle:
- "me ha gustado el último episodio de Huberman"
- "acabo de escuchar un podcast increíble sobre historia de Roma, se llama Historia de Roma con Mike Duncan"
- "vi este vídeo y me encantó: https://youtube.com/watch?v=xxx"
- "estuve escuchando Lex Fridman con Sam Altman y no me convenció mucho"
- "descubrí un podcast nuevo: [nombre] y me parece muy bueno"

**How the bot handles this:**
1. V2 conversation workflow receives the message
2. Claude identifies it as a "proactive feedback report" (vs a question or preference change)
3. Claude extracts: content type (podcast/youtube/article), title/URL, sentiment (positive/negative/mixed), any mentioned reason
4. Claude asks 1-2 targeted follow-up questions based on what's missing:
   - If podcast not in profile: "¿Quieres que lo añada a tu lista de seguidos?"
   - If YouTube: "¿Es de un canal que debería seguir para ti?"
   - If positive + reason vague: "¿Qué es lo que más te ha gustado — el tema, el presentador, o cómo lo explicaron?"
5. Claude updates profile: adds/updates item, adjusts interest weights, stores in interaction_history
6. Bot confirms: "Anotado. He subido el peso de [tema] a [N] y añadido [podcast] a tu lista."

**The agent must distinguish:**
- Proactive report → extract + ask 1-2 questions + update profile
- Preference change ("ya no me interesa X") → update directly + confirm
- Question ("¿qué podcast me recomiendas sobre X?") → answer + optionally update profile
- Digest feedback (button tap) → handled by callback query handler

### D. Profile Learning Rules (for AGENT.md)

```
Scoring update rules:
- 👍 quick like: item_score += 0.5, topic_weight += 0.2
- 👎 quick dislike: item_score -= 0.5, topic_weight -= 0.1
- ⭐ full rating: replace item_score with (topic_score + host_score) / 2
- Proactive positive report: topic_weight += 0.5, host_affinity += 0.3 if host mentioned
- Proactive negative report: topic_weight -= 0.2
- Survey completion rate signal: podcast priority = f(frequency + completion_rate)
- All weights capped at [1, 10], floor at 1
- Recalculate discovery search terms after every 5 profile updates
```

---

## FILES TO CREATE

### 1. `CLAUDE.md` (English)
Project overview for Claude Code. Include:
- Full stack + all APIs
- Directory structure with language annotations
- All env vars
- How to test each component (Spotify auth, Telegram webhook, CalDAV fetch, digest generation)
- Security model
- Spotify OAuth2 PKCE flow explanation
- CalDAV iCloud app-specific password requirement

### 2. `AGENT.md` (Spanish — user reads this)
Telegraphic instructions for the Claude curator agent. Sections:
- Rol y personalidad
- Leer/interpretar `data/user_profile.json` y `data/ratings_history.json`
- Proceso de scoring y filtrado de contenidos
- Proceso de descubrimiento de podcasts desconocidos
- Cómo manejar reportes proactivos del usuario (ver spec sección C)
- Reglas de actualización del perfil (ver scoring rules sección D)
- Formato exacto del digest semanal con botones inline
- Reglas Apple Calendar
- Tono: directo, personal, sin relleno

### 3. `docker-compose.yml` (English)
```yaml
services:
  n8n:
    image: n8nio/n8n:latest
    user: "1000:1000"
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./data:/data:rw
      - ./prompts:/prompts:ro
    networks:
      - internal
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
networks:
  internal:
    driver: bridge
volumes:
  n8n_data:
```

### 4. `.env.example` (English keys, Spanish comments)
```
ANTHROPIC_API_KEY=           # Tu API key de Anthropic (console.anthropic.com)
TELEGRAM_BOT_TOKEN=          # Token del bot (@BotFather → /newbot)
TELEGRAM_CHAT_ID=            # Tu chat ID personal (@userinfobot te lo da)
TELEGRAM_WEBHOOK_SECRET=     # Generado automáticamente por setup.sh

SPOTIFY_CLIENT_ID=           # Spotify Developer Dashboard → Create App (gratis)
SPOTIFY_CLIENT_SECRET=       # Spotify Developer Dashboard → Create App (gratis)
SPOTIFY_REDIRECT_URI=        # http://localhost:8888/callback (para auth inicial)

YOUTUBE_API_KEY=             # Google Cloud Console → YouTube Data API v3 (gratis)
LISTENNOTES_API_KEY=         # listen-api.com → plan Free (10k calls/mes)
PODCASTINDEX_API_KEY=        # podcastindex.org → registro gratis
PODCASTINDEX_API_SECRET=     # podcastindex.org → registro gratis

APPLE_CALDAV_URL=https://caldav.icloud.com
APPLE_CALDAV_USER=           # Tu Apple ID (email)
APPLE_CALDAV_PASSWORD=       # Contraseña específica de app: appleid.apple.com → Seguridad
APPLE_CALENDAR_NAME=Personal

N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=     # Elige una contraseña segura
N8N_HOST=localhost
N8N_PORT=5678
N8N_WEBHOOK_URL=             # URL pública si usas ngrok/cloudflare tunnel
N8N_BASIC_AUTH_ACTIVE=true

SMTP_HOST=
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=
SMTP_PASS=
SMTP_FROM=
SMTP_TO=
```

### 5. `data/user_profile.json` (English keys, Spanish values)
Full example with feedback fields:
```json
{
  "version": "1.1",
  "last_updated": "2025-01-01T00:00:00Z",
  "onboarding_complete": false,
  "interests": {
    "inteligencia_artificial": 9,
    "historia_antigua": 7,
    "filosofia_estoica": 6,
    "tecnologia": 8,
    "ciencia_cognitiva": 7,
    "emprendimiento": 5,
    "programacion": 8
  },
  "host_affinities": {},
  "avoid_topics": ["politica_española", "deportes", "cotilleo"],
  "known_podcasts": [
    {
      "name": "Lex Fridman Podcast",
      "rss_url": "https://lexfridman.com/feed/podcast/",
      "spotify_show_id": "2MAi0BvDc6GTFvKFPXnkCL",
      "language": "en",
      "priority": 9,
      "max_duration_minutes": 150,
      "feedback": {
        "topic_score": null,
        "host_score": null,
        "completion_rate": null,
        "why_i_like": [],
        "episodes_rated": 0,
        "quick_likes": 0,
        "quick_dislikes": 0
      }
    }
  ],
  "youtube_channels": [
    {
      "name": "Andrej Karpathy",
      "channel_id": "UCnM6GBSNnbnjqQDh6CbhC1w",
      "priority": 9,
      "feedback": {"quick_likes": 0, "quick_dislikes": 0, "avg_score": null}
    }
  ],
  "youtube_keywords": ["LLM tutorial 2025", "historia roma documental"],
  "websites": [
    {"name": "Hacker News", "url": "https://hnrss.org/frontpage", "type": "rss", "priority": 6}
  ],
  "discovery": {
    "enabled": true,
    "min_relevance_score": 7,
    "max_new_podcasts_per_week": 3,
    "languages": ["es", "en"],
    "search_terms_from_interests": true
  },
  "format_preferences": {
    "max_episode_duration_minutes": 90,
    "languages": ["es", "en"],
    "max_items_per_digest": 12,
    "digest_language": "es"
  },
  "consumption_schedule": {
    "preferred_slots": ["mañana 7:00-9:00", "mediodía 13:00-14:00", "noche 21:00-23:00"],
    "commute_minutes": 30,
    "weekend_longer_slots": true
  },
  "interaction_history": [],
  "profile_update_count": 0
}
```

### 6. `data/ratings_history.json` (initial empty file)
```json
{
  "ratings": [],
  "proactive_reports": []
}
```

### 7. `data/onboarding_state.json` (initial state)
```json
{
  "started": false,
  "spotify_connected": false,
  "survey_day": 0,
  "questions_asked": [],
  "questions_answered": [],
  "completed": false
}
```

### 8. `workflows/v0_onboarding.json`
Real importable n8n workflow JSON. Nodes:
1. `Webhook Trigger` — listens for `/onboarding` command or first-time auto-trigger
2. `Check Onboarding State` — read `data/onboarding_state.json`, skip if complete
3. `Generate Spotify Auth URL` — PKCE: generate code_verifier + code_challenge, build auth URL with scopes
4. `Send Auth Link` — Telegram message with URL + instructions
5. `Wait for Callback` — webhook `/webhook/spotify-callback` receives code
6. `Exchange Code for Token` — POST to Spotify `/api/token`, store in `data/spotify_token.json` (chmod 600)
7. `Fetch Followed Podcasts` — GET `/me/following?type=show`, paginate
8. `Fetch Play History` — GET `/me/player/recently-played?limit=50`
9. `Lookup RSS URLs` — for each show, search Podcast Index by name to get RSS feed URL
10. `Populate Profile` — Function node: merge Spotify data into `user_profile.json`
11. `Schedule Survey` — set survey_day=1 in onboarding_state, trigger first batch of questions
12. `Send Survey Questions` — Telegram sendMessage with inline keyboard buttons (3-5 questions)
13. `Handle Survey Answers` — webhook for callback_query, store answers, update onboarding_state
14. `Claude Profile Synthesis` — after all survey days complete: Claude API call to recalculate weights
15. `Save Final Profile` — write updated profile, mark onboarding complete
16. `Send Summary` — Telegram: "He aprendido esto sobre tus gustos: ..."

### 9. `workflows/v1_weekly_digest.json`
Real importable n8n workflow JSON. Nodes:
1. `Cron` — Monday 08:00
2. `Read Profile` — Read Binary File: `/data/user_profile.json`
3. `Parse Profile` — Function node
4. `Fetch Known RSS` — loop over known_podcasts, HTTP GET RSS, filter last 7 days
5. `Discover - ListenNotes` — HTTP Request to listen-api.listennotes.com/api/v2/search
6. `Discover - PodcastIndex` — HTTP Request with HMAC-SHA1 auth
7. `Discover - iTunes` — HTTP GET itunes.apple.com/search
8. `Merge & Score Discoveries` — Function node: deduplicate, score by topic weight
9. `YouTube Search` — YouTube Data API v3, filter publishedAfter 7 days
10. `Fetch Websites` — HTTP Request for website RSS feeds
11. `Prepare Claude Payload` — Function node: assemble all content
12. `Claude API` — POST https://api.anthropic.com/v1/messages, model claude-sonnet-4-5
13. `Save Last Digest` — write `/data/last_digest.json`
14. `Format Telegram with Buttons` — Function node: Markdown + inline_keyboard for each item with 👍 👎 ⭐ 💬 buttons, callback_data includes item_id and item_type
15. `Send Telegram` — sendMessage with reply_markup inline_keyboard
16. `Send Email` — optional SMTP node (disabled by default)
17. `Trigger V3 Calendar` — HTTP POST to v3 webhook

### 10. `workflows/v2_telegram_conversation.json`
Real importable n8n workflow JSON. Handles BOTH regular messages AND callback_query (button taps):
1. `Webhook` — POST /webhook/telegram, validate secret token header
2. `Validate Sender` — check chat_id
3. `Route by Type` — Function node: distinguish message vs callback_query
4. **Branch A — callback_query (button tap):**
   - `Parse Callback Data` — extract item_id, item_type, action (like/dislike/rate/info)
   - `Handle Quick Rating` — if 👍/👎: update ratings_history.json + profile scores
   - `Handle Rate Request` — if ⭐: send follow-up rating message with number buttons
   - `Handle Rating Response` — store full rating, update profile
   - `Answer Callback` — answerCallbackQuery to remove loading state
5. **Branch B — text message:**
   - `Read Context` — load profile + last digest + ratings history
   - `Detect Intent` — Claude API call: classify as [proactive_report | preference_change | question | feedback]
   - `Handle Proactive Report`:
     - Extract: content type, title/url, sentiment, reason
     - Ask 1-2 follow-up questions if needed
     - Update profile + ratings_history
     - Confirm to user
   - `Handle Other Intents` — general conversation with profile update if needed
   - `Update Profile if needed` — write user_profile.json
   - `Telegram Reply` — sendMessage

### 11. `workflows/v3_calendar_suggestions.json`
Real importable n8n workflow JSON:
1. `Webhook Trigger` — called by V1
2. `Read Last Digest` — `/data/last_digest.json`
3. `CalDAV Fetch` — PROPFIND to Apple CalDAV, Basic Auth, XML body, next 7 days
4. `Parse CalDAV XML` — Function node: extract events, compute free slots
5. `Claude Calendar API` — suggest slots per content item
6. `Send Telegram Supplement` — follow-up message with calendar suggestions

### 12. `scripts/setup.sh` (English code, Spanish output)
Full bash script:
- `set -euo pipefail`
- Check Docker + Docker Compose
- Create all directories including `data/`
- Copy .env.example → .env if not exists
- Generate TELEGRAM_WEBHOOK_SECRET (openssl rand -hex 32), insert into .env
- Create empty data files: ratings_history.json, onboarding_state.json
- `docker-compose up -d`
- Wait loop for n8n health check
- Print step-by-step checklist in Spanish: all API keys needed, where to get them, URL to access n8n

### 13. `scripts/import_workflows.sh` (English code, Spanish output)
Import all 4 workflows (v0, v1, v2, v3) via n8n REST API. Activate each.

### 14. `scripts/rotate_secrets.sh`
Regenerate TELEGRAM_WEBHOOK_SECRET, update .env, restart n8n, re-register Telegram webhook.

### 15. `scripts/spotify_auth.sh`
Helper script for initial Spotify OAuth2 PKCE flow from command line:
- Starts a temporary local HTTP server on port 8888
- Opens browser to Spotify auth URL
- Catches redirect, exchanges code for tokens
- Saves to `data/spotify_token.json` with chmod 600

### 16. `prompts/weekly_digest_system.md` (Spanish)
Telegraphic system prompt. Exact output format:
```
📬 *Digest — semana {N}*

🎙️ *PODCASTS CONOCIDOS* ({N})
• *[Título ep]* — Podcast · {X}min · ⭐{score}/10
  _{Resumen 1-2 frases.}_
  🔗 {url}

🔍 *DESCUBRIMIENTOS* ({N})
• *[Título ep]* — _Nuevo: {Podcast}_ · {X}min · ⭐{score}/10
  _Por qué: {razón ligada a tus intereses concretos}._
  🔗 {url}

📺 *YOUTUBE* ({N})
• *[Título]* — {Canal} · {X}min · ⭐{score}/10
  🔗 {url}

🌐 *ARTÍCULOS* (si hay)
• *[Título]* — {Fuente} · ⭐{score}/10

📅 *AGENDA* (añadido por V3)
```
Each item followed by inline buttons: [👍 Bien] [👎 No era para mí] [⭐ Puntuar] [💬 Más info]
callback_data format: `{action}:{type}:{item_id}` e.g. `like:podcast:abc123`

### 17. `prompts/conversation_system.md` (Spanish)
Telegraphic prompt for V2. Include:
- Cómo detectar intención: reporte_proactivo vs cambio_preferencia vs pregunta vs feedback_botón
- Proceso de extracción para reporte proactivo
- Cuándo hacer preguntas de seguimiento (máx 2, solo si falta info clave)
- Formato del bloque `profile_update` JSON para que n8n lo parsee y actualice el fichero
- Reglas de actualización de pesos (ver scoring rules)
- Tono: natural, directo, confirmaciones breves

### 18. `prompts/calendar_system.md` (Spanish)
Telegraphic calendar prompt. Input/output spec. Absolute rule: NO write CalDAV commands.

### 19. `prompts/onboarding_system.md` (Spanish)
Telegraphic prompt for Claude's role in onboarding survey synthesis:
- Input: lista de respuestas a preguntas del survey
- Output: JSON con pesos de intereses recalculados + prioridades de podcasts
- Cómo interpretar respuestas cualitativas ("lo escucho siempre" → completion_rate=0.9 → priority+2)
- Cómo sintetizar el resumen final para el usuario

### 20. `.gitignore`
```
.env
data/
n8n_data/
*.log
*.tmp
.DS_Store
```

### 21. `README.md` (Spanish)
Sections:
1. Qué hace este sistema (ejemplo de digest + ejemplo de feedback)
2. Cómo aprende tus gustos (Spotify onboarding + encuestas + botones + reportes libres)
3. Prerequisitos
4. Instalación (3 pasos)
5. Cómo obtener cada API gratuita:
   - Anthropic, Telegram, YouTube Data API v3, Listen Notes, Podcast Index
   - Spotify: Developer Dashboard → Create App → Client ID + Secret (gratis)
   - Apple Calendar: contraseña específica de app
6. Spotify: primer login (ejecutar `scripts/spotify_auth.sh`)
7. Cómo hablarle al bot (comandos + lenguaje natural)
8. Personalizar perfil manualmente
9. Importar flujos en n8n
10. Seguridad
11. Exponer n8n con Cloudflare Tunnel / ngrok
12. Troubleshooting
13. Roadmap

---

## DIRECTORY STRUCTURE

```
content-curator/
├── CLAUDE.md                             ← English
├── AGENT.md                              ← Spanish
├── README.md                             ← Spanish
├── docker-compose.yml
├── .env.example                          ← English keys, Spanish comments
├── .gitignore
├── data/                                 ← gitignored
│   ├── user_profile.json                 ← Spanish values
│   ├── ratings_history.json
│   ├── onboarding_state.json
│   ├── last_digest.json                  ← auto-generated
│   └── spotify_token.json                ← auto-generated, chmod 600
├── workflows/
│   ├── v0_onboarding.json
│   ├── v1_weekly_digest.json
│   ├── v2_telegram_conversation.json
│   └── v3_calendar_suggestions.json
├── prompts/
│   ├── weekly_digest_system.md           ← Spanish
│   ├── conversation_system.md            ← Spanish
│   ├── calendar_system.md                ← Spanish
│   └── onboarding_system.md              ← Spanish
└── scripts/
    ├── setup.sh
    ├── import_workflows.sh
    ├── rotate_secrets.sh
    └── spotify_auth.sh
```

---

## QUALITY REQUIREMENTS

- All code: functional, complete, zero TODOs, zero placeholders
- n8n workflow JSONs: valid, directly importable (full n8n v1 node schema)
- Telegram inline keyboards: proper `reply_markup` JSON with `inline_keyboard` array, `callback_data` strings ≤64 bytes
- Callback query handling: `answerCallbackQuery` must be called within 10s to remove loading indicator
- Spotify PKCE: proper SHA256 code_challenge from code_verifier, base64url encoded
- Bash scripts: `set -euo pipefail`, colored output
- Claude API model: `claude-sonnet-4-5`
- CalDAV: PROPFIND with `Depth: 1`, XML time-range, parse VCALENDAR in Function node
- Podcast Index auth: HMAC-SHA1 of `apiKey + apiSecret + unixTimestamp`
- Profile scoring rules: implemented exactly as specified in feedback loop spec
- `data/spotify_token.json`: created with `chmod 600` in scripts

---

## EXECUTION ORDER

1. CLAUDE.md + AGENT.md
2. docker-compose.yml + .env.example + .gitignore
3. data/ initial files (user_profile.json, ratings_history.json, onboarding_state.json)
4. prompts/ (all 4 files)
5. workflows/ (v0 first — most complex; then v1, v2, v3)
6. scripts/ (all 4 bash files)
7. README.md
8. Verify: `bash scripts/setup.sh`

Start now. Create all files in `content-curator/` directory.
