-- The plugin as a whole: what the screens share (settings, engine, puzzle pack) and how they open each other.
local UIManager = require("ui/uimanager")

local AI = require("ajedrez/ai")
local I18n = require("ajedrez/i18n")
local PuzzleStore = require("ajedrez/puzzle_store")
local Store = require("ajedrez/store")
local Strength = require("ajedrez/strength")
local Popup = require("ajedrez/ui/popup")

local App = {}
App.__index = App

-- Makes a folder without starting a shell (a shell is slow to start on a reader); falls back to mkdir -p.
local function mkdir(path)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs and lfs.attributes then
        if lfs.attributes(path, "mode") == "directory" then
            return
        end
        if pcall(lfs.mkdir, path) and lfs.attributes(path, "mode") == "directory" then
            return
        end
    end
    os.execute("mkdir -p '" .. path .. "' 2>/dev/null")
end

local function writable(dir)
    local probe = dir .. "/.ajedrez_probe"
    local f = io.open(probe, "w")
    if f then
        f:close()
        os.remove(probe)
        return true
    end
    return false
end

-- The plugin was called Caissa before: its folder of data (seen puzzles, a bigger puzzle pack, your own engine) and
-- its settings file (ratings, options, game in progress) are moved to the new names, once.
local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

function App.migrate(old_dir, new_dir, old_settings, new_settings)
    pcall(function()
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        local function dir_exists(path)
            return ok and lfs and lfs.attributes(path, "mode") == "directory"
        end
        if dir_exists(old_dir) and not dir_exists(new_dir) then
            os.rename(old_dir, new_dir)
        end
        if exists(old_settings) and not exists(new_settings) then
            os.rename(old_settings, new_settings)
        end
    end)
end

-- ui: the FileManager or ReaderUI that owns the plugin (needed to open KOReader's menu).
function App.new(ui, plugin_dir, version)
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")
    local self = setmetatable({ ui = ui, plugin_dir = plugin_dir, version = version or "?" }, App)
    self.data_dir = DataStorage:getDataDir() .. "/ajedrez"
    local settings_file = DataStorage:getSettingsDir() .. "/ajedrez.lua"
    App.migrate(DataStorage:getDataDir() .. "/caissa", self.data_dir, DataStorage:getSettingsDir() .. "/caissa.lua", settings_file)
    mkdir(self.data_dir)
    -- the engine writes to a file all the time: RAM when there is a /tmp, so the flash is spared
    self.tmp_dir = writable("/tmp") and "/tmp/ajedrez" or (self.data_dir .. "/tmp")
    self.settings = LuaSettings:open(settings_file)
    self.store = Store.new(self.settings, self.data_dir .. "/seen.txt")
    self.T = I18n.strings(G_reader_settings and G_reader_settings:readSetting("language"))
    require("ajedrez/ui/common").set_dark(self.store:option("dark_mode"))
    math.randomseed(os.time())
    return self
end

-- ---------------------------------------------------------------- shared things

function App:get_ai()
    if not self.ai then
        self.ai = AI.new{
            plugin_dir = self.plugin_dir,
            data_dir = self.data_dir,
            tmp_dir = self.tmp_dir,
            schedule = function(seconds, fn)
                UIManager:scheduleIn(seconds, fn)
                return fn
            end,
            unschedule = function(fn)
                UIManager:unschedule(fn)
            end,
        }
    end
    return self.ai
end

-- The puzzle pack: a big one in KOReader's data folder if the reader put one there, otherwise the one in the plugin.
function App:puzzle_pack()
    if self.pack == nil then
        self.pack = PuzzleStore.open(self.data_dir .. "/puzzles.txt")
            or PuzzleStore.open(self.plugin_dir .. "/data/puzzles.txt")
            or false
    end
    return self.pack or nil
end

-- The board colors chosen; the Lichess ones unless the reader picks another set. (Colors drawn on a gray screen are
-- turned to gray by KOReader itself, so there is no need to guess whether the screen has color.)
function App:board_theme()
    return self.store:option("board_theme") or "lichess"
end

-- KOReader's own top menu gets the same shading behind it while Ajedrez is open (as zenOS does): the area under the
-- menu is hatched, and when the menu closes the board is refreshed in "partial" so its colors come back.
function App:install_menu_hatching()
    if self.menu_patch then
        return
    end
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if not ok or type(TouchMenu) ~= "table" then
        return
    end
    local Hatching = require("ajedrez/ui/hatching")
    local Screen = require("device").screen
    local app = self
    local patch = { menu = TouchMenu, paint = TouchMenu.paintTo, show = TouchMenu.onShow, close = TouchMenu.onCloseWidget }
    TouchMenu.paintTo = function(menu, bb, x, y)
        if app.home and menu.dimen then
            local top = y + menu.dimen.h
            local height = Screen:getHeight()
            if top < height then
                Hatching.paint(bb, 0, top, Screen:getWidth(), height - top)
            end
        end
        return patch.paint(menu, bb, x, y)
    end
    TouchMenu.onShow = function(menu, ...)
        local result = patch.show and patch.show(menu, ...)
        if app.home then
            UIManager:setDirty(nil, "partial")
        end
        return result
    end
    TouchMenu.onCloseWidget = function(menu, ...)
        local result = patch.close and patch.close(menu, ...)
        if app.home then
            UIManager:scheduleIn(0.1, function()
                local screen = app.mode and app.mode.screen or app.home
                if screen then
                    UIManager:setDirty(screen, "partial")
                end
            end)
        end
        return result
    end
    self.menu_patch = patch
end

function App:remove_menu_hatching()
    local patch = self.menu_patch
    if patch then
        patch.menu.paintTo, patch.menu.onShow, patch.menu.onCloseWidget = patch.paint, patch.show, patch.close
        self.menu_patch = nil
    end
end

-- ---------------------------------------------------------------- opening and closing

function App:open()
    if self.home then
        return
    end
    pcall(function() self:install_menu_hatching() end)
    local Home = require("ajedrez/ui/home")
    self.home = Home:new{ app = self }
    -- "ui": the default refresh of a show is black and white on a color screen
    UIManager:show(self.home, "ui")
end

function App:mode_closed(mode)
    if self.mode == mode then
        self.mode = nil
    end
    if self.home then
        UIManager:setDirty(self.home, "ui")
    end
end

-- The X of the home screen. The screens go away at once and the screen is redrawn; the slow work (ending the engine
-- process, closing files) is left for a moment later, so the reader is not kept waiting for it.
function App:close_all()
    local home, mode = self.home, self.mode
    self.home = nil
    Popup.close_all()
    self:remove_menu_hatching()
    if mode and mode.screen then
        mode.screen:close()
    end
    if home then
        UIManager:close(home, "ui")
    end
    UIManager:scheduleIn(0.5, function()
        if self.home then
            return -- opened again meanwhile: the engine and the pack are in use
        end
        if self.ai then
            self.ai:stop()
        end
        if self.pack then
            self.pack:close()
            self.pack = nil
        end
    end)
end

-- ---------------------------------------------------------------- the two choices

function App:play_ai()
    local T = self.T
    if self.store:saved_game() then
        local Popup = require("ajedrez/ui/popup")
        local dialog
        dialog = Popup:new{
            buttons = {
                { { text = T.resume, callback = function()
                    UIManager:close(dialog)
                    self:start_game({ resume = true })
                end } },
                { { text = T.new_game, callback = function()
                    UIManager:close(dialog)
                    self.store:clear_game()
                    self:new_game_dialog(function(opts) self:start_game(opts) end)
                end } },
            },
        }
        UIManager:show(dialog)
        return
    end
    self:new_game_dialog(function(opts) self:start_game(opts) end)
end

function App:start_game(opts)
    local ok, err = pcall(function()
        self.mode = require("ajedrez/modes/vs_ai").start(self, opts)
    end)
    if not ok then
        require("logger").warn("Ajedrez: could not start the game", err)
        UIManager:show(require("ajedrez/ui/popup").info(self.T.start_failed, self.T.ok))
    end
end

function App:play_puzzles()
    if not self:puzzle_pack() then
        UIManager:show(require("ajedrez/ui/popup").info(self.T.no_puzzles, self.T.ok))
        return
    end
    local ok, err = pcall(function()
        self.mode = require("ajedrez/modes/puzzles").start(self)
    end)
    if not ok then
        require("logger").warn("Ajedrez: could not start puzzles", err)
        UIManager:show(require("ajedrez/ui/popup").info(self.T.start_failed, self.T.ok))
    end
end

-- Color and clock for a new game. Each choice shows the dialog again with the new choice marked.
function App:new_game_dialog(on_start)
    local T, store = self.T, self.store
    local Popup = require("ajedrez/ui/popup")
    local dialog
    local function again()
        UIManager:close(dialog)
        self:new_game_dialog(on_start)
    end
    local function mark(current, value, text)
        return (current == value and "● " or "") .. text
    end
    local color, time = store:option("color"), store:option("time")
    local color_row = {}
    for _, c in ipairs({ { "w", T.white }, { "b", T.black }, { "random", T.random } }) do
        color_row[#color_row + 1] = { text = mark(color, c[1], c[2]), callback = function()
            store:set_option("color", c[1])
            again()
        end }
    end
    local rows = { color_row }
    local time_row = {}
    for _, t in ipairs(Store.TIMES) do
        local label = t == "none" and "∞" or t
        time_row[#time_row + 1] = { text = mark(time, t, label), callback = function()
            store:set_option("time", t)
            again()
        end }
    end
    rows[#rows + 1] = time_row
    rows[#rows + 1] = { { text = "▶ " .. T.start, callback = function()
        UIManager:close(dialog)
        on_start({ color = store:option("color"), time = store:option("time") })
    end } }
    dialog = Popup:new{
        title = string.format(T.ai_plays_at, store:ai_elo()),
        buttons = rows,
    }
    UIManager:show(dialog)
end

-- ---------------------------------------------------------------- the menu of the home screen

function App:info(text)
    UIManager:show(require("ajedrez/ui/popup").info(text, self.T.ok))
end

function App:stats_text()
    local T, s = self.T, self.store
    local lines = {}
    lines[#lines + 1] = (s.player:provisional() and string.format(T.elo_now_prov, s.player:value()) or string.format(T.elo_now, s.player:value()))
    lines[#lines + 1] = string.format("%s: %d  (%s)", T.games, s.player.games, string.format(T.record, s.stats.wins, s.stats.draws, s.stats.losses))
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%s %s: %d", T.puzzles, T.puzzle_rating, s.puzzle:value())
    lines[#lines + 1] = string.format("%s: %d · %s: %d", T.solved, s.stats.solved, T.puzzle_failed, s.stats.failed)
    return table.concat(lines, "\n")
end

-- Info: only the name and the version.
function App:about_text()
    local T = self.T
    return string.format("Ajedrez (%s)\n%s %s", T.fork_of, T.version, self.version)
end

-- The one menu, from the home screen and from the board: settings, statistics, info. on_close runs when it closes.
function App:open_menu(on_close)
    local T = self.T
    local function item(text, fn)
        return { { text = text, callback = fn } }
    end
    UIManager:show(Popup:new{
        title = T.menu,
        buttons = {
            item(T.settings, function() self:settings_dialog() end),
            item(T.stats, function() self:info(self:stats_text()) end),
            item(T.info, function() self:info(self:about_text()) end),
        },
        on_close = on_close,
    })
end

-- A setting changed: the screen that is open draws again with it.
function App:settings_changed()
    if self.mode and self.mode.on_settings_changed then
        self.mode:on_settings_changed()
    elseif self.home then
        UIManager:setDirty(self.home, "ui")
    end
end

local function theme_label(app)
    return app.T["theme_" .. app:board_theme()] or app:board_theme()
end

function App:settings_dialog()
    local T, store = self.T, self.store
    local function row(label, value, fn)
        return { { text = label .. " · " .. value, callback = fn } }
    end
    local difficulty = store:option("difficulty") == "fixed" and tostring(store:option("fixed_elo")) or T.adaptive_short
    UIManager:show(Popup:new{
        title = T.settings,
        buttons = {
            row(T.difficulty, difficulty, function() self:difficulty_dialog() end),
            row(T.board_colors, theme_label(self), function() self:theme_dialog() end),
            row(T.pieces, T["set_" .. store:option("piece_set")] or store:option("piece_set"), function() self:pieces_dialog() end),
            row(T.dark_mode, store:option("dark_mode") and T.on or T.off, function()
                store:set_option("dark_mode", not store:option("dark_mode"))
                require("ajedrez/ui/common").set_dark(store:option("dark_mode"))
                self:settings_changed()
                self:settings_dialog()
            end),
            row(T.clock_refresh, store:option("clock_refresh") .. " s", function() self:clock_dialog() end),
            { { text = T.reset, callback = function()
                UIManager:show(Popup.confirm{
                    text = T.reset_confirm,
                    ok_text = T.reset,
                    cancel_text = T.cancel,
                    ok_callback = function()
                        self.store:reset()
                        self:settings_changed()
                    end,
                })
            end } },
        },
    })
end

-- The levels of Lichess's computer (see strength.lua) as ratings; the reader may also leave it adaptive.
function App:difficulty_dialog()
    local T, store = self.T, self.store
    local mode = store:option("difficulty")
    local rows = {
        { { text = (mode == "adaptive" and "● " or "") .. T.adaptive, callback = function()
            store:set_option("difficulty", "adaptive")
            self:difficulty_dialog()
        end } },
    }
    local row = {}
    for _, level in ipairs(Strength.LEVELS) do
        local elo = level[2]
        local selected = mode == "fixed" and store:option("fixed_elo") == elo
        row[#row + 1] = { text = (selected and "● " or "") .. elo, callback = function()
            store:set_option("difficulty", "fixed")
            store:set_option("fixed_elo", elo)
            self:difficulty_dialog()
        end }
        if #row == 4 then
            rows[#rows + 1] = row
            row = {}
        end
    end
    rows[#rows + 1] = { { text = T.back, callback = function() self:settings_dialog() end } }
    UIManager:show(Popup:new{ title = T.difficulty, text = T.difficulty_note, buttons = rows })
end

function App:theme_dialog()
    local T, store = self.T, self.store
    local rows = {}
    local current = self:board_theme()
    for _, name in ipairs({ "lichess", "green", "blue", "bw" }) do
        rows[#rows + 1] = { { text = (current == name and "● " or "") .. T["theme_" .. name], callback = function()
            store:set_option("board_theme", name)
            self:settings_changed()
            self:settings_dialog()
        end } }
    end
    UIManager:show(Popup:new{ title = T.board_colors, buttons = rows })
end

function App:pieces_dialog()
    local T, store = self.T, self.store
    local rows = {}
    for _, set in ipairs({ "cburnett", "merida", "chessnut" }) do
        rows[#rows + 1] = { { text = (store:option("piece_set") == set and "● " or "") .. T["set_" .. set], callback = function()
            store:set_option("piece_set", set)
            pcall(function() require("ajedrez/ui/board_view").release(set) end)
            self:settings_changed()
            self:settings_dialog()
        end } }
    end
    UIManager:show(Popup:new{ title = T.piece_set, buttons = rows })
end

-- Seconds between two redraws of the clocks in a timed game.
function App:clock_dialog()
    local T, store = self.T, self.store
    local row = {}
    for _, seconds in ipairs(Store.CLOCK_REFRESH) do
        row[#row + 1] = { text = (store:option("clock_refresh") == seconds and "● " or "") .. seconds .. " s", callback = function()
            store:set_option("clock_refresh", seconds)
            self:settings_changed()
            self:settings_dialog()
        end }
    end
    UIManager:show(Popup:new{ title = T.clock_refresh, text = T.clock_refresh_note, buttons = { row } })
end

return App
