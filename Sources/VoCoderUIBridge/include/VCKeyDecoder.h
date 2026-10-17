// Key normalisation: terminal bytes → the key names the command system binds to.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Maps the bytes of one key press to a normalised name.
///
/// Names: printable characters as themselves ("a", "A", "é", "?"), "Space", "Enter", "Tab",
/// "Shift-Tab", "Esc", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown",
/// "ArrowUp/Down/Left/Right", "F1"…"F12". Modifiers prefix the name in the order
/// "Ctrl-Alt-Shift-": "Ctrl-a", "Alt-1", "Ctrl-ArrowLeft", "Shift-F5". Control letters are
/// lowercase ("Ctrl-p"). Ctrl-Space is NUL ("Ctrl-Space").
///
/// Terminal limits: Ctrl-H is Backspace, Ctrl-I is Tab and Ctrl-J/Ctrl-M are Enter unless the
/// terminal sends CSI-u (`ESC [ code ; mods u`, e.g. Ghostty's Ctrl-I), which is decoded, as is
/// xterm's `ESC [ 27 ; mods ; code ~`. Unknown sequences are "?" followed by the hex bytes.
@interface VCKeyDecoder : NSObject
+ (NSString *)keyNameForBytes:(NSData *)bytes;
/// Convenience for tests: the UTF-8 bytes of `input` (NUL characters included).
+ (NSString *)keyNameForInput:(NSString *)input;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
