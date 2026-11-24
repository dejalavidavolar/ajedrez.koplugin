-- Diagonal hatching to shade what is behind a window, so the eye goes to the window. It is the same idea as the
-- "background hatching" of zenOS (thin diagonal lines every few pixels), written here because that module is not
-- part of KOReader.
--
-- Drawing thousands of pixels one by one would be slow, so a small tile with the lines (and transparent between
-- them) is made once and then blitted over the area.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")

local Hatching = {}

local tile, tile_size

-- Same period as zenOS: twice the size of 2 points on this screen, so it looks alike on any density.
local function period()
    return 2 * math.ceil(math.max(1, Device.screen:scaleBySize(2)))
end

local function build()
    local p = period()
    local size = p * 16 -- a whole number of periods, so tiles meet without a seam
    local t = Blitbuffer.new(size, size, Blitbuffer.TYPE_BBRGB32)
    local line = Blitbuffer.ColorRGB32(0, 0, 0, 0xFF)
    local thick = math.max(1, math.floor(p / 4 + 0.5))
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            if (x + y) % p < thick then
                t:setPixel(x, y, line)
            end
        end
    end
    return t, size
end

-- Hatches the rectangle x, y, w, h of bb. The lines are aligned to the screen, so two strips painted at different
-- times line up.
function Hatching.paint(bb, x, y, w, h)
    if w <= 0 or h <= 0 then
        return
    end
    local ok = pcall(function()
        if not tile then
            tile, tile_size = build()
        end
        for ty = y - y % tile_size, y + h - 1, tile_size do
            for tx = x - x % tile_size, x + w - 1, tile_size do
                local sx, sy = math.max(x - tx, 0), math.max(y - ty, 0)
                local bw = math.min(tile_size, x + w - tx) - sx
                local bh = math.min(tile_size, y + h - ty) - sy
                bb:alphablitFrom(tile, tx + sx, ty + sy, sx, sy, bw, bh)
            end
        end
    end)
    if not ok then
        -- no tile: plain horizontal lines
        local p = period()
        for yy = y - y % p, y + h - 1, p do
            if yy >= y then
                bb:paintRect(x, yy, w, 1, Blitbuffer.Color8(0x60))
            end
        end
    end
end

function Hatching.free()
    if tile then
        pcall(tile.free, tile)
        tile, tile_size = nil, nil
    end
end

return Hatching
