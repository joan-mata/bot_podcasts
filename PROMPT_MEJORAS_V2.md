# PROMPT MEJORAS V2 — bot_podcasts
# Ejecutar desde la raíz del proyecto: claude "lee PROMPT_MEJORAS_V2.md y ejecuta"

---

## CONTEXT

Existing project: personal podcast/YouTube curator bot.
Stack: n8n (Docker) + Telegram bot + Claude API + Spotify API + PostgreSQL (NEW) + Web app (NEW).
Read CLAUDE.md, AGENT.md, all workflows/ and scripts/ before touching anything.

## LANGUAGE RULES
- Code, keys, variables, node names → English
- User-facing content (bot messages, web UI, README, AGENT.md) → Spanish
- Prompts under prompts/ → Spanish

## TOKEN EFFICIENCY
Telegraphic style in all prompts and agent instructions. No filler.

---

## CHANGES REQUIRED

### 1. POSTGRESQL — new service in docker-compose.yml

Add PostgreSQL container:
```yaml
postgres:
  image: postgres:16-alpine
  user: "999:999"
  restart: unless-stopped
  environment:
    POSTGRES_DB: ${POSTGRES_DB}
    POSTGRES_USER: ${POSTGRES_USER}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  volumes:
    - postgres_data:/var/lib/postgresql/data
    - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
  networks:
    - internal
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
    interval: 10s
    retries: 5
```

Add to volumes: `postgres_data:`
Add to .env.example:
```
POSTGRES_DB=curator
POSTGRES_USER=curator
POSTGRES_PASSWORD=        # Elige contraseña segura
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
```

### 2. DB SCHEMA — db/init.sql

Create tables:
```sql
-- Episodes seen/saved by user
CREATE TABLE episodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL CHECK (source IN ('podcast','youtube','article')),
  title TEXT NOT NULL,
  show_name TEXT,
  url TEXT,
  duration_minutes INTEGER,
  listened_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'saved' CHECK (status IN ('saved','listened','dismissed')),
  topic_score NUMERIC(3,1),
  host_score NUMERIC(3,1),
  user_note TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Normalised text search index
CREATE INDEX idx_episodes_search ON episodes
  USING gin(to_tsvector('spanish', coalesce(title,'') || ' ' || coalesce(show_name,'')));

-- Spotify shows cache
CREATE TABLE spotify_shows (
  show_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  rss_url TEXT,
  description TEXT,
  synced_at TIMESTAMPTZ DEFAULT NOW()
);

-- Web users (for web app login)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 3. SEARCH NORMALIZATION — shared utility

Create `scripts/normalize.js` (Node.js, used by n8n Function nodes and web app):
```js
// Normalize text for fuzzy search: lowercase, remove accents, trim
function normalize(str) {
  return str
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')  // remove accents
    .replace(/[^a-z0-9\s]/g, ' ')    // remove special chars
    .replace(/\s+/g, ' ')
    .trim();
}
// Also expose PostgreSQL function via init.sql:
// CREATE OR REPLACE FUNCTION norm(t TEXT) RETURNS TEXT AS $$
//   SELECT lower(unaccent(regexp_replace(t, '[^a-zA-Z0-9\s]', ' ', 'g')));
// $$ LANGUAGE sql IMMUTABLE;
module.exports = { normalize };
```

Add to init.sql:
```sql
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE OR REPLACE FUNCTION norm(t TEXT) RETURNS TEXT AS $$
  SELECT lower(unaccent(regexp_replace(coalesce(t,''), '[^a-zA-Z0-9\s]', ' ', 'g')));
$$ LANGUAGE sql IMMUTABLE;
CREATE INDEX idx_episodes_norm ON episodes (norm(title), norm(show_name));
```

All searches (bot + web) must use norm() for comparison. Never raw string match.

### 4. TELEGRAM BOT — command changes

Modify v2_telegram_conversation.json workflow. Update command routing:

**`/lista`** (NEW behavior — single text message, no pagination):
- Query: `SELECT source, title, show_name, duration_minutes, status FROM episodes WHERE status='saved' ORDER BY created_at DESC`
- Format as single compact message:
```
📋 *Tu lista* (N episodios)

🎙 Podcast · Título del episodio — 45min
📺 YouTube · Título del vídeo — 12min
...
```
- If >50 items, show last 50 + "Usa /lista_editar para gestionar"
- No inline buttons in this view

**`/lista_editar`** (RENAMED from old /lista):
- Same as old /lista but with inline buttons per item:
  `[✅ Marcar escuchado] [🗑 Eliminar] [✏️ Editar nota]`
- callback_data: `mark_listened:{id}`, `delete_episode:{id}`, `edit_note:{id}`
- Paginate: 10 items per message, navigation buttons `[← Anterior] [Siguiente →]`

**`/episodios`** (NEW):
- Query: `SELECT * FROM episodes WHERE status='listened' ORDER BY listened_at DESC LIMIT 20`
- Format:
```
✅ *Episodios escuchados* (N total)

🎙 Podcast · Título — escuchado 12 abr
  ⭐ Tema: 8/10 · Presentador: 7/10
📺 YouTube · Título — escuchado 10 abr
...
```

**Edit/delete callbacks:**
- `mark_listened:{id}` → UPDATE episodes SET status='listened', listened_at=NOW()
- `delete_episode:{id}` → DELETE FROM episodes WHERE id='{id}' (ask confirmation first: "¿Seguro? [Sí, borrar] [Cancelar]")
- `edit_note:{id}` → bot asks "Escribe tu nota:" → next message stored as user_note

**Proactive report (free text):**
When user reports consuming content → INSERT into episodes with status='listened'.
When user saves content for later → INSERT with status='saved'.
Use norm() for deduplication check before insert:
```sql
SELECT id FROM episodes WHERE norm(title) = norm($1) AND norm(show_name) = norm($2)
```

**Spotify sync command `/sync_spotify`:**
- Fetch followed shows from Spotify API
- For each show: upsert into spotify_shows, upsert into episodes with status='saved' if not already present
- Use norm() for name matching to avoid duplicates
- Report: "Sincronizado: N nuevos podcasts añadidos, M ya existían"

### 5. WEB APP — new service

Create `webapp/` directory. Stack: **Node.js + Express + plain HTML/CSS** (no framework, keep it simple).

**docker-compose.yml** — add:
```yaml
webapp:
  build: ./webapp
  restart: unless-stopped
  ports:
    - "127.0.0.1:3000:3000"
  env_file: .env
  depends_on:
    postgres:
      condition: service_healthy
  networks:
    - internal
```

**webapp/Dockerfile:**
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
USER node
CMD ["node", "server.js"]
```

**webapp/server.js** — Express app with:
- `POST /auth/register` — bcrypt hash, insert users table
- `POST /auth/login` — verify, return JWT (httpOnly cookie, 7d expiry)
- `GET /auth/logout`
- Auth middleware: verify JWT on all /api routes
- `GET /api/episodes` — list with filters: status, source, search (uses norm())
- `POST /api/episodes` — add episode manually or via Spotify URL/podcast name
- `PATCH /api/episodes/:id` — update status, scores, note
- `DELETE /api/episodes/:id` — soft delete (status='dismissed')
- `POST /api/spotify/sync` — trigger Spotify sync (same logic as bot /sync_spotify)
- `GET /api/stats` — counts by status/source, top shows

**webapp/public/index.html** — JustWatch-style UI:
- Login/register page (shown if not authenticated)
- After login: grid/list view of episodes
- Filters sidebar: All / Saved / Listened / Source (Podcast/YouTube)
- Search bar (debounced, calls /api/episodes?q=..., uses norm() on backend)
- Each card: thumbnail if available, title, show, duration, status badge, score stars
- Quick actions on hover: ✅ Mark listened, 🗑 Delete, ✏️ Note
- "Add episode" button: paste URL or type name → auto-fetch metadata
- Spotify sync button → calls /api/spotify/sync
- Minimal CSS: dark theme, CSS Grid, no JS framework, vanilla fetch()

**webapp/public/style.css** — dark theme inspired by JustWatch:
- Background: #0f0f0f, cards: #1a1a1a, accent: #e50914 (or #6366f1 for less Netflix)
- CSS Grid for card layout, responsive (1-2-3-4 columns)
- Simple, fast, no animations

### 6. AUTO-IMPORT — reduce manual entry

Both bot and web must support these auto-import methods:

**By Spotify show URL:**
- User pastes `https://open.spotify.com/show/xxx`
- Fetch show metadata from Spotify API
- Look up RSS via Podcast Index API by show name (norm() match)
- Insert into episodes + spotify_shows

**By podcast name (fuzzy):**
- Search Podcast Index + iTunes by norm(name)
- Return top 3 matches with inline buttons: "[✓ Este] [✓ Este] [✓ Este]"
- User selects → insert

**By YouTube URL:**
- Parse video ID from URL
- Fetch title/channel/duration via YouTube Data API
- Insert into episodes

**By YouTube channel name:**
- Search YouTube Data API channels
- Add to youtube_channels in user_profile.json + fetch latest videos

All lookups use norm() for name comparison. Store original name but index norm(name).

### 7. .env.example — add new vars

```
# PostgreSQL
POSTGRES_DB=curator
POSTGRES_USER=curator
POSTGRES_PASSWORD=
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Web app
WEBAPP_PORT=3000
JWT_SECRET=            # Generado por setup.sh (openssl rand -hex 32)
JWT_EXPIRY=7d
BCRYPT_ROUNDS=12
```

### 8. scripts/setup.sh — update

Add:
- Generate JWT_SECRET if not set (openssl rand -hex 32)
- Wait for postgres healthcheck before proceeding
- Print webapp URL: http://localhost:3000

### 9. AGENT.md — update (Spanish)

Add sections:
- Comandos nuevos: /lista, /lista_editar, /episodios, /sync_spotify
- Cómo manejar edición/borrado de episodios (confirmación antes de borrar)
- Normalización de búsqueda: siempre usar norm() — sin distinción mayúsculas/minúsculas/acentos
- Deduplicación: comprobar norm(title)+norm(show_name) antes de insertar
- Cómo interpretar URLs de Spotify/YouTube pegadas por el usuario

### 10. README.md — update (Spanish)

Add sections:
- Web app: acceso en http://localhost:3000
- Nuevos comandos del bot
- Cómo hacer sync con Spotify
- Cómo añadir episodios (bot + web)

---

## DIRECTORY STRUCTURE (additions only)

```
bot_podcasts/
├── db/
│   └── init.sql                    ← NEW
├── webapp/
│   ├── Dockerfile                  ← NEW
│   ├── package.json                ← NEW
│   ├── server.js                   ← NEW
│   └── public/
│       ├── index.html              ← NEW
│       └── style.css               ← NEW
└── scripts/
    └── normalize.js                ← NEW
```

---

## QUALITY REQUIREMENTS

- All DB queries use parameterized statements (no string interpolation)
- All searches use norm() — no exceptions
- Delete always asks confirmation via inline keyboard before executing
- JWT stored as httpOnly cookie, never in localStorage
- Passwords: bcrypt with BCRYPT_ROUNDS=12
- webapp container runs as non-root (USER node)
- Deduplication check before every INSERT into episodes
- n8n Function nodes that query PostgreSQL use the `pg` npm package via HTTP Request to a simple query endpoint in webapp, OR use n8n's built-in Postgres node with credentials from env
- Prefer n8n built-in Postgres node over HTTP calls to webapp

---

## EXECUTION ORDER

1. Read all existing files (CLAUDE.md, workflows/, scripts/, prompts/)
2. db/init.sql
3. Update docker-compose.yml + .env.example
4. scripts/normalize.js
5. webapp/ (Dockerfile, package.json, server.js, public/)
6. Update workflows/v2_telegram_conversation.json (new commands + DB queries)
7. Update scripts/setup.sh
8. Update AGENT.md + README.md
9. Run: docker compose up -d --build
10. Verify: curl http://localhost:3000

Start now.
