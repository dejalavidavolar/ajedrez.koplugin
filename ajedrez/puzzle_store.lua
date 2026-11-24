-- The puzzle database, read straight from a text file, so a pack of millions of puzzles costs no memory.
--
-- The file has one line per puzzle, sorted by rating:   id|FEN|moves|rating[|themes]
-- (the FEN is the position before the opponent's move; the first move is the opponent's, the rest is the solution,
-- exactly as in the Lichess puzzle database). The first line is a header "#caissa-puzzles v1 count=N". To find
-- puzzles near a rating it does a binary search on byte offsets, so nothing is indexed or loaded.
local Store = {}
Store.__index = Store

local function line_at(f, pos, min)
    if pos > min then
        f:seek("set", pos - 1)
        local c = f:read(1)
        if c ~= "\n" then
            f:read("*l") -- the rest of a line that began before pos
        end
    else
        f:seek("set", min)
    end
    local start = f:seek("cur")
    local line = f:read("*l")
    return start, line
end

local function parse(line)
    local id, fen, moves, rating, themes = tostring(line):match("^([^|]+)|([^|]+)|([^|]+)|(%d+)|?(.*)$")
    if not id then
        return nil
    end
    return { id = id, fen = fen, moves = moves, rating = tonumber(rating), themes = (themes and themes ~= "") and themes or nil }
end

-- Opens a pack; nil when the file is missing or is not a pack.
function Store.open(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local header = f:read("*l")
    local count = header and header:match("^#caissa%-puzzles v1 count=(%d+)")
    if not count then
        f:close()
        return nil
    end
    local min = f:seek("cur")
    local size = f:seek("end")
    return setmetatable({ f = f, path = path, count = tonumber(count), min = min, size = size }, Store)
end

function Store:close()
    if self.f then
        self.f:close()
        self.f = nil
    end
end

-- Byte offset of the first puzzle whose rating is >= target (size when there is none).
function Store:first_at(target)
    local f = self.f
    local lo, hi, first = self.min, self.size, self.size
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local start, line = line_at(f, mid, self.min)
        local p = line and parse(line)
        if not line or start >= hi then
            hi = mid
        elseif not p then
            lo = start + #line + 1
        elseif p.rating >= target then
            first = start
            hi = mid
        else
            lo = start + #line + 1
        end
    end
    return first
end

-- Position of the puzzle that starts at byte offset pos in the file (1 for the first one): the lines before it + 1.
function Store:number_at(pos)
    local f, n, at = self.f, 1, self.min
    f:seek("set", at)
    while at < pos do
        local chunk = f:read(math.min(65536, pos - at))
        if not chunk then
            break
        end
        at = at + #chunk
        for _ in chunk:gmatch("\n") do
            n = n + 1
        end
    end
    return n
end

-- A random puzzle with a rating between low and high, avoiding the ones where skip(id) is true.
-- random(n) gives an integer in 1..n. Returns a puzzle table, or nil when the range is empty.
function Store:pick(low, high, skip, random)
    random = random or math.random
    local a = self:first_at(low)
    local b = self:first_at(high + 1)
    if b <= a then
        return nil
    end
    local fallback
    for _ = 1, 40 do
        local pos = a + random(b - a) - 1
        local start, line = line_at(self.f, pos, self.min)
        if not line or start >= b then
            start, line = line_at(self.f, a, self.min)
        end
        local p = line and parse(line)
        if p then
            p.pos = start
        end
        if p and p.rating >= low and p.rating <= high then
            fallback = fallback or p
            if not (skip and skip(p.id)) then
                return p
            end
        end
    end
    return fallback
end

-- Closest puzzle to a rating that is not skipped: widens the window until it finds one.
function Store:pick_near(rating, window, skip, random)
    window = window or 60
    for _ = 1, 8 do
        local p = self:pick(rating - window, rating + window, skip, random)
        if p then
            return p
        end
        window = window * 2
    end
    return nil
end

Store.parse = parse

return Store
