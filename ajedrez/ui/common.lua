-- Small helpers shared by the screens.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Common = {}

Common.BLACK = Blitbuffer.COLOR_BLACK
Common.WHITE = Blitbuffer.COLOR_WHITE
Common.GRAY = Blitbuffer.Color8(0x80)
Common.dark = false

-- Dark mode: BLACK is the ink and WHITE the paper everywhere in the plugin, so swapping the two inverts it.
function Common.set_dark(on)
    Common.dark = on and true or false
    Common.BLACK = Common.dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    Common.WHITE = Common.dark and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    Common.GRAY = Blitbuffer.Color8(Common.dark and 0xA0 or 0x80)
end

-- Inverts a rounded rectangle (the windows in dark mode), leaving the corners outside the radius alone.
function Common.invert_rounded(bb, x, y, w, h, radius)
    radius = math.min(radius, math.floor(math.min(w, h) / 2))
    bb:invertRect(x, y + radius, w, h - 2 * radius)
    for row = 0, radius - 1 do
        local dy = radius - row - 0.5
        local inset = math.ceil(radius - math.sqrt(radius * radius - dy * dy))
        bb:invertRect(x + inset, y + row, w - 2 * inset, 1)
        bb:invertRect(x + inset, y + h - row - 1, w - 2 * inset, 1)
    end
end

-- Size in screen pixels from a size meant for a 160 dpi screen.
function Common.px(n)
    return Screen:scaleBySize(n)
end

-- Text drawn straight onto a blitbuffer. align: "left" (default), "center" or "right" inside the width w.
-- Returns the width and height of the text.
function Common.draw_text(bb, text, x, y, w, size, opts)
    opts = opts or {}
    local widget = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", size),
        bold = opts.bold,
        fgcolor = opts.color or Common.BLACK,
        max_width = w,
    }
    local dim = widget:getSize()
    local left = x
    if opts.align == "center" then
        left = x + math.floor((w - dim.w) / 2)
    elseif opts.align == "right" then
        left = x + w - dim.w
    end
    widget:paintTo(bb, left, y)
    widget:free()
    return dim.w, dim.h
end

function Common.text_width(text, size, bold)
    local widget = TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = bold }
    local w = widget:getSize().w
    widget:free()
    return w
end

-- Small icons made of rectangles, in an s x s square: "hint" (the ring that marks the square on the board), "skip",
-- "undo" and "resign" (a flag).
function Common.draw_icon(bb, kind, x, y, s, color)
    local function tri(tx, ty, tw, th, right)
        -- a triangle that points right (or left), made of vertical strips
        for col = 0, tw - 1 do
            local frac = right and (1 - col / tw) or (col / tw)
            local h = math.max(1, math.floor(th * frac + 0.5))
            bb:paintRect(tx + col, ty + math.floor((th - h) / 2), 1, h, color)
        end
    end
    local t = math.max(3, math.floor(s / 7))
    if kind == "hint" then
        local c = math.floor(s / 2)
        bb:paintCircle(x + c, y + c, math.floor(s / 2), color, t)
        bb:paintCircle(x + c, y + c, math.max(2, math.floor(s / 8)), color)
    elseif kind == "skip" then
        local w = math.floor(s / 2)
        tri(x, y + math.floor(s * 0.1), w, math.floor(s * 0.8), true)
        tri(x + w, y + math.floor(s * 0.1), w, math.floor(s * 0.8), true)
    elseif kind == "undo" then
        tri(x, y + math.floor(s * 0.15), math.floor(s * 0.45), math.floor(s * 0.7), false)
        bb:paintRect(x + math.floor(s * 0.4), y + math.floor(s * 0.5) - math.floor(t / 2), math.floor(s * 0.6), t, color)
        bb:paintRect(x + s - t, y + math.floor(s * 0.5) - math.floor(t / 2), t, math.floor(s * 0.35), color)
    else -- resign: a flag
        bb:paintRect(x + math.floor(s * 0.15), y, t, s, color)
        tri(x + math.floor(s * 0.15) + t, y, math.floor(s * 0.7), math.floor(s * 0.55), true)
    end
end

function Common.text_height(size)
    local widget = TextWidget:new{ text = "Ag", face = Font:getFace("cfont", size) }
    local h = widget:getSize().h
    widget:free()
    return h
end

-- A filled rectangle with rounded corners of radius r (in pixels), made of one-pixel strips.
function Common.round_rect(bb, x, y, w, h, r, color)
    r = math.max(0, math.min(r, math.floor(math.min(w, h) / 2)))
    for i = 0, r - 1 do
        local dy = r - i - 0.5
        local inset = math.floor(r - math.sqrt(r * r - dy * dy) + 0.5)
        bb:paintRect(x + inset, y + i, w - 2 * inset, 1, color)
        bb:paintRect(x + inset, y + h - 1 - i, w - 2 * inset, 1, color)
    end
    bb:paintRect(x, y + r, w, h - 2 * r, color)
end

-- A box with a border of the given width and rounded corners.
function Common.round_box(bb, x, y, w, h, r, border, fill, line)
    Common.round_rect(bb, x, y, w, h, r, line or Common.BLACK)
    Common.round_rect(bb, x + border, y + border, w - 2 * border, h - 2 * border, math.max(0, r - border), fill or Common.WHITE)
end

function Common.in_rect(pos, r)
    return r and pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h
end

-- A swipe that starts in the top strip of the screen and goes down.
function Common.is_top_swipe(ges, strip_height)
    return ges and ges.direction == "south" and ges.pos and ges.pos.y < strip_height
end

-- Shows KOReader's own top menu (the file manager's or the reader's) above whatever is on the screen.
function Common.show_koreader_menu(ui)
    local ok = pcall(function()
        if ui and ui.menu and ui.menu.onShowMenu then
            ui.menu:onShowMenu()
        else
            local Event = require("ui/event")
            UIManager:sendEvent(Event:new("ShowMenu"))
        end
    end)
    return ok
end

return Common
