#import "BridgeInternal.h"

#include "ftxui/component/mouse.hpp"

@implementation VCEvent

- (instancetype)initWithKind:(VCEventKind)kind {
  if ((self = [super init])) {
    _kind = kind;
    _key = @"";
    _rawHex = @"";
  }
  return self;
}

+ (VCEvent *)keyEvent:(NSString *)key rawHex:(NSString *)rawHex {
  VCEvent *event = [[VCEvent alloc] initWithKind:VCEventKindKey];
  event->_key = [key copy];
  event->_rawHex = [rawHex copy];
  return event;
}

+ (VCEvent *)mouseEvent:(ftxui::Mouse)mouse rawHex:(NSString *)rawHex {
  VCEvent *event = [[VCEvent alloc] initWithKind:VCEventKindMouse];
  event->_rawHex = [rawHex copy];
  event->_x = mouse.x;
  event->_y = mouse.y;
  switch (mouse.button) {
    case ftxui::Mouse::Left: event->_mouseButton = VCMouseButtonLeft; break;
    case ftxui::Mouse::Middle: event->_mouseButton = VCMouseButtonMiddle; break;
    case ftxui::Mouse::Right: event->_mouseButton = VCMouseButtonRight; break;
    case ftxui::Mouse::WheelUp: event->_mouseButton = VCMouseButtonWheelUp; break;
    case ftxui::Mouse::WheelDown: event->_mouseButton = VCMouseButtonWheelDown; break;
    case ftxui::Mouse::WheelLeft: event->_mouseButton = VCMouseButtonWheelLeft; break;
    case ftxui::Mouse::WheelRight: event->_mouseButton = VCMouseButtonWheelRight; break;
    default: event->_mouseButton = VCMouseButtonNone; break;
  }
  switch (mouse.motion) {
    case ftxui::Mouse::Released: event->_mouseMotion = VCMouseMotionReleased; break;
    case ftxui::Mouse::Moved: event->_mouseMotion = VCMouseMotionMoved; break;
    default: event->_mouseMotion = VCMouseMotionPressed; break;
  }
  VCModifiers modifiers = VCModifiersNone;
  if (mouse.shift) modifiers |= VCModifiersShift;
  if (mouse.meta) modifiers |= VCModifiersAlt;
  if (mouse.control) modifiers |= VCModifiersControl;
  event->_modifiers = modifiers;
  return event;
}

+ (VCEvent *)widgetEvent:(VCEventKind)kind
                widgetId:(NSString *)widgetId
             stringValue:(NSString *)stringValue
            integerValue:(NSInteger)integerValue {
  VCEvent *event = [[VCEvent alloc] initWithKind:kind];
  event->_widgetId = [widgetId copy];
  event->_stringValue = [stringValue copy];
  event->_integerValue = integerValue;
  return event;
}

+ (VCEvent *)resizeEventWidth:(NSInteger)width height:(NSInteger)height {
  VCEvent *event = [[VCEvent alloc] initWithKind:VCEventKindResize];
  event->_width = width;
  event->_height = height;
  return event;
}

- (NSString *)description {
  switch (_kind) {
    case VCEventKindKey:
      return [NSString stringWithFormat:@"key %@ [%@]", _key, _rawHex];
    case VCEventKindMouse:
      return [NSString stringWithFormat:@"mouse button %ld motion %ld at %ld,%ld",
                                        (long)_mouseButton, (long)_mouseMotion, (long)_x, (long)_y];
    case VCEventKindWidgetChanged:
      return [NSString stringWithFormat:@"changed %@ = %@ (%ld)", _widgetId, _stringValue,
                                        (long)_integerValue];
    case VCEventKindWidgetSubmitted:
      return [NSString stringWithFormat:@"submitted %@ = %@ (%ld)", _widgetId, _stringValue,
                                        (long)_integerValue];
    case VCEventKindResize:
      return [NSString stringWithFormat:@"resize %ldx%ld", (long)_width, (long)_height];
  }
  return @"event";
}

@end
