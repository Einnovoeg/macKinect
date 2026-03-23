#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Publishes rendered preview frames into OBS through the Syphon framework
/// bundled with OBS.app. OBS can then expose the feed system-wide through its
/// Virtual Camera without requiring a custom CMIO camera extension.
@interface OBSSyphonPublisher : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, copy, readonly) NSString *appName;
@property (nonatomic, copy, readonly) NSString *serverName;
@property (nonatomic, copy, readonly, nullable) NSString *lastErrorMessage;

- (BOOL)publishCGImage:(CGImageRef)image;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
