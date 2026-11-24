-- The windows of the plugin: a title, an optional text and rows of large rounded buttons, centered on the screen.
-- Buttons are given as rows of { text, callback }. A text that starts with "● " is the current choice (bold, thick
-- frame) and one that starts with "▶ " is the main action. Pressing a button closes the window and then runs its
-- callback; touching outside the window closes it.
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Common = require("ajedrez/ui/common")
local Hatching = require("ajedrez/ui/hatching")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local Popup = InputContainer:extend{
    modal = true,
    title = nil,
    text = nil,
    buttons = nil, -- rows of { text = , callback = }
    kind = "buttons",
    on_close = nil, -- called whenever the window closes, however it closes
}

-- Windows open right now, so the screens know a window is up (they must not hide their bars under it).
Popup.open = {}

function Popup.count()
    local n = 0
    for _ in pairs(Popup.open) do
        n = n + 1
    end
    return n
end

function Popup.close_all()
    for popup in pairs(Popup.open) do
        popup:close()
    end
end

function Popup:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local width = math.min(math.floor(sw * 0.86), Screen:scaleBySize(620))
    local pad = Screen:scaleBySize(18)
    local gap = Screen:scaleBySize(10)
    local inner = width - 2 * pad - 2 * Size.border.window
    local group = VerticalGroup:new{ align = "center" }
    if self.title then
        group[#group + 1] = TextWidget:new{
            text = self.title,
            face = Font:getFace("cfont", 26),
            bold = true,
            max_width = inner,
        }
        group[#group + 1] = VerticalSpan:new{ width = gap }
    end
    if self.text then
        group[#group + 1] = TextBoxWidget:new{
            text = self.text,
            face = Font:getFace("cfont", 22),
            width = inner,
            alignment = "center",
        }
        group[#group + 1] = VerticalSpan:new{ width = gap * 2 }
    end
    for _, row in ipairs(self.buttons or {}) do
        local line = HorizontalGroup:new{}
        local count = #row
        local button_w = math.floor((inner - (count - 1) * gap) / count)
        for i, def in ipairs(row) do
            local text = tostring(def.text)
            local chosen = text:find("^● ") ~= nil
            local main = text:find("^▶ ") ~= nil
            line[#line + 1] = Button:new{
                text = text,
                width = button_w,
                bordersize = (chosen or main) and Size.border.thick or Size.border.button,
                radius = Size.radius.button,
                margin = 0,
                padding = Screen:scaleBySize(8),
                text_font_size = 22,
                text_font_bold = chosen or main,
                callback = function()
                    self:close()
                    if def.callback then
                        def.callback()
                    end
                end,
                show_parent = self,
            }
            if i < count then
                line[#line + 1] = HorizontalSpan:new{ width = gap }
            end
        end
        group[#group + 1] = line
        group[#group + 1] = VerticalSpan:new{ width = gap }
    end
    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        padding = pad,
        margin = 0,
        group,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Popup:close()
    if self.closed then
        return
    end
    self.closed = true
    Popup.open[self] = nil
    -- "partial" so a color board underneath comes back in color
    UIManager:close(self, "partial")
    if self.on_close then
        self.on_close()
    end
end

function Popup:onTapOutside(_, ges)
    local frame = self.frame and self.frame.dimen
    if not (frame and ges.pos.x >= frame.x and ges.pos.x < frame.x + frame.w
            and ges.pos.y >= frame.y and ges.pos.y < frame.y + frame.h) then
        self:close()
    end
    return true
end

-- The whole screen is shaded with diagonal lines before the window is drawn over it.
function Popup:paintTo(bb, x, y)
    Hatching.paint(bb, 0, 0, self.dimen.w, self.dimen.h)
    InputContainer.paintTo(self, bb, x, y)
    local f = self.frame and self.frame.dimen
    if Common.dark and f then
        Common.invert_rounded(bb, f.x, f.y, f.w, f.h, Size.radius.window)
    end
end

function Popup:onShow()
    Popup.open[self] = true
    UIManager:setDirty(nil, "partial")
end

-- closed from outside (UIManager:close) without going through Popup:close
function Popup:onCloseWidget()
    Popup.open[self] = nil
end

-- A message with an OK button.
function Popup.info(text, ok_text)
    return Popup:new{
        kind = "info",
        text = text,
        buttons = { { { text = ok_text or "OK" } } },
    }
end

-- opts: text, ok_text, cancel_text, ok_callback
function Popup.confirm(opts)
    return Popup:new{
        kind = "confirm",
        text = opts.text,
        buttons = { {
            { text = opts.cancel_text or "Cancel" },
            { text = "▶ " .. (opts.ok_text or "OK"), callback = opts.ok_callback },
        } },
    }
end

return Popup
