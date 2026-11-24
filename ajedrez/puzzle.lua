-- One puzzle being solved: follows the Lichess rules. No screen here.
--
-- The first move of the line belongs to the opponent and is played for the player; then the player must find each
-- move of the solution, and the opponent answers. A move other than the expected one is wrong, except that any
-- move giving checkmate is accepted on the last step, as Lichess does.
local Chess = require("ajedrez/chess")

local Puzzle = {}
Puzzle.__index = Puzzle

-- entry: { id, fen, moves = "m1 m2 ...", rating }
function Puzzle.new(entry)
    local line = {}
    for uci in tostring(entry.moves):gmatch("%S+") do
        line[#line + 1] = uci
    end
    if #line < 2 then
        return nil
    end
    local position = Chess.parse_fen(entry.fen)
    if not position then
        return nil
    end
    local self = setmetatable({
        id = entry.id,
        rating = entry.rating,
        line = line,
        start_fen = entry.fen,
        position = position,
        themes = entry.themes, -- Lichess themes, when the pack has them (a pack made from the full database does)
        step = 1, -- next move of the line to be played
        failed = false,
        hinted = false,
        solved = false,
        last = nil,
    }, Puzzle)
    -- the opponent's move that creates the problem
    if not self:apply(line[1]) then
        return nil
    end
    self.step = 2
    self.player = self.position.turn
    return self
end

function Puzzle:apply(uci)
    local move = Chess.legal_uci(self.position, uci)
    if not move then
        return false
    end
    self.last = { from = move.from, to = move.to }
    self.position = Chess.play(self.position, move)
    return true
end

function Puzzle:expected()
    return self.line[self.step]
end

-- The square the player should move from (for a hint).
function Puzzle:hint()
    local uci = self:expected()
    self.hinted = true
    return uci and Chess.square_from_name(uci:sub(1, 2))
end

-- Tries a move of the player. Returns "wrong" (nothing changes), "correct" (the opponent has answered, if there
-- was an answer: the second value is that reply), or "solved".
function Puzzle:try(move)
    local uci = Chess.move_to_uci(move)
    local want = self:expected()
    local after = Chess.play(self.position, move)
    local is_mate = Chess.ending(after) == "mate"
    if uci ~= want and not (is_mate and self.step >= #self.line) then
        self.failed = true
        return "wrong"
    end
    self.last = { from = move.from, to = move.to }
    self.position = after
    self.step = self.step + 1
    if self.step > #self.line or is_mate then
        self.solved = true
        return "solved"
    end
    local reply = self.line[self.step]
    self:apply(reply)
    self.step = self.step + 1
    if self.step > #self.line then
        self.solved = true
        return "solved", reply
    end
    return "correct", reply
end

-- As on Lichess: 1 for a solution without help, 0 when a wrong move was made (the rating goes down), and nil when a
-- hint was used and nothing was failed: no points, the rating does not change.
function Puzzle:score()
    if self.failed or not self.solved then
        return 0
    end
    if self.hinted then
        return nil
    end
    return 1
end

-- Plays out the rest of the line without the player (for "show solution"). Returns the list of moves.
function Puzzle:rest_of_solution()
    local out = {}
    for i = self.step, #self.line do
        out[#out + 1] = self.line[i]
    end
    return out
end

return Puzzle
