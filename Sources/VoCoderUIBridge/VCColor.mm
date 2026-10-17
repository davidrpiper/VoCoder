#import "BridgeInternal.h"

// Stores the requested value and converts at build time: FTXUI degrades a colour to the
// terminal's support when the ftxui::Color is constructed, and support is known only then.
@implementation VCColor {
  enum class Kind { Named, Palette, RGB } _kind;
  uint8_t _red, _green, _blue;  // index in _red for Named/Palette
}

- (instancetype)initWithKind:(int)kind red:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue {
  if ((self = [super init])) {
    _kind = static_cast<decltype(_kind)>(kind);
    _red = red;
    _green = green;
    _blue = blue;
  }
  return self;
}

+ (VCColor *)named:(VCNamedColor)color {
  auto index = static_cast<uint8_t>(MAX(0, MIN(15, color)));
  return [[VCColor alloc] initWithKind:0 red:index green:0 blue:0];
}

+ (VCColor *)palette256:(uint8_t)index {
  return [[VCColor alloc] initWithKind:1 red:index green:0 blue:0];
}

+ (VCColor *)red:(uint8_t)red green:(uint8_t)green blue:(uint8_t)blue {
  return [[VCColor alloc] initWithKind:2 red:red green:green blue:blue];
}

- (ftxui::Color)ftxuiColor {
  switch (_kind) {
    case Kind::Named: return ftxui::Color(static_cast<ftxui::Color::Palette16>(_red));
    case Kind::Palette: return ftxui::Color(static_cast<ftxui::Color::Palette256>(_red));
    case Kind::RGB: return ftxui::Color::RGB(_red, _green, _blue);
  }
  return ftxui::Color::Default;
}

@end
