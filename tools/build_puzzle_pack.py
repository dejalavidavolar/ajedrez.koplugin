#!/usr/bin/env python3
"""Builds a Ajedrez puzzle pack from the Lichess puzzle database (CC0).

  1. Download https://database.lichess.org/lichess_db_puzzle.csv.zst  (about 250 MB, ~5 million puzzles)
  2. python3 tools/build_puzzle_pack.py lichess_db_puzzle.csv.zst puzzles.txt
     (needs `zstd` installed for .zst files; a plain .csv works without it, and "-" reads stdin)
  3. Copy puzzles.txt AND puzzles.txt.idx to  <koreader>/data/ajedrez/  on the e-reader (it survives plugin updates
     and is used instead of the small pack that comes inside the plugin).

Options: --min-popularity N (default 80, Lichess's own "good puzzle" signal), --max-deviation N (default 110),
--max N (keep at most N puzzles, spread evenly over all ratings).
Output: first line "#caissa-puzzles v1 count=N", then "id|FEN|moves|rating|themes" sorted by rating (about 100-130 bytes each; the themes
are what the screen uses to name the exercise: opening, middlegame, endgame, mate in N).
"""
import argparse, csv, subprocess, sys, io


def open_input(path):
    if path == "-":
        return io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", newline="")
    if path.endswith(".zst"):
        proc = subprocess.Popen(["zstd", "-dc", path], stdout=subprocess.PIPE)
        return io.TextIOWrapper(proc.stdout, encoding="utf-8", newline="")
    return open(path, encoding="utf-8", newline="")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--min-popularity", type=int, default=80)
    ap.add_argument("--max-deviation", type=int, default=110)
    ap.add_argument("--max", type=int, default=0)
    a = ap.parse_args()
    rows = []
    for r in csv.DictReader(open_input(a.input)):
        try:
            if int(r["Popularity"]) < a.min_popularity or int(r["RatingDeviation"]) > a.max_deviation:
                continue
            rows.append((int(r["Rating"]), r["PuzzleId"], r["FEN"], r["Moves"], r.get("Themes", "")))
        except (KeyError, ValueError):
            continue
    rows.sort()
    if a.max and len(rows) > a.max:
        step = len(rows) / a.max
        rows = [rows[int(i * step)] for i in range(a.max)]
    # Besides the pack, <output>.idx: the byte offset of every 1000th puzzle, so the plugin finds the number
    # (position) of a puzzle without reading the whole file. Copy both files together.
    offsets, at = [], 0
    with open(a.output, "w", encoding="utf-8", newline="\n") as o:
        header = "#caissa-puzzles v1 count=%d\n" % len(rows)
        o.write(header)
        at = len(header.encode("utf-8"))
        for i, (rating, pid, fen, moves, themes) in enumerate(rows):
            line = "%s|%s|%s|%d|%s\n" % (pid, fen, moves, rating, themes) if themes else "%s|%s|%s|%d\n" % (pid, fen, moves, rating)
            if i % 1000 == 0:
                offsets.append(at)
            o.write(line)
            at += len(line.encode("utf-8"))
    with open(a.output + ".idx", "w", newline="\n") as o:
        o.write("\n".join(str(x) for x in offsets) + "\n")
    print("%d puzzles, ratings %d-%d" % (len(rows), rows[0][0] if rows else 0, rows[-1][0] if rows else 0))


main()
