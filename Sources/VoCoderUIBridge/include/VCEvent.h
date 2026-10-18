// Events delivered from the bridge to Swift through `-[VCRenderer onEvent]`.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VCEventKind) {
  /// A key not consumed by the focused widget. See `key` for the normalised name.
  VCEventKindKey = 0,
  /// Only delivered while `-[VCRenderer trackMouse]` is on.
  VCEventKindMouse,
  /// A widget's value changed through user input (not through `setValue`).
  VCEventKindWidgetChanged,
  /// Enter in a single-line input, a prompt input (`submitsOnEnter`) or a menu.
  VCEventKindWidgetSubmitted,
  /// The terminal size changed (also sent once when the first frame is drawn).
  VCEventKindResize,
};

typedef NS_ENUM(NSInteger, VCMouseButton) {
  VCMouseButtonNone = 0,
  VCMouseButtonLeft,
  VCMouseButtonMiddle,
  VCMouseButtonRight,
  VCMouseButtonWheelUp,
  VCMouseButtonWheelDown,
  VCMouseButtonWheelLeft,
  VCMouseButtonWheelRight,
};

typedef NS_ENUM(NSInteger, VCMouseMotion) {
  VCMouseMotionPressed = 0,
  VCMouseMotionReleased,
  VCMouseMotionMoved,
};

typedef NS_OPTIONS(NSUInteger, VCModifiers) {
  VCModifiersNone = 0,
  VCModifiersShift = 1 << 0,
  VCModifiersAlt = 1 << 1,
  VCModifiersControl = 1 << 2,
};

NS_SWIFT_SENDABLE
@interface VCEvent : NSObject
@property(nonatomic, readonly) VCEventKind kind;

/// Key events: normalised name, see `VCKeyDecoder`. Empty for other kinds.
@property(nonatomic, readonly, copy) NSString *key;
/// Raw terminal bytes as hex ("1b 5b 41"), for diagnostics. Key and mouse events.
@property(nonatomic, readonly, copy) NSString *rawHex;

/// Widget events: the widget's id and its value after the change. `stringValue` is the text
/// of an input (nil for other widgets); `integerValue` is the menu selection or input cursor.
@property(nonatomic, readonly, copy, nullable) NSString *widgetId;
@property(nonatomic, readonly, copy, nullable) NSString *stringValue;
@property(nonatomic, readonly) NSInteger integerValue;

/// Resize events: new terminal size in cells.
@property(nonatomic, readonly) NSInteger width;
@property(nonatomic, readonly) NSInteger height;

/// Mouse events: cell coordinates (0-based), button, motion and modifiers.
@property(nonatomic, readonly) NSInteger x;
@property(nonatomic, readonly) NSInteger y;
@property(nonatomic, readonly) VCMouseButton mouseButton;
@property(nonatomic, readonly) VCMouseMotion mouseMotion;
@property(nonatomic, readonly) VCModifiers modifiers;

- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
