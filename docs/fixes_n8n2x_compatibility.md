# Fixes: n8n 2.x Compatibility

Applied during initial setup debug session (2026-04-12).
All fixes are already incorporated into the current files.

---

## 1. Cloudflare Tunnel — n8n no era accesible públicamente

**Problema**: `N8N_WEBHOOK_URL` apuntaba a una URL temporal de `trycloudflare.com` que ya no existía.
Telegram recibía `404 Not Found` en todos los webhooks.

**Causa raíz**: El tunnel persistente de Cloudflare (`~/.cloudflared/config.yml`) no tenía ruta para n8n,
y el container n8n no estaba conectado a la red del tunnel (`proxy-net`).

**Fix aplicado**:
- `~/.cloudflared/config.yml`: añadida entrada `n8n.joanmata.com → http://bot_podcasts-n8n-1:5678`
- `docker-compose.yml`: añadida red `proxy-net` (external) al servicio n8n
- `docker network connect proxy-net bot_podcasts-n8n-1` (en caliente, sin downtime)
- `.env`: `N8N_WEBHOOK_URL=https://n8n.joanmata.com`
- DNS en Cloudflare: CNAME `n8n` → `9cbd37da-4422-4837-b780-c245ae2b432d.cfargotunnel.com` (proxy ON)

**Reproducción en fresh setup**: Ver instrucción 9 en `scripts/setup.sh`.

---

## 2. Nodo `function` deprecado en n8n 2.x

**Problema**: `n8n-nodes-base.function` fue eliminado en n8n 2.x.
Los workflows no cargaban y n8n reportaba "Processed 0 workflows".

**Fix aplicado** (todos los workflows):
- Tipo: `n8n-nodes-base.function` → `n8n-nodes-base.code`
- `typeVersion`: 2 → 1 (versión 1 mantiene compatibilidad con `return [{json: {...}}]`)
- Parámetro: `functionCode` → `jsCode`

---

## 3. `process.env` bloqueado en Code nodes

**Problema**: n8n bloquea por defecto el acceso a variables de entorno desde Code nodes.
Error: `Cannot assign to read only property 'name' of object 'Error: access to env vars denied'`

**Fix aplicado**:
- `docker-compose.yml`: añadido `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`
- En código: `process.env.VAR` → `$env.VAR`

---

## 4. `require('fs')` bloqueado en Code nodes

**Problema**: n8n bloquea módulos Node.js nativos en Code nodes por defecto.
Error: `Module 'fs' is disallowed`

**Fix aplicado**:
- `docker-compose.yml`: añadido `NODE_FUNCTION_ALLOW_BUILTIN=fs,path`

---

## 5. IF node con salidas invertidas (v2)

**Problema**: El nodo `Is Valid?` tenía las conexiones al revés:
- Output 0 (true = sender válido) → sin conexión → workflow terminaba silenciosamente
- Output 1 (false = sender inválido) → `Route by Type` → procesaba mensajes

**Fix aplicado** (`v2_telegram_conversation.json`):
- Intercambiadas las conexiones: output 0 → `Route by Type`, output 1 → vacío

---

## 6. Switch nodes incompatibles con n8n 2.x

**Problema**: `n8n-nodes-base.switch` `typeVersion: 1` lanzaba
`Cannot read properties of undefined (reading 'push')` en n8n 2.x.
El campo `value1` (expresión a comparar) también estaba ausente.

**Fix aplicado** (`v2_telegram_conversation.json`):
- `Switch Route` y `Switch Action` reemplazados por nodos `n8n-nodes-base.if` (`typeVersion: 2`)
- Lógica equivalente: `Switch Route` → IF `route === callback_query`; `Switch Action` → IF `action === rate`

---

## 7. HTTP Request: JSON body con expresiones JavaScript sin resolver

**Problema**: Los nodos HTTP Request con `specifyBody: "json"` y `jsonBody` empezando por `=`
intentaban evaluar el cuerpo como JavaScript puro (ej: `"content": $json.text`).
n8n 2.x no evalúa estas expresiones inline en `jsonBody` — las trata como JSON literal,
lo que produce JSON inválido y errores 400 en la API de Claude.

**Fix aplicado** (todos los workflows):
- Se añadió código al nodo anterior (Code node) que construye el objeto `claudePayload` completo
- El nodo HTTP usa `jsonBody: ={{ $json.claudePayload }}` — n8n serializa el objeto correctamente

**Nodos afectados**:
| Workflow | Code node que construye payload | HTTP node |
|---|---|---|
| v2 | `Read Context` → `detectIntentPayload` | `Detect Intent` |
| v2 | `Parse Intent` → `conversationPayload` | `Claude Conversation` |
| v0 | `Store Survey Answer` → `claudePayload` | `Claude Profile Synthesis` |
| v1 | `Prepare Claude Payload` → `claudePayload` | `Claude Filter & Score` |
| v3 | `Parse CalDAV XML` → `claudePayload` | `Claude Calendar Suggestions` |

**Nodo `Trigger V3 Calendar`** (v1): body estático `={"key": "val"}` — simplemente eliminada la `=`.

---

## 8. Nodos Telegram con credenciales no importables

**Problema**: `n8n-nodes-base.telegram` referenciaba credenciales por ID (`telegram_creds`)
que no existen en una instalación fresca de n8n. No hay forma de importar credenciales
via API pública de n8n.

**Fix aplicado** (todos los workflows):
- Todos los nodos `telegram` reemplazados por `httpRequest` que llaman directamente a la API de Telegram
- URL: `https://api.telegram.org/bot{{ $env.TELEGRAM_BOT_TOKEN }}/sendMessage`
- No requieren credenciales almacenadas en n8n

---

## 9. CalDAV: credenciales `httpBasicAuth` no importables

**Problema**: El nodo `CalDAV Fetch Events` (v3) usaba `authentication: "genericCredentialType"`
con `httpBasicAuth`, que también referencia credenciales por ID.

**Fix aplicado** (`v3_calendar_suggestions.json`):
- Eliminada la autenticación por credenciales
- Añadido header `Authorization: Basic <base64(user:password)>` usando `$env.APPLE_CALDAV_USER` y `$env.APPLE_CALDAV_PASSWORD`

---

## 10. `import_workflows.sh`: endpoint incorrecto

**Problema**: El script usaba `/rest/workflows` (endpoint interno de n8n, requiere sesión de UI)
en lugar de `/api/v1/workflows` (API pública, acepta API key).
Resultado: `{"status":"error","message":"Unauthorized"}` aunque la API key fuera válida.

Además, el endpoint de importación rechaza campos read-only (`id`, `createdAt`, `updatedAt`,
`versionId`, `active`, `meta`) con error 400.

**Fix aplicado** (`scripts/import_workflows.sh`):
- Endpoint: `/rest/workflows` → `/api/v1/workflows` (importar y activar)
- Añadido paso de strip de campos read-only via `python3` antes de cada import
- Mejor reporte de errores: muestra el mensaje de error real de la API

---

## Resumen de archivos modificados

| Archivo | Cambios |
|---|---|
| `docker-compose.yml` | `proxy-net` network, `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`, `NODE_FUNCTION_ALLOW_BUILTIN=fs,path` |
| `.env` | `N8N_WEBHOOK_URL=https://n8n.joanmata.com` |
| `~/.cloudflared/config.yml` | Ruta `n8n.joanmata.com` |
| `scripts/import_workflows.sh` | Endpoint `/api/v1/`, strip de campos read-only |
| `scripts/setup.sh` | Instrucciones Cloudflare tunnel, orden pasos (webhook antes de Spotify) |
| `workflows/v0_onboarding.json` | function→code, Telegram→HTTP, claudePayload en Store Survey Answer |
| `workflows/v1_weekly_digest.json` | function→code, Telegram→HTTP, claudePayload en Prepare Claude Payload, fix Trigger body |
| `workflows/v2_telegram_conversation.json` | function→code, Switch→IF, IF invertido, Telegram→HTTP, claudePayload en Read Context y Parse Intent, CalDAV auth |
| `workflows/v3_calendar_suggestions.json` | function→code, Telegram→HTTP, claudePayload en Parse CalDAV XML, CalDAV Basic Auth via header |
