-- Shared by the tests: paths, a tiny scheduler that stands in for UIManager:scheduleIn, assertions.
local H = {}
H.root = arg[0]:match("^(.*)/tests/[^/]*$") or "."
package.path = H.root .. "/?.lua;" .. package.path

local failures, count = 0, 0
function H.check(cond, message)
    count = count + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. tostring(message))
    end
end
function H.eq(a, b, message)
    H.check(a == b, string.format("%s (got %s, wanted %s)", message, tostring(a), tostring(b)))
end
function H.near(a, b, tol, message)
    H.check(math.abs(a - b) <= tol, string.format("%s (got %s, wanted %s +-%s)", message, tostring(a), tostring(b), tostring(tol)))
end
function H.done(name)
    print(string.format("%s: %d checks, %d failures", name, count, failures))
    os.exit(failures == 0 and 0 or 1)
end

-- scheduler
H.queue = {}
function H.schedule(seconds, fn)
    H.queue[#H.queue + 1] = { at = os.clock() + seconds, fn = fn }
    return fn
end
function H.unschedule(fn)
    for i = #H.queue, 1, -1 do
        if H.queue[i].fn == fn then
            table.remove(H.queue, i)
        end
    end
end
-- Runs the queue until `stop()` is true or it runs dry or the time is up.
function H.run(stop, limit_seconds)
    local t0 = os.time()
    while #H.queue > 0 and not stop() and os.time() - t0 < (limit_seconds or 20) do
        table.sort(H.queue, function(a, b) return a.at < b.at end)
        local item = table.remove(H.queue, 1)
        os.execute("sleep 0.02")
        item.fn()
    end
end
return H
