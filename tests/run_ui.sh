#!/bin/sh
# Drives the screens with stubs for KOReader. Needs a Lua runner: LUA=/path/to/lua sh tests/run_ui.sh
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua}
AJEDREZ_STOCKFISH="$PWD/tests/fake_engine.py" FAKE_SEQ="e7e5,d8h4,e7e5" "$LUA" tests/test_ui.lua
