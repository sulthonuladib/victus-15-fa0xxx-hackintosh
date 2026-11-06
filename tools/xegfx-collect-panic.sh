#!/bin/bash
# xegfx-collect-panic.sh - collect the evidence for an XeGfx stage-4 panic.
#
# Run on macOS after the panic (a normal boot is fine; XeGfx does not load itself):
#
#   sudo bash /Volumes/macUtility/scripts/xegfx/xegfx-collect-panic.sh
#
# It only reads. It does not load XeGfx, write the EFI, or contact GitHub.
# Output:
#   /Users/Shared/xegfx-panic/<stamp>/raw/     exact copies (local only)
#   /Users/Shared/xegfx-panic/<stamp>/report/  redacted copies + REPORT-DRAFT.md
#   /Users/Shared/xegfx-panic/<stamp>/xegfx-panic-<stamp>.tgz  (report/ only)
#
# Review report/ before attaching anything. Do not post raw/.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUTBASE=${XEGFX_PANIC_OUT:-/Users/Shared/xegfx-panic}
STAMP=$(date +%Y%m%d-%H%M%S)
DIR="$OUTBASE/$STAMP"
RAW="$DIR/raw"
REP="$DIR/report"
SRC=${XEGFX_SRC:-}

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*" >&2; }
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "run this inside macOS, not Linux."
[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"

CONSOLE_USER=$(stat -f %Su /dev/console 2>/dev/null || echo "$USER")
USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -n "${USER_HOME:-}" ] || USER_HOME=${HOME:-/var/root}
[ -n "$SRC" ] || SRC="$USER_HOME/src"
MACEFI=/Volumes/MACEFI
PANICDIR=/Library/Logs/DiagnosticReports
PROBEDIR=/Users/Shared/xegfx-reports
BOOTDUMP=/Users/Shared/bootdump

mkdir -p "$RAW"/{panic,probe,bootdump,build,install,efi,logs,scripts}
mkdir -p "$REP"
say "collecting into $DIR"
say "user: $CONSOLE_USER ($USER_HOME)"

# ---- environment ------------------------------------------------------------
{
  date
  sw_vers
  uname -a
  sysctl -n machdep.cpu.brand_string 2>/dev/null || true
  sysctl -n hw.model 2>/dev/null || true
  echo
  echo "## boot-args / csr"
  nvram -p 2>/dev/null | grep -Ei 'boot-args|csr-active-config' || true
  echo
  echo "## loaded kexts"
  kmutil showloaded 2>/dev/null | grep -Ei 'watchthelight|XeGfx|NMIntelFB|NVRM|NVAccel|WhateverGreen|IONDRVSupport|AppleIntel' || true
  echo
  echo "## AuxKC XeGfx/NVIDIA entries"
  kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null \
    | grep -Ei 'watchthelight|XeGfx|NMIntelFB|NVRM|NVAccel' || true
  echo
  echo "## /Library/Extensions"
  ls -1 /Library/Extensions 2>/dev/null || true
} > "$RAW/logs/environment.txt" 2>&1

# ---- hardware and display ---------------------------------------------------
{
  ioreg -l -w0 -r -n IGPU 2>/dev/null || ioreg -l -w0 -r -n GFX0 2>/dev/null || true
  echo
  ioreg -l -w0 -r -c XeGfxResident 2>/dev/null || true
  echo
  ioreg -l -w0 -r -c XeGfxGt 2>/dev/null || true
  echo
  ioreg -l -w0 -r -c IOAccelerator 2>/dev/null || true
} | grep -vE 'IOPlatformSerialNumber|IOPlatformUUID|Serial Number|Hardware UUID' > "$RAW/logs/ioreg-gpu.txt" 2>&1

system_profiler SPDisplaysDataType 2>/dev/null | grep -vE 'Serial Number|Hardware UUID' > "$RAW/logs/displays.txt" 2>&1 || true
sysctl -a 2>/dev/null | grep -i 'xegfx' > "$RAW/logs/xegfx-sysctl.txt" 2>&1 || true
sysctl -b debug.xegfx_log > "$RAW/logs/xegfx-log.bin" 2>/dev/null || true
dmesg 2>/dev/null | tail -300 > "$RAW/logs/dmesg-tail.txt" 2>&1 || true
log show --last boot --style compact --predicate 'process == "kernel"' 2>/dev/null \
  | tail -400 > "$RAW/logs/kernel-current-boot.txt" 2>&1 || true

# ---- panic reports ----------------------------------------------------------
say "panic reports"
if [ -d "$PANICDIR" ]; then
  find "$PANICDIR" -maxdepth 2 -type f -name '*.panic' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -3 | while IFS= read -r f; do
        cp -a "$f" "$RAW/panic/" 2>/dev/null && say "  $(basename "$f")"
      done
fi
[ -d "$PANICDIR/Retired" ] && find "$PANICDIR/Retired" -type f -name '*.panic' -print0 2>/dev/null \
  | xargs -0 ls -t 2>/dev/null | head -2 | while IFS= read -r f; do
      cp -a "$f" "$RAW/panic/" 2>/dev/null && say "  $(basename "$f")"
    done

# ---- XeGfx probe reports ---------------------------------------------------
say "probe reports"
if [ -d "$PROBEDIR" ]; then
  ls -dt "$PROBEDIR"/*/ 2>/dev/null | head -3 | while IFS= read -r d; do
    [ -d "$d" ] || continue
    cp -a "$d" "$RAW/probe/" 2>/dev/null && say "  $(basename "$d")"
  done
  ls -dt "$PROBEDIR"/*.tgz 2>/dev/null | head -1 | while IFS= read -r f; do
    cp -a "$f" "$RAW/probe/" 2>/dev/null && say "  $(basename "$f")"
  done
fi

# ---- bootdump (previous boot is the interesting one) -----------------------
if [ -d "$BOOTDUMP" ]; then
  say "bootdump"
  ls -dt "$BOOTDUMP"/*/ 2>/dev/null | head -2 | while IFS= read -r d; do
    [ -d "$d" ] || continue
    dst="$RAW/bootdump/$(basename "$d")"
    mkdir -p "$dst"
    find "$d" -maxdepth 1 -type f \( -name '00-info.txt' -o -name 'dmesg-*.txt' \
      -o -name 'sysctl-debug-*.txt' -o -name 'ioreg-*.txt' -o -name 'ws-*.txt' \) \
      -exec cp -a {} "$dst/" \; 2>/dev/null
    say "  $(basename "$d")"
  done
fi

# ---- build and installed kext ---------------------------------------------
say "build"
if [ -d "$SRC/WTLIntelGfx" ]; then
  git -C "$SRC/WTLIntelGfx" describe --tags --always > "$RAW/build/source.txt" 2>&1 || true
  git -C "$SRC/WTLIntelGfx" status --porcelain > "$RAW/build/source-status.txt" 2>&1 || true
  [ -f "$SRC/WTLIntelGfx/tools/link.sh" ] && [ -f "$SRC/WTLIntelGfx/tools/link.sh.pre-adlp" ] \
    && diff -u "$SRC/WTLIntelGfx/tools/link.sh.pre-adlp" "$SRC/WTLIntelGfx/tools/link.sh" > "$RAW/build/link-sh.diff" 2>&1 || true
  for f in "$SRC/WTLIntelGfx"/out/*.log "$SRC/WTLIntelGfx"/out/*.err "$SRC/WTLIntelGfx"/out/score.log; do
    [ -f "$f" ] && cp -a "$f" "$RAW/build/" 2>/dev/null
  done
  if [ -d "$SRC/WTLIntelGfx/out/XeGfx.kext" ]; then
    plutil -p "$SRC/WTLIntelGfx/out/XeGfx.kext/Contents/Info.plist" > "$RAW/build/XeGfx-Info.txt" 2>&1 || true
    ls -la "$SRC/WTLIntelGfx/out/XeGfx.kext/Contents/Resources" > "$RAW/build/XeGfx-Resources.txt" 2>&1 || true
    shasum -a 256 "$SRC/WTLIntelGfx/out/XeGfx.kext/Contents/MacOS/XeGfx" \
      "$SRC/WTLIntelGfx/out/XeGfx.kext/Contents/Resources"/*_guc_70.bin 2>/dev/null > "$RAW/build/hashes.txt" || true
  fi
fi

say "installed"
ls -la /Library/Extensions 2>/dev/null > "$RAW/install/extensions.txt" 2>&1 || true
for k in XeGfx XeGfxAccel XeGfxAGDC XeGfxIntelFB NMIntelFB; do
  [ -d "/Library/Extensions/$k.kext" ] || continue
  plutil -p "/Library/Extensions/$k.kext/Contents/Info.plist" > "$RAW/install/$k-Info.txt" 2>&1 || true
  ls -la "/Library/Extensions/$k.kext/Contents/Resources" > "$RAW/install/$k-Resources.txt" 2>&1 || true
  shasum -a 256 "/Library/Extensions/$k.kext/Contents/MacOS/"* 2>/dev/null >> "$RAW/install/hashes.txt" || true
done
[ -d /Library/XeGfx ] && ls -laR /Library/XeGfx > "$RAW/install/xegfx-backups.txt" 2>&1 || true
kmutil showloaded 2>/dev/null > "$RAW/install/showloaded.txt" || true

# ---- EFI summary and OpenCore logs ----------------------------------------
if [ -f "$MACEFI/EFI/OC/config.plist" ]; then
  say "EFI summary"
  python3 - "$MACEFI/EFI/OC/config.plist" "$RAW/efi/summary.txt" <<'PY' 2>/dev/null || true
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
g = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
out = []
out.append("boot-args: " + str(p["NVRAM"]["Add"][g].get("boot-args")))
out.append("csr-active-config: " + repr(p["NVRAM"]["Add"][g].get("csr-active-config")))
out.append("SecureBootModel: " + str(p["Misc"]["Security"].get("SecureBootModel")))
out.append("DeviceProperties keys: " + ", ".join(p["DeviceProperties"]["Add"]))
out.append("Kernel Block: " + repr(p["Kernel"]["Block"]))
out.append("Kernel Add:")
for k in p["Kernel"]["Add"]:
    out.append("  %s enabled=%s" % (k["BundlePath"], k["Enabled"]))
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
  ls -t "$MACEFI"/opencore-*.txt 2>/dev/null | head -2 | while IFS= read -r f; do
    cp -a "$f" "$RAW/efi/" 2>/dev/null
  done
  for f in "$MACEFI"/panic-*.txt; do [ -f "$f" ] && cp -a "$f" "$RAW/efi/" 2>/dev/null; done
fi

# ---- scripts and manifest --------------------------------------------------
for f in "$HERE"/xegfx-patch-guc.sh "$HERE"/xegfx-build-kernel.sh "$HERE"/xegfx-install.sh \
         "$HERE"/xegfx-probe.sh "$HERE"/RUNBOOK.md; do
  [ -f "$f" ] && cp -a "$f" "$RAW/scripts/" 2>/dev/null
done
( cd "$RAW" && find . -type f -exec shasum -a 256 {} \; ) > "$DIR/MANIFEST.sha256" 2>&1 || true

# ---- redacted report copy --------------------------------------------------
cp -a "$RAW/." "$REP/" 2>/dev/null || true
HOST=$(scutil --get ComputerName 2>/dev/null || hostname 2>/dev/null || true)
COMPUTER=$(scutil --get LocalHostName 2>/dev/null || true)
FILES=$(find "$REP" -type f \( -name '*.txt' -o -name '*.log' -o -name '*.md' -o -name '*.panic' -o -name '*.diff' \) 2>/dev/null)
if [ -n "$FILES" ]; then
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    perl -pi -e 's{/Users/[^/\s]+}{/Users/<user>}g; s{(IOPlatformSerialNumber"\s*=\s*")[^"]+}{$1<redacted>}g; s{(IOPlatformUUID"\s*=\s*")[^"]+}{$1<redacted>}g; s{(Serial Number:\s*).*}{$1<redacted>}g; s{(Hardware UUID:\s*).*}{$1<redacted>}g; s{\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b}{<mac>}g; s{\bBSSID=[0-9A-Fa-f:]+}{BSSID=<redacted>}g; s{\bssid\[\d+\]=.*}{ssid=<redacted>}g; s{\b(?:10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}|192\.168\.(?:[0-9]{1,3}\.)[0-9]{1,3}|172\.(?:1[6-9]|2[0-9]|3[01])\.(?:[0-9]{1,3}\.)[0-9]{1,3})\b}{<ip>}g' "$f" 2>/dev/null || true
    [ -n "$HOST" ] && perl -pi -e "s/\Q$HOST\E/<host>/g" "$f" 2>/dev/null || true
    [ -n "$COMPUTER" ] && perl -pi -e "s/\Q$COMPUTER\E/<host>/g" "$f" 2>/dev/null || true
  done
fi

# ---- summary and paste-ready draft ----------------------------------------
PANIC_FILE=$(ls -t "$RAW"/panic/*.panic 2>/dev/null | head -1 || true)
PANIC_TEXT=""
if [ -n "$PANIC_FILE" ] && [ -f "$PANIC_FILE" ]; then
  PANIC_TEXT=$(python3 - "$PANIC_FILE" <<'PY' 2>/dev/null || true
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
dec = json.JSONDecoder()
i = 0
while i < len(text):
    while i < len(text) and text[i].isspace():
        i += 1
    if i >= len(text):
        break
    try:
        obj, end = dec.raw_decode(text, i)
    except Exception:
        break
    if isinstance(obj, dict):
        s = obj.get("macOSPanicString") or obj.get("panicString")
        if s:
            print(s)
            break
    i = end
PY
)
fi
if [ -z "$PANIC_TEXT" ] && [ -n "$PANIC_FILE" ] && [ -f "$PANIC_FILE" ]; then
  PANIC_TEXT=$(sed -n '1,160p' "$PANIC_FILE" 2>/dev/null || true)
fi
printf '%s\n' "$PANIC_TEXT" | sed -n '1,100p' > "$REP/panic-excerpt.txt" 2>/dev/null || true

MODEL=$(sysctl -n hw.model 2>/dev/null || true)
CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
MACOS=$(sw_vers -productVersion 2>/dev/null || true)
BUILD=$(sw_vers -buildVersion 2>/dev/null || true)
BOOTARGS=$(nvram -p 2>/dev/null | grep -i 'boot-args' | head -1 | sed 's/^boot-args[[:space:]]*//' || true)
DEVICE=$(ioreg -l -w0 -r -n IGPU 2>/dev/null | grep -m1 '"device-id"' | tr -d '\t' || true)
SRC_REV=$(git -C "$SRC/WTLIntelGfx" describe --tags --always 2>/dev/null || true)
KEXT_SHA=$(shasum -a 256 "$SRC/WTLIntelGfx/out/XeGfx.kext/Contents/MacOS/XeGfx" 2>/dev/null | awk '{print $1}' || true)
GUC_SHA=$(shasum -a 256 /Library/Extensions/XeGfx.kext/Contents/Resources/adlp_guc_70.bin 2>/dev/null | awk '{print $1}' || true)

cat > "$REP/REPORT-DRAFT.md" <<EOF
# XeGfx stage 4 panic — HP Victus 15-fa0xxx (Alder Lake-P 46A6)

**Draft only. Not posted. Review this and the redaction checklist first.**

## Hardware

- Model: HP Victus 15-fa0xxx / ${MODEL:-8A4F}
- CPU: ${CPU:-Intel Core i7-12700H}
- iGPU: Intel Iris Xe \`8086:46A6\`, Alder Lake-P, 96 EU ${DEVICE:-}
- dGPU: NVIDIA RTX 3050 Mobile \`10DE:25A2\` (NullMoth 1401 driver, HDMI path)
- Display: CMN1521 internal eDP, wired to the Intel iGPU
- macOS: ${MACOS:-26.7.1} (${BUILD:-25G241}), x86_64
- OpenCore: MACEFI, XeGfx test shape (real 46A6, no spoof, no WhateverGreen)
- Boot args: \`${BOOTARGS:-see raw/logs/environment.txt}\`

## XeGfx build

- Source: WTLIntelGfx \`${SRC_REV:-v0.0.47}\`
- Kext: \`${KEXT_SHA:-see raw/build/hashes.txt}\`
- Alder Lake GuC: \`adlp_guc_70.bin\` v70.49.4, sha256 \`${GUC_SHA:-see raw/build/hashes.txt}\`
- Local patch: \`tools/link.sh\` embeds \`adlp_guc_70.bin\` and copies the blobs +
  \`LICENSE.i915\` into \`XeGfx.kext/Contents/Resources\` (upstream v0.0.47 only links
  \`mtl_guc_70.bin\`).
- Install: \`xegfx-install.sh --kernel-only\`, AuxKC rebuilt, rebooted, \`kmutil load
  -b org.watchthelight.XeGfx\`.

## What was run

\`\`\`sh
sudo bash /Volumes/macUtility/scripts/xegfx/xegfx-probe.sh --stage 4 --yes
\`\`\`

The read-only stages passed before this (stage 2 and 3 in the saved probe bundle;
stage 1 was not run there). Stage 4 started i915; the machine got stuck and then
panicked. The panic report and the probe bundle are attached.

## Panic

\`\`\`text
$(sed -n '1,80p' "$REP/panic-excerpt.txt" 2>/dev/null || echo "(see panic/ and logs/)")
\`\`\`

## Evidence

- \`panic/\` — latest macOS panic reports
- \`probe/\` — XeGfx probe report(s), including \`run.log\` and \`20-log.txt\`
- \`bootdump/\` — WTLBootDump snapshots, if installed
- \`build/\` — source revision, \`link.sh\` diff, build logs, GuC/kext hashes
- \`install/\` — installed kexts, AuxKC entries, backups
- \`efi/summary.txt\` — boot-args/CSR/kext list only; no serials
- \`logs/\` — environment, GPU IORegistry, current-boot kernel tail

## Notes

- The EFI is unchanged by the probe; a power cycle recovers. This is a driver
  bring-up panic, not a boot-loader failure.
- The Alder Lake GuC link is a local addition over upstream v0.0.47; stages 1–3 are
  upstream-safe, stage 4 is experimental on 46A6.
- Please say what else would help narrow this down.
EOF

cat > "$REP/REDACTION-REVIEW.md" <<'EOF'
# Review before posting

`raw/` is unredacted and is **local only**. `report/` and the `.tgz` are the redacted
copies. The script replaces user paths, platform serial/UUID fields, display serials,
MAC addresses and IPv4 addresses, and the computer/host name.

Still check by hand:
- panic/ and probe/ text for host names, SSIDs, IPs or account names;
- ioreg[/PCI] and bootdump files for display/EDID serials or USB serials;
- any image/screenshot you add;
- the report draft for anything machine-specific you do not want public.

Do not post until the maintainer asks for this run and you have reviewed it.
EOF

cat > "$REP/SUMMARY.txt" <<EOF
XeGfx panic collection
stamp: $STAMP
host: ${HOST:-unknown}
macOS: ${MACOS:-?} (${BUILD:-?})
CPU: ${CPU:-?}
model: ${MODEL:-?}
panic: ${PANIC_FILE:-none found}
source: ${SRC_REV:-?}
report: $REP
draft: $REP/REPORT-DRAFT.md
EOF

# These files are created after the first redaction pass; redact them too.
for f in "$REP/REPORT-DRAFT.md" "$REP/panic-excerpt.txt" "$REP/SUMMARY.txt"; do
  [ -f "$f" ] || continue
  perl -pi -e 's{/Users/[^/\s]+}{/Users/<user>}g; s{(IOPlatformSerialNumber"\s*=\s*")[^"]+}{$1<redacted>}g; s{(IOPlatformUUID"\s*=\s*")[^"]+}{$1<redacted>}g; s{(Serial Number:\s*).*}{$1<redacted>}g; s{(Hardware UUID:\s*).*}{$1<redacted>}g; s{\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b}{<mac>}g; s{\bBSSID=[0-9A-Fa-f:]+}{BSSID=<redacted>}g; s{\bssid\[\d+\]=.*}{ssid=<redacted>}g; s{\b(?:10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}|192\.168\.(?:[0-9]{1,3}\.)[0-9]{1,3}|172\.(?:1[6-9]|2[0-9]|3[01])\.(?:[0-9]{1,3}\.)[0-9]{1,3})\b}{<ip>}g' "$f" 2>/dev/null || true
  [ -n "$HOST" ] && perl -pi -e "s/\Q$HOST\E/<host>/g" "$f" 2>/dev/null || true
  [ -n "$COMPUTER" ] && perl -pi -e "s/\Q$COMPUTER\E/<host>/g" "$f" 2>/dev/null || true
done

# ---- archive and ownership -------------------------------------------------
( cd "$DIR" && COPYFILE_DISABLE=1 tar -czf "xegfx-panic-$STAMP.tgz" report ) 2>/dev/null || true
chown -R "$CONSOLE_USER":staff "$DIR" 2>/dev/null || true

say ""
say "raw:    $RAW   (unredacted, do not upload)"
say "report: $REP"
say "draft:  $REP/REPORT-DRAFT.md"
[ -f "$DIR/xegfx-panic-$STAMP.tgz" ] && say "attach: $DIR/xegfx-panic-$STAMP.tgz"
say ""
say "Review report/ before posting. Nothing was uploaded."
