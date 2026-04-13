# PROMPT MEJORAS V3 — bot_podcasts
# Ejecutar desde la raíz del proyecto: claude "lee PROMPT_MEJORAS_V3.md y ejecuta"

---

## CONTEXT

Personal podcast/YouTube curator bot.
Stack: n8n (Docker) + Telegram + Claude API + Spotify API + PostgreSQL (shared) + JSON files (legacy).

Read CLAUDE.md, AGENT.md, all workflows/ and scripts/ before touching anything.

## LANGUAGE RULES
- Code, keys, variables, node names, JSON keys → English
- User-facing content (bot messages, README, AGENT.md) → Spanish
- Prompts under prompts/ → Spanish
- CLAUDE.md → English

## TOKEN EFFICIENCY
Telegraphic style in all prompts and agent instructions. No filler.

---

## INFRASTRUCTURE CONTEXT (read before writing any code)

### postgres_shared — already running, shared homelab DB
- Container: `postgres_shared`, network: `proxy-net`
- n8n is also on `proxy-net` → can connect to `postgres_shared:5432` directly
- DB: `homelab`, User/Pass: from `../shared/.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`)
- Schema `podcasts` already exists (created in `infra/postgres/init/00_schemas.sql`)
- Extension `unaccent` already installed
- **Do NOT add a new postgres container to bot_podcasts/docker-compose.yml**

### n8n postgres connectivity
- Use the built-in **n8n Postgres node** for all DB queries (preferred over Code nodes with pg)
- Credentials name: `Postgres Shared` — configure in n8n UI once pointing to `postgres_shared:5432`, DB `homelab`
- n8n has `NODE_FUNCTION_ALLOW_EXTERNAL=pg` available as fallback in Code nodes if needed

### existing data
- `data/podcast_queue.json` — active data, 30+ episodes, must be migrated to DB
- `data/user_profile.json` — stays as JSON (profile/preferences, not episode log)
- `data/ratings_history.json` — stays as JSON (profile feedback loop)

---

## CHANGES REQUIRED

### 1. DB SCHEMA — add tables to podcasts schema

Edit `infra/postgres/init/00_schemas.sql` (in the `infra/postgres/` sibling project).
Add after `CREATE SCHEMA IF NOT EXISTS podcasts;`:

```sql
-- norm() helper — uses already-installed unaccent extension
CREATE OR REPLACE FUNCTION podcasts.norm(t TEXT) RETURNS TEXT AS $$
  SELECT lower(unaccent(regexp_replace(coalesce(t,''), '[^a-zA-Z0-9\s]', ' ', 'g')));
$$ LANGUAGE sql IMMUTABLE;

-- Episode log: every item the user saves or listens to
CREATE TABLE IF NOT EXISTS podcasts.episodes (
  id              TEXT PRIMARY KEY,                  -- keep legacy ids from podcast_queue.json
  source          TEXT NOT NULL DEFAULT 'podcast'
                    CHECK (source IN ('podcast','youtube','article')),
  title           TEXT NOT NULL,
  show_name       TEXT NOT NULL DEFAULT '',
  url             TEXT NOT NULL DEFAULT '',
  duration_min    INTEGER,
  status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','listened','skipped','dismissed')),
  rating          NUMERIC(2,0),                      -- 1-5, nullable
  user_note       TEXT,
  listened_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Full-text search index (Spanish)
CREATE INDEX IF NOT EXISTS idx_episodes_fts ON podcasts.episodes
  USING gin(to_tsvector('spanish',
    coalesce(title,'') || ' ' || coalesce(show_name,'')));

-- Normalised index for deduplication
CREATE INDEX IF NOT EXISTS idx_episodes_norm ON podcasts.episodes
  (podcasts.norm(title), podcasts.norm(show_name));

-- Spotify show cache
CREATE TABLE IF NOT EXISTS podcasts.spotify_shows (
  show_id     TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  rss_url     TEXT,
  description TEXT,
  synced_at   TIMESTAMPTZ DEFAULT NOW()
);
```

**Note:** These tables only need to be created once. The init script only runs on first postgres container start. Since `postgres_shared` is already running, apply the schema manually after editing:

```bash
# Run from infra/postgres/ — apply to running container
docker exec -i postgres_shared psql -U $POSTGRES_USER -d homelab \
  < init/00_schemas.sql
```

Or apply only the new parts:
```bash
source ../shared/.env
docker exec -i postgres_shared psql -U $POSTGRES_USER -d homelab <<'SQL'
-- paste only the new CREATE statements
SQL
```

---

### 2. MIGRATION — podcast_queue.json → podcasts.episodes

Create `scripts/migrate_queue_to_db.sh`:

```bash
#!/usr/bin/env bash
# One-time migration: data/podcast_queue.json → podcasts.episodes
# Run from project root: bash scripts/migrate_queue_to_db.sh
set -euo pipefail

source ../shared/.env

python3 - <<'PYEOF'
import json, subprocess, sys

with open('data/podcast_queue.json') as f:
    items = json.load(f)['items']

# Dedup by id (keep last occurrence)
seen = {}
for item in items:
    seen[item['id']] = item
items = list(seen.values())

rows = []
for i in items:
    # Map legacy fields to new schema
    source = 'youtube' if 'youtube.com' in (i.get('url') or '') else 'podcast'
    status = i.get('status', 'pending')
    if status not in ('pending', 'listened', 'skipped', 'dismissed'):
        status = 'pending'
    row = (
        i['id'],
        source,
        i.get('title', '').replace("'", "''"),
        (i.get('podcast') or '').replace("'", "''"),
        (i.get('url') or '').replace("'", "''"),
        i.get('duration_min'),
        status,
        i.get('rating'),
        i.get('listened_at'),
        i.get('added_at'),
    )
    rows.append(row)

sql_lines = []
for r in rows:
    dur   = 'NULL' if r[5] is None else str(int(r[5]))
    rat   = 'NULL' if r[7] is None else str(int(r[7]))
    lat   = 'NULL' if r[8] is None else f"'{r[8]}'"
    cat   = f"'{r[9]}'" if r[9] else 'NOW()'
    sql_lines.append(
        f"INSERT INTO podcasts.episodes (id,source,title,show_name,url,duration_min,status,rating,listened_at,created_at)"
        f" VALUES ('{r[0]}','{r[1]}','{r[2]}','{r[3]}','{r[4]}',{dur},'{r[6]}',{rat},{lat},{cat})"
        f" ON CONFLICT (id) DO NOTHING;"
    )

sql = '\n'.join(sql_lines)
import os
result = subprocess.run(
    ['docker', 'exec', '-i', 'postgres_shared', 'psql',
     '-U', os.environ['POSTGRES_USER'], '-d', 'homelab'],
    input=sql.encode(), capture_output=True
)
print(result.stdout.decode())
if result.returncode != 0:
    print(result.stderr.decode(), file=sys.stderr)
    sys.exit(1)
print(f"Migrated {len(rows)} episodes.")
PYEOF
```

Run after creating the schema: `bash scripts/migrate_queue_to_db.sh`

---

### 3. TELEGRAM BOT — updated commands in v2_telegram_conversation.json

Modify `workflows/v2_telegram_conversation.json`. All DB access via n8n Postgres node.
Use `podcasts.norm()` for all string comparisons. Parameterized queries only (no string interpolation).

#### Routing — add new commands to "Route by Type" Code node

Current routing handles: `/queue`, `/rate`, `/profile`, `/recommend`, `/search`, `/podcasts`, `/episodes`.
Add:
- `/lista` → route `lista`
- `/lista_editar` → route `lista_editar`
- `/episodios` → route `episodios_db`
- `/sync_spotify` → route `sync_spotify`
- callback prefixes `mark_listened:`, `delete_episode:`, `confirm_delete:`, `cancel_delete:`, `edit_note:` → route `episode_callback`

#### `/lista` — read-only list, single message, no buttons

Query:
```sql
SELECT source, title, show_name, duration_min, status
FROM podcasts.episodes
WHERE status IN ('pending','saved')
ORDER BY created_at DESC
LIMIT 50
```

Format:
```
📋 *Tu lista* (N episodios)

🎙 Podcast · Título del episodio — 45min
📺 YouTube · Título del vídeo
...
```
- Source icon: podcast → 🎙, youtube → 📺, article → 📰
- Duration: show only if not null
- If total > 50: append "_(Mostrando los últimos 50. Usa /lista\_editar para gestionar.)_"
- No inline buttons

#### `/lista_editar` — paginated list with action buttons

Query same as `/lista` but no LIMIT.
Paginate: 10 items per message.
Per item, inline keyboard row:
```
[✅ Escuchado] [🗑 Eliminar] [✏️ Nota]
```
callback_data: `mark_listened:{id}`, `delete_episode:{id}`, `edit_note:{id}`

Navigation buttons: `[← Anterior  {page}/{total_pages}  Siguiente →]`
Navigation callback_data: `lista_page:{page_number}`

#### `/episodios` — listened history

Query:
```sql
SELECT source, title, show_name, rating, listened_at
FROM podcasts.episodes
WHERE status = 'listened'
ORDER BY listened_at DESC NULLS LAST
LIMIT 20
```

Format:
```
✅ *Episodios escuchados* (N total)

🎙 Podcast · Título — escuchado 12 abr
  ⭐ 4/5
📺 YouTube · Título — escuchado 10 abr
...
```
- Date format: `D MMM` in Spanish (use `toLocaleDateString('es-ES', {day:'numeric', month:'short'})`)
- Rating only if not null

#### Callbacks — episode_callback route

**`mark_listened:{id}`**
```sql
UPDATE podcasts.episodes
SET status='listened', listened_at=NOW()
WHERE id=$1
```
Reply: "✅ Marcado como escuchado."

**`delete_episode:{id}`**
First, ask confirmation — send inline keyboard:
```
¿Eliminar este episodio?
[Sí, borrar] [Cancelar]
```
callback_data: `confirm_delete:{id}`, `cancel_delete:{id}`

**`confirm_delete:{id}`**
```sql
UPDATE podcasts.episodes SET status='dismissed' WHERE id=$1
```
Reply: "🗑 Episodio eliminado."

**`cancel_delete:{id}`**
Reply: "Cancelado."

**`edit_note:{id}`**
Bot replies: "✏️ Escribe tu nota para este episodio:"
Store `{waiting_note: id}` in workflow static data (or send as context via a Code node storing in `$execution.data`).
Next free-text message from user (if `waiting_note` set) → `UPDATE podcasts.episodes SET user_note=$1 WHERE id=$2`
Reply: "📝 Nota guardada."

#### Proactive report — free text with content mentioned

When Claude detects the user is reporting content consumed or saved:
- **INSERT** into `podcasts.episodes`, dedup check first:
  ```sql
  SELECT id FROM podcasts.episodes
  WHERE podcasts.norm(title) = podcasts.norm($1)
    AND podcasts.norm(show_name) = podcasts.norm($2)
  ```
- If no match → INSERT with new nanoid, status based on sentiment (listened/pending)
- If match → UPDATE status/rating if improvement

#### `/sync_spotify` — sync followed shows

```
1. Fetch followed shows from Spotify API (GET /me/shows, paginate)
2. For each show:
   a. UPSERT podcasts.spotify_shows (show_id, name, rss_url via Podcast Index lookup, description, synced_at)
   b. Check if in podcasts.episodes: WHERE podcasts.norm(show_name) = podcasts.norm($show_name) AND status='pending'
   c. If not present → INSERT into podcasts.episodes with source='podcast', status='pending'
3. Report: "🔄 Sincronizado: N nuevos podcasts añadidos, M ya existían."
```

---

### 4. Auto-import by URL or name (free text detection)

Both handled inside the Claude Conversation node (free-text flow):

**Spotify show URL** (`open.spotify.com/show/...`):
1. Extract show ID from URL
2. GET `https://api.spotify.com/v1/shows/{id}` → name, description
3. Lookup RSS via Podcast Index by norm(name)
4. INSERT into `podcasts.episodes` + `podcasts.spotify_shows`
5. Confirm: "Añadido: {nombre}. Ya lo tienes en tu lista."

**YouTube URL** (`youtube.com/watch?v=...` or `youtu.be/...`):
1. Extract video ID
2. GET YouTube Data API `videos?id={id}&part=snippet,contentDetails`
3. Parse duration from ISO 8601 (PT1H23M → 83 min)
4. INSERT into `podcasts.episodes` with source='youtube'
5. Confirm: "Añadido: {título} — {canal} ({N}min)."

**Podcast name (fuzzy)**:
1. Search Podcast Index + iTunes by norm(name)
2. Dedup candidates by norm(name), top 3
3. Send inline buttons: "[✓ {name1}] [✓ {name2}] [✓ {name3}]"
4. callback_data: `add_podcast:{encoded_name}:{rss_url}`
5. On selection → INSERT

All inserts: check norm() dedup before inserting.

---

### 5. AGENT.md — update (Spanish)

Add sections after existing content:

```markdown
## Comandos de episodios (base de datos)

- `/lista` — lista compacta de episodios pendientes (solo lectura, sin botones)
- `/lista_editar` — misma lista con botones por episodio: marcar escuchado, eliminar, añadir nota
- `/episodios` — historial de episodios ya escuchados con valoración y fecha
- `/sync_spotify` — sincroniza los podcasts seguidos en Spotify con la lista local

## Gestión de episodios

**Marcar escuchado:** actualiza status='listened' y listened_at=ahora.
**Eliminar:** siempre pide confirmación con botones antes de ejecutar (status='dismissed', no borrado físico).
**Añadir nota:** el bot pide un mensaje de texto libre; se guarda en user_note.

## Búsqueda y deduplicación

Todas las búsquedas de título/show usan `podcasts.norm()` — sin distinción de mayúsculas, acentos ni caracteres especiales.
Antes de cualquier INSERT, verificar: `WHERE podcasts.norm(title)=norm($1) AND podcasts.norm(show_name)=norm($2)`.
Si ya existe: actualizar en lugar de duplicar.

## Auto-import por URL o nombre

- URL de Spotify (`open.spotify.com/show/...`) → obtener metadata y añadir a lista
- URL de YouTube (`youtube.com/watch?v=...`) → obtener título/canal/duración y añadir
- Nombre de podcast (texto libre) → buscar en Podcast Index + iTunes, ofrecer top 3 con botones de confirmación

## Interpretar reportes proactivos

Cuando el usuario menciona haber escuchado o querer escuchar algo:
1. Extraer: tipo (podcast/youtube/artículo), título, show/canal, URL si la hay, sentimiento
2. Verificar dedup en DB por norm(title)+norm(show_name)
3. INSERT si nuevo, UPDATE si ya existe
4. Confirmar al usuario en una línea
```

---

### 6. CLAUDE.md — update (English)

Update the "Workflow Maintenance Rule" section:
- Add PostgreSQL credentials setup: n8n Postgres node named `Postgres Shared`, host=`postgres_shared`, port=5432, DB=`homelab`, user/pass from `../shared/.env`
- Update workflow IDs table with real IDs:
  - V2 Telegram Conversation: `MfX38SzD8FwEyOKA`
  - V1 Weekly Digest: `NRmOwASsHutmy3TE`
  - V4 Daily Tracker: `0u3BHLauQ3ZDWWle`
- Add section: **Data Storage**
  - Episodes/shows: `postgres_shared` container, DB `homelab`, schema `podcasts`
  - User profile/preferences: `data/user_profile.json` (stays as JSON)
  - Ratings history: `data/ratings_history.json` (stays as JSON)
  - Both n8n and postgres_shared are on `proxy-net` — n8n connects to `postgres_shared:5432`

---

## EXECUTION ORDER

1. Read all existing files: CLAUDE.md, AGENT.md, workflows/v2_telegram_conversation.json, scripts/, prompts/
2. Edit `infra/postgres/init/00_schemas.sql` — add podcasts tables + norm() function
3. Apply schema to running postgres_shared:
   ```bash
   source ../shared/.env
   docker exec -i postgres_shared psql -U $POSTGRES_USER -d homelab < ../infra/postgres/init/00_schemas.sql
   ```
4. Create `scripts/migrate_queue_to_db.sh` and run it
5. Verify migration:
   ```bash
   source ../shared/.env
   docker exec -i postgres_shared psql -U $POSTGRES_USER -d homelab \
     -c "SELECT status, count(*) FROM podcasts.episodes GROUP BY status;"
   ```
6. Configure n8n Postgres credentials in n8n UI (one-time, manual step — note this in output)
7. Update `workflows/v2_telegram_conversation.json` — new commands + DB nodes
8. Upload updated workflow to n8n:
   ```bash
   source .env && python3 -c "
   import json
   with open('workflows/v2_telegram_conversation.json') as f:
       w = json.load(f)
   for field in ['id','createdAt','updatedAt','versionId','active','meta']:
       w.pop(field, None)
   print(json.dumps(w))
   " | curl -s "http://localhost:5678/api/v1/workflows/MfX38SzD8FwEyOKA" \
     -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
     -X PUT -H "Content-Type: application/json" -d @-
   ```
9. Update AGENT.md (Spanish)
10. Update CLAUDE.md (English)
11. Verify: send `/lista`, `/lista_editar`, `/episodios` to the bot

---

## QUALITY REQUIREMENTS

- All DB queries: parameterized (n8n Postgres node uses `$1,$2` placeholders)
- All string comparisons: use `podcasts.norm()` — no raw string match
- Delete: always ask confirmation via inline keyboard before executing (soft delete → status='dismissed', never DELETE)
- Deduplication: norm(title)+norm(show_name) check before every INSERT
- Source detection: if URL contains `youtube.com` or `youtu.be` → source='youtube', else 'podcast'
- Pagination state: store page number in n8n workflow static data or embed in callback_data
- Do not remove or break existing workflow routes (/queue, /rate, /profile, /recommend, /search, /podcasts)

---

## OUT OF SCOPE (phase 2)

- Web app (Express + HTML) — not needed while bot covers all use cases
- New postgres container — postgres_shared already serves this
- users table / JWT auth — no web app, no auth needed
- Email delivery (SMTP) — already optional, no changes needed
