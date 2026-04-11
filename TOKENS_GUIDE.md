# Guia de Tokens: Como hablar con Claude Code para optimizar coste

## Que son los tokens

Los tokens son la unidad de medida del procesamiento de texto. Aproximadamente:
- 1 token ≈ 4 caracteres en ingles
- 1 token ≈ 3 caracteres en castellano/catalan
- 1000 palabras ≈ 1300 tokens

## Como se gastan los tokens en Claude Code

Cada turno de conversacion consume:
1. **Tokens de entrada (input)**: Todo el contexto previo + tu mensaje nuevo
2. **Tokens de salida (output)**: La respuesta de Claude + codigo generado
3. **Tokens de herramientas**: Cada llamada a Read, Grep, Bash, etc. tiene coste de entrada y salida

La trampa: **el contexto se acumula**. Si llevas 50 mensajes, cada nuevo mensaje re-envia los 50 anteriores como contexto. El coste crece de forma cuadratica a lo largo de la sesion.

## Como reducir el gasto de tokens

### Mensajes concisos
Mal: "Oye, estaba pensando que quizas podrias echarle un vistazo al archivo de configuracion y ver si hay algo que no este bien configurado y que pueda estar causando problemas"
Bien: "Lee config.py y dime que esta mal"

### Usa referencias en lugar de repetir codigo
Mal: Pegar 200 lineas de codigo y preguntar "que hace esto?"
Bien: "Explica la funcion `parse_feed` en [feed_parser.py](feed_parser.py)"

### Empieza sesiones nuevas para tareas nuevas
Cada sesion empieza con contexto 0. Si terminas una tarea, cierra y abre sesion nueva para la siguiente. No arrastres contexto innecesario.

### Agrupa preguntas relacionadas
Mal: 5 mensajes separados con 5 preguntas pequenas
Bien: 1 mensaje con las 5 preguntas agrupadas

### Pide respuestas cortas cuando no necesitas explicacion
Añade al final: "respuesta corta", "sin explicacion", "solo el codigo", "una linea"

### Evita pedir a Claude que re-lea archivos que ya leyo en la misma sesion
Si Claude ya leyo un archivo, referencialo por nombre. No hace falta que lo vuelva a leer.

### `/clear` para limpiar contexto
El comando `/clear` limpia el historial de la sesion actual. Util cuando:
- Has terminado una subtarea y vas a empezar otra distinta
- El contexto se ha llenado de codigo/resultados que ya no son relevantes

## Cuantos tokens tengo (plan Pro de Claude)

Con el plan Pro (suscripcion mensual):
- No hay un limite de tokens fijo publicado — hay un limite de uso "justo" por hora
- Si usas mucho en poco tiempo, Claude Code puede ralentizarse o pausarse temporalmente
- El comando `/cost` muestra el coste acumulado de la sesion actual

## Herramientas que mas tokens consumen (de mayor a menor)

| Herramienta | Coste relativo | Motivo |
|-------------|---------------|--------|
| Agent (subagente) | Muy alto | Abre una sub-sesion completa |
| Read (archivo grande) | Alto | Envia todo el contenido |
| Bash con mucho output | Alto | Output verboso |
| Grep con muchos resultados | Medio | Muchas lineas de resultado |
| Edit | Bajo | Solo envia el diff |
| Glob | Bajo | Solo lista rutas |

## Trucos practicos

- **Archivos grandes**: Si solo necesitas una parte, di "lee las lineas 50-100 de archivo.py"
- **Errores**: Copia solo el stack trace relevante, no todo el log
- **Exploracion**: Usa `/clear` + pregunta directa en vez de explorar incrementalmente en la misma sesion
- **Codigo repetitivo**: Da un ejemplo y di "haz lo mismo para X, Y, Z" — no pegues los tres
