#!/bin/sh
# Cross-compiles a recent Stockfish for 32-bit ARM Linux (Kobo, e.g. Libra Colour) on a Linux PC.
# Needs: git, make, and the cross compiler  (Debian/Ubuntu: sudo apt install g++-arm-linux-gnueabihf)
#
#   sh tools/build_stockfish_kobo.sh [tag]        e.g. sf_18  (default: master)
#
# Result: ./stockfish-kobo  (+ the .nnue network files next to it when the build downloads them).
# Copy all of it to  <koreader>/data/ajedrez/  on the e-reader and rename the binary to "stockfish"
# (Ajedrez looks for  data/ajedrez/stockfish  before the Stockfish 11 that comes inside the plugin).
# The binary must be static, hard-float, with NEON:  file stockfish-kobo  ->  "ELF 32-bit ... ARM ... statically linked".
set -e
TAG=${1:-master}
[ -d Stockfish ] || git clone https://github.com/official-stockfish/Stockfish.git
cd Stockfish
git checkout "$TAG"
cd src
make -j"$(nproc)" build ARCH=armv7-neon COMP=gcc CXX=arm-linux-gnueabihf-g++ \
     EXTRACXXFLAGS="-static" EXTRALDFLAGS="-static" || {
  echo "If NNUE networks fail to embed, run 'make net' first, or build with ARCH=armv7 (no NEON)."; exit 1; }
cp stockfish ../../stockfish-kobo
cp -n *.nnue ../../ 2>/dev/null || true
echo "done: $(file ../../stockfish-kobo)"
