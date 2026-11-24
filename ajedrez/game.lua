-- A game in progress: the moves, the position, and what the rules say about it. No screen, no engine.
local Chess = require("ajedrez/chess")

local Game = {}
Game.__index = Game

-- opts.fen: starting position (default: the usual one). opts.moves: UCI moves already played.
function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.start_fen = opts.fen or Chess.START_FEN
    self.position = assert(Chess.parse_fen(self.start_fen))
    self.moves = {}
    self.last = nil -- { from, to } squares of the last move
    self.seen = {}
    self.seen[Chess.position_key(self.position)] = 1
    self.over = nil
    for _, uci in ipairs(opts.moves or {}) do
        if not self:play_uci(uci) then
            break
        end
    end
    return self
end

function Game:turn()
    return self.position.turn
end

function Game:legal_moves()
    if not self._legal then
        self._legal = Chess.legal_moves(self.position)
    end
    return self._legal
end

function Game:in_check()
    return Chess.in_check(self.position)
end

-- Plays a legal move given in UCI. Returns the move, or nil when it is not legal.
function Game:play_uci(uci)
    local move = Chess.legal_uci(self.position, uci)
    if not move then
        return nil
    end
    return self:play(move)
end

function Game:play(move)
    local uci = Chess.move_to_uci(move)
    self.san = Chess.to_san(self.position, move)
    self.position = Chess.play(self.position, move)
    self._legal = nil
    self.moves[#self.moves + 1] = uci
    self.last = { from = move.from, to = move.to }
    local key = Chess.position_key(self.position)
    self.seen[key] = (self.seen[key] or 0) + 1
    self.over = self:evaluate(key)
    return move
end

-- nil while the game goes on, or { result = "mate"|"stalemate"|"insufficient"|"fifty"|"repetition", winner = "w"|"b"|nil }.
function Game:evaluate(key)
    local ending = Chess.ending(self.position)
    if ending == "mate" then
        return { result = "mate", winner = self.position.turn == "w" and "b" or "w" }
    elseif ending then
        return { result = ending }
    end
    if (self.seen[key or Chess.position_key(self.position)] or 0) >= 3 then
        return { result = "repetition" }
    end
    return nil
end

function Game:moves_string()
    return table.concat(self.moves, " ")
end

-- A game that ends outside the board: resignation or time.
function Game:finish(result, winner)
    self.over = { result = result, winner = winner }
end

function Game:to_save()
    return { fen = self.start_fen, moves = self:moves_string() }
end

function Game.from_save(t)
    local moves = {}
    for uci in tostring(t and t.moves or ""):gmatch("%S+") do
        moves[#moves + 1] = uci
    end
    local ok, game = pcall(Game.new, { fen = t and t.fen, moves = moves })
    return ok and game or nil
end

return Game
