# Ajedrez — ajedrez minimalista y offline para KOReader

Plugin para KOReader (probado en lógica; pensado para Kobo Libra Colour, ARM 32-bit).

## Qué hace
- **Inicio**: ☰ a la izquierda y ✕ a la derecha, con dos opciones: *Jugar vs IA* y *Puzzles*.
- **Menú ☰** (siempre el mismo): *Ajustes* (dificultad, colores del tablero, piezas, modo oscuro, actualización del reloj, reiniciar), *Estadísticas* e *Info*.
- **Partida / puzzle**: el tablero, el reloj si la partida es con tiempo y, al tocar fuera del tablero, la barra superior y los botones inferiores (partida: *Deshacer jugada* —solo sin reloj— y *Rendirse*; puzzles: *Pista* y *Saltar*).
- **IA**: Stockfish con la fuerza emulada según el Elo de Lichess; con la dificultad adaptativa tu nivel se estima con un modelo bayesiano.
- **Puzzles offline** de Lichess (CC0), puntuados como en Lichess: sin pista y sin fallos sube el Elo, un fallo lo baja, con pista no cambia. El puzzle sin terminar se retoma al volver; el número es su posición en el pack.
- Reloj opcional. La partida en curso se guarda y se puede continuar.

> Estado: la lógica está probada con tests (`tests/`), pero **no se ha probado en una Kobo real**; los refrescos de pantalla en Kaleido se han diseñado a partir del plugin zenOS, no medido.

## Instalación
Copia la carpeta `ajedrez.koplugin` a `koreader/plugins/` y reinicia KOReader. Abre *Menú → Herramientas → Ajedrez* (o asigna el gesto "Ajedrez" en Ajustes de gestos).

## Cómo funciona la fuerza de la IA (`ajedrez/strength.lua`)
La IA replica los 8 niveles del "jugar contra la computadora" de Lichess: cada nivel es Stockfish con un *Skill Level*, un límite de profundidad y un tiempo por jugada (nivel 1…8 = Elo 800, 1100, 1400, 1700, 2000, 2300, 2700, 3000; Skill −9, −5, −1, 3, 7, 11, 16, 20; profundidad 5, 5, 5, 5, 5, 8, 13, 22; 50…1000 ms). Los datos salen de las fuentes citadas en `strength.lua` (el código de fishnet no se pudo abrir directamente; las dos fuentes coinciden entre sí).

El *Skill Level* se aplica igual que Stockfish (`Skill::pick_best`): se piden las 4 mejores jugadas y se elige con un sesgo y un azar que dependen solo del nivel. Se calcula en Ajedrez con las puntuaciones del motor, así funcionan también los niveles negativos de Lichess con un Stockfish 11 normal. **Consecuencia: a los niveles bajos la IA se equivoca bastante, igual que en Lichess** (el nivel 3 ≈ 1400 juega profundidad 5 y elige entre sus 4 mejores jugadas con mucho azar).

Entre dos niveles se interpolan los ajustes; por debajo de 800 el Skill sigue bajando (extensión mía, no de Lichess). Como el Kobo es más lento que un servidor, el tiempo por jugada se alarga (hasta ×6, medido con la velocidad real del motor) para llegar a la misma profundidad. Los niveles 1–5 están limitados por profundidad, así que no dependen de la velocidad del aparato. Los Elo nominales de Lichess no son una medición rigurosa: tu nivel se estima contra ellos, así que cualquier sesgo se traslada a tu número.

## Motor
La IA es siempre Stockfish; no hay motor de respaldo. Incluye Stockfish 11 para ARM (`bin/stockfish-armhf`, GPL-3). A los niveles que usa la IA (cientos a decenas de miles de nodos) la diferencia con versiones nuevas es pequeña, así que se mantiene el 11. Si el motor no arranca, Ajedrez lo reinicia una vez (la segunda desde una copia en `/tmp`, por si la carpeta no permite ejecutar) y, si sigue fallando, muestra el motivo exacto y un botón *Reintentar*; la partida espera. Opcionalmente puedes usar otro binario copiándolo como `koreader/data/ajedrez/stockfish` (ver `tools/build_stockfish_kobo.sh`, Stockfish 19 = `sf_19`, sin probar). Corre con prioridad mínima (`nice 19`), 1 hilo, 16 MB de hash, solo mientras piensa la IA; máximo 8 s por jugada (`AI.MAX_MOVE_MS`). El motor se mantiene entre partidas y se cierra al salir del plugin.

## Tablero a color
Por defecto usa los colores de Lichess. La última jugada se marca con casillas amarillas y un marco interior oscuro; las pistas y jugadas posibles son círculos suavizados. Cámbialo en ☰ → Ajustes → *Colores del tablero* (Lichess, verde, azul, blanco y negro).

## Puzzles
Dentro del plugin van 50.000 puzzles (`data/puzzles.txt`, 4,4 MB). Para toda la base de Lichess (~5 millones):
```
python3 tools/build_puzzle_pack.py lichess_db_puzzle.csv.zst puzzles.txt
```
y copia `puzzles.txt` a `koreader/data/ajedrez/puzzles.txt`. Se lee con búsqueda binaria directamente del archivo, sin cargarlo en memoria.

## Pruebas (en un PC, con Lua y Python)
`LUA=lua sh tests/run_ai.sh`, `LUA=lua sh tests/run_ui.sh` y `lua tests/test_pure.lua`.

## Licencias
GPL-3.0. Reglas de ajedrez: de Ink Knight (Beater Studios, GPL-3.0); Stockfish 11: GPL-3.0; piezas Cburnett/Merida (GPL-2+), Chessnut (Apache-2.0); puzzles: base de Lichess, CC0.
