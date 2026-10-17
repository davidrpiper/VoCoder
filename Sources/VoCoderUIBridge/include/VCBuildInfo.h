// Plain Objective-C surface of the UI bridge. No C++ in public headers: Swift imports them
// without C++ interop (DESIGN §4.2). The real bridge (VCRenderer, VCNode, …) arrives in P1-02.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Build probe: proves FTXUI compiles and links into the package.
@interface VCBuildInfo : NSObject
/// Renders `text` to an off-screen FTXUI screen of the given width and returns it as a string.
+ (NSString *)renderText:(NSString *)text width:(NSInteger)width;
@end

NS_ASSUME_NONNULL_END
