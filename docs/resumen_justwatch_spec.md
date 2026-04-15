# Resumen: JustWatch para Podcasts

## ¿De qué trata?

La spec adapta la UX de JustWatch (agregador de streaming) al bot de podcasts. La idea central: cada episodio tiene una "ficha" con plataformas disponibles, acciones rápidas y secciones de descubrimiento, igual que JustWatch muestra dónde ver una película.

---

## Componentes principales

### A. Tarjetas de episodio con badges de plataforma
Cada episodio en el tracker diario muestra un badge según origen:
- `📺` YouTube · `🎵` Spotify · `🎙️` RSS puro

Función `formatEpisodeCard()` ya definida en la spec para el nodo "Format Episode Items" de V4.

### B. Filtros rápidos (`/buscar`)
Menú inline con botones para filtrar por:
- Plataforma: YouTube / Spotify / Solo RSS
- Duración: <20 min / 20-60 min / >60 min
- Tema: Tecnología / Economía / Internacional / Más...

### C. Secciones de descubrimiento (en el digest semanal)
1. **Nuevos esta semana** — episodios recientes de tus podcasts
2. **Para ti** — top 3 recomendados por Claude según perfil
3. **Más valorados** — tus mejores puntuaciones del mes

### D. Vista de historial mejorada (`/episodios`)
Lista paginada con filtros inline (plataforma, rating, fecha). Muestra título, podcast, duración, puntuación y botones de acción por episodio.

### E. Edición inline de episodios
Desde cualquier ficha: cambiar puntuación, editar nota, añadir enlace, cambiar fecha o eliminar — sin salir del contexto del chat.

---

## Cambios de schema requeridos

**PostgreSQL (`podcasts.episodes`):** añadir columnas `url_normalized`, `youtube_url`, `spotify_url`, `thumbnail_url`, `description`, `platforms TEXT[]` + índices GIN y btree.

**`user_profile.json`:** cada podcast necesita `youtube_url`, `youtube_rss_url`, `spotify_url`, `rss_url`.

---

## Prioridad de implementación

| Prioridad | Componente |
|-----------|-----------|
| 🔴 Alta | Dedup por URL + perfiles dual YouTube+Spotify en tracker diario |
| 🟡 Media | Filtros en `/buscar` + ficha de episodio enriquecida |
| 🟢 Baja | Secciones de descubrimiento en digest + edición inline completa |

---

## Restricciones técnicas de Telegram

- Sin grids reales → simular con filas de botones inline
- `callback_data` máx 64 bytes → usar IDs cortos con prefijos (ej: `ep:yt_abc123:add`)
- "Card con poster": `sendPhoto` + caption con thumbnail de YouTube (`mqdefault.jpg`)
- Filtros: reusar el mismo mensaje con `editMessageText` + `editMessageReplyMarkup`

---

## Tabla de equivalencias JustWatch → Bot

| JustWatch | Bot de Podcasts |
|-----------|----------------|
| Poster de película | Nombre del episodio en negrita |
| Logo de plataforma (Netflix, HBO...) | Badge 📺 / 🎵 / 🎙️ |
| Puntuación IMDb/RT | Puntuación propia 0-5 ⭐ |
| + Watchlist | 📋 Añadir a lista |
| Visto | ✅ Ya lo escuché |
| Grid de tarjetas | Lista con separadores |
| "Nuevos en Netflix" | 🆕 Nuevos esta semana |
