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
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    error ".env no encontrado"
fi

set -a
source "$ENV_FILE"
set +a

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Rotación de secrets — Content Curator ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Generate new webhook secret
info "Generando nuevo TELEGRAM_WEBHOOK_SECRET..."
NEW_SECRET=$(openssl rand -hex 32)

OLD_SECRET="${TELEGRAM_WEBHOOK_SECRET:-}"
if [ -n "$OLD_SECRET" ]; then
    info "Secret anterior: ${OLD_SECRET:0:8}...${OLD_SECRET: -8}"
fi

# Update .env
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=${NEW_SECRET}/" "$ENV_FILE"
else
    sed -i "s/^TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=${NEW_SECRET}/" "$ENV_FILE"
fi
success "TELEGRAM_WEBHOOK_SECRET actualizado: ${NEW_SECRET:0:8}...${NEW_SECRET: -8}"

# Restart n8n
if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    fi
    info "Reiniciando n8n..."
    cd "$PROJECT_DIR"
    $COMPOSE_CMD restart n8n
    # Wait for health
    sleep 3
    MAX_WAIT=30
    WAITED=0
    until curl -sf http://localhost:${N8N_PORT:-5678}/healthz >/dev/null 2>&1; do
        sleep 2
        WAITED=$((WAITED + 2))
        [ $WAITED -ge $MAX_WAIT ] && error "n8n no respondió tras reinicio"
        echo -n "."
    done
    echo ""
    success "n8n reiniciado"
fi

# Re-register Telegram webhook
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"

if [ -z "$BOT_TOKEN" ]; then
    warn "TELEGRAM_BOT_TOKEN no configurado — webhook no re-registrado"
    echo "  Registrar manualmente:"
    echo "  curl -X POST https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/setWebhook \\"
    echo "    -d url=\${N8N_WEBHOOK_URL}/webhook/telegram \\"
    echo "    -d secret_token=${NEW_SECRET}"
elif [ -z "$WEBHOOK_URL" ]; then
    warn "N8N_WEBHOOK_URL no configurado — webhook no re-registrado"
else
    info "Re-registrando webhook de Telegram..."
    RESPONSE=$(curl -sf -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"${WEBHOOK_URL}/webhook/telegram\", \"secret_token\": \"${NEW_SECRET}\"}" 2>/dev/null || echo '{"ok": false}')
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        success "Webhook de Telegram actualizado"
    else
        warn "Error al actualizar webhook: $RESPONSE"
        echo "  Re-registrar manualmente con el nuevo secret: ${NEW_SECRET}"
    fi
fi

echo ""
success "Rotación completada. Nuevo secret: ${NEW_SECRET:0:8}...${NEW_SECRET: -8}"
echo ""
