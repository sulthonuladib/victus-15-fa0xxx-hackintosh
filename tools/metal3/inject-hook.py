#!/usr/bin/env python3
"""inject-hook.py - add one LC_LOAD_DYLIB to the Metal driver without moving any bytes.

The driver's load-command area has no slack (27 commands, sizeofcmds 0x10b0), so the only way to add
a dylib is to reuse space an existing command already owns. We shorten the
MetalPerformanceShaders LC (95-character path, 0x78-byte command) to `@loader_path/mps` - a symlink
placed next to the driver that points at the real framework binary - which shrinks that command to
0x30 bytes and frees 0x48. The new LC_LOAD_DYLIB for our hook (0x38 bytes) is written into that freed
space and ncmds is incremented. sizeofcmds does not change, every other command keeps its offset,
and MPS still resolves (its 9 strong imports stay satisfied through the symlink).

    python3 inject-hook.py <bundle> <dylib-name-in-Contents/MacOS> [--sign]

Both the rewritten driver and the injected dylib are ad-hoc signed at the end. The caller still has
to install the bundle (tools/metal3/metal3-bundle.sh install) and keep the mps symlink in place.
"""
import argparse
import os
import struct
import subprocess
import sys

MPS_FRAMEWORK = "/System/Library/Frameworks/MetalPerformanceShaders.framework/Versions/A/MetalPerformanceShaders"
MPS_SHORT = "@loader_path/mps"


def align8(n: int) -> int:
    return (n + 7) & ~7


def lc_dylib(path: str, cmd: int = 0xC, size: int = 0) -> bytes:
    """One LC_LOAD_DYLIB. `size` pads the command so a rewritten region keeps the exact same extent:
    the next command must start where it started before, or dyld parses the leftover bytes as one."""
    name_off = 0x18
    body = struct.pack("<IIIIII", cmd, 0, name_off, 0, 0x10000, 0x10000) + path.encode() + b"\0"
    size = max(size, align8(len(body)))
    if size < len(body):
        raise SystemExit(f"command for {path} needs {len(body)} bytes, slot is {size}")
    body += b"\0" * (size - len(body))
    return body[:4] + struct.pack("<I", size) + body[8:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle")
    ap.add_argument("dylib_name", help="file name inside Contents/MacOS, e.g. xedrv.dylib")
    ap.add_argument("--sign", action="store_true")
    args = ap.parse_args()

    exe = None
    for f in os.listdir(os.path.join(args.bundle, "Contents", "MacOS")):
        p = os.path.join(args.bundle, "Contents", "MacOS", f)
        if os.path.isfile(p) and not f.endswith(".dylib"):
            with open(p, "rb") as fh:
                if fh.read(4) == b"\xcf\xfa\xed\xfe":
                    exe = p
                    break
    if not exe:
        sys.exit("no Mach-O executable in Contents/MacOS")

    data = bytearray(open(exe, "rb").read())
    magic, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data, 0)
    if magic != 0xFEEDFACF:
        sys.exit(f"unexpected Mach-O magic {magic:#x}")

    off, mps_off, mps_size = 32, None, None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<2I", data, off)
        if cmd == 0xC:
            name_off = struct.unpack_from("<I", data, off + 8)[0]
            path = bytes(data[off + name_off:off + size]).split(b"\0")[0].decode()
            if "MetalPerformanceShaders" in path:
                mps_off, mps_size = off, size
                break
        off += size
    if mps_off is None:
        sys.exit("no LC_LOAD_DYLIB for MetalPerformanceShaders found")

    short = lc_dylib(MPS_SHORT)
    if len(short) + align8(24 + len(args.dylib_name) + 12) > mps_size:
        sys.exit(f"does not fit: need {len(short)}+hook, the MPS command owns {mps_size}")
    # pad the hook command so the pair occupies exactly the old command's extent
    hook = lc_dylib(f"@loader_path/{args.dylib_name}", size=mps_size - len(short))

    old = bytes(data[mps_off:mps_off + mps_size])
    data[mps_off:mps_off + len(short) + len(hook)] = short + hook
    struct.pack_into("<I", data, 0x10, ncmds + 1)  # one more load command, same sizeofcmds
    open(exe, "wb").write(data)
    print(f"  MPS command 0x{mps_off:x} ({mps_size} B): {len(old)} -> {len(short)} B, path -> {MPS_SHORT}")
    print(f"  added LC_LOAD_DYLIB @loader_path/{args.dylib_name} ({len(hook)} B), ncmds {ncmds} -> {ncmds+1}")

    link = os.path.join(args.bundle, "Contents", "MacOS", "mps")
    if not os.path.lexists(link):
        os.symlink(MPS_FRAMEWORK, link)
        print(f"  symlink mps -> {MPS_FRAMEWORK}")

    if args.sign:
        macos = os.path.join(args.bundle, "Contents", "MacOS")
        for f in os.listdir(macos):
            p = os.path.join(macos, f)
            if f.endswith(".dylib") and os.path.isfile(p):
                subprocess.run(["codesign", "-f", "-s", "-", p], check=True)
        subprocess.run(["codesign", "-f", "-s", "-", args.bundle], check=True)
        subprocess.run(["codesign", "-v", args.bundle], check=True)
        print("  ad-hoc signed the bundle and its dylibs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
