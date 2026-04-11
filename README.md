# Curador de Contenidos Personal

Sistema de curación de podcasts, vídeos de YouTube y artículos con aprendizaje de gustos mediante feedback.

---

## Qué hace este sistema

**Ejemplo de digest semanal (lunes 8:00, vía Telegram):**

> 📬 *Digest — semana 12*
>
> 🎙️ *PODCASTS CONOCIDOS* (3)
> • *Sam Altman on the future of AI* — Lex Fridman · 87min · ⭐9.2/10
>   _Conversación sobre AGI, seguridad y la visión de OpenAI. Directo al grano._
>   🔗 https://...
>   [👍 Bien] [👎 No era para mí] [⭐ Puntuar] [💬 Más info]
>
> 🔍 *DESCUBRIMIENTOS* (2)
> • *Historia de Roma: La caída de la República* — _Nuevo: The History of Rome_ · 42min · ⭐8.1/10
>   _Por qué: Tu interés en historia_antigua (peso 7) y el estilo narrativo coinciden con tus preferencias._
>   🔗 https://...

**Ejemplo de feedback libre (cualquier momento):**

> Tú: "me ha gustado el último episodio de Huberman sobre el sueño"
> Bot: "¿Es porque el tema te interesa o porque te gustó cómo lo explicó?"
> Tú: "los dos"
> Bot: "Anotado. He subido el peso de ciencia_cognitiva a 8.5 y añadido a Huberman a tus afinidades de presentador."

---

## Cómo aprende tus gustos

1. **Onboarding Spotify** — Importa los podcasts que sigues y tu historial de escucha
2. **Encuesta progresiva** — 3-5 preguntas/día durante la primera semana (frecuencia, completitud, qué te atrae)
3. **Botones inline** — Cada ítem del digest tiene botones 👍 👎 ⭐ que actualizan tu perfil automáticamente
4. **Reportes libres** — Escribe a tu bot en lenguaje natural sobre contenido que hayas consumido
5. **Preferencias directas** — "ya no me interesa la política" → el sistema lo aplica inmediatamente

---

## Prerequisitos

- Linux con Docker instalado (`docker`, `docker compose`)
- Python 3 (para el script de auth de Spotify)
- URL pública HTTPS para el webhook de Telegram (ngrok o Cloudflare Tunnel)
- Cuentas gratuitas en: Anthropic, Telegram, Spotify Developer, Google Cloud, Listen Notes, Podcast Index

---

## Instalación (3 pasos)

```bash
git clone <repo> content-curator
cd content-curator
bash scripts/setup.sh
```

Sigue el checklist que imprime `setup.sh`.

---

## Cómo obtener cada API gratuita

### Anthropic (Claude)
1. https://console.anthropic.com → API Keys → Create Key
2. Copiar en `.env` → `ANTHROPIC_API_KEY`

### Telegram Bot
1. Abrir Telegram → buscar **@BotFather** → `/newbot`
2. Seguir instrucciones → guardar token en `TELEGRAM_BOT_TOKEN`
3. Buscar **@userinfobot** → te da tu chat ID → `TELEGRAM_CHAT_ID`

### YouTube Data API v3
1. https://console.cloud.google.com → Nuevo proyecto
2. APIs y servicios → Biblioteca → YouTube Data API v3 → Habilitar
3. Credenciales → Crear credenciales → Clave de API
4. Copiar en `YOUTUBE_API_KEY`

### Listen Notes (descubrimiento de podcasts)
1. https://www.listennotes.com/api/ → Get Free API Key
2. Registro gratuito → 10.000 llamadas/mes
3. Copiar en `LISTENNOTES_API_KEY`

### Podcast Index (descubrimiento + RSS)
1. https://podcastindex.org/login → Create Account (gratis)
2. Developer → API Keys → crear clave
3. Copiar `API Key` → `PODCASTINDEX_API_KEY`
4. Copiar `API Secret` → `PODCASTINDEX_API_SECRET`

### Spotify Developer
1. https://developer.spotify.com/dashboard → Log In → Create App
2. App name: cualquiera | Redirect URI: `http://localhost:8888/callback`
3. Copiar Client ID → `SPOTIFY_CLIENT_ID`
4. Copiar Client Secret → `SPOTIFY_CLIENT_SECRET`
5. Sin coste, sin tarjeta

### Apple Calendar (CalDAV)
1. Ve a https://appleid.apple.com → Iniciar sesión
2. Seguridad → Contraseñas específicas de app → `+`
3. Nombre: "ContentCurator" → Generar
4. Copiar contraseña generada (16 chars, con guiones) → `APPLE_CALDAV_PASSWORD`
5. `APPLE_CALDAV_USER` = tu Apple ID (email)

---

## Spotify: primer login

Después de configurar el `.env` con tus credenciales de Spotify:

```bash
bash scripts/spotify_auth.sh
```

Se abre el navegador, autorizas, y el script guarda el token en `data/spotify_token.json` (chmod 600).

---

## Cómo hablarle al bot

**Comandos:**
- `/onboarding` — iniciar el proceso de onboarding con Spotify

**Lenguaje natural (ejemplos):**
- "me ha gustado el podcast de Huberman de hoy"
- "acabo de descubrir un podcast increíble sobre historia de Roma: [nombre]"
- "vi este vídeo y me encantó: https://youtube.com/watch?v=xxx"
- "ya no me interesa la política española"
- "¿qué podcast me recomiendas sobre filosofía estoica?"
- "sube el peso de inteligencia artificial"
- "añade este podcast a mi lista: [nombre]"

---

## Personalizar perfil manualmente

Edita `data/user_profile.json`. Campos principales:

```json
{
  "interests": {"inteligencia_artificial": 9, "historia_antigua": 7},
  "avoid_topics": ["politica_española", "deportes"],
  "known_podcasts": [...],
  "youtube_channels": [...],
  "format_preferences": {"max_episode_duration_minutes": 90}
}
```

---

## Importar workflows en n8n

```bash
bash scripts/import_workflows.sh
```

O manualmente desde la UI de n8n:
1. Abrir http://localhost:5678
2. Workflows → Import from File
3. Seleccionar cada fichero en `workflows/`

Workflows disponibles:
- `v0_onboarding.json` — Onboarding Spotify + encuesta progresiva
- `v1_weekly_digest.json` — Digest semanal (lunes 8:00)
- `v2_telegram_conversation.json` — Conversación libre + botones de feedback
- `v3_calendar_suggestions.json` — Sugerencias basadas en Apple Calendar

---

## Seguridad

- n8n solo escucha en `127.0.0.1:5678` — no expuesto directamente a Internet
- Webhook de Telegram valida header `X-Telegram-Bot-Api-Secret-Token` en cada petición
- Todos los secrets en `.env` (gitignoreado) — nunca en el código
- `data/` gitignoreado — tokens y ratings no salen del servidor
- Token de Spotify en `data/spotify_token.json` con permisos 600
- Apple Calendar: solo PROPFIND/REPORT, nunca PUT/DELETE

Para rotar el webhook secret:
```bash
bash scripts/rotate_secrets.sh
```

---

## Exponer n8n con ngrok o Cloudflare Tunnel

**ngrok (opción rápida):**
```bash
ngrok http 5678
# Copia la URL https://xxx.ngrok.io → N8N_WEBHOOK_URL en .env
```

**Cloudflare Tunnel (opción estable y gratis):**
```bash
cloudflared tunnel --url http://localhost:5678
# Copia la URL https://xxx.trycloudflare.com → N8N_WEBHOOK_URL en .env
```

Después de actualizar `N8N_WEBHOOK_URL`, registrar el webhook de Telegram:
```bash
source .env
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${N8N_WEBHOOK_URL}/webhook/telegram\", \"secret_token\": \"${TELEGRAM_WEBHOOK_SECRET}\"}"
```

---

## Troubleshooting

**n8n no arranca:**
```bash
docker compose logs n8n
```

**Webhook de Telegram no funciona:**
```bash
# Verificar estado del webhook
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

**Error de auth en Spotify:**
```bash
bash scripts/spotify_auth.sh  # Re-autenticar
```

**CalDAV no conecta:**
- Verificar que `APPLE_CALDAV_PASSWORD` es una contraseña específica de app (no tu password de Apple ID)
- Probar: `curl -X PROPFIND https://caldav.icloud.com -u "tu@email.com:xxxx-xxxx-xxxx-xxxx" -H "Depth: 1"`

**Ver logs en tiempo real:**
```bash
docker compose logs -f n8n
```

---

## Roadmap

- [ ] Soporte para newsletters via email (RSS de Substack)
- [ ] Exportar digest semanal a PDF
- [ ] Integración con Pocket/Instapaper para artículos
- [ ] Estadísticas mensuales de consumo
- [ ] Modo multi-usuario
