-- The first screen: a title bar (menu on the left, X on the right) and two big choices, play against the AI and puzzles.
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")

local BoardView = require("ajedrez/ui/board_view")
local Blitbuffer = require("ffi/blitbuffer")
local Common = require("ajedrez/ui/common")

local Screen = Device.screen

local Home = InputContainer:extend{
    name = "ajedrez_home",
    covers_fullscreen = true,
    stop_events_propagation = true,
    app = nil,
}

function Home:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local T = self.app.T
    self.titlebar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        title = T.app,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self.app:open_menu() end,
        close_callback = function() self.app:close_all() end,
        show_parent = self,
        with_bottom_line = true,
    }
    self[1] = self.titlebar
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    self:compute_buttons()
end

-- Two columns side by side, each an icon with its title below.
function Home:compute_buttons()
    local sw, sh = self.dimen.w, self.dimen.h
    local bar = self.titlebar:getHeight()
    local icon = math.floor(math.min(sw * 0.34, (sh - bar) * 0.26))
    local title_h = Common.text_height(28)
    local info_h = Common.text_height(16)
    local block = icon + Common.px(26) + title_h + Common.px(6) + info_h
    local top = bar + math.floor((sh - bar - block) / 2)
    self.icon_size = icon
    self.buttons = {}
    for i, key in ipairs({ "ai", "puzzles" }) do
        local cx = math.floor(sw * (i == 1 and 0.27 or 0.73))
        local pad = Common.px(16)
        self.buttons[#self.buttons + 1] = {
            key = key,
            cx = cx,
            icon_y = top,
            rect = { x = cx - math.floor(sw * 0.23), y = top - pad, w = math.floor(sw * 0.46), h = block + 2 * pad },
        }
    end
end

-- The knight, drawn once per size and kept for the next time the home opens (drawing the vector file is slow).
local knights = {}

function Home:knight_image()
    local size = self.icon_size
    if knights[size] == nil then
        local ok, image = pcall(function()
            local RenderImage = require("ui/renderimage")
            return RenderImage:renderSVGImageFile(string.format("%s/pieces/cburnett/bN.svg", self.app.plugin_dir), size, size)
        end)
        knights[size] = (ok and image) or false
    end
    return knights[size] or nil
end

-- A small board as the icon of the puzzles.
function Home:paint_board_icon(bb, x, y, size)
    local theme = BoardView.THEMES[self.app:board_theme()] or BoardView.THEMES.lichess
    local cell = math.floor(size / 4)
    local side = cell * 4
    local left = x + math.floor((size - side) / 2)
    for row = 0, 3 do
        for col = 0, 3 do
            local color = ((row + col) % 2 == 0) and theme.light or theme.dark
            if not theme.plain and bb.paintRectRGB32 then
                bb:paintRectRGB32(left + col * cell, y + row * cell, cell, cell, color)
            else
                bb:paintRect(left + col * cell, y + row * cell, cell, cell, color)
            end
        end
    end
    bb:paintBorder(left - 2, y - 2, side + 4, side + 4, 3, Common.BLACK)
end

-- The two lines of text of each button, from the state of the app.
function Home:lines(key)
    local T, app = self.app.T, self.app
    if key == "ai" then
        local store = app.store
        local info
        if store.player:provisional() then
            info = string.format("%s ~%d (%d/%d)", T.level, store.player:value(), store.player.games, store.player.placement)
        else
            info = string.format("%s %d", T.level, store.player:value())
        end
        if store:saved_game() then
            info = T.resume
        end
        return T.play_ai, info
    end
    local pack = app:puzzle_pack()
    local info
    if pack then
        info = string.format("%s %d", T.puzzle_rating, app.store.puzzle:value())
    else
        info = T.no_puzzles
    end
    return T.puzzles, info
end

function Home:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.dimen.w, self.dimen.h, Common.WHITE)
    for _, button in ipairs(self.buttons) do
        local icon = self.icon_size
        local left = button.cx - math.floor(icon / 2)
        if button.key == "ai" then
            local knight = self:knight_image()
            if knight then
                if Common.dark then
                    -- the black pieces vanish on black: a light tile behind them
                    Common.round_rect(bb, left, button.icon_y, icon, icon, Common.px(14), Blitbuffer.Color8(0xEE))
                end
                bb:alphablitFrom(knight, left, button.icon_y, 0, 0, knight:getWidth(), knight:getHeight())
            else
                Common.draw_text(bb, "♞", left, button.icon_y, icon, 120, { align = "center" })
            end
        else
            self:paint_board_icon(bb, left, button.icon_y, icon)
        end
        local title, info = self:lines(button.key)
        local r = button.rect
        local title_y = button.icon_y + icon + Common.px(26)
        local title_h = Common.text_height(28)
        Common.draw_text(bb, title, r.x, title_y, r.w, 28, { align = "center", bold = true })
        Common.draw_text(bb, info, r.x, title_y + title_h + Common.px(6), r.w, 16, { align = "center", color = Common.GRAY })
        if self.pressed == button.key then
            bb:invertRect(r.x, r.y, r.w, r.h)
        end
    end
    if Common.dark then
        -- the bar is drawn for a white page (it paints no background of its own): white first, inverted after
        bb:paintRect(0, 0, self.dimen.w, self.titlebar:getSize().h, Blitbuffer.COLOR_WHITE)
    end
    self.titlebar:paintTo(bb, 0, 0)
    if Common.dark then
        bb:invertRect(0, 0, self.dimen.w, self.titlebar:getSize().h)
    end
end

function Home:refresh()
    UIManager:setDirty(self, "ui")
end

function Home:onTap(_, ges)
    for _, button in ipairs(self.buttons) do
        if Common.in_rect(ges.pos, button.rect) then
            self.pressed = button.key
            UIManager:setDirty(self, "ui", Geom:new(button.rect))
            UIManager:scheduleIn(0.12, function()
                self.pressed = nil
                UIManager:setDirty(self, "ui", Geom:new(button.rect))
                if button.key == "ai" then
                    self.app:play_ai()
                else
                    self.app:play_puzzles()
                end
            end)
            return true
        end
    end
    return true
end

function Home:onSwipe(_, ges)
    if Common.is_top_swipe(ges, math.floor(self.dimen.h * 0.12)) then
        Common.show_koreader_menu(self.app.ui)
    end
    return true
end

return Home
