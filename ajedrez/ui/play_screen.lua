-- The screen of a game or a puzzle: only the board (and the clock, when there is one).
--
--   tap anywhere but the board      shows or hides the interface: the title bar on top (menu on the left, X on the
--                                    right) and the action buttons at the bottom (the mode says which: undo, resign...)
--   swipe down from the top edge     opens KOReader's own menu
--   tap on a square                  goes to the mode (game or puzzle), which knows the rules of what to do
--
-- It knows nothing about chess rules or engines: the mode tells it what to draw (set_position, select, set_banner...).
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")

local BoardView = require("ajedrez/ui/board_view")
local Common = require("ajedrez/ui/common")

local Screen = Device.screen

-- Seconds the title bar stays after being shown by a tap, when nothing is touched.
local BAR_SECONDS = 5

local Popup = require("ajedrez/ui/popup")

local PlayScreen = InputContainer:extend{
    opening = true,
    name = "ajedrez_play",
    covers_fullscreen = true,
    stop_events_propagation = true,
    app = nil,
    mode = nil,
    flipped = false,
}

function PlayScreen:init()
    self:layout()
    self.view = { position = nil }
    self.bar_visible = false
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
end

function PlayScreen:layout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local margin = Common.px(14) -- blank space at the sides of the screen
    local gutter = Common.px(22) -- room for the coordinates around the board
    local reserve = Common.px(64) -- room above and below for the clocks
    local side = math.min(sw - 2 * margin - 2 * gutter, sh - 2 * reserve - 2 * gutter)
    side = math.max(64, math.floor(side / 8) * 8)
    self.board = BoardView.new{
        x = math.floor((sw - side) / 2),
        y = math.floor((sh - side) / 2),
        side = side,
        gutter = gutter,
        flipped = self.flipped,
        piece_set = self.app.store:option("piece_set"),
        theme = self.app:board_theme(),
        plugin_dir = self.app.plugin_dir,
    }
    self.top_zone = math.floor(sh * 0.12)
    self.clock_size = 26
    self.clock_h = Common.text_height(self.clock_size) + Common.px(6)
    if self.bar_visible then
        self:build_bar()
    end
    self:place_bottom()
    -- the circles are made a moment after the board is up, while the reader looks at it
    local board = self.board
    UIManager:scheduleIn(0.8, function()
        if not self.closed and self.board == board then
            pcall(board.warm, board)
        end
    end)
end

-- The action buttons take the bottom of the screen when the interface is shown; a banner goes above them then.
function PlayScreen:place_bottom()
    local sw, sh = self.dimen.w, self.dimen.h
    local margin = Common.px(14)
    local h = Common.px(46)
    local gap = Common.px(12)
    self.actions_rect = { x = margin, y = sh - h - margin, w = sw - 2 * margin, h = h }
    self.button_rects = {}
    local count = #(self.actions or {})
    if count > 0 then
        -- small buttons, centered as a group
        local bw = math.min(Common.px(190), math.floor((self.actions_rect.w - (count - 1) * gap) / count))
        local left = self.actions_rect.x + math.floor((self.actions_rect.w - (count * bw + (count - 1) * gap)) / 2)
        for i = 1, count do
            self.button_rects[i] = { x = left + (i - 1) * (bw + gap), y = self.actions_rect.y, w = bw, h = h }
        end
    end
    if self.banner then
        local bh = Common.px(60)
        local y = sh - bh - margin
        if self:actions_visible() then
            y = self.actions_rect.y - bh - gap
        end
        self.banner_rect = { x = margin, y = y, w = sw - 2 * margin, h = bh }
    else
        self.banner_rect = nil
    end
end

function PlayScreen:actions_visible()
    return self.bar_visible and self.actions ~= nil and #self.actions > 0
end

-- The region below the board where banner and buttons go.
function PlayScreen:bottom_region()
    local top = self.actions_rect.y - Common.px(60) - Common.px(12) - Common.px(8)
    return Geom:new{ x = 0, y = top, w = self.dimen.w, h = self.dimen.h - top }
end

-- list of { label, callback }; nil removes them. They show with the title bar.
function PlayScreen:set_actions(list)
    local had = self:actions_visible()
    self.actions = list
    self:place_bottom()
    if had or self:actions_visible() then
        self:dirty("ui", self:bottom_region())
    end
end

-- The settings changed (board colors, pieces): draw again with them.
-- While the screen opens, its show already refreshes everything (the one full refresh): nothing else is asked for,
-- or the reader would see a second flash right after the first. The mode calls finish_opening when it is set up.
function PlayScreen:dirty(mode, region)
    if self.opening then
        return
    end
    UIManager:setDirty(self, mode, region)
end

function PlayScreen:finish_opening()
    self.opening = false
    -- one full refresh when the board opens, so nothing of the screen before stays (joins the one of the show)
    UIManager:setDirty(self, "full")
end

function PlayScreen:apply_settings()
    self:layout()
    self:dirty("ui")
end

-- Screen rotated or resized.
function PlayScreen:onSetDimensions()
    self:layout()
    self:dirty("full")
end

function PlayScreen:onScreenResize()
    self:layout()
    self:dirty("full")
end

-- ---------------------------------------------------------------- what the mode draws

-- Squares that are marked (selected, targets, hint) of a view.
local function marked(view)
    local list = {}
    if view.selected then
        list[#list + 1] = view.selected
    end
    for square in pairs(view.targets or {}) do
        list[#list + 1] = square
    end
    if view.hint then
        list[#list + 1] = view.hint
    end
    return list
end

-- opts: { last = {from,to}, check = square, full = true to draw the whole board again (a new puzzle) }
-- Only the squares that changed are refreshed: a refresh of the whole board flashes the whole board.
function PlayScreen:set_position(position, opts)
    opts = opts or {}
    local old = self.view
    self.view = { position = position, last = opts.last, check = opts.check, hint = nil }
    if opts.full or not (old and old.position) then
        self:refresh_board()
        return old
    end
    local changed = {}
    local before, after = old.position.board, position.board
    for square = 1, 64 do
        if before[square] ~= after[square] then
            changed[square] = true
        end
    end
    for _, view in ipairs({ old, self.view }) do
        if view.last then
            changed[view.last.from], changed[view.last.to] = true, true
        end
        if view.check then
            changed[view.check] = true
        end
    end
    for _, square in ipairs(marked(old)) do
        changed[square] = true
    end
    local list = {}
    for square in pairs(changed) do
        list[#list + 1] = square
    end
    self:refresh_squares(list)
    return old
end

function PlayScreen:select(square, targets)
    local list = marked(self.view)
    self.view.selected, self.view.targets = square, targets
    for _, sq in ipairs(marked(self.view)) do
        list[#list + 1] = sq
    end
    self:refresh_squares(list, true)
end

function PlayScreen:clear_selection()
    if self.view.selected or self.view.targets then
        local list = marked(self.view)
        self.view.selected, self.view.targets = nil, nil
        self:refresh_squares(list, true)
    end
end

function PlayScreen:set_hint(square)
    local list = marked(self.view)
    self.view.hint = square
    list[#list + 1] = square
    self:refresh_squares(list)
end

function PlayScreen:set_flipped(flag)
    if self.flipped ~= flag then
        self.flipped = flag
        self.board.flipped = flag
    end
end

-- fn() -> top_text, bottom_text, running ("top" or "bottom"); nil removes the clock.
function PlayScreen:set_clock(fn)
    self.clock_fn = fn
    self:refresh_clocks()
end

-- A line of text at the top left of the board, where the clock goes (the kind of a puzzle). nil removes it.
function PlayScreen:set_label(text)
    self.label = text
    local r = self:clock_rects().top
    self:dirty("ui", Geom:new(r))
end

-- A line of text under the board, left aligned like the label above it (the answer to a move of a puzzle). nil removes it.
function PlayScreen:set_note(text)
    if self.note == text then
        return
    end
    self.note = text
    local r = self:clock_rects().bottom
    local b = self.board
    self:dirty("ui", Geom:new{ x = b.x - b.gutter, y = r.y, w = b.side + 2 * b.gutter, h = r.h })
end

function PlayScreen:set_banner(text, label, callback)
    self.banner = { text = text, label = label, callback = callback }
    self:place_bottom()
    self:dirty("ui", self:bottom_region())
end

function PlayScreen:clear_banner()
    if self.banner then
        local region = self:bottom_region()
        self.banner = nil
        self:place_bottom()
        self:dirty("ui", region)
    end
end

function PlayScreen:set_title(title, subtitle)
    self.title, self.subtitle = title, subtitle
    if self.bar_visible then
        self:build_bar()
        self:dirty("ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.bar_height })
    end
end

-- ---------------------------------------------------------------- title bar

function PlayScreen:build_bar()
    self.titlebar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        title = self.title or "Ajedrez",
        subtitle = self.subtitle,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:open_menu() end,
        close_callback = function() self:close_requested() end,
        show_parent = self,
        with_bottom_line = true,
    }
    self.bar_height = self.titlebar:getHeight()
    self[1] = self.titlebar
end

function PlayScreen:cancel_autohide()
    if self.hide_fn then
        UIManager:unschedule(self.hide_fn)
        self.hide_fn = nil
    end
end

-- The interface shown by a tap goes away by itself when nothing is touched (not while a window is open).
function PlayScreen:arm_autohide()
    self:cancel_autohide()
    if not self.bar_visible or self.bar_sticky or self.closed then
        return
    end
    self.hide_fn = function()
        self.hide_fn = nil
        if not self.bar_visible or self.bar_sticky then
            return
        end
        if Popup.count() > 0 then
            self:arm_autohide()
        else
            self:show_bar(false)
        end
    end
    UIManager:scheduleIn(BAR_SECONDS, self.hide_fn)
end

-- sticky: the bar stays until the reader touches outside the board again (end of a game or a puzzle).
function PlayScreen:show_bar(flag, sticky)
    self.bar_sticky = flag and sticky or false
    if flag == self.bar_visible then
        if flag then
            self:arm_autohide()
        end
        return
    end
    self.bar_visible = flag
    if flag then
        self:build_bar()
        self:arm_autohide()
    else
        self:cancel_autohide()
        self[1] = nil
    end
    self:place_bottom()
    self:dirty("ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = (self.bar_height or Common.px(60)) + 2 })
    if self.actions and #self.actions > 0 or self.banner then
        self:dirty("ui", self:bottom_region())
    end
end

function PlayScreen:toggle_bar()
    self:show_bar(not self.bar_visible)
end

-- The same menu from everywhere: settings, statistics, info.
function PlayScreen:open_menu()
    self:cancel_autohide()
    self.app:open_menu(function()
        self:arm_autohide()
    end)
end

-- The window to choose a piece when a pawn promotes: the pieces of the player's color, drawn.
function PlayScreen:ask_promotion(strings, color, callback, on_cancel)
    local Promotion = require("ajedrez/ui/promotion")
    UIManager:show(Promotion:new{
        title = strings.promote,
        color = color,
        piece_set = self.app.store:option("piece_set"),
        plugin_dir = self.app.plugin_dir,
        callback = callback,
        on_cancel = on_cancel,
    })
end

function PlayScreen:close_requested()
    self:close()
end

function PlayScreen:close()
    if self.closed then
        return
    end
    self.closed = true
    self:cancel_autohide()
    Popup.close_all()
    -- "ui": whatever is underneath (the home, a color board icon) comes back in color
    UIManager:close(self, "ui")
    if self.mode and self.mode.on_close then
        self.mode:on_close()
    end
    if self.on_closed then
        self.on_closed()
    end
end

-- ---------------------------------------------------------------- drawing

-- Refresh policy (taken from zenOS, which has no color artifacts on Kaleido): never "fast" (black and white waveform),
-- always the same mode "ui", and always the same rectangle for the board (its whole frame) instead of rectangles
-- of many sizes. The only "full" refresh is the one of UIManager:show.
function PlayScreen:refresh_board()
    -- "partial" (GC16, without the black flash of "full") leaves the board clean: "ui" leaves ghosts of the old pieces
    -- and of the dots; it is always the same rectangle, so nothing looks like a patch.
    self:dirty("partial", self.board:frame_rect())
end

-- A move changed some squares: the board frame is refreshed as one piece with the clean waveform ("partial").
-- light: a selection (dots, a ring) is refreshed at once with the faster "ui" waveform over the same rectangle, so
-- tapping a piece answers without lag; the refresh of the move that follows cleans the leftovers.
function PlayScreen:refresh_squares(squares, light)
    if #squares == 0 then
        return
    end
    if light then
        self:dirty("ui", self.board:frame_rect())
    else
        self:refresh_board()
    end
end

function PlayScreen:clock_rects()
    local b = self.board
    local w = Common.px(150)
    return {
        -- the clock of the top side is on the left, the one of the bottom side on the right, level with the frame
        top = { x = b.x - b.gutter, y = b.y - b.gutter - self.clock_h, w = w, h = self.clock_h },
        bottom = { x = b.x + b.side + b.gutter - w, y = b.y + b.side + b.gutter, w = w, h = self.clock_h },
    }
end

function PlayScreen:refresh_clocks()
    if not self.clock_fn then
        local r = self:clock_rects()
        self:dirty("ui", Geom:new{ x = r.top.x, y = r.top.y, w = r.top.w, h = r.bottom.y + r.bottom.h - r.top.y })
        return
    end
    local rects = self:clock_rects()
    self:dirty("ui", Geom:new(rects.top))
    self:dirty("ui", Geom:new(rects.bottom))
end

function PlayScreen:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.dimen.w, self.dimen.h, Common.WHITE)
    self.board:paint(bb, self.view)
    if self.label then
        local r = self:clock_rects().top
        Common.draw_text(bb, self.label, r.x, r.y, self.board.side + 2 * self.board.gutter, self.clock_size - 4,
            { align = "left", bold = true })
    end
    if self.note then
        local r = self:clock_rects().bottom
        -- same size and same distance from the frame as the label above the board
        Common.draw_text(bb, self.note, self.board.x - self.board.gutter, r.y + Common.px(6),
            self.board.side + 2 * self.board.gutter, self.clock_size - 4, { align = "left", bold = true })
    end
    if self.clock_fn then
        local top, bottom, running = self.clock_fn()
        local rects = self:clock_rects()
        if top then
            Common.draw_text(bb, top, rects.top.x, rects.top.y, rects.top.w, self.clock_size,
                { align = "left", bold = running == "top" })
        end
        if bottom then
            Common.draw_text(bb, bottom, rects.bottom.x, rects.bottom.y, rects.bottom.w, self.clock_size,
                { align = "right", bold = running == "bottom" })
        end
    end
    if self.banner and self.banner_rect then
        local r = self.banner_rect
        Common.round_box(bb, r.x, r.y, r.w, r.h, Common.px(10), 3, Common.WHITE)
        local text_w = r.w
        if self.banner.label then
            -- the button: a black rounded block inside the banner, with room around it
            local inset = Common.px(7)
            local bw = Common.px(170)
            local bx, by, bh = r.x + r.w - bw - inset, r.y + inset, r.h - 2 * inset
            text_w = r.w - bw - inset
            Common.round_rect(bb, bx, by, bw, bh, Common.px(8), Common.BLACK)
            Common.draw_text(bb, self.banner.label .. "  ▶", bx, by + math.floor((bh - Common.text_height(22)) / 2),
                bw, 22, { align = "center", bold = true, color = Common.WHITE })
        end
        Common.draw_text(bb, self.banner.text, r.x + Common.px(14), r.y + math.floor((r.h - Common.text_height(20)) / 2),
            text_w - Common.px(20), 20, { align = "left", bold = self.banner.label ~= nil })
    end
    if self:actions_visible() then
        -- the buttons look like the frame of the board: ink rounded blocks (8 px) with the label and a small icon in
        -- paper color; pressed, they swap colors
        for i, action in ipairs(self.actions) do
            local r = self.button_rects[i]
            local pressed = self.pressed == i
            local bg, fg = pressed and Common.WHITE or Common.BLACK, pressed and Common.BLACK or Common.WHITE
            Common.round_rect(bb, r.x, r.y, r.w, r.h, Common.px(8), Common.BLACK)
            if pressed then
                Common.round_rect(bb, r.x + 3, r.y + 3, r.w - 6, r.h - 6, Common.px(8) - 3, bg)
            end
            local size = 20
            local text_w = Common.text_width(action.label, size, true)
            local icon_s = action.icon and Common.px(20) or 0
            local gap = action.icon and Common.px(12) or 0
            local left = r.x + math.floor((r.w - (icon_s + gap + text_w)) / 2)
            if action.icon then
                Common.draw_icon(bb, action.icon, left, r.y + math.floor((r.h - icon_s) / 2), icon_s, fg)
            end
            Common.draw_text(bb, action.label, left + icon_s + gap, r.y + math.floor((r.h - Common.text_height(size)) / 2),
                text_w + 4, size, { align = "left", bold = true, color = fg })
        end
    end
    if self.bar_visible and self.titlebar then
        if Common.dark then
            -- the bar is drawn for a white page (it paints no background of its own): white first, inverted after
            bb:paintRect(0, 0, self.dimen.w, self.titlebar:getSize().h, Blitbuffer.COLOR_WHITE)
        end
        self.titlebar:paintTo(bb, 0, 0)
        if Common.dark then
            bb:invertRect(0, 0, self.dimen.w, self.titlebar:getSize().h)
        end
    end
end

-- ---------------------------------------------------------------- gestures

function PlayScreen:onTap(_, ges)
    local pos = ges.pos
    if self:actions_visible() then
        for i, r in ipairs(self.button_rects) do
            if Common.in_rect(pos, r) then
                self:press_action(i)
                return true
            end
        end
    end
    if self.banner_rect and Common.in_rect(pos, self.banner_rect) then
        local cb = self.banner and self.banner.callback
        if cb then
            cb()
        end
        return true
    end
    local square = self.board:square_at(pos.x, pos.y)
    if not square then
        -- anywhere but the board: the interface comes or goes
        self:toggle_bar()
        return true
    end
    if self.bar_visible and not self.bar_sticky then
        self:show_bar(false)
    end
    if self.mode and self.mode.on_square then
        self.mode:on_square(square)
    end
    return true
end

-- A button is shown pressed for a moment, then its action runs.
function PlayScreen:press_action(i)
    local action = self.actions[i]
    self:arm_autohide()
    self.pressed = i
    self:dirty("ui", Geom:new(self.button_rects[i]))
    UIManager:scheduleIn(0.12, function()
        self.pressed = nil
        if self.closed then
            return
        end
        self:dirty("ui", Geom:new(self.button_rects[i] or self.actions_rect))
        if action and action.callback then
            action.callback()
        end
    end)
end

function PlayScreen:onSwipe(_, ges)
    if Common.is_top_swipe(ges, self.top_zone) then
        Common.show_koreader_menu(self.app.ui)
    end
    return true
end

-- The device went to sleep or woke up.
function PlayScreen:onSuspend()
    if self.mode and self.mode.on_suspend then
        self.mode:on_suspend()
    end
end

function PlayScreen:onResume()
    if self.mode and self.mode.on_resume then
        self.mode:on_resume()
    end
end

return PlayScreen
