#!/usr/bin/env bash
set -euo pipefail

# Colors
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

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   Curador de Contenidos Personal — Instalación    ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check Docker
info "Verificando Docker..."
command -v docker >/dev/null 2>&1 || error "Docker no instalado. Instalar desde https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || error "Docker daemon no está corriendo. Ejecutar: sudo systemctl start docker"
success "Docker disponible"

# Check Docker Compose
info "Verificando Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose no instalado."
fi
success "Docker Compose disponible ($COMPOSE_CMD)"

# Create directories
info "Creando directorios..."
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/workflows"
mkdir -p "$PROJECT_DIR/prompts"
mkdir -p "$PROJECT_DIR/scripts"
success "Directorios creados"

# Copy .env.example → .env if not exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    info "Creando .env desde .env.example..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    success ".env creado"
else
    warn ".env ya existe, no se sobreescribe"
fi

# Generate TELEGRAM_WEBHOOK_SECRET if empty
CURRENT_SECRET=$(grep "^TELEGRAM_WEBHOOK_SECRET=" "$PROJECT_DIR/.env" | cut -d= -f2 | tr -d ' ')
if [ -z "$CURRENT_SECRET" ]; then
    info "Generando TELEGRAM_WEBHOOK_SECRET..."
    NEW_SECRET=$(openssl rand -hex 32)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=${NEW_SECRET}/" "$PROJECT_DIR/.env"
    else
        sed -i "s/^TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=${NEW_SECRET}/" "$PROJECT_DIR/.env"
    fi
    success "TELEGRAM_WEBHOOK_SECRET generado: ${NEW_SECRET:0:8}...${NEW_SECRET: -8}"
else
    warn "TELEGRAM_WEBHOOK_SECRET ya configurado"
fi

# Create initial data files if not exist
info "Creando ficheros de datos iniciales..."

if [ ! -f "$PROJECT_DIR/data/ratings_history.json" ]; then
    echo '{"ratings": [], "proactive_reports": []}' > "$PROJECT_DIR/data/ratings_history.json"
    success "ratings_history.json creado"
fi

if [ ! -f "$PROJECT_DIR/data/onboarding_state.json" ]; then
    echo '{"started": false, "spotify_connected": false, "survey_day": 0, "questions_asked": [], "questions_answered": [], "completed": false}' > "$PROJECT_DIR/data/onboarding_state.json"
    success "onboarding_state.json creado"
fi

if [ ! -f "$PROJECT_DIR/data/last_digest.json" ]; then
    echo '{"items": [], "generated_at": null}' > "$PROJECT_DIR/data/last_digest.json"
    success "last_digest.json creado"
fi

if [ ! -f "$PROJECT_DIR/data/user_profile.json" ]; then
    cat > "$PROJECT_DIR/data/user_profile.json" <<'EOF'
{
  "topics": [],
  "known_podcasts": [],
  "websites": [],
  "preferred_duration_minutes": 30,
  "preferred_days": ["monday"],
  "language": "es",
  "discovery_terms": []
}
EOF
    success "user_profile.json creado"
fi

# Start n8n
info "Iniciando n8n con Docker Compose..."
cd "$PROJECT_DIR"
$COMPOSE_CMD up -d

# Wait for n8n health
info "Esperando a que n8n esté listo..."
MAX_WAIT=60
WAITED=0
until curl -sf http://localhost:5678/healthz >/dev/null 2>&1; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ $WAITED -ge $MAX_WAIT ]; then
        error "n8n no respondió en ${MAX_WAIT}s. Ver logs: $COMPOSE_CMD logs n8n"
    fi
    echo -n "."
done
echo ""
success "n8n está listo"

# Print checklist
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                   CHECKLIST DE CONFIGURACIÓN                      ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${YELLOW}Edita el fichero .env con estas claves (sin las cuales el sistema no funciona):${NC}"
echo ""
echo -e "  ${BLUE}1. ANTHROPIC_API_KEY${NC}"
echo "     → https://console.anthropic.com → API Keys → Create Key"
echo ""
echo -e "  ${BLUE}2. TELEGRAM_BOT_TOKEN${NC}"
echo "     → Telegram: habla con @BotFather → /newbot → sigue instrucciones"
echo ""
echo -e "  ${BLUE}3. TELEGRAM_CHAT_ID${NC}"
echo "     → Telegram: habla con @userinfobot → te da tu chat ID"
echo ""
echo -e "  ${BLUE}4. SPOTIFY_CLIENT_ID + SPOTIFY_CLIENT_SECRET${NC}"
echo "     → https://developer.spotify.com/dashboard → Create App"
echo "     → Redirect URI: http://localhost:8888/callback"
echo "     → Scopes: user-follow-read, user-read-recently-played, user-library-read"
echo ""
echo -e "  ${BLUE}5. YOUTUBE_API_KEY${NC}"
echo "     → https://console.cloud.google.com → APIs → YouTube Data API v3 → Credenciales"
echo ""
echo -e "  ${BLUE}6. LISTENNOTES_API_KEY${NC}"
echo "     → https://www.listennotes.com/api/ → Get Free API Key"
echo ""
echo -e "  ${BLUE}7. PODCASTINDEX_API_KEY + PODCASTINDEX_API_SECRET${NC}"
echo "     → https://podcastindex.org/login → crear cuenta gratis"
echo ""
echo -e "  ${BLUE}8. APPLE_CALDAV_USER + APPLE_CALDAV_PASSWORD${NC}"
echo "     → Apple ID (email) + contraseña específica de app"
echo "     → https://appleid.apple.com → Seguridad → App-Specific Passwords"
echo ""
echo -e "  ${BLUE}9. N8N_WEBHOOK_URL${NC}"
echo "     → URL pública HTTPS, ej: https://n8n.tudominio.com"
echo "     → En ~/.cloudflared/config.yml añade ANTES del catch-all:"
echo "          - hostname: n8n.tudominio.com"
echo "            service: http://NOMBRE_CONTAINER_N8N:5678"
echo "     → Conecta el container n8n a la red del tunnel:"
echo "          docker network connect NOMBRE_RED_TUNNEL NOMBRE_CONTAINER_N8N"
echo "     → Añade DNS CNAME en Cloudflare: n8n → TUNNEL_ID.cfargotunnel.com (proxy ON)"
echo "     → Reinicia cloudflared: docker restart NOMBRE_CONTAINER_CLOUDFLARED"
echo ""
echo -e "  ${BLUE}10. N8N_API_KEY${NC}"
echo "      → Generado dentro de n8n: Settings → API → Create API Key"
echo "      → Necesario para importar los workflows con el script"
echo ""
echo "────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${GREEN}PRÓXIMOS PASOS:${NC}"
echo ""
echo "  1. Edita .env con todas las claves de arriba"
echo "  2. Reinicia n8n: $COMPOSE_CMD restart"
echo "  3. Importa los workflows: bash scripts/import_workflows.sh"
echo "  4. Registra el webhook de Telegram:"
echo "     source .env && curl -X POST https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/setWebhook \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d \"{\\\"url\\\": \\\"\${N8N_WEBHOOK_URL}/webhook/telegram\\\", \\\"secret_token\\\": \\\"\${TELEGRAM_WEBHOOK_SECRET}\\\"}\""
echo "  5. Conecta Spotify: bash scripts/spotify_auth.sh"
echo "  6. Abre n8n: http://localhost:5678"
echo "  7. Envía /onboarding a tu bot para iniciar"
echo ""
echo -e "${GREEN}Instalación completada.${NC}"
