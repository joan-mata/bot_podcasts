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
TOKEN_FILE="$PROJECT_DIR/data/spotify_token.json"
PORT=8888

if [ ! -f "$ENV_FILE" ]; then
    error ".env no encontrado. Ejecutar setup.sh primero."
fi

set -a
source "$ENV_FILE"
set +a

CLIENT_ID="${SPOTIFY_CLIENT_ID:-}"
CLIENT_SECRET="${SPOTIFY_CLIENT_SECRET:-}"
REDIRECT_URI="${SPOTIFY_REDIRECT_URI:-http://localhost:${PORT}/callback}"

if [ -z "$CLIENT_ID" ]; then
    error "SPOTIFY_CLIENT_ID no configurado en .env"
fi

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   Spotify OAuth2 PKCE — Autenticación inicial     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Generate code_verifier (96 chars, URL-safe base64)
CODE_VERIFIER=$(python3 -c "
import secrets, base64
v = secrets.token_bytes(72)
print(base64.urlsafe_b64encode(v).decode().rstrip('=')[:96])
" 2>/dev/null || openssl rand -base64 72 | tr -d '=\n/' | tr '+' '-' | head -c 96)

# Generate code_challenge = BASE64URL(SHA256(code_verifier))
CODE_CHALLENGE=$(python3 -c "
import hashlib, base64, sys
v = '${CODE_VERIFIER}'.encode('ascii')
digest = hashlib.sha256(v).digest()
print(base64.urlsafe_b64encode(digest).decode().rstrip('='))
" 2>/dev/null || echo "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')

SCOPES="user-follow-read user-read-recently-played user-library-read"
SCOPES_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SCOPES}'))" 2>/dev/null || echo "$SCOPES" | sed 's/ /%20/g')
REDIRECT_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REDIRECT_URI}'))" 2>/dev/null || echo "$REDIRECT_URI" | sed 's/:/%3A/g; s/\//%2F/g')

AUTH_URL="https://accounts.spotify.com/authorize?response_type=code&client_id=${CLIENT_ID}&scope=${SCOPES_ENCODED}&redirect_uri=${REDIRECT_ENCODED}&code_challenge_method=S256&code_challenge=${CODE_CHALLENGE}"

echo -e "${YELLOW}Paso 1: Autorizar Spotify${NC}"
echo ""
echo "Abre esta URL en tu navegador:"
echo ""
echo "$AUTH_URL"
echo ""

# Try to open browser automatically
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$AUTH_URL" 2>/dev/null &
elif command -v open >/dev/null 2>&1; then
    open "$AUTH_URL" 2>/dev/null &
else
    warn "No se pudo abrir el navegador automáticamente. Copia la URL de arriba."
fi

# Start local HTTP server to catch callback
info "Esperando callback en http://localhost:${PORT}/callback ..."
echo ""

# Use Python to handle the callback
AUTH_CODE=$(python3 - <<PYTHON_SCRIPT
import http.server
import urllib.parse
import sys

class CallbackHandler(http.server.BaseHTTPRequestHandler):
    code = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        if 'code' in params:
            CallbackHandler.code = params['code'][0]
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'<html><body><h2>Autorizado. Puedes cerrar esta ventana.</h2></body></html>')
        elif 'error' in params:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'<html><body><h2>Error de autorizacion.</h2></body></html>')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(('localhost', ${PORT}), CallbackHandler)
server.timeout = 120
server.handle_request()
if CallbackHandler.code:
    print(CallbackHandler.code)
else:
    sys.exit(1)
PYTHON_SCRIPT
)

if [ -z "$AUTH_CODE" ]; then
    error "No se recibió el código de autorización. Intenta de nuevo."
fi

success "Código de autorización recibido"

# Exchange code for token
info "Intercambiando código por token de acceso..."

RESPONSE=$(curl -sf -X POST "https://accounts.spotify.com/api/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "code=${AUTH_CODE}" \
    -d "redirect_uri=${REDIRECT_URI}" \
    -d "client_id=${CLIENT_ID}" \
    -d "code_verifier=${CODE_VERIFIER}")

if ! echo "$RESPONSE" | grep -q '"access_token"'; then
    error "Error al obtener token. Respuesta: $RESPONSE"
fi

ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['access_token'])")
REFRESH_TOKEN=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('refresh_token', ''))")
EXPIRES_IN=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('expires_in', 3600))")

# Save token file
mkdir -p "$(dirname "$TOKEN_FILE")"
python3 -c "
import json, datetime
data = {
    'access_token': '${ACCESS_TOKEN}',
    'refresh_token': '${REFRESH_TOKEN}',
    'expires_in': ${EXPIRES_IN},
    'obtained_at': datetime.datetime.utcnow().isoformat() + 'Z'
}
with open('${TOKEN_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
"
chmod 600 "$TOKEN_FILE"
success "Token guardado en $TOKEN_FILE (chmod 600)"

# Verify token by fetching profile
info "Verificando token con Spotify API..."
PROFILE=$(curl -sf -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://api.spotify.com/v1/me" 2>/dev/null || echo '{}')
DISPLAY_NAME=$(echo "$PROFILE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('display_name', 'desconocido'))" 2>/dev/null || echo "desconocido")

echo ""
success "Conectado a Spotify como: $DISPLAY_NAME"
echo ""
echo -e "${GREEN}Autenticación completada.${NC}"
echo "El token se renovará automáticamente mediante n8n."
echo ""
