-- Draws the board and finds which square a tap hit. It is not a widget: the screen owns it and calls paint().
-- Squares are numbered 1 (a1) to 64 (h8), as in chess.lua.
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Common = require("ajedrez/ui/common")

local BoardView = {}
BoardView.__index = BoardView

local BLACK = Blitbuffer.COLOR_BLACK
local MID = Blitbuffer.Color8(0x55)
local COORD = Blitbuffer.Color8(0x33)

-- the components of the colors made here, to draw circles of those colors
local raw = {}

local function rgb(r, g, b)
    local color = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    raw[color] = { r, g, b }
    return color
end

-- Colors as Lichess draws them (the highlights are the translucent greens and yellows blended into each square), but
-- a bit stronger: on a color e-ink screen (Kaleido) pale colors almost vanish. last_*: squares of the last move,
-- last_edge: the frame drawn inside them; hint_*: square of a hint, ring: the circle of the hint; dot: move marks.
-- "bw" is the plain gray board for screens without color; there highlights are frames instead of fills.
BoardView.THEMES = {
    lichess = { light = rgb(240, 217, 181), dark = rgb(181, 136, 99),
        last_light = rgb(244, 232, 70), last_dark = rgb(212, 186, 38), last_edge = rgb(120, 100, 0),
        sel_light = rgb(130, 151, 105), sel_dark = rgb(100, 111, 64),
        hint_light = rgb(168, 200, 245), hint_dark = rgb(98, 140, 205), ring = rgb(0, 60, 185),
        check = rgb(235, 80, 60), dot = rgb(14, 98, 34) },
    green = { light = rgb(238, 238, 210), dark = rgb(118, 150, 86),
        last_light = rgb(250, 240, 70), last_dark = rgb(205, 205, 40), last_edge = rgb(110, 105, 0),
        sel_light = rgb(160, 200, 110), sel_dark = rgb(90, 140, 50),
        hint_light = rgb(168, 200, 245), hint_dark = rgb(98, 140, 205), ring = rgb(0, 60, 185),
        check = rgb(235, 80, 60), dot = rgb(14, 98, 34) },
    blue = { light = rgb(222, 227, 230), dark = rgb(140, 162, 173),
        last_light = rgb(190, 228, 100), last_dark = rgb(120, 190, 80), last_edge = rgb(30, 100, 20),
        sel_light = rgb(150, 190, 215), sel_dark = rgb(90, 140, 175),
        hint_light = rgb(250, 205, 150), hint_dark = rgb(225, 150, 90), ring = rgb(190, 60, 0),
        check = rgb(235, 80, 60), dot = rgb(20, 70, 120) },
    bw = { light = Blitbuffer.COLOR_WHITE, dark = Blitbuffer.Color8(0xAA), plain = true,
        check = BLACK, dot = BLACK, ring = BLACK },
}
BoardView.THEME_NAMES = { "lichess", "green", "blue", "bw" }

-- Circles (move marks, hint) are pictures with smooth edges made once per size: Blitbuffer:paintCircle has no smoothing
-- and its edge looks like steps on a big e-ink screen.
local disc_cache = {}

local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end

-- layers: from the bottom up, { ro = outer radius, ri = inner radius or nil, color = {r,g,b}, alpha = 0..1 }.
local function build_disc(d, layers)
    -- a new picture is transparent; only the box that holds the biggest layer is worked out
    local img = Blitbuffer.new(d, d, Blitbuffer.TYPE_BBRGB32)
    local c = d / 2
    local reach = 0
    for _, layer in ipairs(layers) do
        reach = math.max(reach, layer.ro)
    end
    local lo = math.max(0, math.floor(c - reach - 1))
    local hi = math.min(d - 1, math.ceil(c + reach + 1))
    for y = lo, hi do
        for x = lo, hi do
            local dist = math.sqrt((x + 0.5 - c) ^ 2 + (y + 0.5 - c) ^ 2)
            local r, g, b, a = 0, 0, 0, 0
            for _, layer in ipairs(layers) do
                local cover = clamp01(layer.ro - dist + 0.5)
                if layer.ri then
                    cover = cover * clamp01(dist - layer.ri + 0.5)
                end
                local la = cover * (layer.alpha or 1)
                if la > 0 then
                    local out = la + a * (1 - la)
                    r = (layer.color[1] * la + r * a * (1 - la)) / out
                    g = (layer.color[2] * la + g * a * (1 - la)) / out
                    b = (layer.color[3] * la + b * a * (1 - la)) / out
                    a = out
                end
            end
            img:setPixel(x, y, Blitbuffer.ColorRGB32(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), math.floor(a * 255 + 0.5)))
        end
    end
    return img
end

local function color_parts(color)
    return raw[color] or { 0, 0, 0 }
end

-- kind: "dot" (move to an empty square), "capture" (ring around a piece that can be taken), "hint" (ring).
local function disc(kind, size, theme)
    local key = kind .. "@" .. size .. "@" .. tostring(theme)
    if disc_cache[key] then
        return disc_cache[key]
    end
    local t = BoardView.THEMES[theme] or BoardView.THEMES.lichess
    local white = { 255, 255, 255 }
    local halo = math.max(1.5, size / 40)
    local img
    if kind == "dot" then
        local r = size * 0.17
        img = build_disc(size, {
            { ro = r + halo, color = white, alpha = 0.7 },
            { ro = r, color = color_parts(t.dot) },
        })
    elseif kind == "capture" then
        local ro = size * 0.47
        local width = math.max(3.5, size / 11)
        img = build_disc(size, {
            { ro = ro + halo, ri = ro - width - halo, color = white, alpha = 0.7 },
            { ro = ro, ri = ro - width, color = color_parts(t.dot) },
        })
    else
        local ro = size * 0.46
        local width = math.max(4.5, size / 9)
        img = build_disc(size, {
            { ro = ro + halo, ri = ro - width - halo, color = white, alpha = 0.85 },
            { ro = ro, ri = ro - width, color = color_parts(t.ring) },
        })
    end
    disc_cache[key] = img
    return img
end

-- The pictures of a set at a size never change, and drawing them is the slow part, so they are kept.
local art_cache = {}

local function load_art(plugin_dir, set, size)
    local key = set .. "@" .. size
    if art_cache[key] then
        return art_cache[key]
    end
    local RenderImage = require("ui/renderimage")
    local art = {}
    for _, color in ipairs({ "w", "b" }) do
        for _, kind in ipairs({ "P", "N", "B", "R", "Q", "K" }) do
            local path = string.format("%s/pieces/%s/%s%s.svg", plugin_dir, set, color, kind)
            local ok, image = pcall(RenderImage.renderSVGImageFile, RenderImage, path, size, size)
            if ok and image then
                art[(color == "w") and kind or kind:lower()] = image
            end
        end
    end
    art_cache[key] = art
    return art
end

-- Makes the pictures of the circles before they are needed, so the first tap on a piece does not wait for them.
function BoardView:warm()
    for _, kind in ipairs({ "dot", "capture", "hint" }) do
        disc(kind, self.size, self.theme_name)
    end
end

-- The pictures of the pieces of a set at a size (for the window that offers the pieces to promote to).
function BoardView.art(plugin_dir, set, size)
    return load_art(plugin_dir, set, size)
end

-- Frees the pictures of every piece set but `keep` (the whole cache when nil). The pictures are kept between games
-- on purpose: drawing the vector files is the slow part of opening a game.
function BoardView.release(keep)
    for key, art in pairs(art_cache) do
        if not (keep and key:sub(1, #keep + 1) == keep .. "@") then
            for _, image in pairs(art) do
                pcall(image.free, image)
            end
            art_cache[key] = nil
        end
    end
    if not keep then
        for key, image in pairs(disc_cache) do
            pcall(image.free, image)
            disc_cache[key] = nil
        end
    end
end

-- Filled rectangle. KOReader's own code paints colors with paintRectRGB32 and gray values with paintRect
-- (see ReaderView, which branches on Blitbuffer.isColor8): paintRect takes a gray value, so a color given to it
-- comes out gray. That was why the board stayed black and white.
local function fill(bb, x, y, w, h, color, plain)
    if not plain and bb.paintRectRGB32 then
        bb:paintRectRGB32(x, y, w, h, color)
    else
        bb:paintRect(x, y, w, h, color)
    end
end

-- opts: x, y, side (pixels, multiple of 8), flipped, piece_set, plugin_dir
function BoardView.new(opts)
    local self = setmetatable({}, BoardView)
    self.x, self.y = opts.x, opts.y
    self.size = math.floor(opts.side / 8)
    self.side = self.size * 8
    self.flipped = opts.flipped or false
    self.piece_set = opts.piece_set or "cburnett"
    self.plugin_dir = opts.plugin_dir
    self.theme_name = BoardView.THEMES[opts.theme] and opts.theme or "lichess"
    self.theme = BoardView.THEMES[self.theme_name]
    self.gutter = opts.gutter or 0 -- room around the board for the coordinates
    return self
end

function BoardView:rect()
    return Geom:new{ x = self.x, y = self.y, w = self.side, h = self.side }
end

local function file_rank(square)
    return (square - 1) % 8 + 1, math.floor((square - 1) / 8) + 1
end

-- The board and its coordinates around it.
function BoardView:frame_rect()
    local g = self.gutter
    return Geom:new{ x = self.x - g, y = self.y - g, w = self.side + 2 * g, h = self.side + 2 * g }
end

-- Top-left pixel of a square.
function BoardView:square_origin(square)
    local file, rank = file_rank(square)
    local col = self.flipped and 9 - file or file
    local row = self.flipped and rank or 9 - rank
    return self.x + (col - 1) * self.size, self.y + (row - 1) * self.size
end

function BoardView:square_rect(square)
    local x, y = self:square_origin(square)
    return Geom:new{ x = x, y = y, w = self.size, h = self.size }
end

-- The square under a pixel, or nil.
function BoardView:square_at(px, py)
    if px < self.x or py < self.y or px >= self.x + self.side or py >= self.y + self.side then
        return nil
    end
    local col = math.floor((px - self.x) / self.size) + 1
    local row = math.floor((py - self.y) / self.size) + 1
    local file = self.flipped and 9 - col or col
    local rank = self.flipped and row or 9 - row
    return (rank - 1) * 8 + file
end

-- The smallest rectangle holding all the squares of a list.
function BoardView:union_rect(squares)
    local rect
    for _, square in ipairs(squares) do
        local r = self:square_rect(square)
        rect = rect and rect:combine(r) or r
    end
    return rect
end

-- A black frame with the coordinates in white: files (a-h) above and below, ranks (1-8) left and right, so the
-- board stays centered. Drawn before the squares, which cover its middle.
function BoardView:paint_frame(bb)
    local g = self.gutter
    local x, y, w = self.x - g, self.y - g, self.side + 2 * g
    -- rounded corners (8 pixels)
    Common.round_rect(bb, x, y, w, w, 8, Common.BLACK)
    self:paint_coordinates(bb)
    if Common.dark then
        -- dark mode only: a line between the margin of the coordinates and the squares (Common.WHITE is black here)
        bb:paintBorder(self.x - 3, self.y - 3, self.side + 6, self.side + 6, 3, Common.WHITE)
    end
end

function BoardView:paint_coordinates(bb)
    local g, size = self.gutter, self.size
    local text_h = Common.text_height(15)
    local files, ranks = "abcdefgh", "12345678"
    for col = 1, 8 do
        local file = self.flipped and 9 - col or col
        local letter = files:sub(file, file)
        local x = self.x + (col - 1) * size
        local opts = { align = "center", bold = true, color = Common.WHITE }
        Common.draw_text(bb, letter, x, self.y - g + math.floor((g - text_h) / 2), size, 15, opts)
        Common.draw_text(bb, letter, x, self.y + self.side + math.floor((g - text_h) / 2), size, 15, opts)
    end
    for row = 1, 8 do
        local rank = self.flipped and row or 9 - row
        local digit = ranks:sub(rank, rank)
        local y = self.y + (row - 1) * size + math.floor((size - text_h) / 2)
        local opts = { align = "center", bold = true, color = Common.WHITE }
        Common.draw_text(bb, digit, self.x - g, y, g, 15, opts)
        Common.draw_text(bb, digit, self.x + self.side, y, g, 15, opts)
    end
end

-- A frame of width bw inside the square, in color (four filled strips: paintBorder would turn a color to gray).
local function inner_frame(bb, x, y, size, bw, color, plain)
    fill(bb, x, y, size, bw, color, plain)
    fill(bb, x, y + size - bw, size, bw, color, plain)
    fill(bb, x, y + bw, bw, size - 2 * bw, color, plain)
    fill(bb, x + size - bw, y + bw, bw, size - 2 * bw, color, plain)
end

local function blit_disc(bb, image, x, y)
    bb:alphablitFrom(image, x, y, 0, 0, image:getWidth(), image:getHeight())
end

-- state: { position, last = {from,to}, selected = sq, targets = { [sq] = true }, check = sq, hint = sq }
function BoardView:paint(bb, state)
    local size = self.size
    local art = load_art(self.plugin_dir, self.piece_set, math.floor(size * 0.94))
    local edge = math.max(3, math.floor(size / 16)) -- frame of the squares of the last move
    local line = math.max(3, math.floor(size / 22))
    local board = state.position and state.position.board or {}
    local t = self.theme
    if self.gutter > 0 then
        self:paint_frame(bb)
    end
    for square = 1, 64 do
        local file, rank = file_rank(square)
        local x, y = self:square_origin(square)
        local dark = (file + rank) % 2 == 0
        local fill_color = dark and t.dark or t.light
        local is_last = state.last and (square == state.last.from or square == state.last.to)
        if not t.plain then
            if state.hint == square then
                fill_color = dark and t.hint_dark or t.hint_light
            end
            if state.selected == square then
                fill_color = dark and t.sel_dark or t.sel_light
            elseif is_last then
                fill_color = dark and t.last_dark or t.last_light
            end
            if state.check == square then
                fill_color = t.check
            end
        end
        fill(bb, x, y, size, size, fill_color, t.plain)
        if is_last and state.selected ~= square then
            if t.plain then
                bb:paintBorder(x, y, size, size, edge, Blitbuffer.Color8(0x30))
            else
                inner_frame(bb, x, y, size, edge, t.last_edge, false)
            end
        end
        if t.plain then
            if state.check == square then
                bb:paintBorder(x, y, size, size, line + 2, BLACK)
            end
            if state.selected == square then
                bb:paintBorder(x, y, size, size, line + 3, BLACK)
            end
        end
        local piece = board[square]
        if piece and art[piece] then
            local image = art[piece]
            local w, h = image:getWidth(), image:getHeight()
            bb:alphablitFrom(image, x + math.floor((size - w) / 2), y + math.floor((size - h) / 2), 0, 0, w, h)
        end
        if state.targets and state.targets[square] then
            blit_disc(bb, disc(piece and "capture" or "dot", size, self.theme_name), x, y)
        end
        if state.hint == square then
            blit_disc(bb, disc("hint", size, self.theme_name), x, y)
        end
    end
end

return BoardView
