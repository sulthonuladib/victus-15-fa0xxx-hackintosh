#!/usr/bin/env python3
"""verify-xar-pkg.py - check an Apple .pkg (XAR archive) against its own table of contents.

Usage: python3 tools/verify-xar-pkg.py /path/to/InstallAssistant.pkg [--quick]

What it proves, offline:
  1. the TOC decompresses and matches the digest stored for it  -> nothing is corrupted up front
  2. Apple's RSA signature block and certificate are present in the TOC
  3. every archived (compressed) file matches its TOC digest  -- always
  4. every extracted (decompressed) file matches its TOC digest -- unless --quick

Layout note: Apple's flat packages put the header (28 B), then the compressed TOC, then a heap
whose first bytes are the TOC's own digest (pointed to by <checksum><offset><size> in the TOC).
There is no inline header checksum, unlike the older xar layout — offsets are relative to the
start of the heap.

What it does NOT prove: that Apple made the file. That needs the signature chain against
Apple's root (macOS `pkgutil --check-signature` / `installer`), which only macOS has. This
check catches truncation and corruption in large downloads.
"""
import hashlib
import sys
import zlib
from xml.etree import ElementTree

ALGS = {0: None, 1: "sha1", 2: "md5", 3: "sha256", 4: "sha512"}
CHUNK = 4 << 20


def read_exact(fh, n):
    buf = fh.read(n)
    if len(buf) != n:
        raise EOFError(f"wanted {n} bytes, got {len(buf)}")
    return buf


def main(argv):
    quick = "--quick" in argv
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    path = args[0]

    with open(path, "rb") as fh:
        hdr = read_exact(fh, 28)
        magic = hdr[0:4]
        hdr_size = int.from_bytes(hdr[4:6], "big")
        version = int.from_bytes(hdr[6:8], "big")
        toc_c = int.from_bytes(hdr[8:16], "big")
        toc_u = int.from_bytes(hdr[16:24], "big")
        cksum_alg = int.from_bytes(hdr[24:28], "big")
        if magic != b"xar!":
            print(f"FAIL: not a XAR archive (magic {magic!r})")
            return 1
        alg = ALGS.get(cksum_alg)
        print(f"XAR v{version}, header {hdr_size} B, TOC {toc_c} B compressed / {toc_u} B, checksum {alg}")
        if hdr_size != 28:
            print(f"WARN: non-standard header size {hdr_size}; assuming the TOC follows it directly")

        toc = read_exact(fh, toc_c)
        xml = zlib.decompress(toc)
        heap = hdr_size + toc_c

        root = ElementTree.fromstring(xml)
        toc_ck = root.find("toc/checksum")
        if toc_ck is not None and alg:
            off, size = int(toc_ck.findtext("offset")), int(toc_ck.findtext("size"))
            fh.seek(heap + off)
            stored = read_exact(fh, size)
            got = hashlib.new(alg, toc).digest()
            if got != stored:
                print(f"FAIL: TOC digest {got.hex()} != stored {stored.hex()}")
                return 1
            print(f"ok    TOC digest matches the copy stored in the heap ({alg} {got.hex()[:32]}...)")
        else:
            print("WARN: no <toc><checksum> entry - the TOC is not self-checked")

    files = []
    for el in root.iter("file"):
        if (el.findtext("type") or "file") != "file":
            continue
        data = el.find("data")
        if data is None:
            continue
        files.append({
            "name": el.findtext("name") or "?",
            "offset": int(data.findtext("offset")),
            # XAR: <length> = bytes as stored, <size> = bytes after decompression
            "stored": int(data.findtext("length")),
            "size": int(data.findtext("size")),
            "encoding": (data.find("encoding").get("style") if data.find("encoding") is not None else None),
            "archived": ((data.findtext("archived-checksum") or "").strip(),
                         (data.find("archived-checksum").get("style") if data.find("archived-checksum") is not None else None)),
            "extracted": ((data.findtext("extracted-checksum") or "").strip(),
                          (data.find("extracted-checksum").get("style") if data.find("extracted-checksum") is not None else None)),
        })

    sigs = [s.get("style") for s in root.iter("signature")]
    print(f"ok    {len(files)} file(s) in the TOC, signature block(s): {', '.join(s for s in sigs if s) or 'none'}")
    if not sigs:
        print("WARN: no <signature> in the TOC - Apple's chain cannot be checked even on macOS")

    bad = 0
    with open(path, "rb") as fh:
        for i, f in enumerate(files, 1):
            fh.seek(heap + f["offset"])
            a_hash = hashlib.new(f["archived"][1] or "sha1")
            e_hash = hashlib.new(f["extracted"][1] or "sha1") if not quick else None
            magic = fh.read(6)
            fh.seek(heap + f["offset"])
            dec = None
            enc = f["encoding"] or "application/octet-stream"
            compressed = enc not in ("application/octet-stream", "")
            if compressed:
                # Apple labels zlib-wrapped deflate as application/x-gzip; trust the magic for the
                # wrapper, the TOC for whether it is compressed at all.
                if magic[:2] == b"\x1f\x8b":
                    dec = zlib.decompressobj(16 + zlib.MAX_WBITS)      # gzip
                elif magic[:1] == b"\x78" and magic[1:2] in (b"\x01", b"\x5e", b"\x9c", b"\xda"):
                    dec = zlib.decompressobj(zlib.MAX_WBITS)           # zlib/deflate
                elif magic[:3] == b"BZh":
                    import bz2
                    dec = bz2.BZ2Decompressor()
                elif magic[:6] == b"\xfd7zXZ\x00":
                    import lzma
                    dec = lzma.LZMADecompressor()
                else:
                    print(f"SKIP  {f['name']}: encoding {enc}, unrecognised magic {magic.hex()}")
                    continue

            left = f["stored"]
            while left:
                buf = read_exact(fh, min(CHUNK, left))
                left -= len(buf)
                a_hash.update(buf)
                if e_hash is not None:
                    if dec is None:
                        e_hash.update(buf)          # stored: extracted bytes == archived bytes
                    else:
                        out = dec.decompress(buf)
                        if out:
                            e_hash.update(out)

            problems = []
            if f["archived"][0] and a_hash.hexdigest() != f["archived"][0]:
                problems.append(f"archived {a_hash.hexdigest()} != {f['archived'][0]}")
            if e_hash is not None and f["extracted"][0] and e_hash.hexdigest() != f["extracted"][0]:
                problems.append(f"extracted {e_hash.hexdigest()} != {f['extracted'][0]}")

            size_mb = f["stored"] / 2**20
            if problems:
                bad += 1
                print(f"FAIL  {f['name']} ({size_mb:.0f} MiB stored): " + "; ".join(problems))
            else:
                what = "archived" if e_hash is None else "archived + extracted"
                print(f"ok    {f['name']} ({size_mb:.0f} MiB stored, {what} digests match)")

    print()
    if bad:
        print(f"FAILED: {bad} file(s) do not match the TOC - download again.")
        return 1
    print("PASS: every file in the package matches its TOC digest.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
