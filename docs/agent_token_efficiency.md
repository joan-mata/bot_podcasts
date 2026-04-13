# Guía de eficiencia de tokens con agentes

Estrategias para usar agentes de Claude (API, subagentes de Claude Code, nodos AI de n8n) con el mínimo consumo de tokens.

---

## 1. Selección de modelo

Usa el modelo más barato que cumpla con los requisitos de la tarea:

| Tarea | Modelo recomendado | Por qué |
|---|---|---|
| Clasificación simple / scoring | `claude-haiku-4-5` | 10–20× más barato que Sonnet |
| Filtrado de contenido, resúmenes cortos | `claude-haiku-4-5` | Rápido, calidad suficiente |
| Razonamiento complejo, planes multi-paso | `claude-sonnet-4-6` | Solo cuando es necesario |
| Investigación profunda / arquitectura | `claude-opus-4-6` | Último recurso |

Regla: **empieza con Haiku, sube de modelo solo si la calidad no es suficiente.**

---

## 2. Ingeniería de prompts

### System prompt
- Mantenerlo bajo 500 tokens.
- Eliminar ejemplos obvios a partir de la instrucción.
- Usar reglas estructuradas en vez de párrafos en prosa.

```
# MAL (verboso)
Eres un asistente útil que lee cuidadosamente títulos y descripciones de podcasts
y determina si el usuario los encontraría interesantes según su perfil...

# BIEN (conciso)
Puntúa relevancia del podcast del 1 al 10 según el perfil del usuario.
Devuelve JSON: {"score": N, "reason": "<10 palabras"}
```

### Mensaje de usuario
- Enviar solo los campos que el modelo realmente necesita. Eliminar metadata que no usará.
- Para listas, enviar la representación mínima:

```json
// MAL — objeto completo
{"id": "abc", "title": "...", "description": "...", "author": "...", "feed": "...", "pubDate": "...", "duration": 3600, "image": "https://..."}

// BIEN — solo lo que el modelo lee
{"title": "...", "desc_snippet": "primeros 120 caracteres..."}
```

### Evitar repetición
- No repetir el system prompt en el mensaje de usuario.
- No reenviar el perfil completo en cada llamada — enviar solo los temas con mayor peso (ej. top 5).

---

## 3. Output estructurado (modo JSON)

Siempre pedir JSON cuando se va a parsear la respuesta programáticamente.
- Elimina frases de relleno ("¡Claro! Aquí tienes...", "Espero que esto ayude...").
- Output más pequeño y predecible → menos tokens de salida.

En los nodos AI de n8n configurar el parser como **Structured Output Parser** o terminar el prompt con:
```
Responde ÚNICAMENTE con JSON válido. Sin markdown, sin explicaciones.
```

---

## 4. Batching

En vez de una llamada por ítem, agrupar varios en una sola llamada:

```
// MAL — 10 llamadas × ~300 tokens c/u = 3,000 tokens
for item in items: llamar_claude(item)

// BIEN — 1 llamada × ~600 tokens = 600 tokens
llamar_claude(items[0..9])  # puntuar los 10 a la vez
```

Tamaño máximo práctico: **20–30 ítems cortos** por llamada antes de que la calidad baje o desborde el contexto.

En n8n usar el nodo **Aggregate** antes del nodo AI, luego **Split Out** después.

---

## 5. Caché con `cache_control` (solo API)

El prompt caching de Anthropic ahorra hasta **90% en system prompts repetidos**.

```python
messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": CONTEXTO_SISTEMA_LARGO,   # perfil, reglas, etc.
                "cache_control": {"type": "ephemeral"}
            },
            {
                "type": "text",
                "text": consulta_usuario          # cambia en cada llamada
            }
        ]
    }
]
```

TTL del caché: 5 minutos. Efectivo cuando el mismo system prompt se reutiliza en muchas llamadas en una ventana corta (ej. scoring de un digest en batch).

---

## 6. Gestión de la ventana de contexto

- **No pasar historial de conversación que no se necesita.** Para tareas sin estado (scoring, filtrado), enviar cero historial.
- Para conversaciones multi-turno (V2 Telegram), limitar el historial a los últimos **6 mensajes** (~800 tokens) salvo que el usuario haga referencia explícita a contexto anterior.
- Resumir historiales largos en vez de truncar: un mensaje resumen reemplaza N mensajes crudos.

En n8n el nodo **Window Buffer Memory** con `windowSize: 6` lo gestiona automáticamente.

---

## 7. Control de longitud de output

Añadir restricciones explícitas de longitud al prompt:

```
- reason: máximo 15 palabras
- summary: máximo 2 oraciones
- title: máximo 8 palabras
```

O en la API:
```python
max_tokens=256   # para tareas cortas de clasificación
```

---

## 8. Estrategia de subagentes (Claude Code)

Al construir workflows multi-paso con agentes de Claude Code:

| Tipo de agente | Cuándo usarlo | Coste en tokens |
|---|---|---|
| Modelo `haiku` | Investigación, grep, lectura de archivos | Bajo |
| Modelo `sonnet` | Edición de código, lógica | Medio |
| Inline (sin subagente) | <3 llamadas a herramientas, búsqueda simple | Sin overhead |

- **No lanzar un subagente para tareas que puedes hacer inline con 1–2 tool calls.**
- Pasar solo las rutas de archivo / números de línea relevantes, no el contenido completo del archivo, en el prompt del subagente.
- Usar `run_in_background: true` para tareas paralelas independientes y evitar overhead secuencial.

---

## 9. Patrones específicos de este proyecto

### Weekly Digest (V1)
- Agrupar todos los candidatos en una sola llamada de scoring (Aggregate → nodo AI → Split Out).
- System prompt: solo los top-5 temas del usuario, no el `user_profile.json` completo.
- Output: `[{"id","score","reason"}]` — array JSON mínimo.

### Conversación Telegram (V2)
- Ventana de historial: máximo 6 mensajes.
- System prompt cacheado (el mismo en todos los mensajes de una sesión).
- Para botones de feedback rápido (👍/👎): **no se necesita llamada al AI** — manejar con nodo de lógica pura.

### Daily Tracker (V4)
- Usar Haiku para todas las tareas de clasificación/scoring.
- Sonnet solo para resúmenes en texto libre enviados al usuario.

---

## 10. Estimación de presupuesto de tokens

Referencia rápida para planificar:

| Componente | Tokens aprox. |
|---|---|
| System prompt (conciso) | 200–400 |
| Top-5 temas del perfil de usuario | ~150 |
| Un ítem de podcast (mínimo) | ~80 |
| Batch de 20 ítems | ~1,600 |
| Output JSON por ítem | ~40 |
| Historial de 6 mensajes | ~600–800 |

Llamada típica de scoring de digest: **~2,500 tokens** (entrada + salida) para 20 candidatos.

---

## Referencias

- [Documentación de prompt caching de Anthropic](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [API de conteo de tokens](https://docs.anthropic.com/en/docs/build-with-claude/token-counting)
- [Precios de modelos](https://www.anthropic.com/pricing)
