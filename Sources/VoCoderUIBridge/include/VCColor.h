// Colours for the node tree. FTXUI degrades 256-colour and RGB values to what the terminal
// supports, so callers can always ask for the precise colour.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The 16 ANSI colours, in FTXUI's `Color::Palette16` order.
typedef NS_ENUM(NSInteger, VCNamedColor) {
  VCNamedColorBlack = 0,
  VCNamedColorRed,
  VCNamedColorGreen,
  VCNamedColorYellow,
  VCNamedColorBlue,
  VCNamedColorMagenta,
  VCNamedColorCyan,
  VCNamedColorGrayLight,
  VCNamedColorGrayDark,
  VCNamedColorRedLight,
  VCNamedColorGreenLight,
  VCNamedColorYellowLight,
  VCNamedColorBlueLight,
  VCNamedColorMagentaLight,
  VCNamedColorCyanLight,
  VCNamedColorWhite,
};

/// An immutable colour value: one of the 16 named colours, a 256-palette index or 24-bit RGB.
NS_SWIFT_SENDABLE
@interface VCColor : NSObject
+ (VCColor *)named:(VCNamedColor)color;
+ (VCColor *)palette256:(uint8_t)index;
+ (VCColor *)red:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue NS_SWIFT_NAME(rgb(_:_:_:));
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
