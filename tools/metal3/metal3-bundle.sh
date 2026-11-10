#!/bin/bash
# metal3-bundle.sh - build / install / restore the patched Metal driver bundle.
#
#   tools/metal3/metal3-bundle.sh build     apply the XPS driver patches to the installed bundle
#   tools/metal3/metal3-bundle.sh install   install the built bundle into /Library/GPUBundles
#   tools/metal3/metal3-bundle.sh restore   put the stock (Metal 2) bundle back
#   tools/metal3/metal3-bundle.sh status    what is live, plus the WindowServer leak baseline
#
# It only ever touches /Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle. WhateverXe's kernel
# kext, the .kexts and the EFI are untouched. The stock bundle is kept on the utility drive.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$ROOT/tools/metal3
WORK=${XPS_WORK:-$HOME/xpsbuild}
BUNDLE=AppleIntelTGLGraphicsMTLDriver.bundle
LIVE=/Library/GPUBundles/$BUNDLE
BACKUP=/Volumes/macUtility/whateverxe/mtl3-backup  # exFAT: readable from Linux if a boot goes wrong
BUILT=$WORK/mtl-xps/$BUNDLE

say() { printf '%s\n' "$*"; }
need_root() { [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }; }

case ${1:-status} in
build)
  [ -d "$LIVE" ] || { echo "$LIVE missing" >&2; exit 1; }
  mkdir -p "$WORK/mtl-xps"
  say "== patching a copy of the installed bundle"
  python3 "$HERE/apply-xps-patches.py" "$LIVE" "$BUILT" --patches "${PATCHES:-2,3,4,5,6,7,8,9}" --sign
  say "== built $BUILT"
  ;;
install)
  need_root
  [ -d "$BUILT" ] || { echo "nothing built: run '$0 build' first" >&2; exit 1; }
  if [ ! -d "$BACKUP/$BUNDLE.orig" ]; then
    mkdir -p "$BACKUP"; cp -R "$LIVE" "$BACKUP/$BUNDLE.orig"
    say "== stock bundle backed up to $BACKUP/$BUNDLE.orig"
  fi
  rm -rf "$LIVE" && cp -R "$BUILT" "$LIVE"
  # FAT/exFAT loses unix modes and ownership: Metal clients must be able to read/traverse it
  chown -R root:wheel "$LIVE"; chmod -R u+rwX,go+rX "$LIVE"
  say "== installed patched bundle"
  say "   restart WindowServer (logout/login or reboot) for it to take effect in the GUI"
  ;;
restore)
  need_root
  [ -d "$BACKUP/$BUNDLE.orig" ] || { echo "no backup in $BACKUP" >&2; exit 1; }
  rm -rf "$LIVE" && cp -R "$BACKUP/$BUNDLE.orig" "$LIVE"
  chown -R root:wheel "$LIVE"; chmod -R u+rwX,go+rX "$LIVE"
  say "== restored the stock bundle (Metal 2)"
  ;;
status)
  say "== live bundle"
  shasum -a 256 "$LIVE/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver" 2>/dev/null | cut -c1-24
  codesign -dv "$LIVE" 2>&1 | grep -E "Signature|Authority" | head -2 || true
  say "== WindowServer RSS / uptime (the 96 KB-per-command-buffer leak shows here)"
  ps -o rss=,etime= -p "$(pgrep -x WindowServer)" 2>/dev/null | awk '{printf "   %.1f MB, up %s\n", $1/1024, $2}'
  say "== display-pipe underruns since boot"
  say "   $(log show --last boot --predicate 'process == "kernel" AND eventMessage CONTAINS "Underrun"' 2>/dev/null | grep -c Underrun)"
  say "== Metal families + Metal 3 feature calls"
  if [ -x "$HERE/probe" ]; then "$HERE/probe"; else say "   (build it: clang -fobjc-arc -O1 -o $HERE/probe $HERE/probe.m -framework Foundation -framework Metal)"; fi
  ;;
*)
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
