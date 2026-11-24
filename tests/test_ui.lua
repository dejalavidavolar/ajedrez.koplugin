-- Drives the real screens and modes with stubs for KOReader, against the fake engine.
local H = dofile(arg[0]:match("^(.*)/[^/]*$") .. "/harness.lua")
local S = loadfile(H.root .. "/tests/koreader_stubs.lua")(H)
local Chess = require("ajedrez/chess")

-- answers the promotion window by touching the queen
local function pick_queen()
    for i = #S.shown, 1, -1 do
        local w = S.shown[i]
        if w.cells then
            w:onTap(nil, { pos = { x = w.cells[1].x + 2, y = w.cells[1].y + 2 } })
            return true
        end
    end
end

local menu_shown = 0
local ui = { menu = { registerToMainMenu = function() end, onShowMenu = function() menu_shown = menu_shown + 1 end } }
local Ajedrez = dofile(H.root .. "/main.lua")
local plugin = Ajedrez:new{ ui = ui }
plugin:open()
local app = plugin.app
local home = S.top
H.check(home and home.name == "ajedrez_home", "home screen opens")
H.eq(#S.shown, 1, "one screen")

-- the home screen paints its icons
S.texts = {}
home:paintTo(S.bb, 0, 0)
local seen = {}
for _, t in ipairs(S.texts) do seen[t] = true end
H.check(seen["Jugar vs IA"] and seen["Puzzles"], "home titles under the icons")
H.check(home.buttons[1].cx < home.buttons[2].cx, "two icons side by side")
H.eq(home.buttons[1].icon_y, home.buttons[2].icon_y, "same height")

-- home: tap on the top buttons; swipe from the top opens KOReader's menu
H.check(home:onSwipe(nil, { direction = "south", pos = { x = 600, y = 20 } }), "swipe handled")
H.eq(menu_shown, 1, "swipe down from the top opens KOReader's menu")
home:onSwipe(nil, { direction = "south", pos = { x = 600, y = 900 } })
H.eq(menu_shown, 1, "a swipe in the middle does not")

local function tap_home(key)
    for _, b in ipairs(home.buttons) do
        if b.key == key then
            home:onTap(nil, { pos = { x = b.rect.x + 5, y = b.rect.y + 5 } })
        end
    end
    H.run(function() return false end, 1)
end

-- ============ play against the AI, human white, fixed engine replies
app.store:set_option("difficulty", "fixed")
app.store:set_option("fixed_elo", 2800)
app.store:set_option("color", "w")
app.store:set_option("time", "none")
tap_home("ai")
local dialog = S.last_dialog("buttons")
H.check(dialog, "new game dialog shown")
H.check(S.press(dialog, "Empezar"), "start pressed")
local play = S.top
H.eq(play.name, "ajedrez_play", "game screen on top")
H.eq(#S.shown, 2, "home below, game above")
H.eq(play.flipped, false, "white at the bottom")
H.eq(play.board.theme, require("ajedrez/ui/board_view").THEMES.lichess, "Lichess colors by default")

-- margins and coordinates: the board is centered and keeps blank space at the sides
local b = play.board
H.check(b.gutter > 0, "coordinates have a gutter")
H.eq(b.x * 2 + b.side, S.screen:getWidth(), "board centered horizontally")
H.check(b.x - b.gutter >= 20, "blank margin at the sides: " .. (b.x - b.gutter))
local fr = b:frame_rect()
H.check(fr.x >= 0 and fr.x + fr.w <= S.screen:getWidth(), "frame inside the screen")
S.texts = {}
play:paintTo(S.bb, 0, 0)
local letters = {}
for _, t in ipairs(S.texts) do letters[t] = true end
H.check(letters.a and letters.h and letters["1"] and letters["8"], "coordinates drawn")
local fulls = 0
for _, d in ipairs(S.dirty) do if d.w == play and d.mode == "full" then fulls = fulls + 1 end end
H.check(fulls >= 1 and fulls <= 2, "full refresh on entering the board (the show and the end of opening, merged by UIManager): " .. fulls)
local extra = 0
for _, d in ipairs(S.dirty) do if d.w == play and d.mode ~= "full" then extra = extra + 1 end end
H.eq(extra, 0, "nothing else is refreshed while the board opens (no second flash)")
H.eq(play.opening, false, "the opening ends once the mode is set up")

-- the UI is hidden at first; tap near the top shows the title bar; again hides it
H.eq(play.bar_visible, false, "bar hidden at the start")
play:onTap(nil, { pos = { x = 600, y = 30 } })
H.eq(play.bar_visible, true, "tap on the top shows the bar")
play:onTap(nil, { pos = { x = 600, y = 30 } })
H.eq(play.bar_visible, false, "tap on the top hides it")
-- left alone, the bar goes away by itself
play:onTap(nil, { pos = { x = 600, y = 30 } })
H.eq(play.bar_visible, true, "bar shown again")
H.check(play.hide_fn ~= nil, "auto-hide armed")
play.hide_fn()
H.eq(play.bar_visible, false, "bar hides itself when not touched")
-- opening the menu keeps it (no auto-hide while a window is up)
play:onTap(nil, { pos = { x = 600, y = 30 } })
play:open_menu()
H.eq(play.hide_fn, nil, "no auto-hide with the menu open")
S.last_dialog("buttons"):close()
H.check(play.hide_fn ~= nil, "auto-hide re-armed after the menu closes")
-- touching the board hides it too
play:onTap(nil, { pos = S.pixel_of(play, "e2") })
H.eq(play.bar_visible, false, "tap on the board hides the bar")
play:clear_selection()
play:onSwipe(nil, { direction = "south", pos = { x = 600, y = 15 } })
H.eq(menu_shown, 2, "swipe from the top inside a game opens KOReader's menu")

-- windows are drawn over a hatched screen
S.bb.calls.alphablitFrom = 0
local popup = require("ajedrez/ui/popup"):new{ buttons = { { { text = "x" } } } }
popup:paintTo(S.bb, 0, 0)
H.check(S.bb.calls.alphablitFrom > 50, "hatching blits tiles behind a window: " .. tostring(S.bb.calls.alphablitFrom))
H.check((S.pixels or 0) > 0, "hatching tile built")
-- KOReader's own menu is hatched too while Ajedrez is open, and left alone afterwards
S.bb.calls.alphablitFrom = 0
local menu = S.TouchMenu:new{ dimen = { w = 1264, h = 400 } }
menu:paintTo(S.bb, 0, 0)
H.check(S.bb.calls.alphablitFrom > 0 and S.menu_painted == 1, "touch menu: hatching under it and the menu itself painted")

-- bottom buttons of a game: undo and resign, with the interface
play:onTap(nil, { pos = { x = 600, y = 30 } })
H.check(play:actions_visible(), "buttons shown with the interface")
H.eq(play.actions[1].label, "Deshacer jugada", "undo first")
H.eq(play.actions[2].label, "Rendirse", "resign second")
local fr2 = play.board:frame_rect()
for _, r in ipairs(play.button_rects) do
    H.check(r.y >= fr2.y + fr2.h, "button below the board")
end
-- a tap on the frame (not a square) also toggles the interface
play:onTap(nil, { pos = { x = fr2.x + 2, y = fr2.y + 2 } })
H.eq(play.bar_visible, false, "tap outside the squares hides it")
play:onTap(nil, { pos = { x = 600, y = 30 } })
play.hide_fn()
H.eq(play:actions_visible(), false, "buttons hide with the interface")
-- the hamburger opens the same menu as the home screen
play:onTap(nil, { pos = { x = 600, y = 30 } })
play:open_menu()
local pm1 = S.last_dialog("buttons")
local items = {}
for _, row in ipairs(pm1.buttons) do items[#items + 1] = row[1].text end
H.eq(table.concat(items, "|"), "Ajustes|Estadísticas|Info", "same menu in the game")
pm1:close()
play:show_bar(false)
-- clocks are not drawn in an untimed game
-- illegal selection and moves
S.tap_square(play, "e7") -- not mine
H.eq(play.view.selected, nil, "opponent piece is not selected")
S.tap_square(play, "e2")
H.eq(play.view.selected, Chess.square_from_name("e2"), "e2 selected")
H.check(play.view.targets[Chess.square_from_name("e4")], "e4 is a target")
H.check(not play.view.targets[Chess.square_from_name("e5")], "e5 is not")
S.tap_square(play, "e2")
H.eq(play.view.selected, nil, "tap again deselects")

-- only squares that changed are refreshed: an identical position refreshes nothing, a move only its squares
do
    local n = #S.dirty
    play:set_position(play.view.position, { last = play.view.last })
    H.eq(#S.dirty, n, "nothing changed, nothing refreshed")
end

-- one move = one refresh rectangle, not several flashes
do
    local n = #S.dirty
    play:set_position(play.view.position, { last = play.view.last })
    local pos = play.view.position
    -- pretend a pawn moved: the squares involved are refreshed together
    local moved = { board = {} }
    for sq, pc in pairs(pos.board) do moved.board[sq] = pc end
    moved.board[13], moved.board[29] = nil, "P"
    local before = #S.dirty
    play:set_position(moved, { last = { from = 13, to = 29 } })
    local partials = 0
    for i = before + 1, #S.dirty do if S.dirty[i].mode == "ui" then partials = partials + 1 end end
    H.check(partials <= 1, "a move refreshes one rectangle, got " .. partials)
    play:set_position(pos, { last = play.view.last })
end

-- no full refresh during the game
local fulls_before = 0
for _, d in ipairs(S.dirty) do if d.mode == "full" then fulls_before = fulls_before + 1 end end

-- fool's mate: the fake engine answers e7e5 then d8h4
local mode = app.mode
local function human(from, to)
    S.tap_square(play, from)
    S.tap_square(play, to)
    H.run(function() return mode.game:turn() == "w" or mode.game.over end, 25)
end
-- the fake engine has to answer; it reads FAKE_SEQ
human("f2", "f3")
H.eq(mode.game.moves[2], "e7e5", "AI answered e7e5, got " .. tostring(mode.game.moves[2]))
human("g2", "g4")
H.check(mode.game.over and mode.game.over.result == "mate" and mode.game.over.winner == "b", "AI mated")
local fulls_after = 0
for _, d in ipairs(S.dirty) do if d.mode == "full" then fulls_after = fulls_after + 1 end end
H.eq(fulls_after, fulls_before, "no full refresh while playing")
H.check(play.banner ~= nil, "end banner shown")
H.check(play.bar_sticky == true, "bar stays at the end of a game")
H.check(play.hide_fn == nil, "no auto-hide at the end")
H.check(play.banner.text:find("Perdiste", 1, true) ~= nil, "banner says you lost: " .. tostring(play.banner.text))
H.eq(play.bar_visible, true, "bar shown at the end")
H.eq(app.store.stats.losses, 1, "loss recorded")
H.eq(app.store.player.games, 1, "rating updated")
H.eq(app.store:saved_game(), nil, "no saved game after the end")
-- banner button asks for a new game
play:onTap(nil, { pos = { x = play.banner_rect.x + play.banner_rect.w - 20, y = play.banner_rect.y + 10 } })
local nd = S.last_dialog("buttons")
H.check(S.press(nd, "Empezar"), "new game from the banner")
local play2 = S.top
H.check(play2 ~= play and play2.name == "ajedrez_play", "a new game screen")
H.eq(#S.shown, 2, "old game screen closed")
play2:close()
H.eq(#S.shown, 1, "closing returns to home")

-- ============ resume: a game left in the middle comes back
app.store:clear_game()
app.store:set_option("color", "b")
tap_home("ai")
S.press(S.last_dialog("buttons"), "Empezar")
local black_game = S.top
H.eq(black_game.flipped, true, "black at the bottom")
H.run(function() return app.mode.game.moves[1] ~= nil end, 25)
H.check(app.mode.game.moves[1] ~= nil, "AI (white) opens")
black_game:close()
H.check(app.store:saved_game() ~= nil, "game saved on exit")
tap_home("ai")
local choose = S.last_dialog("buttons")
H.check(S.press(choose, "Continuar"), "resume offered")
H.eq(app.mode.game.moves[1] ~= nil, true, "resumed game keeps its moves")
local resumed = S.top
-- resign counts as a loss
app.mode:resign()
H.check(app.mode.game.over and app.mode.game.over.result == "resign", "resigned")
H.eq(app.store.stats.losses, 2, "second loss")
resumed:close()

-- color screen: Lichess colors by default, and the menu can change them
S.color = true
H.eq(app:board_theme(), "lichess", "Lichess colors on a color screen")
app:open_menu()
S.press(S.last_dialog("buttons"), "Ajustes")
S.press(S.last_dialog("buttons"), "Colores")
H.check(S.press(S.last_dialog("buttons"), "Verde"), "theme dialog")
H.eq(app:board_theme(), "green", "green chosen")
H.check(S.last_dialog("buttons") and S.last_dialog("buttons").title == "Ajustes", "settings come back after a choice")
app.store:set_option("board_theme", "lichess")
-- a game on a color board paints without error
app.store:clear_game()
tap_home("ai")
S.press(S.last_dialog("buttons"), "Empezar")
H.eq(S.top.board.theme, require("ajedrez/ui/board_view").THEMES.lichess, "game uses the Lichess board")
S.tap_square(S.top, "e2")
S.top:close()

-- ============ undo and resign buttons (untimed game)
app.store:clear_game()
app.store:set_option("color", "w")
app.store:set_option("time", "none")
tap_home("ai")
S.press(S.last_dialog("buttons"), "Empezar")
local ug = S.top
local um = app.mode
S.tap_square(ug, "f2")
S.tap_square(ug, "f3")
H.run(function() return #um.game.moves >= 2 end, 25)
H.eq(#um.game.moves, 2, "a move and the answer")
ug:onTap(nil, { pos = { x = 600, y = 30 } })
local ur = ug.button_rects[1]
ug:onTap(nil, { pos = { x = ur.x + 10, y = ur.y + 10 } })
H.run(function() return #um.game.moves == 0 end, 2)
H.eq(#um.game.moves, 0, "undo takes back the move and the answer")
H.eq(um.game:turn(), "w", "it is the player's turn again")
H.eq(app.store:saved_game(), nil, "nothing to resume after undoing everything")
H.check(um.game.over == nil, "the game goes on")
-- resign asks first
local rr = ug.button_rects[2]
ug:onTap(nil, { pos = { x = rr.x + 10, y = rr.y + 10 } })
H.run(function() return false end, 1)
local conf = S.last_dialog("confirm")
H.check(conf and S.press(conf, "Rendirse"), "resign asks for confirmation")
H.check(um.game.over and um.game.over.result == "resign", "resigned")
H.eq(ug:actions_visible(), false, "buttons gone when the game is over")
ug:close()
app.store:clear_game()

-- ============ clock
app.store:clear_game()
app.store:set_option("color", "w")
app.store:set_option("time", "3+2")
local UIM = require("ui/uimanager")
local orig_schedule, delays = UIM.scheduleIn, {}
UIM.scheduleIn = function(self, sec, fn) delays[#delays + 1] = sec return orig_schedule(self, sec, fn) end
tap_home("ai")
S.press(S.last_dialog("buttons"), "Empezar")
local timed = S.top
H.check(timed.clock_fn ~= nil, "clock shown for a timed game")
local top, bottom = timed.clock_fn()
H.eq(bottom, "3:00", "player starts with 3 minutes")
local found15 = false
for _, d in ipairs(delays) do if d == 15 then found15 = true end end
H.check(found15, "the clock is redrawn every 15 seconds by default")
UIM.scheduleIn = orig_schedule
local cr = timed:clock_rects()
H.check(cr.top.x < cr.bottom.x, "top clock on the left, bottom clock on the right")
H.eq(cr.top.x, timed.board.x - timed.board.gutter, "top clock level with the left edge of the frame")
H.eq(cr.bottom.x + cr.bottom.w, timed.board.x + timed.board.side + timed.board.gutter, "bottom clock ends at the right edge of the frame")
timed:onTap(nil, { pos = { x = 600, y = 30 } })
H.eq(#timed.actions, 1, "no undo in a timed game")
H.eq(timed.actions[1].label, "Rendirse", "only resign")
timed:close()
app.store:set_option("time", "none")

-- ============ puzzles
app.store:clear_game()
tap_home("puzzles")
local pz = S.top
H.eq(pz.name, "ajedrez_play", "puzzle screen")
local pm = app.mode
H.check(pm.puzzle, "a puzzle was chosen")
H.check(type(pm.number) == "number" and pm.number >= 1 and pm.number <= pm.pack.count, "number is a position in the pack: " .. tostring(pm.number))
H.eq(pz.label, "#" .. pm.number, "the puzzle number (a plain count) is shown where the clock goes")
H.eq(app.store:current_puzzle().entry.id, pm.puzzle.id, "the puzzle in progress is saved")
do
    local r = pz:clock_rects().top
    S.texts = {}
    pz:paintTo(S.bb, 0, 0)
    local drawn = false
    for _, t in ipairs(S.texts) do if t == pz.label then drawn = true end end
    H.check(drawn, "the label is drawn")
    H.eq(r.x, pz.board.x - pz.board.gutter, "label at the top left")
end
local rating0 = app.store.puzzle:value()
-- wrong move first: pick any legal move that is not the expected one
local expected = pm.puzzle:expected()
for _, move in ipairs(Chess.legal_moves(pm.puzzle.position)) do
    if Chess.move_to_uci(move) ~= expected then
        local uci = Chess.move_to_uci(move)
        S.tap_square(pz, uci:sub(1, 2))
        S.tap_square(pz, uci:sub(3, 4))
        break
    end
end
H.check(pz.note and pz.note:find("¡Ese no es el movimiento! Prueba algo distinto.", 1, true) and not pz.banner, "wrong move: note under the board, no banner")
H.eq(app.store.stats.failed, 1, "failure recorded")
-- now solve it
local guard = 0
while not pm.finished and guard < 20 do
    guard = guard + 1
    local uci = pm.puzzle:expected()
    S.tap_square(pz, uci:sub(1, 2))
    S.tap_square(pz, uci:sub(3, 4))
    if #uci == 5 then
        -- promotion: answer the dialog
        pick_queen()
    end
    H.run(function() return not pm.waiting end, 5)
end
H.check(pm.finished, "puzzle finished")
H.eq(pz.bar_visible, false, "at the end of a puzzle only the bottom speaks: no top bar")
H.check(pz.banner.text:find("ELO", 1, true) and pz.banner.text:find("-", 1, true) and not pz.banner.text:find("Puntaje", 1, true), "failed puzzle: rating goes down, no score: " .. pz.banner.text)
H.check(pz.banner and pz.banner.label == "Siguiente", "next button offered")
H.check(app.store.puzzle:value() < rating0 + 1, "a failed-then-solved puzzle does not raise the rating")
-- next puzzle, solve cleanly: rating goes up
local before = app.store.puzzle:value()
pz:onTap(nil, { pos = { x = pz.banner_rect.x + pz.banner_rect.w - 20, y = pz.banner_rect.y + 10 } })
H.check(pm.puzzle and not pm.finished, "next puzzle")
guard = 0
while not pm.finished and guard < 20 do
    guard = guard + 1
    local uci = pm.puzzle:expected()
    S.tap_square(pz, uci:sub(1, 2))
    S.tap_square(pz, uci:sub(3, 4))
    if #uci == 5 then pick_queen() end
    H.run(function() return not pm.waiting end, 5)
end
H.check(pm.finished and pm.puzzle:score() == 1, "clean solve")
H.check(pz.banner.text:find("+", 1, true) and not pz.banner.text:find("Puntaje", 1, true), "solved puzzle: rating goes up, no score: " .. pz.banner.text)
H.eq(pz.bar_visible, false, "no top bar after solving")
H.check(app.store.puzzle:value() > before, "clean solve raises the rating")
pz:onTap(nil, { pos = { x = pz.banner_rect.x + pz.banner_rect.w - 20, y = pz.banner_rect.y + 10 } })
-- bottom buttons: hint and skip appear with the interface, on a tap outside the board
H.eq(pz.bar_visible, false, "interface hidden")
pz:onTap(nil, { pos = { x = 600, y = 30 } })
H.eq(pz.bar_visible, true, "tap outside the board shows the interface")
H.check(pz:actions_visible(), "puzzle buttons shown with it")
H.eq(#pz.actions, 2, "two buttons: hint and skip")
H.eq(pz.actions[1].label, "Pista", "first is the hint")
H.eq(pz.actions[2].label, "Saltar", "second is skip")
local r1 = pz.button_rects[1]
H.check(r1.y > pz.board:frame_rect().y + pz.board:frame_rect().h, "buttons below the board")
pz:onTap(nil, { pos = { x = r1.x + 10, y = r1.y + 10 } })
H.run(function() return pz.view.hint ~= nil end, 2)
H.check(pz.view.hint ~= nil, "hint marks a square")
local r2 = pz.button_rects[2]
pz:onTap(nil, { pos = { x = r2.x + 10, y = r2.y + 10 } })
H.run(function() return false end, 1)
H.check(pm.puzzle and not pm.finished, "skipped to a new puzzle")
-- no show-solution and no flip anywhere
H.check(pm.show_solution == nil and pz.flip == nil, "no solution/flip functions left")
pz:close()

-- ============ the menu: settings, statistics, info (the same from the home screen and from the board)
app:open_menu()
local hm = S.last_dialog("buttons")
local labels = {}
for _, row in ipairs(hm.buttons) do labels[#labels + 1] = row[1].text end
H.eq(table.concat(labels, "|"), "Ajustes|Estadísticas|Info", "menu has exactly three entries")
H.check(S.press(hm, "Estadísticas"), "stats")
H.check(S.last_dialog("info").text:find("nivel", 1, true), "stats text: " .. tostring(S.last_dialog("info").text))
app:open_menu()
S.press(S.last_dialog("buttons"), "Info")
local about = S.last_dialog("info").text
H.eq(about, "Ajedrez (fork de Paperknight)\nVersión 0.2.0", "info shows only the name and the version")
app:open_menu()
S.press(S.last_dialog("buttons"), "Ajustes")
local st = S.last_dialog("buttons")
local entries = {}
for _, row in ipairs(st.buttons) do entries[#entries + 1] = row[1].text end
H.check(#entries == 6 and entries[1]:find("Dificultad", 1, true) and entries[2]:find("Colores", 1, true)
    and entries[3]:find("Piezas", 1, true) and entries[4]:find("oscuro", 1, true) and entries[5]:find("reloj", 1, true), "settings list: " .. table.concat(entries, " | "))
H.check(entries[5]:find("15 s", 1, true), "clock update is 15 s by default")
S.press(st, "Dificultad")
S.press(S.last_dialog("buttons"), "Adaptativa")
H.eq(app.store:option("difficulty"), "adaptive", "adaptive chosen")
S.press(S.last_dialog("buttons"), "Volver")
S.press(S.last_dialog("buttons"), "Piezas")
S.press(S.last_dialog("buttons"), "Merida")
H.eq(app.store:option("piece_set"), "merida", "piece set chosen")
S.press(S.last_dialog("buttons"), "reloj")
S.press(S.last_dialog("buttons"), "30 s")
H.eq(app.store:option("clock_refresh"), 30, "clock refresh chosen")
app.store:set_option("clock_refresh", 15)
app.store:set_option("piece_set", "cburnett")

-- X on the home screen closes everything
-- (dialogs and infos left open by the checks above are not screens)
local screens = {}
for _, w in ipairs(S.shown) do if w.name then screens[#screens + 1] = w end end
H.eq(#screens, 1, "only the home screen is left")
app:close_all()
screens = {}
for _, w in ipairs(S.shown) do if w.name then screens[#screens + 1] = w end end
H.eq(#screens, 0, "X closes the plugin")
plugin:open()
H.eq(S.top.name, "ajedrez_home", "can be opened again")
app:close_all()
S.bb.calls.alphablitFrom = 0
S.TouchMenu:new{ dimen = { w = 1264, h = 400 } }:paintTo(S.bb, 0, 0)
H.eq(S.bb.calls.alphablitFrom, 0, "touch menu back to normal after closing Ajedrez")

-- dark mode swaps ink and paper
local Common = require("ajedrez/ui/common")
Common.set_dark(true)
H.check(Common.WHITE ~= require("ffi/blitbuffer").COLOR_WHITE, "dark mode: paper is black")
Common.set_dark(false)

-- a selection refreshes at once with the light waveform, the move afterwards with the clean one
do
    local before = #S.dirty
    play:select(30, { [38] = true })
    local ui, partial = 0, 0
    for i = before + 1, #S.dirty do
        if S.dirty[i].mode == "ui" then ui = ui + 1 elseif S.dirty[i].mode == "partial" then partial = partial + 1 end
    end
    H.check(ui == 1 and partial == 0, "selecting: one immediate light refresh (" .. ui .. "/" .. partial .. ")")
    H.check(play.deferred == nil, "nothing is deferred")
end

H.done("ui")
