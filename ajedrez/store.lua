-- Everything that is kept between sessions: options, the two ratings, the game in progress, the puzzles seen.
-- Uses KOReader's LuaSettings for the small things and a text file for the (possibly long) list of solved puzzles.
local Rating = require("ajedrez/rating")

local Store = {}
Store.__index = Store

Store.DEFAULTS = {
    piece_set = "cburnett",
    difficulty = "adaptive", -- or "fixed"
    fixed_elo = 1500,
    color = "random",
    time = "none", -- "none" or "base+inc" in minutes, e.g. "5+3"
    flipped = false,
    dark_mode = false,
    clock_refresh = 15, -- seconds between redraws of the clocks
}

Store.CLOCK_REFRESH = { 1, 5, 15, 30, 60 }

Store.TIMES = { "none", "3+2", "10+0", "15+10", "30+0" }

-- settings: a LuaSettings-like object (readSetting/saveSetting/flush). seen_path: file of solved puzzle ids.
function Store.new(settings, seen_path)
    local self = setmetatable({ s = settings, seen_path = seen_path, seen = nil }, Store)
    self.player = Rating.from_table(settings:readSetting("player"), 1300, 450, { drift = 20, placement = 8 })
    self.puzzle = Rating.from_table(settings:readSetting("puzzle"), 1500, 400, { drift = 15, placement = 10 })
    local stats = settings:readSetting("stats") or {}
    self.stats = { wins = stats.wins or 0, draws = stats.draws or 0, losses = stats.losses or 0,
        solved = stats.solved or 0, failed = stats.failed or 0 }
    return self
end

function Store:option(name)
    local v = self.s:readSetting("opt_" .. name)
    if v == nil then
        return Store.DEFAULTS[name]
    end
    return v
end

function Store:set_option(name, value)
    self.s:saveSetting("opt_" .. name, value)
    self.s:flush()
end

function Store:save_ratings()
    self.s:saveSetting("player", self.player:to_table())
    self.s:saveSetting("puzzle", self.puzzle:to_table())
    self.s:saveSetting("stats", self.stats)
    self.s:flush()
end

-- The rating of the AI for the next game.
function Store:ai_elo()
    if self:option("difficulty") == "fixed" then
        return self:option("fixed_elo")
    end
    return self.player:opponent()
end

-- score: 1, 0.5 or 0 for the player. Returns the change in the shown rating.
function Store:record_game(ai_elo, score)
    local delta = self.player:update(ai_elo, score)
    if score == 1 then
        self.stats.wins = self.stats.wins + 1
    elseif score == 0 then
        self.stats.losses = self.stats.losses + 1
    else
        self.stats.draws = self.stats.draws + 1
    end
    self:save_ratings()
    return delta
end

function Store:record_puzzle(puzzle_rating, score)
    local delta = self.puzzle:update(puzzle_rating, score)
    if score >= 1 then
        self.stats.solved = self.stats.solved + 1
    elseif score == 0 then
        self.stats.failed = self.stats.failed + 1
    end
    self:save_ratings()
    return delta
end

-- The game in progress: { moves, fen, human, ai_elo, time = { base, inc, left_w, left_b } } or nil.
function Store:saved_game()
    return self.s:readSetting("saved_game")
end

function Store:save_game(t)
    self.s:saveSetting("saved_game", t)
    self.s:flush()
end

function Store:clear_game()
    self.s:delSetting("saved_game")
    self.s:flush()
end

-- Puzzles already solved or failed, so the same one does not come back soon.
function Store:load_seen()
    if self.seen then
        return self.seen
    end
    self.seen = {}
    local f = self.seen_path and io.open(self.seen_path, "r")
    if f then
        for id in f:lines() do
            self.seen[id] = true
        end
        f:close()
    end
    return self.seen
end

function Store:is_seen(id)
    return self:load_seen()[id] == true
end

function Store:mark_seen(id)
    self:load_seen()[id] = true
    local f = self.seen_path and io.open(self.seen_path, "a")
    if f then
        f:write(id, "\n")
        f:close()
    end
end

-- The puzzle in progress { entry = {id, fen, moves, rating, themes}, n = number } or nil; "puzzle_count" is how many
-- puzzles were finished (solved, failed or skipped), so the number shown is count + 1.
function Store:current_puzzle()
    return self.s:readSetting("puzzle_current")
end

function Store:save_current_puzzle(t)
    self.s:saveSetting("puzzle_current", t)
    self.s:flush()
end

function Store:puzzle_count()
    return tonumber(self.s:readSetting("puzzle_count")) or 0
end

-- The puzzle in progress is over (solved, failed or skipped).
function Store:finish_puzzle()
    self.s:saveSetting("puzzle_count", self:puzzle_count() + 1)
    self.s:delSetting("puzzle_current")
    self.s:flush()
end

function Store:reset()
    for _, key in ipairs({ "player", "puzzle", "stats", "saved_game", "puzzle_current", "puzzle_count" }) do
        self.s:delSetting(key)
    end
    self.s:flush()
    if self.seen_path then
        os.remove(self.seen_path)
    end
    self.seen = {}
    self.player = Rating.new(1300, 450, { drift = 20, placement = 8 })
    self.puzzle = Rating.new(1500, 400, { drift = 15, placement = 10 })
    self.stats = { wins = 0, draws = 0, losses = 0, solved = 0, failed = 0 }
end

return Store
