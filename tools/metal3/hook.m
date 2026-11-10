// hook.m - our Metal 3 probe/hook layer, loaded into every Metal process by the driver bundle.
//
// Built as xedrv.dylib and injected by tools/metal3/inject-hook.py: the driver's existing
// MetalPerformanceShaders LC_LOAD_DYLIB is shortened to a /Library/mps symlink, which frees enough
// room in the load-command area for one more LC_LOAD_DYLIB without touching any section.
//
// First job: log what the driver is actually asked for, so the Metal 3 work is driven by calls that
// happen rather than by guesses. Everything is pass-through: we capture the original IMP, call it,
// log the result, and return it unchanged. Nothing is implemented or faked here yet.
//
// Log: /var/tmp/xedrv-hook-<pid>.log (one line per interesting call, throttled by count).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static FILE *gLog;
static NSLock *gLock;

static void hooklog(NSString *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);
	[gLock lock];
	if (!gLog) {
		char path[256];
		snprintf(path, sizeof path, "/var/tmp/xedrv-hook-%d.log", getpid());
		gLog = fopen(path, "a");
	}
	if (gLog) {
		fprintf(gLog, "%s\n", [s UTF8String]);
		fflush(gLog);
	}
	[gLock unlock];
}

typedef BOOL (*SupportsFamilyIMP)(id, SEL, NSUInteger);
typedef id (*BinaryArchiveIMP)(id, SEL, id, NSError **);
typedef id (*MeshPipelineIMP)(id, SEL, id, NSUInteger, id, NSError **);
typedef id (*ArchitectureIMP)(id, SEL);

static SupportsFamilyIMP orig_supportsFamily;
static BinaryArchiveIMP orig_binaryArchive;
static MeshPipelineIMP orig_meshPipeline;

static BOOL hook_supportsFamily(id self, SEL _cmd, NSUInteger family) {
	BOOL r = orig_supportsFamily ? orig_supportsFamily(self, _cmd, family) : NO;
	// 5001 = MTLGPUFamilyMetal3, 2002 = Mac2
	if (family == 5001 || family == 2002) hooklog(@"[family] %lu -> %d", (unsigned long)family, r);
	return r;
}

static id hook_binaryArchive(id self, SEL _cmd, id desc, NSError **err) {
	id r = orig_binaryArchive ? orig_binaryArchive(self, _cmd, desc, err) : nil;
	hooklog(@"[archive] newBinaryArchiveWithDescriptor -> %s%s", r ? "ok" : "nil",
	        (err && *err) ? [[NSString stringWithFormat:@" (%@)", [*err localizedDescription]] UTF8String] : "");
	return r;
}

static id hook_meshPipeline(id self, SEL _cmd, id desc, NSUInteger opts, id reflection, NSError **err) {
	id r = orig_meshPipeline ? orig_meshPipeline(self, _cmd, desc, opts, reflection, err) : nil;
	hooklog(@"[mesh] newRenderPipelineStateWithMeshDescriptor -> %s%s", r ? "ok" : "nil",
	        (err && *err) ? [[NSString stringWithFormat:@" (%@)", [*err localizedDescription]] UTF8String] : "");
	return r;
}

// If the old driver has no -architecture at all, report that once per process: it is the selector
// that rejects binary archives ("no target architecture"), i.e. the first thing to implement.
static id hook_architecture(id self, SEL _cmd) {
	hooklog(@"[arch] -architecture was called (stub returns nil)");
	return nil;
}

static void swizzle(Class cls, SEL sel, IMP replacement, IMP *original) {
	Method m = class_getInstanceMethod(cls, sel);
	if (!m) {
		hooklog(@"[hook] %@ does not implement %@", NSStringFromClass(cls), NSStringFromSelector(sel));
		return;
	}
	if (original) *original = method_getImplementation(m);
	method_setImplementation(m, replacement);
}

// Load the original impostor.dylib (renamed impostor-orig.dylib next to us). The driver loads
// "@loader_path/impostor.dylib" and imports nothing from it; impostor in turn loads descriptor.dylib.
// Chaining it from here keeps WEX's own shims exactly as they were and only appends our hooks.
static void load_original_impostor(void) {
	Dl_info info;
	if (!dladdr((void *)load_original_impostor, &info) || !info.dli_fname) return;
	char path[4096];
	snprintf(path, sizeof path, "%s", info.dli_fname);
	char *slash = strrchr(path, '/');
	if (!slash) return;
	snprintf(slash + 1, sizeof path - (size_t)(slash + 1 - path), "impostor-orig.dylib");
	void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
	hooklog(@"[hook] original impostor %s: %s", path, h ? "loaded" : dlerror());
}

__attribute__((constructor)) static void xedrv_init(void) {
	gLock = [NSLock new];
	load_original_impostor();
	hooklog(@"[hook] loaded into %@ (pid %d)", [[NSProcessInfo processInfo] processName], getpid());

	Class dev = NSClassFromString(@"MTLIGAccelDevice");
	if (!dev) {
		hooklog(@"[hook] MTLIGAccelDevice not present yet; will retry on first use");
		return;
	}
	swizzle(dev, @selector(supportsFamily:), (IMP)hook_supportsFamily, (IMP *)&orig_supportsFamily);
	swizzle(dev, @selector(newBinaryArchiveWithDescriptor:error:), (IMP)hook_binaryArchive, (IMP *)&orig_binaryArchive);
	if (@available(macOS 13.0, *)) {
		swizzle(dev, @selector(newRenderPipelineStateWithMeshDescriptor:options:reflection:error:),
		        (IMP)hook_meshPipeline, (IMP *)&orig_meshPipeline);
	}
	if (!class_getInstanceMethod(dev, @selector(architecture))) {
		class_addMethod(dev, @selector(architecture), (IMP)hook_architecture, "@@:");
		hooklog(@"[hook] added -architecture stub");
	}
	hooklog(@"[hook] installed hooks on MTLIGAccelDevice");
}
