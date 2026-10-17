#import "VCBuildInfo.h"

#include <ftxui/dom/elements.hpp>
#include <ftxui/screen/screen.hpp>

#include <string>

@implementation VCBuildInfo

+ (NSString *)renderText:(NSString *)text width:(NSInteger)width {
  auto element = ftxui::text(std::string(text.UTF8String));
  auto screen = ftxui::Screen::Create(ftxui::Dimension::Fixed(static_cast<int>(width)),
                                      ftxui::Dimension::Fixed(1));
  ftxui::Render(screen, element);
  return [NSString stringWithUTF8String:screen.ToString().c_str()];
}

@end
