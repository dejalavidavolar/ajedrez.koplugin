#!/usr/bin/env python3
# A stand-in for Stockfish for the tests: answers UCI with the candidate moves given in FAKE_PV
# ("e2e4:35,d2d4:30,..." = move:centipawns, best first). FAKE_PV="crash" makes it exit on the first "go".
import os, sys
multipv = 1
seq = [m for m in os.environ.get("FAKE_SEQ","").split(",") if m]
calls = 0
for line in sys.stdin:
    line = line.strip()
    if line == "uci":
        print("id name FakeFish 1.0"); print("uciok")
    elif line.startswith("setoption") and "MultiPV" in line:
        multipv = int(line.split("value")[1])
    elif line == "isready":
        print("readyok")
    elif line.startswith("go"):
        spec = os.environ.get("FAKE_PV", "e2e4:35,d2d4:30")
        if seq:
            spec = seq[min(calls, len(seq) - 1)] + ":10"
            calls += 1
        if spec == "flaky":
            flag = "/tmp/ajedrez-flaky-flag"
            if not os.path.exists(flag):
                open(flag, "w").close()
                sys.exit(1)
            spec = "e2e4:35,d2d4:30"
        if spec == "crash":
            sys.exit(1)
        cands = [c.split(":") for c in spec.split(",")][:multipv]
        limit = line.split("depth ")[1].split()[0] if "depth " in line else "2"
        open(os.environ.get("FAKE_LOG", "/dev/null"), "a").write(line + " multipv=%d\n" % multipv)
        for depth in range(1, min(int(limit), 6) + 1):
            for k, (mv, cp) in enumerate(cands, 1):
                if mv.startswith("#"):
                    score = "mate " + mv[1:].split("=")[0]
                else:
                    score = "cp " + cp
                print("info depth %d seldepth %d multipv %d score %s nodes 100 pv %s" % (depth, depth, k, score, mv.split("=")[-1] if mv.startswith("#") else mv))
        sys.stdout.flush()
        first = cands[0][0]
        print("bestmove " + (first.split("=")[-1] if first.startswith("#") else first))
    elif line == "quit":
        break
    sys.stdout.flush()
