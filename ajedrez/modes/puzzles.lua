-- Puzzles from the offline Lichess database. The puzzle rating of the player is tracked like a skill (rating.lua)
-- and each new puzzle is drawn close to it, so the puzzles stay at the edge of what the player can solve.
local Chess = require("ajedrez/chess")
local Puzzle = require("ajedrez/puzzle")
local UIManager = require("ui/uimanager")

local PlayScreen = require("ajedrez/ui/play_screen")

local Puzzles = {}
Puzzles.__index = Puzzles

function Puzzles.start(app)
    local self = setmetatable({ app = app, T = app.T, store = app.store, pack = app:puzzle_pack() }, Puzzles)
    self.screen = PlayScreen:new{ app = app, mode = self }
    self.screen.on_closed = function() app:mode_closed(self) end
    -- the one full refresh: it is the refresh of the show itself
    UIManager:show(self.screen, "full")
    self:next_puzzle()
    self.screen:finish_opening()
    return self
end

local function window_for(store)
    -- the more sure we are of the rating, the narrower the window of puzzles
    return math.max(40, math.min(150, math.floor(store.puzzle:sd() * 0.6)))
end

function Puzzles:next_puzzle()
    self.finished, self.recorded, self.selected, self.waiting, self.delta = false, false, nil, false, nil
    if self.pending then
        UIManager:unschedule(self.pending)
        self.pending = nil
    end
    local store = self.store
    local entry
    self.puzzle = nil
    local saved = store:current_puzzle()
    if saved and saved.entry then
        -- the one that was left unfinished comes back
        self.puzzle = Puzzle.new(saved.entry)
        self.number = saved.n
    end
    for _ = 1, self.puzzle and 0 or 6 do
        entry = self.pack:pick_near(store.puzzle:value(), window_for(store), function(id) return store:is_seen(id) end)
        self.puzzle = entry and Puzzle.new(entry)
        if self.puzzle then
            -- the number is the position of the puzzle in the pack
            self.number = entry.pos and self.pack:number_at(entry.pos) or (store:puzzle_count() + 1)
            store:save_current_puzzle({ entry = entry, n = self.number })
            break
        end
    end
    if not self.puzzle then
        self.screen:set_banner(self.T.no_puzzles)
        return
    end
    local p = self.puzzle
    self.screen:clear_banner()
    self.screen:set_note(nil)
    self.screen:show_bar(false)
    self:set_actions()
    self.screen:set_flipped(p.player == "b")
    self.screen:set_label("#" .. self.number)
    self:show(true)
    self:refresh_title()
end

-- position/last: what to show instead of the position of the puzzle (the moment between the move of the player and
-- the answer).
function Puzzles:show(full, position, last)
    local p = self.puzzle
    position = position or p.position
    local check
    if Chess.in_check(position) then
        check = Chess.king_square(position, position.turn)
    end
    self.screen:set_position(position, { last = last or p.last, check = check, full = full })
end

function Puzzles:refresh_title()
    local T = self.T
    self.screen:set_title(string.format("%s · %d", T.puzzles, self.store.puzzle:value()))
end

function Puzzles:record(score)
    if self.recorded then
        return nil
    end
    self.recorded = true
    self.store:mark_seen(self.puzzle.id)
    return self.store:record_puzzle(self.puzzle.rating, score)
end

function Puzzles:on_square(square)
    local p = self.puzzle
    if not p or self.finished or self.waiting then
        return
    end
    local screen = self.screen
    local position = p.position
    local piece = position.board[square]
    local mine = piece and ((piece == piece:upper()) == (p.player == "w"))
    local legal = Chess.legal_moves(position)
    if self.selected then
        local moves = Chess.targets_from(position, self.selected, legal)[square]
        if moves then
            self.selected = nil
            if #moves > 1 then
                return screen:ask_promotion(self.T, p.player, function(letter)
                    for _, move in ipairs(moves) do
                        if move.promotion == letter then
                            return self:play(move)
                        end
                    end
                end, function()
                    screen:clear_selection()
                end)
            end
            return self:play(moves[1])
        end
        if square == self.selected then
            self.selected = nil
            return screen:clear_selection()
        end
    end
    if mine then
        local set = {}
        for target in pairs(Chess.targets_from(position, square, legal)) do
            set[target] = true
        end
        self.selected = square
        screen:select(square, set)
    else
        self.selected = nil
        screen:clear_selection()
    end
end

-- Seconds the answer of the opponent waits, so it does not look instantaneous.
Puzzles.REPLY_DELAY = 0.8

function Puzzles:play(move)
    local p, T = self.puzzle, self.T
    local before = p.position
    local status, reply = p:try(move)
    self.screen:show_bar(false)
    if status == "wrong" then
        self.screen:clear_selection()
        if not self.recorded then
            self.delta = self:record(0)
        end
        -- the puzzle is lost for the rating, but the reader may keep looking for the move (the hint helps)
        self.screen:set_note(T.puzzle_wrong)
        return
    end
    self.screen:clear_banner()
    self.screen:set_note(status ~= "solved" and T.puzzle_right or nil)
    if reply then
        -- first the move of the player alone; the answer comes a moment later
        self.waiting = true
        self:show(false, Chess.play(before, move), { from = move.from, to = move.to })
        self.pending = function()
            self.pending = nil
            self.waiting = false
            if self.closed then
                return
            end
            self:show()
            if status == "solved" then
                self:solved()
            end
        end
        UIManager:scheduleIn(Puzzles.REPLY_DELAY, self.pending)
        return
    end
    self:show()
    if status == "solved" then
        self:solved()
    end
end

-- The end of a puzzle, solved or failed: only the bottom of the screen speaks (the new rating, the score and the
-- button for the next one).
function Puzzles:solved()
    local T = self.T
    self.finished = true
    self.store:finish_puzzle()
    local score = self.puzzle:score()
    local text
    if score == nil then
        -- solved with a hint: no points either way
        if not self.recorded then
            self.recorded = true
            self.store:mark_seen(self.puzzle.id)
        end
        text = string.format(T.puzzle_result, self.store.puzzle:value(), "+", 0)
    else
        local delta = self:record(score) or self.delta or 0
        text = string.format(T.puzzle_result, self.store.puzzle:value(), delta >= 0 and "+" or "-", math.abs(delta))
    end
    self.screen:set_actions(nil)
    self.screen:set_note(nil)
    self.screen:show_bar(false)
    self.screen:set_banner(text, T.puzzle_next, function() self:next_puzzle() end)
    self:refresh_title()
end

function Puzzles:hint()
    local square = self.puzzle and not self.finished and not self.waiting and self.puzzle:hint()
    if square then
        self.screen:set_hint(square)
    end
end

function Puzzles:skip()
    if self.waiting then
        return
    end
    if self.puzzle and not self.recorded then
        self.store:mark_seen(self.puzzle.id)
    end
    if self.puzzle and not self.finished then
        self.store:finish_puzzle()
    end
    self:next_puzzle()
end

-- The buttons at the bottom of the screen.
function Puzzles:set_actions()
    local T = self.T
    self.screen:set_actions({
        { label = T.puzzle_hint, icon = "hint", callback = function() self:hint() end },
        { label = T.puzzle_skip, icon = "skip", callback = function() self:skip() end },
    })
end

function Puzzles:on_settings_changed()
    self.screen:apply_settings()
end

function Puzzles:on_close()
    self.closed = true
    if self.pending then
        UIManager:unschedule(self.pending)
        self.pending = nil
    end
end

return Puzzles
