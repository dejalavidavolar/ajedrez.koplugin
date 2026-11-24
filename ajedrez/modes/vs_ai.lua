-- A game against the AI. The AI plays at the level the player's results point to (see rating.lua), so the game is
-- always close to an even one.
local Chess = require("ajedrez/chess")
local Clock = require("ajedrez/clock")
local Game = require("ajedrez/game")
local UIManager = require("ui/uimanager")

local PlayScreen = require("ajedrez/ui/play_screen")

local VsAI = {}
VsAI.__index = VsAI

local function now()
    local ok, time = pcall(require, "ui/time")
    if ok and time.to_s and time.now then
        return time.to_s(time.now())
    end
    return os.time()
end

local function other(color)
    return color == "w" and "b" or "w"
end

-- opts: resume (bool), color ("w"/"b"/"random"), time ("none" or "5+3")
function VsAI.start(app, opts)
    local self = setmetatable({ app = app, T = app.T, store = app.store }, VsAI)
    local saved = opts.resume and app.store:saved_game() or nil
    local game = saved and Game.from_save(saved)
    if game and not game.over then
        self.game = game
        self.human = saved.human
        self.ai_elo = saved.ai_elo
        self.tc = saved.tc
        self.left = saved.left
    else
        self.game = Game.new()
        local color = opts.color
        if color ~= "w" and color ~= "b" then
            color = math.random(2) == 1 and "w" or "b"
        end
        self.human = color
        self.ai_elo = app.store:ai_elo()
        self.tc = nil
        local base, inc = tostring(opts.time or "none"):match("^(%d+)%+(%d+)$")
        if base then
            self.tc = { base = tonumber(base) * 60, inc = tonumber(inc) }
        end
    end
    self.ai = app:get_ai()
    self.screen = PlayScreen:new{ app = app, mode = self, flipped = self.human == "b" }
    self.screen.on_closed = function() app:mode_closed(self) end
    if self.tc then
        self.clock = Clock.new(self.tc.base, self.tc.inc, now)
        if self.left then
            self.clock.left.w, self.clock.left.b = self.left.w, self.left.b
        end
        self.screen:set_clock(function() return self:clock_texts() end)
    end
    -- the one full refresh: it is the refresh of the show itself
    UIManager:show(self.screen, "full")
    self:set_actions()
    self:refresh_title()
    self:show_position()
    self.screen:finish_opening()
    self:begin_turn()
    return self
end

-- ---------------------------------------------------------------- display

function VsAI:show_position()
    local game = self.game
    local check
    if game:in_check() then
        check = Chess.king_square(game.position, game:turn())
    end
    self.screen:set_position(game.position, { last = game.last, check = check })
end

function VsAI:refresh_title()
    local T = self.T
    self.screen:set_title(string.format(T.ai_plays_at, self.ai_elo))
end

function VsAI:clock_texts()
    local c = self.clock
    local ai = other(self.human)
    local running = c.running
    return Clock.format(c:remaining(ai)), Clock.format(c:remaining(self.human)),
        running and (running == ai and "top" or "bottom") or nil
end

-- ---------------------------------------------------------------- turns

function VsAI:begin_turn()
    if self.game.over then
        return self:finish()
    end
    self:save()
    if self.clock and not self.clock.running then
        self.clock:start(self.game:turn())
        self:schedule_tick()
    end
    if self.game:turn() ~= self.human then
        self:ai_turn()
    end
end

-- Seconds between two redraws of the clocks (a setting): every second would redraw the e-ink screen all the time.
function VsAI:clock_interval()
    return tonumber(self.store:option("clock_refresh")) or 15
end

function VsAI:schedule_tick()
    if self.tick_handle or not self.clock then
        return
    end
    self.tick_handle = function()
        self.tick_handle = nil
        if self.closed or self.game.over then
            return
        end
        local flagged = self.clock:flagged()
        if flagged then
            return self:flag(flagged)
        end
        self.screen:refresh_clocks()
        self:schedule_tick()
    end
    -- never later than the moment a flag falls
    local delay = self:clock_interval()
    if self.clock.running then
        delay = math.min(delay, self.clock:remaining(self.clock.running) + 0.05)
    end
    UIManager:scheduleIn(math.max(0.2, delay), self.tick_handle)
end

function VsAI:stop_tick()
    if self.tick_handle then
        UIManager:unschedule(self.tick_handle)
        self.tick_handle = nil
    end
end

function VsAI:ai_turn()
    self.thinking = true
    self.token = (self.token or 0) + 1
    local token = self.token
    local limit_ms
    if self.clock then
        local ai = other(self.human)
        limit_ms = (self.clock:remaining(ai) / 25 + self.tc.inc * 0.7) * 1000
    end
    self.ai:request(self.game.start_fen, self.game:moves_string(), self.ai_elo, limit_ms, function(uci, info)
        if self.closed or token ~= self.token then
            return
        end
        self.thinking = false
        if info and info.error then
            return self:engine_failed(info.error)
        end
        if not uci or not self.game:play_uci(uci) then
            return
        end
        self.screen:clear_banner()
        self:after_move(other(self.human))
    end)
end

-- Stockfish would not run. The game waits: the banner retries, and the message says why.
function VsAI:engine_failed(reason)
    require("logger").warn("Ajedrez: Stockfish failed:", reason)
    self.screen:set_banner(self.T.engine_failed, self.T.retry, function()
        self.screen:clear_banner()
        self:ai_turn()
    end)
    self.screen:show_bar(true)
    UIManager:show(require("ajedrez/ui/popup").info(string.format(self.T.engine_error, tostring(reason)), self.T.ok))
end

-- The side `mover` has just moved.
function VsAI:after_move(mover)
    if self.clock and not self.game.over then
        self.clock:switch(other(mover))
    elseif self.clock then
        self.clock:stop()
    end
    self:show_position()
    self:refresh_title()
    if self.clock then
        -- the side that moves now has changed: show both times at once, then count with the usual interval
        self.screen:refresh_clocks()
        self:stop_tick()
        self:schedule_tick()
    end
    if self.game.over then
        return self:finish()
    end
    self:save()
end

function VsAI:on_square(square)
    local game = self.game
    if game.over or self.thinking or game:turn() ~= self.human then
        return
    end
    local screen = self.screen
    local position = game.position
    local piece = position.board[square]
    local mine = piece and ((piece == piece:upper()) == (self.human == "w"))
    if self.selected then
        local targets = Chess.targets_from(position, self.selected, game:legal_moves())
        local moves = targets[square]
        if moves then
            self.selected = nil
            if #moves > 1 then
                return screen:ask_promotion(self.T, self.human, function(letter)
                    for _, move in ipairs(moves) do
                        if move.promotion == letter then
                            return self:play_human(move)
                        end
                    end
                end, function()
                    screen:clear_selection()
                end)
            end
            return self:play_human(moves[1])
        end
        if square == self.selected then
            self.selected = nil
            return screen:clear_selection()
        end
    end
    if mine then
        local targets = Chess.targets_from(position, square, game:legal_moves())
        local set = {}
        for target in pairs(targets) do
            set[target] = true
        end
        self.selected = square
        screen:select(square, set)
    else
        self.selected = nil
        screen:clear_selection()
    end
end

function VsAI:play_human(move)
    self.game:play(move)
    -- once the player has moved, the bar goes away so only the board is left
    self.screen:show_bar(false)
    self:after_move(self.human)
    if not self.game.over then
        self:begin_turn()
    end
end

-- ---------------------------------------------------------------- the end

function VsAI:flag(color)
    local game = self.game
    local winner = other(color)
    if not Chess.can_mate(game.position, winner) then
        game:finish("insufficient")
    else
        game:finish("time", winner)
    end
    self.clock:stop()
    self:show_position()
    self:finish()
end

function VsAI:resign()
    if self.game.over then
        return
    end
    self.ai:cancel()
    self.token = (self.token or 0) + 1
    self.thinking = false
    if self.clock then
        self.clock:stop()
    end
    self.game:finish("resign", other(self.human))
    self:finish()
end

function VsAI:finish()
    if self.finished then
        return
    end
    self.finished = true
    local T, over = self.T, self.game.over
    local score
    local headline
    if over.winner == nil then
        score, headline = 0.5, T.draw
    elseif over.winner == self.human then
        score, headline = 1, T.you_win
    else
        score, headline = 0, T.you_lose
    end
    local reasons = {
        mate = T.by_mate, resign = T.by_resign, time = T.by_time, stalemate = T.stalemate,
        insufficient = T.insufficient, fifty = T.fifty, repetition = T.repetition,
    }
    local reason = reasons[over.result]
    local delta = self.store:record_game(self.ai_elo, score)
    self.store:clear_game()
    local rating = self.store.player:value()
    local text = string.format("%s %s · %d (%s%d)", headline, reason or "", rating, delta >= 0 and "+" or "", delta)
    self:set_actions()
    self.screen:set_banner(text, T.new_game, function()
        self.app:new_game_dialog(function(opts)
            self.screen:close()
            self.app:start_game(opts)
        end)
    end)
    self.screen:show_bar(true, true)
    self:refresh_title()
end

-- ---------------------------------------------------------------- persistence, menu, lifecycle

function VsAI:save()
    if self.game.over or #self.game.moves == 0 then
        return
    end
    local t = self.game:to_save()
    t.human, t.ai_elo, t.tc = self.human, self.ai_elo, self.tc
    if self.clock then
        t.left = { w = self.clock:remaining("w"), b = self.clock:remaining("b") }
    end
    self.store:save_game(t)
end

-- The buttons at the bottom of the screen: take back a move (not in timed games) and resign.
function VsAI:set_actions()
    local T = self.T
    if self.game.over then
        return self.screen:set_actions(nil)
    end
    local list = {}
    if not self.clock then
        list[#list + 1] = { label = T.undo, icon = "undo", callback = function() self:undo() end }
    end
    list[#list + 1] = { label = T.resign, icon = "resign", callback = function()
        UIManager:show(require("ajedrez/ui/popup").confirm{
            text = T.resign_confirm,
            ok_text = T.resign,
            cancel_text = T.cancel,
            ok_callback = function() self:resign() end,
        })
    end }
    self.screen:set_actions(list)
end

-- Takes back the last move of the player and the answer of the AI (or the player's move only, if the AI has not
-- answered yet).
function VsAI:undo()
    if self.game.over or self.clock then
        return
    end
    local moves = self.game.moves
    local parity = self.human == "w" and 1 or 0
    local k
    for i = #moves, 1, -1 do
        if i % 2 == parity then
            k = i
            break
        end
    end
    if not k then
        return
    end
    self.ai:cancel()
    self.token = (self.token or 0) + 1
    self.thinking = false
    self.selected = nil
    local keep = {}
    for i = 1, k - 1 do
        keep[i] = moves[i]
    end
    self.game = Game.new{ fen = self.game.start_fen, moves = keep }
    self.screen:clear_banner()
    self:show_position()
    self:refresh_title()
    if #keep == 0 then
        self.store:clear_game()
    else
        self:save()
    end
    self:begin_turn()
end

-- Board colors, pieces or the clock interval changed.
function VsAI:on_settings_changed()
    self.screen:apply_settings()
    self:stop_tick()
    self:schedule_tick()
end

function VsAI:on_suspend()
    self.ai:cancel()
    -- the time the device sleeps is not time of the game
    if self.clock then
        self.clock:stop()
    end
    self.token = (self.token or 0) + 1
    self.thinking = false
    if not self.game.over then
        self:save()
    end
end

function VsAI:on_resume()
    if self.clock and not self.game.over then
        self.clock:start(self.game:turn())
        self:schedule_tick()
    end
    if not self.game.over and self.game:turn() ~= self.human and not self.thinking then
        self:ai_turn()
    end
end

function VsAI:on_close()
    self.closed = true
    self.token = (self.token or 0) + 1
    self:stop_tick()
    if not self.game.over then
        self:save()
    end
    -- only the search is given up; the engine itself goes away when the plugin closes (App:close_all)
    self.ai:cancel()
end

return VsAI
