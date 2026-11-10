// adapter-graft: same five exports as WhateverXe's adapter.dylib; log and forward everything.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdarg.h>
#import <os/log.h>
typedef void *(*fn10)(uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
typedef void *(*fn1)(void *);
static fn10 oBuild, oUntranslated; static fn1 oCreate, oDelete, oRelease; static int loaded;
static void logline(NSString *fmt, ...) {
  va_list ap; va_start(ap, fmt); NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
  os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "GRAFT %{public}@", s);
}
static void load(void) {
  if (loaded) return; loaded = 1;
  Dl_info info; char path[4096];
  if (!dladdr((void *)load, &info) || !info.dli_fname) return;
  snprintf(path, sizeof path, "%s", info.dli_fname);
  char *sl = strrchr(path, '/'); if (!sl) return;
  snprintf(sl + 1, sizeof path - (size_t)(sl+1-path), "adapter-orig.dylib");
  void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  logline(@"[graft] original %s: %s", path, h ? "loaded" : dlerror());
  if (!h) return;
  oBuild = (fn10)dlsym(h, "MTLCompilerBuildRequestWithSerializedBitcode");
  oUntranslated = (fn10)dlsym(h, "XeBuildUntranslated");
  oCreate = (fn1)dlsym(h, "MTLCompilerCreate");
  oDelete = (fn1)dlsym(h, "MTLCompilerDelete");
  oRelease = (fn1)dlsym(h, "MTLCompilerReleaseReply");
}
static void dump(const char *tag, uintptr_t *a) {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < 10; i++) [s appendFormat:@" a%d=0x%llx", i, (unsigned long long)a[i]];
  for (int i = 0; i < 10; i++) for (int j = 0; j < 10; j++) {
    if (i == j || a[i] < 0x1000 || a[j] == 0 || a[j] > 0x40000 || (a[i] & 3)) continue;
    const unsigned char *p = (const unsigned char *)a[i]; [s appendFormat:@" | buf a%d(len a%d)=", i, j];
    for (unsigned k = 0; k < 32 && k < a[j]; k++) [s appendFormat:@"%02x", p[k]];
    i = 10; break;
  }
  logline(@"[%s]%s", tag, s);
}
void *MTLCompilerBuildRequestWithSerializedBitcode(uintptr_t a0,uintptr_t a1,uintptr_t a2,uintptr_t a3,uintptr_t a4,
                                                   uintptr_t a5,uintptr_t a6,uintptr_t a7,uintptr_t a8,uintptr_t a9) {
  load(); uintptr_t a[10] = {a0,a1,a2,a3,a4,a5,a6,a7,a8,a9}; dump("build", a);
  return oBuild ? oBuild(a0,a1,a2,a3,a4,a5,a6,a7,a8,a9) : NULL;
}
void *XeBuildUntranslated(uintptr_t a0,uintptr_t a1,uintptr_t a2,uintptr_t a3,uintptr_t a4,
                          uintptr_t a5,uintptr_t a6,uintptr_t a7) {
  load(); uintptr_t a[10] = {a0,a1,a2,a3,a4,a5,a6,a7,0,0}; dump("untranslated", a);
  return oUntranslated ? oUntranslated(a0,a1,a2,a3,a4,a5,a6,a7,0,0) : NULL;
}
void *MTLCompilerCreate(void *a) { load(); logline(@"[create] arg=0x%lx first=0x%x", (unsigned long)a, a ? *(unsigned *)a : 0); return oCreate ? oCreate(a) : NULL; }
void *MTLCompilerDelete(void *a) { load(); return oDelete ? oDelete(a) : NULL; }
void *MTLCompilerReleaseReply(void *a) { load(); return oRelease ? oRelease(a) : NULL; }
