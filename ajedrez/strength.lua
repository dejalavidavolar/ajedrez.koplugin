-- How strong the AI plays at a given rating: the way Lichess's own computer opponent does it.
--
-- Lichess ("play with the computer") has eight levels, and each one is Stockfish with three settings:
--   * Skill Level: Stockfish's built-in weakening (negative values are allowed in Lichess's build),
--   * a depth limit and a time limit per move.
-- The table below is that configuration, with the rating Lichess shows for each level. Sources (not read from the
-- fishnet code itself, which could not be opened from here, but agreeing with each other):
--   * the table of levels in https://lichess.org/@/MagoGG/blog/stockfish-level-and-its-rating/CvL5k0jL
--   * the same skill/depth/movetime arrays quoted from fishnet in https://talkchess.com/viewtopic.php?p=928225
--   * level 8 = "movetime 1000, skill 20, depth 22" confirmed by a Lichess developer (talkchess p=899498).
--
-- Skill Level in Stockfish works like this (search.cpp, Skill::pick_best): the engine searches the 4 best moves
-- (MultiPV 4) and then does not play the best one: each of them gets a bonus that grows with how much worse it is
-- than the best and with a random number, and the move with the highest result is played. Everything is a function
-- of the skill level, so it is applied here, to the scores the engine reports, exactly as Stockfish does it; this
-- also makes the negative levels of Lichess work with a stock Stockfish 11, whose option stops at 0.
local Strength = {}

-- level, rating shown by Lichess, Skill Level, depth, movetime (ms, on Lichess's servers)
Strength.LEVELS = {
    { 1, 800, -9, 5, 50 },
    { 2, 1100, -5, 5, 100 },
    { 3, 1400, -1, 5, 150 },
    { 4, 1700, 3, 5, 200 },
    { 5, 2000, 7, 5, 300 },
    { 6, 2300, 11, 8, 400 },
    { 7, 2700, 16, 13, 500 },
    { 8, 3000, 20, 22, 1000 },
}

-- Lichess has no level below 800. Down to MIN_ELO the skill keeps falling at the same slope as between levels 1
-- and 2 (this part is an extension of mine, not Lichess's), so a beginner is not given an opponent far too strong.
Strength.MIN_ELO = 400
Strength.MAX_ELO = 3000

Strength.PAWN_MG = 128 -- Stockfish 11: PawnValueMg, the most the random term of the skill can be
Strength.PAWN_EG = 213 -- PawnValueEg: centipawns of UCI = internal value * 100 / 213
Strength.VALUE_MATE = 32000
Strength.MULTIPV = 4

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Settings for a rating: { elo, level (1..8, fractional between two), skill, depth, movetime }.
-- At the exact ratings of the table it is Lichess's level; in between the settings are interpolated.
function Strength.for_elo(elo)
    local L = Strength.LEVELS
    elo = math.max(Strength.MIN_ELO, math.min(Strength.MAX_ELO, elo))
    if elo <= L[1][2] then
        local slope = (L[2][3] - L[1][3]) / (L[2][2] - L[1][2])
        return { elo = elo, level = 1, skill = L[1][3] + (elo - L[1][2]) * slope, depth = L[1][4], movetime = L[1][5] }
    end
    for i = 1, #L - 1 do
        local lo, hi = L[i], L[i + 1]
        if elo <= hi[2] then
            local t = (elo - lo[2]) / (hi[2] - lo[2])
            return {
                elo = elo,
                level = lerp(lo[1], hi[1], t),
                skill = lerp(lo[3], hi[3], t),
                depth = math.floor(lerp(lo[4], hi[4], t) + 0.5),
                movetime = math.floor(lerp(lo[5], hi[5], t) + 0.5),
            }
        end
    end
end

-- Whether the settings weaken the engine at all (Lichess level 8 is the engine at full strength).
function Strength.weakened(params)
    return params.skill < 20
end

-- Candidate moves the engine has to give so the skill can choose among them.
function Strength.candidates_wanted(params)
    return Strength.weakened(params) and Strength.MULTIPV or 1
end

-- A score of the engine (centipawns, or mate in n moves) in Stockfish's internal units.
function Strength.internal(cp, mate)
    if mate then
        local plies = math.max(1, 2 * math.abs(mate) - (mate > 0 and 1 or 0))
        local v = Strength.VALUE_MATE - plies
        return mate > 0 and v or -v
    end
    return math.floor((cp or 0) * Strength.PAWN_EG / 100)
end

-- The depth at which Stockfish takes its decision, if its search gets that far (Skill::time_to_pick: depth ==
-- 1 + level); otherwise it decides with the last scores it has.
function Strength.pick_depth(params)
    if params.skill < 0 then
        return nil
    end
    return 1 + math.floor(params.skill)
end

-- candidates: { { move = "e2e4", score = internal value }, ... }, best first. random(): number in [0, 1).
-- Returns the move chosen and how many internal units it gives up against the best one (Skill::pick_best).
function Strength.pick(candidates, params, random)
    random = random or math.random
    local n = math.min(#candidates, Strength.MULTIPV)
    if n == 0 then
        return nil, 0
    end
    if not Strength.weakened(params) or n == 1 then
        return candidates[1].move, 0
    end
    local top = candidates[1].score
    local delta = math.min(top - candidates[n].score, Strength.PAWN_MG)
    local weakness = 120 - 2 * params.skill
    local best_score, best = -math.huge, candidates[1]
    for i = 1, n do
        local c = candidates[i]
        local push = math.floor((weakness * (top - c.score) + delta * math.floor(random() * weakness)) / 128)
        if c.score + push >= best_score then
            best_score, best = c.score + push, c
        end
    end
    return best.move, top - best.score
end

return Strength
