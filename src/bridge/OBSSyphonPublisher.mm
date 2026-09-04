#import "OBSSyphonPublisher.h"

#import <Metal/Metal.h>
#import <os/log.h>

@interface SyphonMetalServer : NSObject
- (instancetype)initWithName:(NSString *)name device:(id<MTLDevice>)device options:(NSDictionary * _Nullable)options;
- (void)publishFrameTexture:(id<MTLTexture>)texture
            onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                imageRegion:(CGRect)imageRegion
                    flipped:(BOOL)flipped;
- (void)stop;
@end

namespace {

constexpr const char *kSyphonFrameworkPath = "/Applications/OBS.app/Contents/Frameworks/Syphon.framework";
constexpr const char *kSyphonAppName = "macKinect";
constexpr const char *kSyphonServerName = "Kinect Camera";

} // namespace

@interface OBSSyphonPublisher ()
@property (nonatomic, assign, getter=isAvailable) BOOL available;
@property (nonatomic, copy, readwrite) NSString *appName;
@property (nonatomic, copy, readwrite) NSString *serverName;
@property (nonatomic, copy, readwrite, nullable) NSString *lastErrorMessage;
@end

@implementation OBSSyphonPublisher {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _commandQueue;
  id _server;
  id<MTLTexture> _texture;
  NSUInteger _textureWidth;
  NSUInteger _textureHeight;
  os_log_t _log;
}

+ (instancetype)sharedInstance {
  static OBSSyphonPublisher *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _appName = @(kSyphonAppName);
    _serverName = @(kSyphonServerName);
    _log = os_log_create("com.mackinect.obs", "syphon");
    _available = [self loadSyphonIfNeeded];
  }
  return self;
}

- (void)dealloc {
  [self stop];
}

- (BOOL)publishCGImage:(CGImageRef)image {
  if (image == nil) {
    self.lastErrorMessage = @"No image was supplied for OBS publishing.";
    return NO;
  }

  if (![self loadSyphonIfNeeded]) {
    return NO;
  }

  const size_t width = CGImageGetWidth(image);
  const size_t height = CGImageGetHeight(image);
  if (width == 0 || height == 0) {
    self.lastErrorMessage = @"Preview image has invalid dimensions.";
    return NO;
  }

  if (![self ensureTextureWithWidth:width height:height]) {
    return NO;
  }

  const size_t bytesPerRow = width * 4;
  NSMutableData *pixelData = [NSMutableData dataWithLength:bytesPerRow * height];
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
      pixelData.mutableBytes,
      width,
      height,
      8,
      bytesPerRow,
      colorSpace,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(colorSpace);

  if (context == nullptr) {
    self.lastErrorMessage = @"Could not create a bitmap context for OBS publishing.";
    return NO;
  }

  // CoreGraphics has origin at bottom-left, Metal at top-left. Flip vertically
  // so OBS receives right-side-up frames. Without this, the Kinect image
  // appears upside-down in OBS Virtual Camera.
  CGContextSaveGState(context);
  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, 1, -1);
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
  CGContextRestoreGState(context);
  CGContextRelease(context);

  MTLRegion region = MTLRegionMake2D(0, 0, width, height);
  [_texture replaceRegion:region mipmapLevel:0 withBytes:pixelData.bytes bytesPerRow:bytesPerRow];

  id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  if (commandBuffer == nil) {
    self.lastErrorMessage = @"Could not allocate a Metal command buffer for OBS publishing.";
    return NO;
  }

  [_server publishFrameTexture:_texture
               onCommandBuffer:commandBuffer
                   imageRegion:CGRectMake(0, 0, width, height)
                       flipped:NO];
  [commandBuffer commit];
  self.lastErrorMessage = nil;
  return YES;
}

- (void)stop {
  if (_server != nil && [_server respondsToSelector:@selector(stop)]) {
    [_server stop];
  }
  _texture = nil;
  _textureWidth = 0;
  _textureHeight = 0;
}

- (BOOL)loadSyphonIfNeeded {
  if (_server != nil && _commandQueue != nil) {
    self.available = YES;
    self.lastErrorMessage = nil;
    return YES;
  }

  // Syphon is treated as an optional integration owned by the user's OBS
  // install, so the app loads it lazily instead of linking against it.
  NSBundle *bundle = [NSBundle bundleWithPath:@(kSyphonFrameworkPath)];
  if (bundle == nil || ![bundle load]) {
    self.available = NO;
    self.lastErrorMessage = @"Syphon.framework could not be loaded from OBS.app.";
    return NO;
  }

  Class serverClass = NSClassFromString(@"SyphonMetalServer");
  if (serverClass == Nil) {
    self.available = NO;
    self.lastErrorMessage = @"OBS Syphon framework is missing SyphonMetalServer.";
    return NO;
  }

  _device = MTLCreateSystemDefaultDevice();
  _commandQueue = [_device newCommandQueue];
  if (_device == nil || _commandQueue == nil) {
    self.available = NO;
    self.lastErrorMessage = @"Metal is unavailable, so OBS Syphon publishing cannot start.";
    return NO;
  }

  _server = [[serverClass alloc] initWithName:self.serverName device:_device options:nil];
  if (_server == nil) {
    self.available = NO;
    self.lastErrorMessage = @"Could not create the OBS Syphon server.";
    return NO;
  }

  os_log_info(_log, "OBS Syphon server ready.");
  self.available = YES;
  self.lastErrorMessage = nil;
  return YES;
}

- (BOOL)ensureTextureWithWidth:(NSUInteger)width
                        height:(NSUInteger)height {
  if (_texture != nil && _textureWidth == width && _textureHeight == height) {
    return YES;
  }

  MTLTextureDescriptor *descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:width
                                                        height:height
                                                     mipmapped:NO];
  descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
  descriptor.storageMode = MTLStorageModeShared;

  _texture = [_device newTextureWithDescriptor:descriptor];
  _textureWidth = width;
  _textureHeight = height;
  if (_texture == nil) {
    self.lastErrorMessage = @"Could not allocate a Metal texture for OBS publishing.";
    return NO;
  }

  self.lastErrorMessage = nil;
  return YES;
}

@end
