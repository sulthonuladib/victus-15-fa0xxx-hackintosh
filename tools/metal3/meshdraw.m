// meshdraw.m - does a Metal 3 mesh pipeline actually rasterise on this GPU?
//
//   clang -fobjc-arc -O1 -o meshdraw meshdraw.m -framework Foundation -framework Metal -framework MetalKit
//   ./meshdraw
//
// Compiles a minimal [[mesh]] + [[fragment]] pair, builds the pipeline, draws one triangle with
// drawMeshThreadgroups: and reads the colour back through a blit into a shared buffer. Prints the
// centre pixel. A red centre and a black corner means mesh shading runs end to end on this stack.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static const char *kSrc =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 position [[position]]; };\n"
"using MeshT = mesh<VOut, void, 3, 3, topology::triangle>;\n"
"[[mesh]] void mesh_main(MeshT out) {\n"
"  out.set_vertex(0, VOut{float4(-0.8, -0.8, 0, 1)});\n"
"  out.set_vertex(1, VOut{float4( 0.8, -0.8, 0, 1)});\n"
"  out.set_vertex(2, VOut{float4( 0.0,  0.8, 0, 1)});\n"
"  out.set_index(0, 0); out.set_index(1, 1); out.set_index(2, 2);\n"
"  out.set_primitive_count(1);\n"
"}\n"
"[[fragment]] float4 frag_main() { return float4(1.0, 0.0, 0.0, 1.0); }\n";

int main(void) { @autoreleasepool {
	id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
	if (!dev) { printf("no device\n"); return 1; }
	NSError *e = nil;
	id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:kSrc] options:nil error:&e];
	printf("compile mesh+object library: %s%s\n", lib ? "ok" : "FAILED",
	       e ? [[NSString stringWithFormat:@" (%@)", [e localizedDescription]] UTF8String] : "");
	if (!lib) return 1;
	id<MTLFunction> meshFn = [lib newFunctionWithName:@"mesh_main"];
	id<MTLFunction> fragFn = [lib newFunctionWithName:@"frag_main"];
	printf("functions: mesh=%s fragment=%s\n", meshFn ? "yes" : "no", fragFn ? "yes" : "no");
	if (!meshFn || !fragFn) return 1;

	const int W = 64, H = 64;
	MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
	                                                                            width:W height:H mipmapped:NO];
	td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	td.storageMode = MTLStorageModeManaged;
	id<MTLTexture> tex = [dev newTextureWithDescriptor:td];

	MTLMeshRenderPipelineDescriptor *pd = [MTLMeshRenderPipelineDescriptor new];
	pd.meshFunction = meshFn;
	pd.fragmentFunction = fragFn;
	pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithMeshDescriptor:pd options:0 reflection:nil error:&e];
	printf("mesh pipeline: %s%s\n", pso ? "ok" : "FAILED",
	       e ? [[NSString stringWithFormat:@" (%@)", [e localizedDescription]] UTF8String] : "");
	if (!pso) return 1;

	id<MTLCommandQueue> q = [dev newCommandQueue];
	id<MTLCommandBuffer> cb = [q commandBuffer];
	MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
	rp.colorAttachments[0].texture = tex;
	rp.colorAttachments[0].loadAction = MTLLoadActionClear;
	rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
	rp.colorAttachments[0].storeAction = MTLStoreActionStore;
	id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
	[enc setRenderPipelineState:pso];
	[enc drawMeshThreadgroups:MTLSizeMake(1, 1, 1) threadsPerObjectThreadgroup:MTLSizeMake(1, 1, 1)
	    threadsPerMeshThreadgroup:MTLSizeMake(3, 1, 1)];
	[enc endEncoding];

	id<MTLBuffer> buf = [dev newBufferWithLength:W * H * 4 options:MTLResourceStorageModeShared];
	id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
	[blit copyFromTexture:tex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
	           sourceSize:MTLSizeMake(W, H, 1) toBuffer:buf destinationOffset:0
	  destinationBytesPerRow:W * 4 destinationBytesPerImage:W * H * 4];
	[blit endEncoding];
	[cb commit];
	[cb waitUntilCompleted];
	printf("gpu status: %s\n", [cb error] ? [[[cb error] localizedDescription] UTF8String] : "no error");

	const uint8_t *px = (const uint8_t *)[buf contents];
	// centre of the 64x64 target (triangle covers the middle) and a corner
	const uint8_t *c = px + ((H / 2) * W + (W / 2)) * 4;
	const uint8_t *k = px + (2 * W + 2) * 4;
	printf("centre BGRA = %u,%u,%u  corner BGRA = %u,%u,%u\n", c[0], c[1], c[2], k[0], k[1], k[2]);
	printf("verdict: %s\n", (c[2] > 128 && k[0] < 64 && k[1] < 64) ? "MESH DRAW WORKS" : "drew nothing / wrong colour");
	return 0; } }
