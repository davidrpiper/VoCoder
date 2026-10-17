// Plain Objective-C surface of the spike bridge. No C++ in this header: Swift imports it
// without C++ interop.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, VCStyle) {
  VCStyleNone = 0,
  VCStyleBold = 1 << 0,
  VCStyleDim = 1 << 1,
  VCStyleInverted = 1 << 2,
  VCStyleFlex = 1 << 3,
};

typedef NS_ENUM(NSInteger, VCColor) {
  VCColorDefault = 0,
  VCColorRed,
  VCColorGreen,
  VCColorYellow,
  VCColorBlue,
  VCColorMagenta,
  VCColorCyan,
  VCColorGray,
};

/// Immutable node in the UI tree Swift builds each update.
NS_SWIFT_SENDABLE
@interface VCNode : NSObject
+ (VCNode *)text:(NSString *)text;
+ (VCNode *)vbox:(NSArray<VCNode *> *)children;
+ (VCNode *)hbox:(NSArray<VCNode *> *)children;
+ (VCNode *)separator;
+ (VCNode *)filler;
/// Stateful text input owned by C++, keyed by a stable id that survives tree swaps.
+ (VCNode *)inputWithId:(NSString *)widgetId placeholder:(NSString *)placeholder;

- (VCNode *)bordered;
- (VCNode *)styled:(VCStyle)style;
- (VCNode *)color:(VCColor)color;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSInteger, VCEventKind) {
  VCEventKindKey,
  VCEventKindWidgetChanged,
  VCEventKindResize,
};

NS_SWIFT_SENDABLE
@interface VCEvent : NSObject
@property(nonatomic, readonly) VCEventKind kind;
/// Normalised key name: "a", "Enter", "Tab", "Ctrl-Space", "Ctrl-a", "Alt-1", "ArrowLeft", …
@property(nonatomic, readonly, copy) NSString *key;
/// Raw terminal bytes as hex, for diagnostics.
@property(nonatomic, readonly, copy) NSString *rawHex;
@property(nonatomic, readonly, copy, nullable) NSString *widgetId;
@property(nonatomic, readonly, copy, nullable) NSString *value;
@property(nonatomic, readonly) NSInteger width;
@property(nonatomic, readonly) NSInteger height;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Owns the FTXUI App and its thread. All methods are thread-safe.
NS_SWIFT_SENDABLE
@interface VCRenderer : NSObject
/// Called on the FTXUI thread. Hop to the main actor before touching app state.
@property(atomic, copy, nullable) void (^NS_SWIFT_SENDABLE onEvent)(VCEvent *event);
/// Called on the FTXUI thread after the loop has exited and the terminal is restored.
@property(atomic, copy, nullable) void (^NS_SWIFT_SENDABLE onExit)(void);

/// Swap the tree and request a coalesced redraw.
- (void)setRoot:(VCNode *)root;
/// Which input widget (if any) receives key events first.
- (void)setFocusedWidget:(nullable NSString *)widgetId;
- (nullable NSString *)valueForWidget:(NSString *)widgetId;
- (void)setValue:(NSString *)value forWidget:(NSString *)widgetId;

/// Start the fullscreen loop on a dedicated thread.
- (void)start;
/// Ask the loop to exit; onExit fires once the terminal is restored.
- (void)stop;

/// Render the current tree off-screen. Plain text (no escapes) unless ansi is YES.
- (NSString *)renderToStringWidth:(NSInteger)width height:(NSInteger)height ansi:(BOOL)ansi
    NS_SWIFT_NAME(renderToString(width:height:ansi:));

/// Number of frames actually drawn by the loop (for coalescing measurements).
@property(atomic, readonly) NSUInteger framesDrawn;
/// setRoot -> frame drawn latency (spike measurement).
@property(atomic, readonly, copy) NSString *latencySummary;
@end

NS_ASSUME_NONNULL_END
