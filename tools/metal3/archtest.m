#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
static NSString *gName;
static NSString *fakeName(id self, SEL _cmd) { return gName; }
int main(int argc, char **argv) { @autoreleasepool {
  gName = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"Unknown";
  Class ac = NSClassFromString(@"MTLArchitecture");
  Method m = class_getInstanceMethod(ac, @selector(name));
  if (m) method_setImplementation(m, (IMP)fakeName);
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  id arch = [d respondsToSelector:@selector(architecture)] ? [d performSelector:@selector(architecture)] : nil;
  printf("%-18s arch=%@ name=%@ ", argv[1] ?: "(none)", arch ? @"obj" : @"nil", [arch respondsToSelector:@selector(name)] ? [arch performSelector:@selector(name)] : @"-");
  NSError *e = nil;
  id ba = [d newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&e];
  printf("archive=%s%s\n", ba ? "OK" : "nil", e ? [[NSString stringWithFormat:@" (%@)", [e localizedDescription]] UTF8String] : "");
  return 0; } }
