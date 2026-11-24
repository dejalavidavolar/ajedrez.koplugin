local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/main%.lua$", "")

local function meta_version()
    local chunk = loadfile(PLUGIN_DIR .. "/_meta.lua")
    if chunk then
        local ok, meta = pcall(chunk)
        if ok and type(meta) == "table" then
            return meta.version
        end
    end
    return "?"
end

local Ajedrez = WidgetContainer:extend{
    name = "ajedrez",
    is_doc_only = false,
}

function Ajedrez:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    -- lets the reader bind "Ajedrez" to a gesture or a button
    pcall(function()
        local Dispatcher = require("dispatcher")
        Dispatcher:registerAction("ajedrez_open", { category = "none", event = "OpenAjedrez", title = "Ajedrez", general = true })
    end)
end

function Ajedrez:addToMainMenu(menu_items)
    menu_items.ajedrez = {
        text = "Ajedrez",
        sorting_hint = "tools",
        callback = function() self:open() end,
    }
end

function Ajedrez:open()
    local ok, err = pcall(function()
        if not self.app then
            local App = require("ajedrez/app")
            self.app = App.new(self.ui, PLUGIN_DIR, meta_version())
        end
        self.app:open()
    end)
    if not ok then
        logger.warn("Ajedrez: could not open", err)
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Ajedrez: " .. tostring(err) })
    end
end

function Ajedrez:onOpenAjedrez()
    self:open()
    return true
end

return Ajedrez
