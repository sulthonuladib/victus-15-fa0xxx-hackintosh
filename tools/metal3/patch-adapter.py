import sys
src='/Volumes/macUtility/whateverxe/mtl3-backup/XeCompilerAdapter.bundle.orig/Contents/MacOS/adapter.dylib'
dst='/tmp/adapter-iter.dylib'
d=bytearray(open(src,'rb').read())
NOP6=b'\x66\x0f\x1f\x44\x00\x00'
patches=[(0x13f2,b'\x75\x09',b'\xeb\x09'),          # serialized-request gate: jne -> jmp
         (0x0e7e,b'\x0f\x85\xe3\x00\x00\x00',NOP6),  # vertex-state byte 0 check
         (0x0e92,b'\x0f\x85\xcf\x00\x00\x00',NOP6)]  # vertex-state byte 1 check
for off,old,new in patches:
    have=bytes(d[off:off+len(old)])
    if have!=old: print(f"  MISMATCH at 0x{off:x}: {have.hex(' ')} != {old.hex(' ')}"); sys.exit(1)
    d[off:off+len(new)]=new
open(dst,'wb').write(d)
print("patched:", ", ".join(f"0x{o:x}" for o,_,_ in patches))
