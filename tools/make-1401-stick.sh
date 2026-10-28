#!/usr/bin/env bash
# make-1401-stick.sh - build 1401's macOS installer stick from Linux, by hand.
# Local helper, not part of the 1401 repo. Reimplements what 1401's Windows writer does:
#   MBR + one active 0x0C FAT32 partition, EFI/ copied and verified, Apple's recovery image
#   downloaded and chunk-verified, NVIDIA driver optional.
#
#   ./make-1401-stick.sh              check everything, ask, then erase the stick
#   ./make-1401-stick.sh --dry-run    same checks, print the plan, change nothing
#   ./make-1401-stick.sh --verify     read-only: is this stick a finished 1401 installer?
#
# Safety rules are the app's (p1401/usbwriter.py eligible()): USB whole disk only, never the disk
# this system runs from, never a disk that holds an OS, size limits, and the stick is
# re-identified by serial + size immediately before it is erased.
set -euo pipefail

# ---- what to write ---------------------------------------------------------
REPO=${REPO:-$HOME/repo/nullmoth/1401}
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EFI=${EFI:-$PROJECT_ROOT}          # parent containing EFI/
DARWIN=${DARWIN:-25}                # macOS Tahoe
LABEL=${LABEL:-1401}
VOL_ID=${VOL_ID:-1401C0DE}          # FAT volume serial, e.g. 1401-C0DE
PART_SIZE=${PART_SIZE:-16GiB}       # the app caps at 16 GiB (Windows' FAT32 formatter limit)
WITH_DRIVER=${WITH_DRIVER:-0}       # 1 = also stage the NVIDIA driver package for the Mac app
PART_START=2048                     # sectors (1 MiB), same as the app

# ---- which stick -----------------------------------------------------------
DEV=${DEV:-/dev/sda}
EXPECT_SERIAL=${EXPECT_SERIAL-CHANGEME-STICK-SERIAL}   # empty = accept any stick
MIN_BYTES=$((2 * 1024 * 1024 * 1024))
MAX_BYTES=$((256 * 1024 * 1024 * 1024))
OS_PARTTYPES_GPT="c12a7328-f81f-11d2-ba4b-00a0c93ec93b 7c3457ef-0000-11aa-aa11-00306543ecac
48465300-0000-11aa-aa11-00306543ecac e3c9e316-0b5c-4db8-817d-f92df00215ae
de94bba4-06d1-4d40-a16a-bfd50179d6ac"
# ESP, WinRE, HFS+ (macOS), Linux, LVM, Linux RAID. A plain data stick is never an installed
# system, so FAT32 (0x0c/0x1b/0x1c) and NTFS/exFAT (0x07/0x0b) are allowed - the app only
# refuses real OS partitions too.
OS_PARTTYPES_MBR="0xef 0x27 0xaf 0x83 0x8e 0xfd"

MODE=write
for a in "$@"; do
  case $a in
    --dry-run) MODE=dry ;;
    --verify)  MODE=verify ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
DRY=0; [ "$MODE" = dry ] && DRY=1

say()  { printf '%s\n' "$*"; }
die()  { printf 'STOP: %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }

# ---- identify the stick, refuse everything else ---------------------------
identify() {
  step "the stick"
  [ -b "$DEV" ] || die "$DEV is not a block device."
  NAME=$(basename "$DEV")
  [ -d "/sys/block/$NAME" ] || die "$DEV is a partition, not a whole disk. Pick the whole disk (for example /dev/sda)."
  read -r SIZE TRAN RM HOTPLUG SERIAL <<<"$(lsblk -bdno SIZE,TRAN,RM,HOTPLUG,SERIAL "$DEV" | tr -s ' ')"
  MODEL=$(lsblk -dno MODEL "$DEV" | sed 's/^ *//; s/ *$//')
  say "   $DEV  $MODEL  $((SIZE / 1000000000)) GB  serial=${SERIAL:-<none>}  tran=${TRAN:-?} removable=$RM"

  [ "${TRAN:-}" = "usb" ] || { [ "$RM" = 1 ] && [ "$HOTPLUG" = 1 ]; } \
    || die "$DEV is not a USB disk (transport ${TRAN:-unknown}). Refusing."
  if [ -n "${EXPECT_SERIAL:-}" ] && [ "${SERIAL:-}" != "$EXPECT_SERIAL" ]; then
    die "expected stick serial $EXPECT_SERIAL, found ${SERIAL:-<none>}. Refusing - set EXPECT_SERIAL= to accept any."
  fi
  [ "$SIZE" -ge "$MIN_BYTES" ] || die "$DEV is smaller than 2 GB."
  [ "$SIZE" -le "$MAX_BYTES" ] || die "$DEV is bigger than 256 GB - that is a drive, not a stick. Refusing."

  local m
  while read -r m; do
    [ -n "$m" ] || continue
    for os_mnt in / /boot /boot/efi /efi /home /usr /var '[SWAP]'; do
      [ "$m" = "$os_mnt" ] && die "$DEV holds $os_mnt - this is the system you are running on. Refusing."
    done
  done < <(lsblk -rno MOUNTPOINTS "$DEV" | grep -v '^$' || true)

  local p t os_type
  while read -r p t; do
    [ -n "${p:-}" ] || continue
    for os_type in $OS_PARTTYPES_GPT $OS_PARTTYPES_MBR; do
      if [ "${t,,}" = "${os_type,,}" ]; then die "$p has partition type $t (an operating system lives there). Refusing."; fi
    done
  done < <(lsblk -rno PATH,PARTTYPE "$DEV" | awk 'NF==2')

  case $NAME in
    *[0-9]) PART="${DEV}p1" ;;
    *)      PART="${DEV}1" ;;
  esac
}

unmount_part() {
  local mp src
  while read -r mp; do
    [ -n "$mp" ] || continue
    src=$(findmnt -no SOURCE --target "$mp" 2>/dev/null || true)
    say "   unmounting $mp"
    if [ -n "$src" ]; then sudo umount "$mp" || udisksctl unmount -b "$src" >/dev/null; else sudo umount "$mp"; fi
  done < <(lsblk -rno MOUNTPOINTS "$PART" | grep -v '^$' || true)
}

mount_part() {
  local ro=${1:-rw} mp
  mp=$(lsblk -rno MOUNTPOINTS "$PART" | grep -v '^$' | head -1 || true)
  if [ -n "$mp" ] && [ -d "$mp" ]; then MNT=$mp; return; fi
  local opts=(); [ "$ro" = ro ] && opts=(-o ro)
  if out=$(udisksctl mount -b "$PART" "${opts[@]}" 2>/dev/null); then
    MNT=$(printf '%s\n' "$out" | sed -n 's/.* at \(.*\)\.$/\1/p')
  fi
  if [ -z "${MNT:-}" ] || [ ! -d "$MNT" ]; then
    MNT=$(mktemp -d /tmp/1401-stick-XXXXXX)
    sudo mount "${opts[@]}" "$PART" "$MNT"
  fi
}

# ---- read-only verification of a finished stick ---------------------------
if [ "$MODE" = verify ]; then
  identify
  say "   partition: $PART"
  fails=0
  bad() { printf '   FAIL  %s\n' "$*"; fails=$((fails + 1)); }
  ok()  { printf '   ok    %s\n' "$*"; }

  step "partition table"
  [ "$(lsblk -dno PTTYPE "$DEV")" = dos ] && ok "MBR (dos) partition table" || bad "not an MBR table"
  [ -r "/sys/block/$NAME/$(basename "$PART")/start" ] \
    && [ "$(cat "/sys/block/$NAME/$(basename "$PART")/start")" = "$PART_START" ] \
    && ok "partition starts at sector $PART_START (1 MiB)" || bad "partition does not start at 1 MiB"
  [ "$(lsblk -rno PARTTYPE "$PART")" = 0xc ] && ok "type 0x0C (FAT32 LBA)" || bad "partition type is $(lsblk -rno PARTTYPE "$PART")"
  [ "$(lsblk -dno LABEL "$PART")" = "$LABEL" ] && ok "label $LABEL" || bad "label is '$(lsblk -dno LABEL "$PART")'"
  [ "$(lsblk -dno FSTYPE "$PART")" = vfat ] && ok "FAT" || bad "not a FAT filesystem"

  step "contents"
  mount_part ro
  trap 'sudo umount "$MNT" 2>/dev/null || true' EXIT
  [ -f "$MNT/EFI/BOOT/BOOTx64.efi" ] && ok "EFI/BOOT/BOOTx64.efi" || bad "EFI/BOOT/BOOTx64.efi missing"
  [ -f "$MNT/EFI/OC/config.plist" ] && ok "EFI/OC/config.plist" || bad "EFI/OC/config.plist missing"
  if [ -d "$EFI/EFI" ]; then
    if diff -r "$EFI/EFI" "$MNT/EFI" >/dev/null 2>&1; then ok "EFI matches the build ($(find "$MNT/EFI" -type f | wc -l) files)"
    else bad "EFI differs from $EFI/EFI"; fi
  else
    say "   ..    no build at $EFI to compare against"
  fi
  [ -d "$MNT/com.apple.recovery.boot" ] && ok "com.apple.recovery.boot/" || bad "com.apple.recovery.boot/ missing"

  step "Apple's recovery image (signature + every chunk, offline)"
  if ( cd "$REPO" && python3 - "$MNT" <<'PY'
import glob, hashlib, os, sys
from p1401 import apple
root = sys.argv[1]
d = os.path.join(root, "com.apple.recovery.boot")
cks = sorted(glob.glob(os.path.join(d, "*.chunklist")))
imgs = sorted(glob.glob(os.path.join(d, "*.dmg")))
if not cks or not imgs:
    print("   FAIL  chunklist or image missing"); sys.exit(1)
chunks = apple.parse_chunklist(open(cks[0], "rb").read())
print(f"   ok    chunklist signature verifies against Apple's EFI ROM key ({len(chunks)} chunks)")
total = sum(s for s, _ in chunks)
size = os.path.getsize(imgs[0])
if size != total:
    print(f"   FAIL  image is {size} bytes, its chunklist describes {total}"); sys.exit(1)
bad = 0
with open(imgs[0], "rb") as fh:
    for i, (n, want) in enumerate(chunks, 1):
        got = fh.read(n)
        if len(got) != n or hashlib.sha256(got).digest() != want:
            print(f"   FAIL  chunk {i}/{len(chunks)} of {os.path.basename(imgs[0])} does not match")
            bad += 1
            break
if bad:
    sys.exit(1)
print(f"   ok    {os.path.basename(imgs[0])} {size / 2**20:.0f} MiB, all {len(chunks)} chunks match")
PY
  ); then :; else fails=$((fails + 1)); fi

  step "result"
  if [ "$fails" = 0 ]; then
    say "   PASS: $DEV holds a finished 1401 installer for macOS $DARWIN."
    say "   Boot it with Secure Boot off; pick the installer in the OpenCore menu."
    exit 0
  fi
  say "   FAILED: $fails problem(s) above. Nothing to boot yet."
  exit 1
fi

# ---- write mode ------------------------------------------------------------
step "1/6 the EFI build"
[ -d "$EFI" ] || die "$EFI does not exist. Prepare the Tahoe candidate, or set EFI to a folder containing EFI/."
[ -f "$EFI/EFI/BOOT/BOOTx64.efi" ] || die "$EFI/EFI/BOOT/BOOTx64.efi is missing - the firmware would have nothing to boot."
[ -f "$EFI/EFI/OC/config.plist" ] || die "$EFI/EFI/OC/config.plist is missing."
say "   $EFI  ($(find "$EFI/EFI" -type f | wc -l) files)"

step "2/6 the stick"
identify
say "   target partition: $PART (${PART_SIZE} FAT32, label $LABEL)"

step "3/6 confirmation"
say "   Everything on $DEV will be erased. Type the device name ($NAME) to continue:"
if [ "$DRY" = 1 ]; then
  say "   (dry run: not asking, not erasing)"
else
  read -r answer
  [ "$answer" = "$NAME" ] || die "not confirmed - nothing was erased."
fi

step "4/6 erase and format"
if [ "$DRY" = 1 ]; then
  while read -r mp; do [ -n "$mp" ] && say "   would unmount $mp"; done < <(lsblk -rno MOUNTPOINTS "$DEV" | grep -v '^$' || true)
  say "   would run: printf 'label: dos\\nstart=2048, size=$PART_SIZE, type=c, bootable\\n' | sudo sfdisk $DEV"
  say "   would run: sudo mkfs.vfat -F 32 -n $LABEL -i $VOL_ID $PART"
else
  unmount_part
  printf 'label: dos\nstart=%s, size=%s, type=c, bootable\n' "$PART_START" "$PART_SIZE" | sudo sfdisk "$DEV" >/dev/null
  sudo partprobe "$DEV" 2>/dev/null || true
  udevadm settle
  for _ in $(seq 1 20); do [ -b "$PART" ] && break; sleep 0.5; done
  [ -b "$PART" ] || die "$PART did not appear after partitioning."

  # udisks remounts the stick as soon as udev sees the new partition; mkfs then fails "busy".
  # Unmount again right before formatting, and retry a couple of times.
  for attempt in 1 2 3; do
    unmount_part
    udevadm settle
    if sudo mkfs.vfat -F 32 -n "$LABEL" -i "$VOL_ID" "$PART"; then break; fi
    [ "$attempt" = 3 ] && die "could not format $PART (still in use). Unplug it, plug it back in and run again."
    sleep 2
  done
  udevadm settle
  got_label=$(lsblk -dno LABEL "$PART" | tr -d ' ')
  [ "$got_label" = "$LABEL" ] || die "the new filesystem did not take (label reads '$got_label'). Nothing was written."
  say "   formatted $PART: label $LABEL, FAT32, $(lsblk -dno SIZE "$PART")"
fi

step "5/6 write the installer"
if [ "$DRY" = 1 ]; then
  say "   would mount $PART, copy $EFI/EFI, verify it, then download macOS $DARWIN recovery from Apple"
  exit 0
fi

MNT=""
mount_part rw
cleanup() { sudo umount "$MNT" 2>/dev/null || udisksctl unmount -b "$PART" >/dev/null 2>&1 || true; }
trap cleanup EXIT
say "   mounted at $MNT"
[ -d "$MNT" ] || die "the stick is not mounted."

cp -a "$EFI/EFI" "$MNT"/
diff -r "$EFI/EFI" "$MNT/EFI" >/dev/null || die "the written EFI differs from the build - the stick is not ready."
say "   EFI copied and verified byte for byte ($(find "$MNT/EFI" -type f | wc -l) files)"

say "   asking Apple for the macOS $DARWIN recovery image (a few hundred MB, chunk-verified as it streams)"
( cd "$REPO" && python3 -c "from p1401 import apple; apple.download(apple.image_info($DARWIN), '$MNT')" )
ls -1 "$MNT/com.apple.recovery.boot"

if [ "$WITH_DRIVER" = 1 ]; then
  say "   staging the NVIDIA driver package under NullMoth/"
  ( cd "$REPO" && python3 -c "
from p1401 import nullmoth, usbwriter
nullmoth.stage('$MNT', '$EFI/.cache', fetch=usbwriter._fetch)
" )
fi

sync
say "   syncing..."
trap - EXIT
cleanup

step "6/6 done"
say "   $DEV now holds:"
say "     EFI/EFI/BOOT/BOOTx64.efi + EFI/OC/...  OpenCore, built and validated for this PC"
say "     com.apple.recovery.boot/              Apple's recovery, chunk-verified"
[ "$WITH_DRIVER" = 1 ] && say "     NullMoth/                             NVIDIA driver for the Mac app (after install)"
say ""
say "   Check it any time with: $0 --verify"
say "   Next: BIOS - Secure Boot off, boot from USB (F9 on HP), pick the macOS installer in OpenCore."
say "   Your BIOS steps: cd $REPO && python3 -m p1401.guide \$HOME/1401/scan/Report.json \\"
say "                    $EFI/EFI/OC/config.plist --html \$HOME/1401/bios.html"
