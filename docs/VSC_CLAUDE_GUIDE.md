# Claude Code en VS Code: Maximo rendimiento al minimo coste

## Dos modos de uso: CLI vs Extension

| | Terminal (CLI) | Extension VS Code |
|---|---|---|
| Acceso | `claude` en terminal | Panel lateral o Cmd+Shift+P |
| Contexto visual | No ve el editor | Ve tu seleccion y archivo activo |
| Coste | Igual | Igual |
| Mejor para | Scripts, git, tareas largas | Edicion de codigo, explicaciones |

## Funciones de VS Code que ahorran tokens

### 1. Selecciona codigo antes de preguntar
Si seleccionas 20 lineas antes de escribirle a Claude, Claude recibe exactamente esas 20 lineas como contexto — no el archivo entero (cientos de lineas). Esto puede reducir el input x10.

Como: Selecciona codigo en el editor → escribe tu pregunta en el panel de Claude.

### 2. Usa referencias de archivo con @
En el chat de Claude Code puedes escribir `@archivo.py` y Claude leera ese archivo. Pero si ya lo tienes abierto y seleccionas la parte relevante, es mas barato.

### 3. Abre solo los archivos relevantes
Claude puede ver que archivos tienes abiertos. Cierra pestanas irrelevantes antes de una sesion larga para no contaminar el contexto.

## Workflows eficientes

### Para un bug concreto
1. Ve a la linea del error
2. Selecciona la funcion completa (no el archivo)
3. Escribe: "hay un bug aqui: [pega el error]. Arreglalo"
4. Coste: bajo — contexto minimo, tarea clara

### Para entender codigo nuevo
1. Selecciona la clase/funcion que no entiendes
2. Escribe: "explica esto en 3 lineas"
3. No pidas que explore el repo — dale solo lo que necesita

### Para refactorizar
1. Selecciona el bloque a refactorizar
2. Escribe: "refactoriza esto para que sea mas limpio. Sin cambiar la logica."
3. Claude edita directamente — no genera codigo nuevo en el chat

### Para tareas de proyecto completas (arquitectura, nuevos modulos)
1. Usa el terminal con `claude` — no la extension
2. Dale un CLAUDE.md en la raiz con el contexto del proyecto (evitas repetirlo cada sesion)
3. Usa `/plan` para alinear el approach antes de que empiece a escribir codigo

## El archivo CLAUDE.md — tu mejor inversion de tokens

Crea un archivo `CLAUDE.md` en la raiz del proyecto con:
- Descripcion del proyecto (2-3 lineas)
- Stack tecnico
- Convenciones de codigo (nombres, estructura)
- Comandos frecuentes (como correr tests, como deployar)

Claude lo lee automaticamente al inicio de cada sesion. Evita que tengas que explicar el proyecto cada vez.

Ejemplo minimo:
```markdown
# bot_podcasts
Bot que descarga y procesa podcasts automaticamente.
Stack: Python 3.11, SQLite, RSS feeds.
Tests: pytest. Run: `pytest tests/`
Convencion: snake_case, funciones pequenas, sin clases innecesarias.
```

## Atajos utiles en VS Code con Claude Code

| Accion | Como |
|--------|------|
| Abrir chat Claude | Cmd+Shift+P → "Claude: Open Chat" |
| Limpiar contexto | `/clear` en el chat |
| Ver coste sesion | `/cost` en el chat |
| Modo rapido | `/fast` (mismo modelo, output mas rapido) |
| Deshacer cambios de Claude | Cmd+Z normal en el editor |

## Cuando usar el terminal en vez de la extension

- Tareas largas que tocaran muchos archivos (refactors grandes, scaffolding)
- Comandos git, scripts de sistema
- Cuando quieres ver el output paso a paso
- Cuando trabajas sin interfaz grafica (SSH al servidor Intel)

## Patron: sesiones cortas y enfocadas

La forma mas barata de usar Claude Code:
1. Sesion nueva para cada tarea (contexto 0 = tokens 0 de arrastre)
2. Mensaje inicial claro con toda la info necesaria
3. Maximo 5-10 turnos por tarea
4. `/clear` o nueva sesion si cambias de tema

Evita el patron: "bueno, ya que estamos... y otra cosa..."
Cada desvio acumula contexto y sube el coste.
