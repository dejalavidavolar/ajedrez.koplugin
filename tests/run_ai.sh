#!/bin/sh
# Runs the AI scenarios against a fake UCI engine. Needs a Lua runner: LUA=/path/to/lua sh tests/run_ai.sh
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua}
FAKE="$PWD/tests/fake_engine.py"
fail=0
run() { # name, FAKE_PV
    AJEDREZ_STOCKFISH="$FAKE" FAKE_PV="$2" "$LUA" tests/test_ai.lua "$1" || fail=1
}
run basics "e2e4:35,d2d4:30"
run strong "e2e4:35,d2d4:30,c2c4:-50,a2a3:-400,h2h4:-600"
run weak "e2e4:35,d2d4:30,c2c4:-50,a2a3:-90,b2b3:-40,h2h3:-20,g2g3:-120,d2d3:-60,e2e3:-45,b1c3:-10"
run mate "#1=e2e4:0,d2d4:30,c2c4:-50"
run crash "crash"
run flaky "flaky"
AJEDREZ_STOCKFISH=/nonexistent "$LUA" tests/test_ai.lua none || fail=1
exit $fail
