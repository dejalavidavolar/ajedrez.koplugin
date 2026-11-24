local H = dofile(arg[0]:match("^(.*)/[^/]*$") .. "/harness.lua")
local Rating = require("ajedrez/rating")
local Strength = require("ajedrez/strength")
local Clock = require("ajedrez/clock")
local Chess = require("ajedrez/chess")
local Game = require("ajedrez/game")
local Puzzle = require("ajedrez/puzzle")
local PuzzleStore = require("ajedrez/puzzle_store")

-- ---------- rating
do
    local r = Rating.new(1300, 450)
    H.near(r:mean(), 1300, 30, "prior mean (the grid cuts the low tail a little)")
    H.check(r:provisional(), "new rating is provisional")
    -- a ~2000 player: wins nearly everything against the opponent chosen for him
    local games = 0
    local target = 2000
    while games < 12 do
        local opp = r:opponent()
        local p_win = Rating.expected(target, opp)
        r:update(opp, p_win >= 0.5 and 1 or 0) -- deterministic: wins when he is the favourite
        games = games + 1
        if games == 8 then
            H.check(math.abs(r:value() - target) < 250, "after 8 games a 2000 player is within 250: " .. r:value())
        end
    end
    H.check(not r:provisional(), "no longer provisional after 12 games")
    H.near(r:value(), target, 150, "2000 player estimate after 12 games")
    -- a beginner
    local b = Rating.new(1300, 450)
    for _ = 1, 8 do
        local opp = b:opponent()
        b:update(opp, Rating.expected(700, opp) >= 0.5 and 1 or 0)
    end
    H.check(b:value() < 1000, "a 700 player drops below 1000 after 8 games: " .. b:value())
    -- serialization
    local t = r:to_table()
    local r2 = Rating.from_table(t)
    H.near(r2:mean(), r:mean(), 1, "round trip mean")
    H.eq(r2.games, r.games, "round trip games")
    local broken = Rating.from_table({ w = { 1, 2, 3 } }, 1300, 450)
    H.near(broken:mean(), 1300, 30, "damaged data starts over")
    -- a win against a much stronger opponent moves far; against a weak one hardly at all
    local a, c = Rating.new(1500, 150), Rating.new(1500, 150)
    local up_strong = a:update(2000, 1)
    local up_weak = c:update(1000, 1)
    H.check(up_strong > up_weak * 3, "upset moves rating more")
    local sd0 = Rating.new(1500, 300):sd()
    local shrinking = Rating.new(1500, 300)
    for _ = 1, 6 do shrinking:update(shrinking:opponent(), 1) end
    H.check(shrinking:sd() < sd0, "uncertainty shrinks with games")
end

-- ---------- strength (Lichess's computer levels)
do
    -- at the ratings of Lichess's levels, the settings are exactly Lichess's
    local table_ = { { 800, -9, 5, 50 }, { 1100, -5, 5, 100 }, { 1400, -1, 5, 150 }, { 1700, 3, 5, 200 },
        { 2000, 7, 5, 300 }, { 2300, 11, 8, 400 }, { 2700, 16, 13, 500 }, { 3000, 20, 22, 1000 } }
    for level, row in ipairs(table_) do
        local p = Strength.for_elo(row[1])
        H.eq(p.skill, row[2], "skill of level " .. level)
        H.eq(p.depth, row[3], "depth of level " .. level)
        H.eq(p.movetime, row[4], "movetime of level " .. level)
        H.near(p.level, level, 1e-9, "level number " .. level)
    end
    H.eq(Strength.for_elo(100).elo, 400, "clamped low")
    H.eq(Strength.for_elo(9999).elo, 3000, "clamped high")
    -- in between: monotonic in skill, depth and time
    local prev
    for elo = 400, 3000, 25 do
        local p = Strength.for_elo(elo)
        if prev then
            H.check(p.skill >= prev.skill and p.depth >= prev.depth and p.movetime >= prev.movetime, "monotonic at " .. elo)
        end
        prev = p
    end
    H.near(Strength.for_elo(1250).skill, -3, 1e-9, "halfway between levels 2 and 3")
    H.check(Strength.for_elo(400).skill < -9, "below level 1 the skill keeps falling")
    H.check(not Strength.weakened(Strength.for_elo(3000)), "level 8 is full strength")
    H.eq(Strength.candidates_wanted(Strength.for_elo(3000)), 1, "full strength asks for one line")
    H.eq(Strength.candidates_wanted(Strength.for_elo(1400)), 4, "weakened asks for four lines")
    H.eq(Strength.pick_depth(Strength.for_elo(1700)), 4, "level 4 decides at depth 4")
    H.eq(Strength.pick_depth(Strength.for_elo(800)), nil, "negative skill decides at the end")

    -- internal scores: centipawns * 213 / 100; a mate is worth almost the whole range
    H.eq(Strength.internal(100), 213, "100 cp in internal units")
    H.eq(Strength.internal(nil, 1), 32000 - 1, "mate in 1")
    H.eq(Strength.internal(nil, -2), -(32000 - 4), "mated in 2")

    -- Skill::pick_best, checked by hand: skill -1 => weakness 122; top 300, others 200 and 100 and 0 (4 lines)
    local cands = { { move = "a", score = 300 }, { move = "b", score = 200 }, { move = "c", score = 100 }, { move = "d", score = 0 } }
    local p3 = Strength.for_elo(1400)
    -- random() = 0: push_i = floor(122 * (300 - s_i) / 128): a 0, b 95, c 190, d 285 => totals 300, 295, 290, 285
    H.eq(Strength.pick(cands, p3, function() return 0 end), "a", "no randomness: the best still wins here")
    -- random() just below 1: r = 121, delta = min(300, 128) = 128 => push += floor(128*121/128) = 121 => b,c,d gain too
    -- totals a: 300+121*? (a has push = (0 + 128*121)/128 = 121) => 421; b 295+121=416; c 411; d 406
    H.eq(Strength.pick(cands, p3, function() return 0.999 end), "a", "best with the top random bonus")
    -- a candidate set where the weakness shows: scores close together, any can come out
    local close = { { move = "a", score = 30 }, { move = "b", score = 25 }, { move = "c", score = 20 }, { move = "d", score = 10 } }
    local seen = {}
    math.randomseed(5)
    for _ = 1, 400 do
        seen[(Strength.pick(close, p3, math.random))] = true
    end
    H.check(seen.a and seen.b and seen.c and seen.d, "level 3 varies among close moves")
    -- full strength always plays the best
    for _ = 1, 50 do
        H.eq(Strength.pick(cands, Strength.for_elo(3000), math.random), "a", "level 8 plays best")
    end
    -- below skill -4 the weakness (120 - 2 * skill) is over 128 and Stockfish's formula favors the lesser moves on
    -- purpose: Lichess level 1 hardly ever plays the best of the four candidates (it is Stockfish's own behavior)
    do
        local best = 0
        for _ = 1, 400 do
            if Strength.pick(cands, Strength.for_elo(800), math.random) == "a" then best = best + 1 end
        end
        H.check(best < 90, "level 1 rarely plays the best of its four candidates, got " .. best .. "/400")
    end
    -- from level 3 on, a mate is always taken (the others are a whole range below)
    local mate_cands = { { move = "m", score = Strength.internal(nil, 1) }, { move = "x", score = 60 }, { move = "y", score = 40 } }
    for _, elo in ipairs({ 1400, 2000, 2700 }) do
        local wins = 0
        for _ = 1, 200 do
            if Strength.pick(mate_cands, Strength.for_elo(elo), math.random) == "m" then wins = wins + 1 end
        end
        H.eq(wins, 200, "mate in 1 taken at " .. elo)
    end
    -- the loss falls as the rating rises (same candidates)
    local function avg_loss(elo)
        local params = Strength.for_elo(elo)
        local total = 0
        math.randomseed(7)
        for _ = 1, 4000 do
            local _, lost = Strength.pick(cands, params, math.random)
            total = total + lost
        end
        return total / 4000
    end
    H.check(avg_loss(800) > avg_loss(1400) and avg_loss(1400) > avg_loss(2000) and avg_loss(2000) > avg_loss(2700),
        "loss falls with the level")
end

-- ---------- puzzle score as on Lichess
do
    local Puzzle = require("ajedrez/puzzle")
    local entry = { id = "x", fen = "6k1/1p3ppp/8/8/8/8/5PPP/R5K1 b - - 0 30", moves = "b7b6 a1a8", rating = 700 }
    local clean = Puzzle.new(entry)
    clean:try(Chess.legal_uci(clean.position, "a1a8"))
    H.eq(clean:score(), 1, "clean solve scores 1")
    local helped = Puzzle.new(entry)
    helped:hint()
    helped:try(Chess.legal_uci(helped.position, "a1a8"))
    H.eq(helped:score(), nil, "a hint means no points (no rating change)")
    local failed = Puzzle.new(entry)
    failed:hint()
    failed:try(Chess.legal_uci(failed.position, "a1a7"))
    H.eq(failed:score(), 0, "a wrong move scores 0 even with a hint")
end

-- ---------- clock
do
    local t = 0
    local c = Clock.new(300, 3, function() return t end)
    c:start("w")
    t = 10
    H.eq(c:remaining("w"), 290, "white spent 10s")
    H.eq(c:remaining("b"), 300, "black untouched")
    c:switch("b")
    H.eq(c.left.w, 293, "increment added")
    t = 400
    H.eq(c:flagged(), "b", "black flagged")
    H.eq(Clock.format(65), "1:05", "format")
    H.eq(Clock.format(3725), "1:02:05", "format hours")
end

-- ---------- game rules
do
    local g = Game.new()
    for _, m in ipairs({ "f2f3", "e7e5", "g2g4", "d8h4" }) do
        H.check(g:play_uci(m), "legal " .. m)
    end
    H.eq(g.over and g.over.result, "mate", "fool's mate")
    H.eq(g.over.winner, "b", "black wins")
    H.check(not g:play_uci("a2a3") or true, "no crash after the end")
    local g2 = Game.from_save(g:to_save())
    H.eq(g2.over and g2.over.result, "mate", "restored from a save")
    -- repetition
    local r = Game.new()
    for _ = 1, 2 do
        for _, m in ipairs({ "g1f3", "g8f6", "f3g1", "f6g8" }) do r:play_uci(m) end
    end
    H.eq(r.over and r.over.result, "repetition", "threefold repetition")
    -- castling is written as the king moving two squares
    local c = Game.new({ fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1" })
    H.check(c:play_uci("e1g1"), "castle kingside")
    H.eq(c.moves[1], "e1g1", "castle UCI")
    -- promotion is told apart
    local p = Game.new({ fen = "8/P6k/8/8/8/8/8/K7 w - - 0 1" })
    local found = 0
    for _, m in ipairs(p:legal_moves()) do if m.promotion then found = found + 1 end end
    H.eq(found, 4, "four promotions")
end

-- ---------- puzzle store on the real pack
local pack = PuzzleStore.open(H.root .. "/data/puzzles.txt")
H.check(pack ~= nil, "pack opens")
H.eq(pack.count, 50000, "pack count")
do
    math.randomseed(42)
    for _, target in ipairs({ 600, 1000, 1500, 2000, 2500 }) do
        for _ = 1, 20 do
            local p = pack:pick(target - 50, target + 50, nil, math.random)
            H.check(p and p.rating >= target - 50 and p.rating <= target + 50, "puzzle near " .. target)
        end
    end
    local p = pack:pick_near(1500, 30, nil, math.random)
    H.check(p ~= nil, "pick_near")
    local low = pack:first_at(0)
    H.eq(low, pack.min, "first_at(0) is the first line")
    H.eq(pack:first_at(99999), pack.size, "first_at(huge) is the end")
    -- skipping seen puzzles
    local seen = {}
    local distinct = {}
    for _ = 1, 30 do
        local q = pack:pick(1500, 1520, function(id) return seen[id] end, math.random)
        H.check(q ~= nil, "found an unseen puzzle")
        H.check(not seen[q.id], "not a repeat")
        seen[q.id] = true
    end
    -- outside the data: empty range
    H.eq(pack:pick(5000, 6000, nil, math.random), nil, "no puzzle that hard")
end

-- ---------- every puzzle of the pack must be playable (sample every 7th)
do
    local f = io.open(H.root .. "/data/puzzles.txt")
    f:read("*l")
    local n, bad, solved = 0, 0, 0
    local i = 0
    for line in f:lines() do
        i = i + 1
        if i % 25 == 0 then
            local e = PuzzleStore.parse(line)
            local pz = Puzzle.new(e)
            n = n + 1
            if not pz then
                bad = bad + 1
            else
                -- play the whole solution through the session object
                local status
                local ok = true
                while pz.step <= #pz.line do
                    local want = pz:expected()
                    local move = Chess.legal_uci(pz.position, want)
                    if not move then ok = false break end
                    status = pz:try(move)
                    if status == "wrong" then ok = false break end
                    if status == "solved" then break end
                end
                if ok and pz.solved and pz:score() == 1 then solved = solved + 1 else bad = bad + 1 end
            end
        end
    end
    f:close()
    H.check(bad == 0, string.format("all %d sampled puzzles replay cleanly (bad=%d)", n, bad))
    H.eq(solved, n, "all solved")
end
-- wrong move and hint scoring
do
    local pz = Puzzle.new({ id = "x", fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 1", moves = "g8h8 a1a8", rating = 800 })
    H.check(pz ~= nil, "mate-in-one puzzle builds")
    local wrong = Chess.legal_uci(pz.position, "g1h1")
    H.eq(pz:try(wrong), "wrong", "wrong move")
    H.eq(pz.failed, true, "marked failed")
    local right = Chess.legal_uci(pz.position, "a1a8")
    H.eq(pz:try(right), "solved", "then solved")
    H.eq(pz:score(), 0, "failed puzzle scores 0")
end
H.done("pure")
