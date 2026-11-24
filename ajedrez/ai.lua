-- The opponent: Stockfish set up as Lichess sets up its computer levels (see strength.lua): a depth, a time and
-- a Skill Level that picks among the engine's best moves. Everything is asynchronous: request() returns at once and calls back later,
-- so the screen is never blocked while the engine thinks.
local Chess = require("ajedrez/chess")
local Strength = require("ajedrez/strength")
local Uci = require("ajedrez/uci")

local AI = {}
AI.__index = AI

-- Longest a single move may take, in milliseconds, whatever the rating asks for.
AI.MAX_MOVE_MS = 8000
-- Lichess's time per move is for its servers (about a million nodes per second per core). A reader is slower, so
-- the time is stretched by the ratio, as far as MAX_STRETCH, to let the search reach the same depth. The speed is
-- measured from the engine's own reports; until the first measure, a slow reader is assumed.
AI.SERVER_NPS = 1000000
AI.ASSUMED_NPS = 200000
AI.MAX_STRETCH = 6
AI.POLL_SECONDS = 0.12

-- opts: plugin_dir, data_dir, tmp_dir, schedule(seconds, fn) -> handle, unschedule(handle), random()
function AI.new(opts)
    local self = setmetatable({}, AI)
    self.opts = opts
    self.schedule = opts.schedule
    self.unschedule = opts.unschedule
    self.random = opts.random or math.random
    self.binary = Uci.find(opts.plugin_dir, opts.data_dir)
    return self
end

function AI:engine_name()
    if self.engine and self.engine.name then
        return self.engine.name
    end
    return self.binary and self.binary:match("[^/]*$") or nil
end

-- Whether there is an engine file to run at all.
function AI:has_engine()
    return self.binary ~= nil
end

local function legal_list(position)
    local list = {}
    for _, move in ipairs(Chess.legal_moves(position)) do
        list[#list + 1] = Chess.move_to_uci(move)
    end
    return list
end

-- fen/moves: the game so far. elo: strength wanted. limits_ms: time the clock can spare, or nil.
-- done(uci, info): called once, with nil if there is no legal move. info = { elo, nodes, lost, engine }.
function AI:request(fen, moves, elo, limits_ms, done)
    self:cancel()
    local position, err = Chess.from_moves(fen, moves)
    if not position then
        return done(nil, { error = err })
    end
    local legal = legal_list(position)
    if #legal == 0 then
        return done(nil, {})
    end
    local params = Strength.for_elo(elo)
    local function finish(uci, extra)
        extra = extra or {}
        extra.elo, extra.level = elo, params.level
        -- never trust the engine blindly: the move must be legal
        if extra.error then
            return done(nil, extra)
        end
        local ok = false
        for _, l in ipairs(legal) do
            if l == uci then
                ok = true
            end
        end
        if not ok then
            uci = legal[self.random(#legal)]
            extra.replaced = true
        end
        done(uci, extra)
    end
    if #legal == 1 then
        return finish(legal[1], { forced = true })
    end
    if not self:has_engine() then
        return done(nil, { error = "no engine file found (bin/stockfish-armhf)" })
    end
    return self:search_engine(fen, moves, params, limits_ms, legal, finish, 1)
end

-- Starts the process if it is not running. attempt 2 runs a copy placed in the temporary folder.
function AI:ensure_engine(attempt)
    if self.engine and self.engine.pipe and not self.engine.ended then
        return true
    end
    if self.engine then
        self.engine:stop()
        self.engine = nil
    end
    local binary = self.binary
    if attempt >= 2 then
        binary = self.copy or Uci.copy_to(self.binary, self.opts.tmp_dir)
        self.copy = binary
        if not binary then
            return false
        end
    end
    self.engine = Uci.start(binary, self.opts.tmp_dir)
    return self.engine ~= nil
end

-- The engine must answer: if it does not start or dies, it is started again (the second time from a copy in the
-- temporary folder, which covers a folder that forbids running programs) and only then is the error reported,
-- with what the system said. There is no weaker engine to fall back on: the AI is Stockfish or nothing.
function AI:search_engine(fen, moves, params, limits_ms, legal, finish, attempt)
    local nps = (self.engine and self.engine.nps) or self.nps or AI.ASSUMED_NPS
    local stretch = math.max(1, math.min(AI.MAX_STRETCH, AI.SERVER_NPS / nps))
    local movetime = math.min(AI.MAX_MOVE_MS, math.floor(params.movetime * stretch))
    if limits_ms then
        movetime = math.max(150, math.min(movetime, limits_ms))
    end
    local function fail()
        local why = self.engine and self.engine:diagnostics() or ""
        if self.engine then
            self.engine:stop()
            self.engine = nil
        end
        if attempt < 2 then
            return self:search_engine(fen, moves, params, limits_ms, legal, finish, attempt + 1)
        end
        self.handle = nil
        finish(nil, { error = why ~= "" and why or "the engine does not start or ends at once" })
    end
    if not self:ensure_engine(attempt) then
        return fail()
    end
    local engine = self.engine
    engine:search(fen, moves, { depth = params.depth, movetime = movetime, multipv = Strength.candidates_wanted(params) })
    local started = os.time()
    local function poll()
        self.handle = nil
        local result = engine:poll()
        if result and not result.best and next(result.lines) == nil then
            return fail()
        end
        if result then
            if engine.nps then
                self.nps = engine.nps
            end
            local move, lost = self:choose(result, params, #legal)
            return finish(move or result.best, { lost = lost, engine = engine.name })
        end
        -- died, or silent for far longer than any search takes
        if engine.ended or os.time() - started > (movetime / 1000) * 3 + 10 then
            return fail()
        end
        self.handle = self.schedule(AI.POLL_SECONDS, poll)
    end
    self.handle = self.schedule(AI.POLL_SECONDS, poll)
end

-- The move Stockfish's skill picks from what the search reported. If the search reached the depth at which
-- Stockfish decides, it decides there; otherwise with the last scores of each candidate.
function AI:choose(result, params, legal_count)
    local wanted = math.min(Strength.candidates_wanted(params), legal_count)
    local lines = result.lines
    local at = Strength.pick_depth(params)
    local h = at and result.hist and result.hist[at]
    if h then
        local complete = true
        for k = 1, wanted do
            complete = complete and h[k] ~= nil
        end
        if complete then
            lines = h
        end
    end
    local candidates = {}
    for k = 1, wanted do
        local line = lines[k]
        if line then
            candidates[#candidates + 1] = { move = line.move, score = Strength.internal(line.cp, line.mate) }
        end
    end
    -- the engine sorts them already; sorting again keeps the order stable when scores tie
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.move < b.move
    end)
    if #candidates == 0 then
        return result.best, 0
    end
    return Strength.pick(candidates, params, self.random)
end

-- Gives up the search under way, if any; its answer will never arrive.
function AI:cancel()
    if self.handle then
        self.unschedule(self.handle)
        self.handle = nil
    end
    if self.engine then
        self.engine:cancel()
    end
end

-- Ends the engine process. Called whenever the game screen closes.
function AI:stop()
    self:cancel()
    if self.engine then
        self.engine:stop()
        self.engine = nil
    end
end

return AI
