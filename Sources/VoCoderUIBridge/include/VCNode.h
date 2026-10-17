// The node vocabulary Swift uses to describe the screen (DESIGN §4.2). Swift builds a fresh,
// immutable tree each update and hands it to `-[VCRenderer setRoot:]`; C++ maps it to FTXUI.
#import <Foundation/Foundation.h>

#import "VCColor.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, VCTextStyle) {
  VCTextStyleNone = 0,
  VCTextStyleBold = 1 << 0,
  VCTextStyleDim = 1 << 1,
  VCTextStyleItalic = 1 << 2,
  VCTextStyleUnderlined = 1 << 3,
  VCTextStyleInverted = 1 << 4,
  VCTextStyleStrikethrough = 1 << 5,
};

typedef NS_ENUM(NSInteger, VCBorderStyle) {
  VCBorderStyleLight = 0,
  VCBorderStyleRounded,
  VCBorderStyleHeavy,
  VCBorderStyleDouble,
  VCBorderStyleDashed,
  /// Takes the space of a border but draws nothing.
  VCBorderStyleEmpty,
};

typedef NS_ENUM(NSInteger, VCFlex) {
  /// Grow and shrink on both axes.
  VCFlexBoth = 0,
  VCFlexHorizontal,
  VCFlexVertical,
  /// Reset any flex set further down the tree.
  VCFlexNone,
};

typedef NS_ENUM(NSInteger, VCSizeConstraint) {
  VCSizeConstraintLessThan = 0,
  VCSizeConstraintEqual,
  VCSizeConstraintGreaterThan,
};

typedef NS_ENUM(NSInteger, VCAlignment) {
  VCAlignmentCenterHorizontally = 0,
  VCAlignmentCenterVertically,
  VCAlignmentCenter,
};

typedef NS_ENUM(NSInteger, VCAxis) {
  VCAxisHorizontal = 0,
  VCAxisVertical,
};

typedef NS_OPTIONS(NSUInteger, VCTableOptions) {
  VCTableOptionsNone = 0,
  /// First row is a header: bold, with a separator below it.
  VCTableOptionsHeader = 1 << 0,
  VCTableOptionsBorder = 1 << 1,
  VCTableOptionsColumnSeparators = 1 << 2,
  VCTableOptionsRowSeparators = 1 << 3,
};

/// Immutable node in the UI tree. Modifiers return a new node and never change the receiver;
/// they apply in call order (`[[n styled:…] bordered]` styles the content, not the border).
NS_SWIFT_SENDABLE
@interface VCNode : NSObject

// MARK: Layout
+ (VCNode *)vbox:(NSArray<VCNode *> *)children;
+ (VCNode *)hbox:(NSArray<VCNode *> *)children;
/// Children drawn on top of each other (later ones on top).
+ (VCNode *)dbox:(NSArray<VCNode *> *)children;
+ (VCNode *)filler;
+ (VCNode *)separator;

// MARK: Content
/// A single line; never wraps.
+ (VCNode *)text:(NSString *)text;
/// Text that wraps at word boundaries to the available width.
+ (VCNode *)paragraph:(NSString *)text;
/// Progress in 0…1.
+ (VCNode *)gauge:(float)progress axis:(VCAxis)axis NS_SWIFT_NAME(gauge(_:axis:));
/// One frame of an FTXUI spinner; `charset` selects the glyph set (0…22), the caller advances
/// `frame` over time.
+ (VCNode *)spinnerWithCharset:(NSInteger)charset frame:(NSInteger)frame
    NS_SWIFT_NAME(spinner(charset:frame:));
/// Rows of cells. Rows may have different lengths.
+ (VCNode *)tableWithRows:(NSArray<NSArray<VCNode *> *> *)rows options:(VCTableOptions)options
    NS_SWIFT_NAME(table(_:options:));
/// A horizontal row of tab titles with the selected one highlighted (inverted, bold).
+ (VCNode *)tabBarWithTitles:(NSArray<NSString *> *)titles selected:(NSInteger)selected
    NS_SWIFT_NAME(tabBar(_:selected:));

// MARK: Stateful widgets (state lives in C++, keyed by a stable id that survives tree swaps)
/// Text input. Single-line inputs report Enter as `VCEventKindWidgetSubmitted`; multi-line
/// inputs insert a newline and leave submission to a key binding.
+ (VCNode *)inputWithId:(NSString *)widgetId
            placeholder:(NSString *)placeholder
              multiline:(BOOL)multiline NS_SWIFT_NAME(input(id:placeholder:multiline:));
/// Vertical selection list. The selected index is the widget's integer value; Enter reports
/// `VCEventKindWidgetSubmitted`.
+ (VCNode *)menuWithId:(NSString *)widgetId entries:(NSArray<NSString *> *)entries
    NS_SWIFT_NAME(menu(id:entries:));
/// Vertical scroll viewport over `child`. The first visible row is the widget's integer value.
/// A `focusMarker` inside `child` is kept visible; otherwise `followingEnd` pins the view to the
/// bottom (streaming output); otherwise the stored offset is used. The offset actually drawn is
/// written back after each layout. Shrinks to fit the space it is given.
+ (VCNode *)scrollFrameWithId:(NSString *)widgetId
                 followingEnd:(BOOL)followingEnd
                        child:(VCNode *)child
    NS_SWIFT_NAME(scrollFrame(id:followingEnd:child:));

// MARK: Modifiers
- (VCNode *)styled:(VCTextStyle)style;
- (VCNode *)foreground:(VCColor *)color;
- (VCNode *)background:(VCColor *)color;
- (VCNode *)flex:(VCFlex)flex;
- (VCNode *)width:(VCSizeConstraint)constraint value:(NSInteger)value NS_SWIFT_NAME(width(_:_:));
- (VCNode *)height:(VCSizeConstraint)constraint value:(NSInteger)value NS_SWIFT_NAME(height(_:_:));
- (VCNode *)aligned:(VCAlignment)alignment;
- (VCNode *)bordered;
- (VCNode *)borderedWithStyle:(VCBorderStyle)style title:(nullable NSString *)title
    NS_SWIFT_NAME(bordered(style:title:));
/// A border (and title) drawn in `color`; the content's colours are untouched. A nil `color`
/// is the same as `bordered(style:title:)`.
- (VCNode *)borderedWithStyle:(VCBorderStyle)style
                        title:(nullable NSString *)title
                        color:(nullable VCColor *)color
    NS_SWIFT_NAME(bordered(style:title:color:));
/// Marks this node as the one an enclosing scroll frame keeps visible (e.g. a selected row).
- (VCNode *)focusMarker;

- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
