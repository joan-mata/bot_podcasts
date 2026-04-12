#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
else
    error ".env no encontrado. Ejecutar setup.sh primero."
fi

N8N_URL="http://localhost:${N8N_PORT:-5678}"
N8N_API_KEY="${N8N_API_KEY:-}"

if [ -z "$N8N_API_KEY" ]; then
    error "N8N_API_KEY no configurado en .env. Generarlo en n8n UI → Settings → API → Create API Key"
fi

# Wait for n8n
info "Verificando conectividad con n8n..."
curl -sf "${N8N_URL}/healthz" >/dev/null 2>&1 || error "n8n no responde en ${N8N_URL}. Ejecutar setup.sh primero."
success "n8n accesible"

API_KEY_HEADER="X-N8N-API-KEY: ${N8N_API_KEY}"

WORKFLOWS=(
    "v0_onboarding.json"
    "v1_weekly_digest.json"
    "v2_telegram_conversation.json"
    "v3_calendar_suggestions.json"
)

WORKFLOW_NAMES=(
    "V0 - Spotify Onboarding"
    "V1 - Weekly Digest"
    "V2 - Telegram Conversation"
    "V3 - Calendar Suggestions"
)

echo ""
info "Importando workflows..."

for i in "${!WORKFLOWS[@]}"; do
    wf_file="${PROJECT_DIR}/workflows/${WORKFLOWS[$i]}"
    wf_name="${WORKFLOW_NAMES[$i]}"

    if [ ! -f "$wf_file" ]; then
        warn "No encontrado: $wf_file — saltando"
        continue
    fi

    info "Importando: $wf_name"

    # Import via n8n public API (v1)
    # Strip read-only fields that cause 400 errors
    WF_PAYLOAD=$(python3 -c "
import json, sys
with open('${wf_file}') as f:
    w = json.load(f)
for field in ['id','createdAt','updatedAt','versionId','active','meta']:
    w.pop(field, None)
print(json.dumps(w))
" 2>/dev/null)

    IMPORT_RESPONSE=$(echo "$WF_PAYLOAD" | curl -sf -H "$API_KEY_HEADER" -X POST "${N8N_URL}/api/v1/workflows" \
        -H "Content-Type: application/json" \
        -d @- 2>/dev/null || echo '{"error": "import_failed"}')

    if echo "$IMPORT_RESPONSE" | grep -q '"id"'; then
        WF_ID=$(echo "$IMPORT_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
        success "Importado: $wf_name (id: $WF_ID)"

        # Activate workflow
        info "Activando: $wf_name"
        ACTIVATE_RESPONSE=$(curl -sf -H "$API_KEY_HEADER" -X PATCH "${N8N_URL}/api/v1/workflows/${WF_ID}" \
            -H "Content-Type: application/json" \
            -d '{"active": true}' 2>/dev/null || echo '{"error": "activate_failed"}')

        if echo "$ACTIVATE_RESPONSE" | grep -q '"active":true'; then
            success "Activado: $wf_name"
        else
            warn "No se pudo activar $wf_name — activar manualmente en la UI"
        fi
    else
        warn "Error importando $wf_name — intentar importar manualmente desde la UI n8n"
        echo "  Fichero: $wf_file"
        echo "  Respuesta: $(echo "$IMPORT_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message','unknown'))" 2>/dev/null)"
    fi
done

echo ""
echo "────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${GREEN}Workflows importados.${NC}"
echo ""
echo "Verifica en: ${N8N_URL}"
echo ""
echo -e "${YELLOW}Si hay errores de importación:${NC}"
echo "  1. Abre n8n en el navegador: ${N8N_URL}"
echo "  2. Ir a Workflows → Import from File"
echo "  3. Seleccionar cada fichero en workflows/"
echo ""
