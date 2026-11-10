// adapter-graft: five exports from WhateverXe's compiler adapter, logged and forwarded.
// Signatures reconstructed from the disassembly: Build… and XeBuildUntranslated both take 13
// arguments (6 in registers + 7 at rbp+0x10..0x40); Create/Delete/ReleaseReply take one pointer.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <os/log.h>
#import <stdarg.h>

typedef uintptr_t (*fn13)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,
                          uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef uintptr_t (*fn1)(uintptr_t);
static fn13 oBuild, oUntranslated; static fn1 oCreate, oDelete, oRelease; static int loaded;
static int gBuilds;

static void L(NSString *s) { os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "GRAFT %{public}@", s); }
static void load(void) {
  if (loaded) return; loaded = 1;
  Dl_info info; char path[4096];
  if (!dladdr((void *)load, &info) || !info.dli_fname) return;
  snprintf(path, sizeof path, "%s", info.dli_fname);
  /* the service sandbox refuses a sibling file; /System/Library/Caches is inside /System */
  snprintf(path, sizeof path, "/System/Library/Caches/adapter-orig.dylib");
  void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  L([NSString stringWithFormat:@"original %s: %s", path, h ? "loaded" : dlerror()]);
  if (!h) return;
  oBuild = (fn13)dlsym(h, "MTLCompilerBuildRequestWithSerializedBitcode");
  oUntranslated = (fn13)dlsym(h, "XeBuildUntranslated");
  oCreate = (fn1)dlsym(h, "MTLCompilerCreate");
  oDelete = (fn1)dlsym(h, "MTLCompilerDelete");
  oRelease = (fn1)dlsym(h, "MTLCompilerReleaseReply");
}
static NSString *describe(uintptr_t *a) {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < 13; i++) [s appendFormat:@"a%d=0x%llx ", i, (unsigned long long)a[i]];
  // a pointer/len pair among the arguments: dump the first 48 bytes of the most plausible buffer
  for (int len_i = 0; len_i < 13; len_i++) {
    if (a[len_i] < 16 || a[len_i] > 0x200000) continue;
    for (int p_i = 0; p_i < 13; p_i++) {
      if (p_i == len_i || a[p_i] < 0x1000 || (a[p_i] & 7)) continue;
      if (a[len_i] > 0x10000) continue;  // not likely a length then
      const unsigned char *p = (const unsigned char *)a[p_i];
      [s appendFormat:@"| ptr a%d len a%d:", p_i, len_i];
      unsigned n = a[len_i] > 48 ? 48 : (unsigned)a[len_i];
      for (unsigned k = 0; k < n; k++) [s appendFormat:@"%02x", p[k]];
      return s;
    }
  }
  return s;
}
uintptr_t MTLCompilerBuildRequestWithSerializedBitcode(uintptr_t a0,uintptr_t a1,uintptr_t a2,uintptr_t a3,
  uintptr_t a4,uintptr_t a5,uintptr_t a6,uintptr_t a7,uintptr_t a8,uintptr_t a9,uintptr_t a10,uintptr_t a11,uintptr_t a12) {
  load(); uintptr_t a[13] = {a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12};
  if (gBuilds < 40) { gBuilds++; L([NSString stringWithFormat:@"build#%d %@", gBuilds, describe(a)]); }
  return oBuild ? oBuild(a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12) : 0;
}
uintptr_t XeBuildUntranslated(uintptr_t a0,uintptr_t a1,uintptr_t a2,uintptr_t a3,uintptr_t a4,uintptr_t a5,
  uintptr_t a6,uintptr_t a7,uintptr_t a8,uintptr_t a9,uintptr_t a10,uintptr_t a11,uintptr_t a12) {
  load(); uintptr_t a[13] = {a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12};
  L([NSString stringWithFormat:@"untranslated %@", describe(a)]);
  return oUntranslated ? oUntranslated(a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12) : 0;
}
uintptr_t MTLCompilerCreate(uintptr_t a) { load(); L([NSString stringWithFormat:@"create arg=0x%lx", (unsigned long)a]); return oCreate ? oCreate(a) : 0; }
uintptr_t MTLCompilerDelete(uintptr_t a) { load(); return oDelete ? oDelete(a) : 0; }
uintptr_t MTLCompilerReleaseReply(uintptr_t a) { load(); return oRelease ? oRelease(a) : 0; }
