-- A chess clock that knows nothing about the screen. now() gives seconds (any origin).
local Clock = {}
Clock.__index = Clock

-- base, increment: seconds. now: function returning the current time in seconds.
function Clock.new(base, increment, now)
    return setmetatable({
        left = { w = base, b = base },
        inc = increment or 0,
        now = now or os.time,
        running = nil, -- "w" or "b"
        since = nil,
    }, Clock)
end

-- The time left of a color, counting what the running side has used since the last stop.
function Clock:remaining(color)
    local t = self.left[color]
    if self.running == color and self.since then
        t = t - (self.now() - self.since)
    end
    return math.max(0, t)
end

function Clock:start(color)
    self:stop()
    self.running = color
    self.since = self.now()
end

-- Stops the running side and charges it the time used. Returns that color or nil.
function Clock:stop()
    local color = self.running
    if color then
        self.left[color] = math.max(0, self:remaining(color))
        self.running, self.since = nil, nil
    end
    return color
end

-- The side that just moved stops, gets its increment, and the other side starts.
function Clock:switch(to)
    local from = self:stop()
    if from then
        self.left[from] = self.left[from] + self.inc
    end
    self:start(to)
end

-- The color whose time is over, if any.
function Clock:flagged()
    for _, c in ipairs({ "w", "b" }) do
        if self:remaining(c) <= 0 then
            return c
        end
    end
    return nil
end

function Clock.format(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

return Clock
