-- Run by tests/run_ai.sh once per scenario (the fake engine takes its candidates from the environment).
local H = dofile(arg[0]:match("^(.*)/[^/]*$") .. "/harness.lua")
local AI = require("ajedrez/ai")
local Chess = require("ajedrez/chess")

local scenario = arg[1]
local ai = AI.new{ plugin_dir = H.root, tmp_dir = "/tmp/ajedrez-test", schedule = H.schedule, unschedule = H.unschedule }

local function ask(fen, moves, elo)
    local out
    ai:request(fen, moves, elo, nil, function(uci, info) out = { uci = uci, info = info } end)
    H.run(function() return out ~= nil end, 25)
    return out
end

if scenario == "basics" then
    H.check(ai:has_engine(), "engine found through AJEDREZ_STOCKFISH")
    local first = ask(Chess.START_FEN, "", 1500)
    H.check(first and first.uci and not first.info.book, "the first move comes from the engine, not a book")
    local forced = ask("1R5k/6p1/8/8/8/8/8/7K b - - 0 1", "", 1500)
    H.check(forced and forced.info.forced and forced.uci == "h8h7", "forced move without searching")
    local mate = ask("7k/8/5K2/8/8/8/8/R7 w - - 0 1", "", 1500)
    H.check(mate and mate.uci, "a move in a mate position")
    H.eq(ai.engine and ai.engine.name, "FakeFish 1.0", "engine name is read")
elseif scenario == "strong" then
    local counts = {}
    for _ = 1, 8 do
        local r = ask(Chess.START_FEN, "g1f3 g8f6", 3000)
        H.check(r and r.uci and not r.info.basic, "engine answered")
        counts[r.uci] = (counts[r.uci] or 0) + 1
    end
    H.eq(counts["e2e4"], 8, "full strength always plays the best candidate")
elseif scenario == "weak" then
    local counts = {}
    for _ = 1, 40 do
        local r = ask(Chess.START_FEN, "g1f3 g8f6", 500)
        H.check(r and r.uci, "engine answered")
        counts[r.uci] = (counts[r.uci] or 0) + 1
    end
    local kinds = 0
    for _ in pairs(counts) do kinds = kinds + 1 end
    H.check(kinds >= 3, "weak level varies its choice, got " .. kinds .. " different moves")
    H.check((counts["e2e4"] or 0) < 40, "weak level does not always play the best")
elseif scenario == "mate" then
    -- the fake reports a forced mate with e2e4: a 1500 player takes it
    for _ = 1, 8 do
        local r = ask(Chess.START_FEN, "g1f3 g8f6", 1500)
        H.eq(r and r.uci, "e2e4", "takes the mate")
    end
elseif scenario == "crash" then
    -- Stockfish dies on every search: it is restarted once, then the error is reported. No weaker engine plays.
    local r = ask(Chess.START_FEN, "g1f3 g8f6", 1500)
    H.check(r and r.uci == nil and r.info.error, "reports an error when Stockfish keeps dying")
elseif scenario == "flaky" then
    -- dies the first time only: the restart makes it work
    os.remove("/tmp/ajedrez-flaky-flag")
    local r = ask(Chess.START_FEN, "g1f3 g8f6", 3000)
    H.check(r and r.uci == "e2e4" and not r.info.error, "recovers after one crash")
elseif scenario == "none" then
    H.check(not ai:has_engine(), "no engine in this setup")
    local r = ask(Chess.START_FEN, "g1f3 g8f6", 900)
    H.check(r and r.uci == nil and r.info.error, "error when there is no engine file")
end
ai:stop()
H.done("ai:" .. scenario)
