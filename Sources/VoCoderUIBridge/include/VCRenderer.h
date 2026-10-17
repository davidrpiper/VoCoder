// The renderer: owns the FTXUI App, its thread and the stateful widgets (DESIGN §4.2, §4.3).
#import <Foundation/Foundation.h>

#import "VCEvent.h"
#import "VCNode.h"

NS_ASSUME_NONNULL_BEGIN

/// Returned by `integerValueForWidget:` for an unknown widget id.
static const NSInteger VCNoValue = NSNotFound;

/// Thread-safe: every method may be called from any thread.
///
/// Keys: every key reaches the focused widget first (if any); keys it doesn't consume arrive
/// as `VCEventKindKey`. Esc, Tab, Shift-Tab, Ctrl-C and Ctrl-Space always go to Swift. Ctrl-C
/// is a key, not SIGINT.
///
/// Signals (ADR 0001): the app sets SIGINT/SIGTERM/SIGHUP to `SIG_IGN` and observes them with
/// `DispatchSource`, then calls `stop`. FTXUI restores the terminal on fatal signals; the
/// bridge additionally restores it on SIGTRAP (Swift runtime traps) while the loop runs.
NS_SWIFT_SENDABLE
@interface VCRenderer : NSObject

/// Called on the FTXUI thread (or the thread calling `injectInput:` when not running). Hop to
/// the main actor before touching app state. Must not call `runSuspended:` synchronously.
@property(atomic, copy, nullable) void (^NS_SWIFT_SENDABLE onEvent)(VCEvent *event);
/// Called on the FTXUI thread after the loop has exited and the terminal is restored.
@property(atomic, copy, nullable) void (^NS_SWIFT_SENDABLE onExit)(void);
/// Report mouse events. Off by default so the terminal's own text selection keeps working.
/// The terminal's mouse reporting is switched on when the loop starts, so set it before.
@property(atomic) BOOL trackMouse;
@property(atomic, readonly, getter=isRunning) BOOL running;
/// Frames drawn by the loop so far (diagnostics; shows redraw coalescing).
@property(atomic, readonly) NSUInteger framesDrawn;

/// Swap the tree and request a redraw. Redraws coalesce: at most one is pending.
- (void)setRoot:(VCNode *)root;

// MARK: Widgets
/// Which widget receives keys first; nil for none. The bridge doesn't move focus by itself.
@property(atomic, copy, nullable) NSString *focusedWidget;
/// Text of an input; nil if there is no input with that id.
- (nullable NSString *)stringValueForWidget:(NSString *)widgetId;
/// Sets an input's text (cursor moves to the end). Creates the widget state if it doesn't
/// exist yet, so values can be set before the first render. No change event is sent.
- (void)setStringValue:(NSString *)value forWidget:(NSString *)widgetId;
/// Menu: selected index. Scroll frame: first visible row. Input: cursor (UTF-8 bytes).
/// `VCNoValue` for an unknown id.
- (NSInteger)integerValueForWidget:(NSString *)widgetId;
/// Counterpart of `integerValueForWidget:`; creates the state like `setStringValue:`.
- (void)setIntegerValue:(NSInteger)value forWidget:(NSString *)widgetId;
/// Drops a widget's state. Widgets are never dropped automatically.
- (void)removeWidget:(NSString *)widgetId;
@property(atomic, readonly, copy) NSArray<NSString *> *widgetIds;

// MARK: Lifecycle
/// Start the fullscreen loop on a dedicated thread. No-op if running.
- (void)start;
/// Ask the loop to exit; `onExit` fires once the terminal is restored.
- (void)stop;
/// Pop out: on the FTXUI thread, restore the terminal, run `block` (e.g. an interactive child
/// process, waited for synchronously), then take the terminal back and redraw. Returns
/// immediately. Runs `block` directly (terminal untouched) if the loop isn't running.
- (void)runSuspended:(void (^NS_SWIFT_SENDABLE)(void))block;

// MARK: Testing
/// Render the current tree off-screen with the same node mapping the loop uses. Plain text
/// (trailing spaces trimmed, one "\n" per row) unless `ansi`; ANSI output is always rendered
/// with true colour so it doesn't depend on the environment. `height` <= 0 fits the content.
- (NSString *)renderToStringWidth:(NSInteger)width height:(NSInteger)height ansi:(BOOL)ansi
    NS_SWIFT_NAME(renderToString(width:height:ansi:));
/// **Testing only.** Feed raw terminal input through FTXUI's parser as if typed. While the
/// loop runs the events are posted to it; otherwise they are handled synchronously on the
/// calling thread and `onEvent` fires before this returns. A trailing lone ESC is flushed.
- (void)injectInput:(NSString *)input;

@end

NS_ASSUME_NONNULL_END
