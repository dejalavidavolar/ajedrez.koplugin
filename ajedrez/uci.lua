-- Stockfish (or any UCI engine) as a process of its own. The commands go to its input through a pipe, and what it
-- says goes to a file that is read a little at a time, so a search never freezes the screen. It runs at the lowest
-- priority (nice 19) and with one thread, so the reader and the system keep their turn.
--
-- The launch script is the one proven on e-readers: the engine runs beside the shell, which keeps reading the pipe
-- after it ends, so a write to an engine that died never raises SIGPIPE and closes KOReader; file descriptors of
-- KOReader are closed before the engine starts, so it holds none of them.
local Uci = {}
Uci.__index = Uci

Uci.ENDED = "ajedrez: the engine ended"
Uci.HASH_MB = 16

local function quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function exists(path)
    local file = path and io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

local function dirname(path)
    return path:match("^(.*)/[^/]*$") or "."
end

-- What the engine (or the shell that launched it) printed so far, for the error message when it does not start.
function Uci:diagnostics()
    local f = io.open(self.out_path, "rb")
    local text = f and f:read("*a") or ""
    if f then
        f:close()
    end
    text = text:gsub(Uci.ENDED, ""):gsub("%s+", " ")
    return text:sub(1, 300)
end

-- Copies the engine into a folder where it is surely allowed to run (the data folder of an e-reader can be
-- mounted without permission to execute). Returns the new path, or nil.
function Uci.copy_to(binary, dir)
    os.execute("mkdir -p " .. quote(dir))
    local target = dir .. "/stockfish-run"
    os.remove(target)
    local ok = os.execute("cp " .. quote(binary) .. " " .. quote(target) .. " && chmod 755 " .. quote(target))
    if (ok == 0 or ok == true) and exists(target) then
        return target
    end
    return nil
end

-- The engine to run, or nil. Looked for in this order, so a newer build can be dropped in without touching the plugin:
--   1. the AJEDREZ_STOCKFISH environment variable (used on a computer/emulator);
--   2. <koreader data>/ajedrez/stockfish (a build of your own, e.g. Stockfish 17/18 for ARM);
--   3. <plugin>/bin/stockfish-armv7, then the Stockfish 11 build that comes with the plugin (bin/stockfish-armhf).
local found = {}
function Uci.find(plugin_dir, data_dir)
    local key = tostring(plugin_dir) .. "|" .. tostring(data_dir)
    if found[key] == nil then
        local named = os.getenv("AJEDREZ_STOCKFISH")
        local candidates = {}
        if named and named ~= "" then
            candidates[#candidates + 1] = named
        else
            if data_dir then
                candidates[#candidates + 1] = data_dir .. "/stockfish"
            end
            candidates[#candidates + 1] = plugin_dir .. "/bin/stockfish-armv7"
            candidates[#candidates + 1] = plugin_dir .. "/bin/stockfish-armhf"
        end
        found[key] = false
        for _, path in ipairs(candidates) do
            if exists(path) then
                -- A copy over USB or from a zip may lose the execute bit.
                os.execute("chmod +x " .. quote(path) .. " 2>/dev/null")
                found[key] = path
                break
            end
        end
    end
    return found[key] or nil
end

local started = 0

-- dir: a private folder for the output files. Returns the process, or nil when it cannot start.
function Uci.start(binary, dir)
    os.execute("mkdir -p " .. quote(dir) .. " && chmod 700 " .. quote(dir))
    if started == 0 then
        os.execute("rm -f " .. quote(dir) .. "/engine-*.out " .. quote(dir) .. "/engine-*.pid")
    end
    started = started + 1
    local base = string.format("%s/engine-%d", dir, started)
    local self = setmetatable({ out_path = base .. ".out", pid_path = base .. ".pid", offset = 0, partial = "", binary = binary }, Uci)
    os.remove(self.out_path)
    os.remove(self.pid_path)
    local script = string.format("exec 3<&0; big=; (eval 'exec 10<&-') 2>/dev/null && big=1; "
        .. "for fd in /proc/$$/fd/*; do n=${fd##*/}; [ \"$n\" -gt 3 ] 2>/dev/null || continue; "
        .. "[ ${#n} -gt 1 ] && [ -z \"$big\" ] && continue; eval \"exec $n<&-\"; done; "
        .. "cd %s 2>/dev/null; "
        .. "nice -n 19 %s <&3 3<&- > %s 2>&1 & echo $! > %s; wait $! 2>/dev/null; rm -f %s; { echo; echo %s; } >> %s; cat > /dev/null",
        quote(dirname(binary)), quote(binary), quote(self.out_path), quote(self.pid_path), quote(self.pid_path),
        quote(Uci.ENDED), quote(self.out_path))
    self.pipe = io.popen("sh -c " .. quote(script), "w")
    if not self.pipe then
        return nil
    end
    self:send("uci")
    self:send("setoption name Threads value 1")
    self:send("setoption name Hash value " .. Uci.HASH_MB)
    self:send("isready")
    return self
end

function Uci:send(line)
    if self.pipe then
        self.pipe:write(line, "\n")
        self.pipe:flush()
    end
end

function Uci:read_lines()
    local file = io.open(self.out_path, "rb")
    if not file then
        return {}
    end
    file:seek("set", self.offset)
    local chunk = file:read("*a") or ""
    file:close()
    self.offset = self.offset + #chunk
    local text = self.partial .. chunk
    local lines, last = {}, 1
    for line, stop in text:gmatch("([^\n]*)\n()") do
        lines[#lines + 1] = line
        last = stop
    end
    self.partial = text:sub(last)
    return lines
end

function Uci:set_option(name, value)
    self.options = self.options or {}
    if self.options[name] ~= value then
        self.options[name] = value
        self:send("setoption name " .. name .. " value " .. tostring(value))
    end
end

-- Reads an "info" line into the table of lines being kept: into[k] = { depth, cp, mate, move } for line k of MultiPV.
-- hist (optional) keeps every depth: hist[depth][k].
function Uci.read_info(line, into, hist)
    if not line:match("^info ") or line:find(" upperbound", 1, true) or line:find(" lowerbound", 1, true) then
        return false
    end
    local k = tonumber(line:match(" multipv (%d+)")) or 1
    local depth = tonumber(line:match(" depth (%d+)"))
    local cp = tonumber(line:match(" score cp (%-?%d+)"))
    local mate = tonumber(line:match(" score mate (%-?%d+)"))
    local move = line:match(" pv (%S+)")
    if not depth or not (cp or mate) or not move then
        return false
    end
    local old = into[k]
    if old and old.depth > depth then
        return true
    end
    into[k] = { depth = depth, cp = cp, mate = mate, move = move }
    if hist then
        hist[depth] = hist[depth] or {}
        hist[depth][k] = into[k]
    end
    return true
end

-- Starts a search of the position after `moves` (UCI, separated by spaces) from `fen`.
-- limits: { depth = d, nodes = n, movetime = ms, multipv = k } ; whichever limit comes first ends the search.
function Uci:search(fen, moves, limits)
    self.result = { lines = {}, hist = {} }
    self.searching = true
    self:set_option("MultiPV", math.max(1, limits.multipv or 1))
    self:send("position fen " .. fen .. (moves and moves ~= "" and (" moves " .. moves) or ""))
    local go = "go"
    if limits.depth then
        go = go .. " depth " .. math.floor(limits.depth)
    end
    if limits.nodes then
        go = go .. " nodes " .. math.floor(limits.nodes)
    end
    go = go .. " movetime " .. math.floor(limits.movetime or 5000)
    self:send(go)
end

-- Remembers how fast the engine is (nodes per second) from long enough searches. Always returns false, so the line
-- is still read as an info line.
function Uci:note_speed(line)
    if line:sub(1, 5) == "info " then
        local nps = tonumber(line:match(" nps (%d+)"))
        local nodes = tonumber(line:match(" nodes (%d+)"))
        if nps and nodes and nodes >= 20000 then
            self.nps = nps
        end
    end
    return false
end

-- nil while it thinks; then { lines = { [k] = {depth, cp, mate, move} }, best = "e2e4" or nil }.
function Uci:poll()
    if not self.searching then
        return nil
    end
    local answer
    for _, line in ipairs(self:read_lines()) do
        if line == Uci.ENDED then
            self.ended = true
        elseif line:match("^id name ") then
            self.name = line:match("^id name (.+)$")
        elseif (self.dropped or 0) > 0 then
            if line:match("^bestmove ") then
                self.dropped = self.dropped - 1
            end
        elseif not answer and not self:note_speed(line) and not Uci.read_info(line, self.result.lines, self.result.hist) then
            local best = line:match("^bestmove (%S+)")
            if best then
                self.searching = false
                self.result.best = best ~= "(none)" and best or nil
                answer = self.result
            end
        end
    end
    return answer
end

-- Drops the search under way; the bestmove it still sends is skipped.
function Uci:cancel()
    if self.searching then
        self:send("stop")
        self.searching = false
        self.dropped = (self.dropped or 0) + 1
    end
end

function Uci:alive()
    local file = io.open(self.pid_path, "rb")
    local pid = file and tonumber(file:read("*a"))
    if file then
        file:close()
    end
    if not pid then
        return false
    end
    local result = os.execute(string.format("kill -0 %d 2>/dev/null", pid))
    return result == 0 or result == true
end

-- Ends the process: asked to quit, then killed, so closing never waits on it.
function Uci:stop()
    if not self.pipe then
        return
    end
    self:send("quit")
    local file = io.open(self.pid_path, "rb")
    local pid = file and tonumber(file:read("*a"))
    if file then
        file:close()
    end
    if pid then
        os.execute(string.format("kill -9 %d 2>/dev/null", pid))
    end
    self.pipe:close()
    self.pipe = nil
    os.remove(self.out_path)
    os.remove(self.pid_path)
end

return Uci
