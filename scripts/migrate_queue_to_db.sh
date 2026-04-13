#!/usr/bin/env bash
# One-time migration: data/podcast_queue.json → podcasts.episodes
# Run from project root: bash scripts/migrate_queue_to_db.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SHARED_ENV="$PROJECT_DIR/../shared/.env"

if [ ! -f "$SHARED_ENV" ]; then
  echo "ERROR: shared .env not found at $SHARED_ENV" >&2
  exit 1
fi
set -a; source "$SHARED_ENV"; set +a

if [ ! -f "$PROJECT_DIR/data/podcast_queue.json" ]; then
  echo "ERROR: data/podcast_queue.json not found" >&2
  exit 1
fi

echo "Migrating data/podcast_queue.json → podcasts.episodes..."

python3 - "$PROJECT_DIR/data/podcast_queue.json" <<'PYEOF'
import json, subprocess, sys, os

queue_file = sys.argv[1]
with open(queue_file) as f:
    raw = json.load(f)
items = raw.get('items', raw) if isinstance(raw, dict) else raw

# Dedup by id (last occurrence wins)
seen = {}
for item in items:
    seen[item['id']] = item
items = list(seen.values())

def esc(s):
    return (s or '').replace("'", "''")

def detect_source(item):
    url = item.get('url') or ''
    if 'youtube.com' in url or 'youtu.be' in url:
        return 'youtube'
    return 'podcast'

def map_status(s):
    mapping = {'pending': 'pending', 'listened': 'listened',
               'skipped': 'skipped', 'dismissed': 'dismissed'}
    return mapping.get(s, 'pending')

sql_lines = []
for item in items:
    iid    = esc(item['id'])
    source = detect_source(item)
    title  = esc(item.get('title') or 'Sin título')
    show   = esc(item.get('podcast') or '')
    url    = esc(item.get('url') or '')
    dur    = 'NULL' if item.get('duration_min') is None else str(int(item['duration_min']))
    status = map_status(item.get('status', 'pending'))
    rat    = 'NULL' if item.get('rating') is None else str(int(item['rating']))
    lat    = 'NULL' if not item.get('listened_at') else f"'{item['listened_at']}'"
    cat    = f"'{item['added_at']}'" if item.get('added_at') else 'NOW()'
    sql_lines.append(
        f"INSERT INTO podcasts.episodes "
        f"(id,source,title,show_name,url,duration_min,status,rating,listened_at,created_at) "
        f"VALUES ('{iid}','{source}','{title}','{show}','{url}',{dur},'{status}',{rat},{lat},{cat}) "
        f"ON CONFLICT (id) DO NOTHING;"
    )

sql = '\n'.join(sql_lines)

result = subprocess.run(
    ['docker', 'exec', '-i', 'postgres_shared', 'psql',
     '-U', os.environ['POSTGRES_USER'], '-d', 'homelab', '-q'],
    input=sql.encode(), capture_output=True
)
if result.returncode != 0:
    print(result.stderr.decode(), file=sys.stderr)
    sys.exit(1)
if result.stdout.decode().strip():
    print(result.stdout.decode())

print(f"Done. {len(sql_lines)} episodes processed (duplicates skipped).")
PYEOF
