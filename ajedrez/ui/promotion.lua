-- The window to choose a piece when a pawn reaches the last rank: the four pieces drawn, not their names.
-- Touching a piece chooses it; touching outside the window gives the move up.
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local BoardView = require("ajedrez/ui/board_view")
local Common = require("ajedrez/ui/common")
local Hatching = require("ajedrez/ui/hatching")
local Popup = require("ajedrez/ui/popup")

local Screen = Device.screen

local LETTERS = { "q", "r", "b", "n" }

local Promotion = InputContainer:extend{
    modal = true,
    title = nil,
    color = "w", -- color of the pawn: the pieces drawn are of this color
    piece_set = "cburnett",
    plugin_dir = nil,
    callback = nil, -- callback(letter) with "q", "r", "b" or "n"
    on_cancel = nil,
}

function Promotion:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local width = math.min(math.floor(sw * 0.86), Common.px(620))
    local pad = Common.px(20)
    local gap = Common.px(12)
    local title_h = Common.text_height(26)
    local cell = math.floor((width - 2 * pad - 3 * gap) / 4)
    local height = pad + title_h + gap * 2 + cell + pad
    local x, y = math.floor((sw - width) / 2), math.floor((sh - height) / 2)
    self.window = { x = x, y = y, w = width, h = height }
    self.title_pos = { x = x, y = y + pad, w = width }
    self.cells = {}
    for i, letter in ipairs(LETTERS) do
        self.cells[i] = { letter = letter, x = x + pad + (i - 1) * (cell + gap), y = y + pad + title_h + gap * 2, w = cell, h = cell }
    end
    self.art = BoardView.art(self.plugin_dir, self.piece_set, math.floor(cell * 0.84))
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end

function Promotion:paintTo(bb, x, y)
    Hatching.paint(bb, 0, 0, self.dimen.w, self.dimen.h)
    local w = self.window
    Common.round_box(bb, w.x, w.y, w.w, w.h, Common.px(16), 3, Common.WHITE)
    if self.title then
        Common.draw_text(bb, self.title, self.title_pos.x, self.title_pos.y, self.title_pos.w, 26, { align = "center", bold = true })
    end
    for _, cell in ipairs(self.cells) do
        Common.round_box(bb, cell.x, cell.y, cell.w, cell.h, Common.px(10), 3, Common.dark and require("ffi/blitbuffer").Color8(0xEE) or Common.WHITE)
        local key = self.color == "w" and cell.letter:upper() or cell.letter
        local image = self.art and self.art[key]
        if image then
            local iw, ih = image:getWidth(), image:getHeight()
            bb:alphablitFrom(image, cell.x + math.floor((cell.w - iw) / 2), cell.y + math.floor((cell.h - ih) / 2), 0, 0, iw, ih)
        end
    end
end

function Promotion:close(chosen)
    if self.closed then
        return
    end
    self.closed = true
    Popup.open[self] = nil
    UIManager:close(self, "partial")
    if chosen then
        if self.callback then
            self.callback(chosen)
        end
    elseif self.on_cancel then
        self.on_cancel()
    end
end

function Promotion:onTap(_, ges)
    for _, cell in ipairs(self.cells) do
        if Common.in_rect(ges.pos, cell) then
            self:close(cell.letter)
            return true
        end
    end
    if not Common.in_rect(ges.pos, self.window) then
        self:close()
    end
    return true
end

function Promotion:onShow()
    Popup.open[self] = true
    UIManager:setDirty(nil, "partial")
end

function Promotion:onCloseWidget()
    Popup.open[self] = nil
end

return Promotion
