-- Bayesian skill tracker, used for the player's level against the AI and for the puzzle rating.
--
-- Instead of a single number it keeps a probability distribution over ratings (a grid from 300 to 3100). Every
-- result multiplies the distribution by how likely that result was at each possible rating, so a few games already
-- narrow it down (a win against a strong opponent moves it far, a win against a weak one barely moves it), which
-- is what an adaptive opponent needs. After each game the distribution is blurred a little ("drift") so the
-- estimate keeps following a player who improves or has a bad week, instead of freezing.
--
-- The scale is the usual logistic one (400 points = 10 to 1), the same as Lichess/Glicko.
local Rating = {}
Rating.__index = Rating

local LO, HI, STEP = 300, 3100, 20
local N = (HI - LO) / STEP + 1

Rating.LO, Rating.HI, Rating.STEP, Rating.N = LO, HI, STEP, N

local function rating_at(i)
    return LO + (i - 1) * STEP
end

-- Expected score (0..1) of a player rated r against one rated opp.
function Rating.expected(r, opp)
    return 1 / (1 + 10 ^ ((opp - r) / 400))
end

local function normalize(w)
    local total = 0
    for i = 1, N do
        total = total + w[i]
    end
    if total <= 0 or total ~= total then
        return false
    end
    for i = 1, N do
        w[i] = w[i] / total
    end
    return true
end

local function gaussian(mean, sd)
    local w = {}
    for i = 1, N do
        local z = (rating_at(i) - mean) / sd
        w[i] = math.exp(-0.5 * z * z)
    end
    normalize(w)
    return w
end

-- opts.drift: rating points of random walk per game (default 20, which settles at about +-80 for a regular player)
-- opts.placement: games after which the rating stops being called provisional (default 8)
function Rating.new(mean, sd, opts)
    opts = opts or {}
    return setmetatable({
        w = gaussian(mean or 1300, sd or 450),
        games = 0,
        drift = opts.drift or 20,
        placement = opts.placement or 8,
        prior_mean = mean or 1300,
        prior_sd = sd or 450,
    }, Rating)
end

-- Rebuilds a tracker from what to_table() gave; anything damaged starts over from the prior.
function Rating.from_table(t, mean, sd, opts)
    local self = Rating.new(mean, sd, opts)
    if type(t) == "table" and type(t.w) == "table" and #t.w == N then
        local w, ok = {}, true
        for i = 1, N do
            local v = tonumber(t.w[i])
            if not v or v < 0 or v ~= v then
                ok = false
                break
            end
            w[i] = v
        end
        if ok and normalize(w) then
            self.w = w
            self.games = math.floor(tonumber(t.games) or 0)
        end
    end
    return self
end

function Rating:to_table()
    local w = {}
    for i = 1, N do
        w[i] = tonumber(string.format("%.6g", self.w[i]))
    end
    return { w = w, games = self.games }
end

function Rating:mean()
    local m = 0
    for i = 1, N do
        m = m + rating_at(i) * self.w[i]
    end
    return m
end

function Rating:sd()
    local m = self:mean()
    local v = 0
    for i = 1, N do
        local d = rating_at(i) - m
        v = v + d * d * self.w[i]
    end
    return math.sqrt(v)
end

-- The rating below which p (0..1) of the probability lies.
function Rating:quantile(p)
    local acc = 0
    for i = 1, N do
        acc = acc + self.w[i]
        if acc >= p then
            return rating_at(i)
        end
    end
    return HI
end

function Rating:median()
    return self:quantile(0.5)
end

-- The number to show the player.
function Rating:value()
    return math.floor(self:mean() / 5 + 0.5) * 5
end

-- Still being placed: too few games for the number to mean much.
function Rating:provisional()
    return self.games < self.placement
end

-- score: 1 win, 0.5 draw, 0 loss, for the player against an opponent rated opp.
-- Returns how much the shown rating moved.
function Rating:update(opp, score)
    local before = self:value()
    local w = self.w
    for i = 1, N do
        local e = Rating.expected(rating_at(i), opp)
        -- keeps the likelihood away from exactly 0 so a surprising result can never wipe a rating out
        e = math.min(math.max(e, 1e-4), 1 - 1e-4)
        w[i] = w[i] * (e ^ score) * ((1 - e) ^ (1 - score))
    end
    if not normalize(w) then
        self.w = gaussian(self.prior_mean, self.prior_sd)
        w = self.w
    end
    -- blur: the player may have changed since the last game
    local half = math.ceil(3 * self.drift / STEP)
    local kernel = {}
    for j = -half, half do
        local z = j * STEP / self.drift
        kernel[j] = math.exp(-0.5 * z * z)
    end
    local out = {}
    for i = 1, N do
        local acc, norm = 0, 0
        for j = -half, half do
            local k = i + j
            if k >= 1 and k <= N then
                acc = acc + w[k] * kernel[j]
                norm = norm + kernel[j]
            end
        end
        out[i] = acc / norm
    end
    -- a thin floor of uniform probability keeps the tails alive
    for i = 1, N do
        out[i] = out[i] * 0.995 + 0.005 / N
    end
    normalize(out)
    self.w = out
    self.games = self.games + 1
    return self:value() - before
end

-- The rating of the next opponent, chosen where the result is least predictable: the middle of the distribution.
function Rating:opponent()
    return math.max(400, math.min(2900, math.floor(self:median() / 10 + 0.5) * 10))
end

return Rating
