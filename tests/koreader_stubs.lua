-- Just enough of KOReader to load and drive the screens on a computer. Nothing is drawn: every drawing call is counted.
local H = ...
local S = { shown = {}, dirty = {}, closed = {}, paints = 0 }

local Base = {}
Base.__index = Base
function Base:extend(t)
    t = t or {}
    t.__index = t
    setmetatable(t, { __index = self })
    return t
end
function Base:new(o)
    o = o or {}
    setmetatable(o, self)
    if o.init then o:init() end
    return o
end
function Base:paintTo() end
S.Base = Base

local function preload(name, fn)
    package.preload[name] = fn
end

local screen = {}
function screen:getWidth() return S.width or 1264 end
function screen:getHeight() return S.height or 1680 end
function screen:isColorEnabled() return S.color end
function screen:scaleBySize(n) return math.floor(n * 1.875) end
S.screen = screen
preload("device", function() return { screen = screen } end)

local function color(v) return { v = v } end
local BB = { COLOR_BLACK = color(0), COLOR_WHITE = color(255) }
BB.TYPE_BBRGB32 = 4
function BB.new(w, h, kind)
    return { w = w, h = h, setPixel = function(self, x, y, c) S.pixels = (S.pixels or 0) + 1 end, free = function() end,
        getWidth = function(self) return w end, getHeight = function(self) return h end }
end
function BB.Color8(v) return color(v) end
function BB.ColorRGB32(r, g, b, a) return { r = r, g = g, b = b } end
preload("ffi/blitbuffer", function() return BB end)

-- a blitbuffer that only counts
S.bb = setmetatable({ calls = {} }, { __index = function(t, k)
    return function(self, ...)
        t.calls[k] = (t.calls[k] or 0) + 1
    end
end })

preload("ui/font", function() return { getFace = function(self, name, size) return { name = name, size = size } end } end)

local TextWidget = Base:extend{}
function TextWidget:getSize() return { w = #tostring(self.text) * (self.face.size or 10) * 0.5, h = (self.face.size or 10) * 1.3 } end
function TextWidget:paintTo() S.texts = S.texts or {}; S.texts[#S.texts + 1] = self.text end
function TextWidget:free() end
preload("ui/widget/textwidget", function() return TextWidget end)

local Geom = Base:extend{}
function Geom:combine(r)
    local x1, y1 = math.min(self.x, r.x), math.min(self.y, r.y)
    local x2, y2 = math.max(self.x + self.w, r.x + r.w), math.max(self.y + self.h, r.y + r.h)
    return Geom:new{ x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end
preload("ui/geometry", function() return Geom end)
preload("ui/gesturerange", function() return Base:extend{} end)
preload("ui/widget/container/inputcontainer", function() return Base:extend{} end)
preload("ui/widget/container/widgetcontainer", function() return Base:extend{} end)

local TitleBar = Base:extend{}
function TitleBar:getHeight() return 110 end
function TitleBar:paintTo() end
local TouchMenu = Base:extend{ name = "touchmenu" }
function TouchMenu:paintTo(bb, x, y) S.menu_painted = (S.menu_painted or 0) + 1 end
preload("ui/widget/touchmenu", function() return TouchMenu end)
S.TouchMenu = TouchMenu
preload("ui/widget/titlebar", function() return TitleBar end)

local UIManager = {}
function UIManager:show(w, refreshtype)
    if refreshtype then S.dirty[#S.dirty + 1] = { w = w, mode = refreshtype } end
    if w.buttons then S.dialogs = S.dialogs or {}; S.dialogs[#S.dialogs + 1] = w end
    S.shown[#S.shown + 1] = w; S.top = w; if w.onShow then w:onShow() end end
function UIManager:close(w, mode)
    for i = #S.shown, 1, -1 do if S.shown[i] == w then table.remove(S.shown, i) end end
    S.closed[#S.closed + 1] = w
    S.top = S.shown[#S.shown]
end
function UIManager:setDirty(w, mode, region)
    S.dirty[#S.dirty + 1] = { w = w, mode = mode, region = region }
    -- like the real thing, a dirty widget gets painted
    if w and type(w) == "table" and w.paintTo then
        w:paintTo(S.bb, 0, 0)
        S.paints = S.paints + 1
    end
end
function UIManager:scheduleIn(seconds, fn) return H.schedule(seconds, fn) end
function UIManager:unschedule(fn) return H.unschedule(fn) end
function UIManager:sendEvent(e) S.event = e end
preload("ui/uimanager", function() return UIManager end)
preload("ui/event", function() return { new = function(self, name) return { name = name } end } end)
preload("ui/time", function() return { now = function() return os.clock() end, to_s = function(t) return t end } end)
preload("logger", function() return { warn = function(...) print("WARN", ...) end, info = function() end } end)

-- layout widgets: plain containers
local function container(name)
    preload(name, function() return Base:extend{} end)
end
for _, n in ipairs({ "ui/widget/container/centercontainer", "ui/widget/container/framecontainer", "ui/widget/horizontalgroup",
    "ui/widget/horizontalspan", "ui/widget/verticalgroup", "ui/widget/verticalspan" }) do
    container(n)
end
local Button = Base:extend{}
preload("ui/widget/button", function() return Button end)
local TextBox = Base:extend{}
preload("ui/widget/textboxwidget", function() return TextBox end)
preload("ui/size", function()
    return { border = { window = 2, button = 1, thick = 3 }, radius = { window = 8, button = 4 }, padding = { large = 8 } }
end)
BB.COLOR_GRAY = color(128)

-- dialogs: kept so a test can press their buttons
-- every window of the plugin (Popup) that has buttons is recorded when shown; the stubs of KOReader's own
-- dialogs stay for main.lua
local function dialog_class(kind)
    return Base:extend{ kind = kind }
end
preload("ui/widget/infomessage", function() return dialog_class("info") end)
preload("ui/renderimage", function()
    return { renderSVGImageFile = function(self, path, w, h)
        local f = io.open(path)
        assert(f, "missing piece image: " .. path)
        f:close()
        return { getWidth = function() return w end, getHeight = function() return h end, free = function() end }
    end }
end)

local dir = os.getenv("TMPDIR") or "/tmp"
S.dir = dir .. "/ajedrez-ui-test"
os.execute("rm -rf '" .. S.dir .. "' && mkdir -p '" .. S.dir .. "/settings'")
preload("datastorage", function()
    return { getDataDir = function() return S.dir end, getSettingsDir = function() return S.dir .. "/settings" end }
end)
preload("luasettings", function()
    local L = {}
    function L:open(path)
        return setmetatable({ data = {} }, { __index = {
            readSetting = function(self, k) return self.data[k] end,
            saveSetting = function(self, k, v) self.data[k] = v end,
            delSetting = function(self, k) self.data[k] = nil end,
            flush = function(self) S.flushes = (S.flushes or 0) + 1 end,
        } })
    end
    return L
end)
_G.G_reader_settings = { readSetting = function(self, k) return k == "language" and "es_CL" or nil end }

-- helpers for the tests
function S.pixel_of(screen_widget, square_name)
    local Chess = require("ajedrez/chess")
    local x, y = screen_widget.board:square_origin(Chess.square_from_name(square_name))
    return { x = x + 10, y = y + 10 }
end
function S.tap_square(screen_widget, name)
    return screen_widget:onTap(nil, { pos = S.pixel_of(screen_widget, name) })
end
function S.press(dialog, text_part)
    for _, row in ipairs(dialog.buttons) do
        for _, b in ipairs(row) do
            if tostring(b.text):find(text_part, 1, true) then
                dialog:close() -- like the real button: close, then run
                if b.callback then b.callback() end
                return true
            end
        end
    end
    return false
end
function S.last_dialog(kind)
    for i = #(S.dialogs or {}), 1, -1 do
        if not kind or S.dialogs[i].kind == kind then return S.dialogs[i] end
    end
end
return S
