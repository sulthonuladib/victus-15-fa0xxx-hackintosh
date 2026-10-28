#!/usr/bin/env bash
# deploy-efi.sh - copy EFI/ to the MACEFI partition, keeping the private identity out of git.
#
#   ./tools/deploy-efi.sh --capture    read the identity from the deployed config into
#                                      EFI/OC/identity.plist (git-ignored), write nothing else
#   ./tools/deploy-efi.sh --check      read-only: is the deployed EFI EFI/ plus only the identity?
#   ./tools/deploy-efi.sh              deploy EFI/ and splice the identity back in, then validate
#
# The identity (SystemSerialNumber, MLB, ROM, SystemUUID) is machine-private and stays only in
# EFI/OC/identity.plist and in the deployed MACEFI/EFI/OC/config.plist. The committed
# EFI/OC/config.plist keeps placeholders, so git history never carries a real serial.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/EFI
IDENTITY=$ROOT/EFI/OC/identity.plist
TARGET=""
MODE=deploy

say()  { printf '%s\n' "$*"; }
die()  { printf 'STOP: %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

for a in "$@"; do
  case $a in
    --capture) MODE=capture ;;
    --check)   MODE=check ;;
    --target=*) TARGET=${a#--target=} ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $a" ;;
  esac
done

[ -f "$SRC/OC/config.plist" ] || die "$SRC/OC/config.plist is missing - this is not an EFI tree."
[ -f "$SRC/OC/OpenCore.efi" ] || die "$SRC/OC/OpenCore.efi is missing - the ESP would not boot."

# ---- the target: the vfat volume labelled MACEFI, never the Omarchy ESP -----
if [ -z "$TARGET" ]; then
  TARGET=$(findmnt -rno TARGET,LABEL | awk '$2=="MACEFI"{print $1; exit}')
fi
[ -n "$TARGET" ] || die "MACEFI is not mounted. Mount it, or pass --target=<mountpoint>."
[ -d "$TARGET" ] || die "$TARGET is not a directory."

read -r TGT_SRC TGT_TYPE <<<"$(findmnt -rno SOURCE,FSTYPE --target "$TARGET")"
BOOT_SRC=$(findmnt -rno SOURCE --target /boot 2>/dev/null || true)
ROOT_SRC=$(findmnt -rno SOURCE --target / 2>/dev/null || true)
[ "${TGT_TYPE:-}" = "vfat" ] || die "$TARGET is ${TGT_TYPE:-unknown}, not vfat - refusing to write."
[ "${TGT_SRC:-}" != "${BOOT_SRC:-}" ] || die "$TARGET is the Omarchy ESP ($BOOT_SRC) - refusing."
case "${TGT_SRC:-}" in
  "${ROOT_SRC:-/nonexistent}"|"/dev/mapper/"*) die "$TARGET holds this Linux system - refusing." ;;
esac
CONF=$TARGET/EFI/OC/config.plist
if [ -f "$TARGET/EFI/OC/OpenCore.efi" ] && [ ! -f "$CONF" ]; then
  die "$TARGET/EFI/OC has an OpenCore but no config.plist - inspect it by hand first."
fi
say "   target $TARGET ($TGT_SRC, $TGT_TYPE)"

# ---- ocvalidate ------------------------------------------------------------
OCVALIDATE=$(command -v ocvalidate 2>/dev/null || true)
if [ -z "$OCVALIDATE" ]; then
  OCVALIDATE=$(find "$ROOT/.downloads" "$ROOT/tools" -maxdepth 4 -type f -name 'ocvalidate*' -perm -u+x 2>/dev/null | head -1 || true)
fi
[ -n "$OCVALIDATE" ] || die "no ocvalidate binary found (put one in tools/ or .downloads/)."

validate() { # $1 = config path
  local out rc=0
  out=$("$OCVALIDATE" "$1" 2>&1) || rc=$?
  printf '%s\n' "$out" | grep -E 'NOTE:|Completed validating|issues|error' | sed 's/^/   /' || true
  [ "$rc" = 0 ] || die "ocvalidate rejected $1"
  printf '%s\n' "$out" | grep -q 'No issues found' || die "ocvalidate did not report a clean run on $1"
}

# The four private fields, spliced as text so the deployed config stays byte-identical to
# EFI/OC/config.plist everywhere else.
splice() { # $1 = identity plist, $2 = config to patch
  python3 -B - "$1" "$2" "$ROOT/EFI/OC/config.plist" <<'PY'
import plistlib, re, sys
ident_path, target_path, public_path = sys.argv[1:4]
KEYS = ("SystemSerialNumber", "MLB", "ROM", "SystemUUID")
ident = plistlib.load(open(ident_path, "rb"))
missing = [k for k in KEYS if not ident.get(k)]
if missing:
    raise SystemExit(f"identity file lacks {', '.join(missing)}")

def node(text, key):
    m = re.search(r"<key>%s</key>\s*(<string>[^<]*</string>|<data>.*?</data>)" % re.escape(key), text, re.S)
    if not m:
        raise SystemExit(f"<key>{key}</key> not found in {target_path}")
    return m.group(0)

def swapped(block, value):
    """Replace only the value inside the element, keeping the file's own indentation."""
    if isinstance(value, bytes):
        import base64
        head, rest = block.split("<data>", 1)
        inner, tail = rest.split("</data>", 1)
        lead = inner[:len(inner) - len(inner.lstrip())]
        trail = inner[len(inner.rstrip()):]
        return head + "<data>" + lead + base64.b64encode(value).decode() + trail + "</data>" + tail
    head, rest = block.split("<string>", 1)
    _inner, tail = rest.split("</string>", 1)
    return head + "<string>" + str(value) + "</string>" + tail

text = open(target_path, encoding="utf-8").read()
for key in KEYS:
    block = node(text, key)
    new = swapped(block, ident[key])
    if block == new:
        continue
    if text.count(block) != 1:
        raise SystemExit(f"{key}: value appears {text.count(block)} times, refusing to guess")
    text = text.replace(block, new)
open(target_path, "w", encoding="utf-8").write(text)

# the deployed config must equal the committed one except for those four fields
deployed = plistlib.load(open(target_path, "rb"))
public = plistlib.load(open(public_path, "rb"))
for cfg in (deployed, public):
    for key in KEYS:
        cfg["PlatformInfo"]["Generic"].pop(key, None)
if deployed != public:
    raise SystemExit("deployed config differs from EFI/OC/config.plist beyond the identity fields")
g = plistlib.load(open(target_path, "rb"))["PlatformInfo"]["Generic"]
print(f"   identity spliced: serial {g['SystemSerialNumber']}, MLB {g['MLB']}, UUID {g['SystemUUID']}")
PY
}

deps() { # $1 = EFI dir
  python3 -B - "$1" <<'PY'
import os, plistlib, sys
efi = sys.argv[1]
oc = os.path.join(efi, "OC")
cfg = plistlib.load(open(os.path.join(oc, "config.plist"), "rb"))
bad = []
for a in cfg["ACPI"]["Add"]:
    if a["Enabled"] and not os.path.exists(os.path.join(oc, "ACPI", a["Path"])):
        bad.append("ACPI " + a["Path"])
for d in cfg["UEFI"]["Drivers"]:
    p = d if isinstance(d, str) else d["Path"]
    if not os.path.exists(os.path.join(oc, "Drivers", p)):
        bad.append("driver " + p)
kexts = 0
for k in cfg["Kernel"]["Add"]:
    if not k["Enabled"]:
        continue
    kexts += 1
    p = os.path.join(oc, "Kexts", k["BundlePath"])
    try:
        info = plistlib.load(open(os.path.join(p, "Contents", "Info.plist"), "rb"))
    except OSError:
        bad.append("kext " + k["BundlePath"])
        continue
    exe = info.get("CFBundleExecutable")
    if exe and not os.path.exists(os.path.join(p, "Contents", "MacOS", exe)):
        bad.append("binary " + k["BundlePath"])
if not os.path.exists(os.path.join(efi, "BOOT", "BOOTx64.efi")):
    bad.append("BOOT/BOOTx64.efi")
if bad:
    for b in bad:
        print("   MISSING " + b)
    sys.exit(1)
print(f"   files: {kexts} kexts, {len(cfg['ACPI']['Add'])} ACPI tables, {len(cfg['UEFI']['Drivers'])} drivers")
PY
}

# ---- capture: identity out of the deployed config --------------------------
if [ "$MODE" = capture ]; then
  step "capture the identity"
  [ -f "$CONF" ] || die "$CONF not found - nothing to capture."
  python3 -B - "$CONF" "$IDENTITY" <<'PY'
import plistlib, sys
src, dst = sys.argv[1:3]
KEYS = ("SystemSerialNumber", "MLB", "ROM", "SystemUUID")
g = plistlib.load(open(src, "rb"))["PlatformInfo"]["Generic"]
ident = {k: g[k] for k in KEYS if k in g}
missing = [k for k in KEYS if k not in ident]
if missing:
    raise SystemExit("deployed config lacks " + ", ".join(missing) + " - not capturing placeholders")
plistlib.dump(ident, open(dst, "wb"))
print(f"   wrote {dst}")
print("   serial", ident["SystemSerialNumber"], "MLB", ident["MLB"], "UUID", ident["SystemUUID"])
PY
  say "   $IDENTITY is git-ignored; never commit it."
  exit 0
fi

# ---- check: is the deployed tree EFI/ plus the identity? -------------------
if [ "$MODE" = check ]; then
  step "compare $TARGET/EFI with $SRC"
  [ -f "$CONF" ] || die "$CONF not found - deploy EFI/ first."
  diffs=$(diff -rq "$SRC" "$TARGET/EFI" 2>&1 || true)
  extra=$(printf '%s\n' "$diffs" | grep -v 'config.plist.bak-' | grep -vE '^Files .*config\.plist and .*config\.plist differ$' || true)
  if [ -n "$extra" ]; then
    printf '%s\n' "$extra" | sed 's/^/   /'
    die "the ESP differs from EFI/ by more than OC/config.plist"
  fi
  say "   only OC/config.plist differs (the identity fields)"
  step "identity and validity"
  python3 -B - "$CONF" "$ROOT/EFI/OC/config.plist" <<'PY'
import plistlib, sys
deployed, public = (plistlib.load(open(p, "rb")) for p in sys.argv[1:3])
KEYS = ("SystemSerialNumber", "MLB", "ROM", "SystemUUID")
gd, gp = deployed["PlatformInfo"]["Generic"], public["PlatformInfo"]["Generic"]
real = all(gd.get(k) and "REPLACEME" not in str(gd.get(k)) for k in KEYS)
print("   identity on the ESP: serial", gd.get("SystemSerialNumber"), "| committed:", gp.get("SystemSerialNumber"))
print("   real identity, not placeholders:", "yes" if real else "NO")
for cfg in (deployed, public):
    for k in KEYS:
        cfg["PlatformInfo"]["Generic"].pop(k, None)
same = deployed == public
print("   rest of the config matches EFI/OC/config.plist:", "yes" if same else "NO")
sys.exit(0 if same and real else 1)
PY
  validate "$CONF"
  deps "$TARGET/EFI"
  step "result"
  say "   PASS: the ESP holds EFI/ plus the private identity only."
  exit 0
fi

# ---- deploy ----------------------------------------------------------------
step "1/4 identity"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ -f "$CONF" ]; then
  python3 -B - "$CONF" "$TMP/identity.plist" <<'PY'
import plistlib, sys
g = plistlib.load(open(sys.argv[1], "rb"))["PlatformInfo"]["Generic"]
KEYS = ("SystemSerialNumber", "MLB", "ROM", "SystemUUID")
ident = {k: g[k] for k in KEYS if k in g}
plistlib.dump(ident, open(sys.argv[2], "wb"))
PY
  say "   kept the identity already on the ESP"
elif [ -f "$IDENTITY" ]; then
  cp "$IDENTITY" "$TMP/identity.plist"
  say "   using $IDENTITY (git-ignored)"
else
  die "no identity on the ESP and no $IDENTITY. Run --capture on the deployed config first."
fi

step "2/4 validate EFI/ before writing"
validate "$SRC/OC/config.plist"
deps "$SRC"

step "3/4 copy EFI/ to $TARGET"
rsync -a --delete "$SRC/" "$TARGET/EFI/"
splice "$TMP/identity.plist" "$CONF"
sync

step "4/4 validate the deployed copy"
validate "$CONF"
deps "$TARGET/EFI"
step "result"
say "   PASS: $TARGET/EFI is EFI/ with the private identity, validated."
say "   The ESP is the only place the identity lives outside $IDENTITY."
