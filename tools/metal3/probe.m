// probe.m - what this Metal device actually supports, and where Metal 3 feature calls die.
//
//   clang -fobjc-arc -O1 -o probe probe.m -framework Foundation -framework Metal
//   ./probe
//
// Prints the supported GPU families, then tries the calls that separate "Metal 2 with a patched
// family bit" from real Metal 3: binary archives, dynamic libraries, mesh/object stage compilation
// and mesh pipeline creation. The error strings name the layer that refuses, which is what we chase.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void fam(id<MTLDevice> d, const char *n, MTLGPUFamily f) {
	printf("  %-10s %s\n", n, [d supportsFamily:f] ? "yes" : "no");
}
static void result(const char *label, BOOL ok, NSError *e) {
	NSMutableString *msg = [NSMutableString string];
	if (e) {
		NSString *s = [[e localizedDescription] stringByReplacingOccurrencesOfString:@"\n" withString:@" | "];
		[msg appendFormat:@" (%@)", [s substringToIndex:MIN((NSUInteger)160, s.length)]];
	}
	printf("  %-28s %s%s\n", label, ok ? "ok" : "FAILED", [msg UTF8String]);
}

int main(void) { @autoreleasepool {
	id<MTLDevice> d = MTLCreateSystemDefaultDevice();
	if (!d) { printf("no Metal device\n"); return 1; }
	printf("device %s  regID %llu\n", [[d name] UTF8String], (unsigned long long)[d registryID]);
	fam(d, "Metal3", MTLGPUFamilyMetal3);
	fam(d, "Mac2", MTLGPUFamilyMac2);
	fam(d, "Mac1", MTLGPUFamilyMac1);
	fam(d, "Common3", MTLGPUFamilyCommon3);
	printf("  %-10s %s\n", "raytracing",
		[d respondsToSelector:@selector(supportsRaytracing)] && [d supportsRaytracing] ? "yes" : "no");

	NSError *e = nil;
	id<MTLBinaryArchive> ba = [d newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
	result("binary archive", ba != nil, e);

	NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
	                 "kernel void k(device float* b){ b[0]+=1; }\n";
	for (int t = 0; t < 2; t++) {
		e = nil;
		MTLCompileOptions *o = [MTLCompileOptions new];
		if (@available(macOS 13.0, *)) {
			o.libraryType = t ? MTLLibraryTypeDynamic : MTLLibraryTypeExecutable;
			o.installName = @"x";
		}
		id<MTLLibrary> l = [d newLibraryWithSource:src options:o error:&e];
		result(t ? "libraryTypeDynamic" : "libraryTypeExecutable", l != nil, e);
	}

	NSString *mesh = @"#include <metal_stdlib>\nusing namespace metal;\n"
	                  "[[object]] void obj_main() {}\n[[mesh]] void mesh_main() {}\n"
	                  "[[fragment]] float4 frag_main() { return float4(1); }\n";
	e = nil;
	id<MTLLibrary> lib = [d newLibraryWithSource:mesh options:nil error:&e];
	result("mesh/object compile", lib != nil, e);
	if (lib) {
		id<MTLFunction> mo = [lib newFunctionWithName:@"mesh_main"];
		id<MTLFunction> ob = [lib newFunctionWithName:@"obj_main"];
		id<MTLFunction> fr = [lib newFunctionWithName:@"frag_main"];
		printf("  %-28s mesh=%s object=%s fragment=%s\n", "functions", mo ? "yes" : "no",
		       ob ? "yes" : "no", fr ? "yes" : "no");
		if (@available(macOS 13.0, *)) {
			if (mo && ob && fr) {
				MTLMeshRenderPipelineDescriptor *md = [MTLMeshRenderPipelineDescriptor new];
				md.meshFunction = mo;
				md.objectFunction = ob;
				md.fragmentFunction = fr;
				md.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
				NSError *pe = nil;
				id<MTLRenderPipelineState> ps =
				    [d newRenderPipelineStateWithMeshDescriptor:md options:0 reflection:nil error:&pe];
				result("mesh pipeline state", ps != nil, pe);
			}
		}
	}
	return 0;
} }
