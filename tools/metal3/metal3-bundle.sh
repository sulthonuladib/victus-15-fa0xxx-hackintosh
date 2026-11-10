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
  # Measured 2026-11-10: an ad-hoc signed bundle is rejected by AMFI's library validation inside
  # WindowServer ("Error loading /Library/..." + AppleMobileFileIntegrity library_validation),
  # WindowServer dies and the screen goes black while sshd keeps running. The stock bundle is signed
  # with OCLP's "Mod Software Signing" identity, which is why it loads. Only install ad-hoc builds
  # when `amfi_get_out_of_my_way=1` is in the boot-args, or when the signer matches the stock one.
  if ! codesign -dv "$BUILT" 2>&1 | grep -q "Authority=OCLP Hackintosh Mod"; then
    if ! nvram boot-args 2>/dev/null | grep -q "amfi_get_out_of_my_way=1"; then
      echo "STOP: $BUILT is not Mod-signed and amfi_get_out_of_my_way=1 is not in boot-args." >&2
      echo "      WindowServer will reject it (library validation) and the GUI will not come back." >&2
      echo "      Recovery is ssh only. Set the boot-arg or sign with the Mod identity first," >&2
      echo "      or force with: FORCE=1 $0 install" >&2
      [ "${FORCE:-0}" = 1 ] || exit 1
      echo "      FORCE=1: installing anyway"
    fi
  fi
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
watch)
  # watch [minutes] - sample WindowServer RSS every 15 s and report the growth rate.
  mins=${2:-5}
  pid=$(pgrep -x WindowServer)
  start=$(ps -o rss= -p "$pid" | tr -d ' ')
  say "== WindowServer pid $pid, sampling for ${mins} min"
  for i in $(seq 1 $((mins*4))); do
    sleep 15
    now=$(ps -o rss= -p "$pid" | tr -d ' ')
    printf '   t+%3ds  %.1f MB\n' $((i*15)) "$(echo "scale=1; $now/1024" | bc)"
  done
  end=$(ps -o rss= -p "$pid" | tr -d ' ')
  rate=$(echo "scale=1; ($end-$start)/1024/($mins)" | bc)
  say "== growth: $rate MB/min (leak baseline was ~196 MB/min with the unpatched driver)"
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
