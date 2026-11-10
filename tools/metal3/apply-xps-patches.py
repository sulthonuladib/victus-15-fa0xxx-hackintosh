#!/usr/bin/env python3
"""apply-xps-patches.py - apply the JulioNectar/XPS13Plus-IrisXe-Tahoe driver patches to a bundle.

The offsets and byte pairs are *their* work, read from their repository
(`macos/mtl17-patches.json`, GPL/ISC mix - see REFERENCES.md); this script only selects a subset,
verifies every `old` byte pair before writing, and reports what changed. Nothing is installed here.

    python3 apply-xps-patches.py <bundle-in> <bundle-out> [--patches 2,3,4,5,6,7,8,9] [--sign]

Which patches mean what (from their docs/METAL.md):
  0, 1  Mach-O header + LC_LOAD_DYLIB of libxedrv.dylib   (their shim; needs their header layout)
  2     ignore the kernel's IOSurface compression flag
  3, 4  no render-target fast clear / no dual-SIMD8 clear PS
  5     no fast-clear write PS state
  6     L3 allocation immediate 0x88000020 -> 0xd0000020
  7, 8  programClearPipeline: always emit a disabled VS, then mark VS dirty
  9     -[MTLIGAccelCommandBuffer dealloc]: free the 96 KB POSH block (WindowServer leak)
  10    compiler plugin path -> their xe.bundle (we keep WhateverXe's adapter instead)

Default is 2-9: the behaviour fixes that apply to the bundle WhateverXe installs. Patches 0/1 only
match a stock Big Sur 16.0.32 header (WhateverXe has already added its own load commands), and 10
points at a bundle we do not have.
"""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys

DEFAULT_PATCHES = "2,3,4,5,6,7,8,9"
XPS_JSON = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", ".references", "xps-irisexetahoe", "macos", "mtl17-patches.json")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src_bundle")
    ap.add_argument("dst_bundle")
    ap.add_argument("--patches", default=DEFAULT_PATCHES)
    ap.add_argument("--sign", action="store_true", help="ad-hoc codesign the result")
    args = ap.parse_args()

    patches = json.load(open(XPS_JSON))
    selected = [int(x) for x in args.patches.split(",") if x.strip()]

    info = plistlib.load(open(os.path.join(args.src_bundle, "Contents", "Info.plist"), "rb"))
    exe = info.get("CFBundleExecutable", "AppleIntelTGLGraphicsMTLDriver")

    if os.path.exists(args.dst_bundle):
        shutil.rmtree(args.dst_bundle)
    shutil.copytree(args.src_bundle, args.dst_bundle)

    binary = os.path.join(args.dst_bundle, "Contents", "MacOS", exe)
    data = bytearray(open(binary, "rb").read())

    for i in selected:
        p = patches[i]
        off, old, new = p["off"], bytes.fromhex(p["old"]), bytes.fromhex(p["new"])
        have = bytes(data[off:off + len(old)])
        if have != old:
            sys.exit(f"patch {i}: bytes at 0x{off:x} are {have.hex()}, expected {old.hex()} - refusing")
        data[off:off + len(new)] = new
        print(f"  patch {i:2d}  0x{off:<8x} {old.hex()} -> {new.hex()}")

    open(binary, "wb").write(data)
    print(f"patched {os.path.basename(args.dst_bundle)} with {selected}")

    if args.sign:
        subprocess.run(["codesign", "-f", "-s", "-", args.dst_bundle], check=True)
        subprocess.run(["codesign", "-v", args.dst_bundle], check=True)
        print("ad-hoc signature applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
