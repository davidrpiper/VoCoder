// Private C++ side of the bridge, shared by the .mm files. Never imported by Swift.
// Never `using namespace ftxui;` here or in .mm files: MacTypes.h declares `bold` etc. globally.
#pragma once

#import "VCColor.h"
#import "VCEvent.h"
#import "VCNode.h"

#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "ftxui/component/component.hpp"
#include "ftxui/component/component_base.hpp"
#include "ftxui/component/event.hpp"
#include "ftxui/dom/elements.hpp"
#include "ftxui/screen/color.hpp"

namespace ftxui {
class App;
}

// MARK: - Conversions (BridgeState.mm)

NSString *VCToNS(const std::string &s);
std::string VCToStd(NSString *s);
NSString *VCHexOf(const std::string &bytes);

// MARK: - Key names (VCKeyDecoder.mm)

NSString *VCKeyName(const std::string &input);

// MARK: - Colours and nodes

@interface VCColor ()
- (ftxui::Color)ftxuiColor;
@end

typedef NS_ENUM(NSInteger, VCNodeKind) {
  VCNodeKindVBox,
  VCNodeKindHBox,
  VCNodeKindDBox,
  VCNodeKindFiller,
  VCNodeKindSeparator,
  VCNodeKindText,
  VCNodeKindParagraph,
  VCNodeKindGauge,
  VCNodeKindSpinner,
  VCNodeKindTable,
  VCNodeKindTabBar,
  VCNodeKindInput,
  VCNodeKindMenu,
  VCNodeKindScrollFrame,
};

/// A modifier, applied in the order it was added.
struct VCDecorator {
  enum class Type { Style, Foreground, Background, Flex, Width, Height, Align, Border, FocusMarker, ClearUnder };
  Type type;
  NSInteger a = 0;
  NSInteger b = 0;
  VCColor *color = nil;
  NSString *title = nil;
};

@interface VCNode ()
@property(nonatomic, readonly) VCNodeKind kind;
/// Text, paragraph, input placeholder.
@property(nonatomic, readonly, copy) NSString *string;
@property(nonatomic, readonly, copy) NSString *widgetId;
@property(nonatomic, readonly, copy) NSArray<VCNode *> *children;
/// Table rows.
@property(nonatomic, readonly, copy) NSArray<NSArray<VCNode *> *> *rows;
/// Tab titles, menu entries.
@property(nonatomic, readonly, copy) NSArray<NSString *> *strings;
/// Axis, spinner charset, table options, selected tab.
@property(nonatomic, readonly) NSInteger integer;
/// Spinner frame.
@property(nonatomic, readonly) NSInteger integer2;
@property(nonatomic, readonly) float number;
/// Input multiline, scroll frame following end.
@property(nonatomic, readonly) BOOL flag;
- (const std::vector<VCDecorator> &)decorators;
@end

// MARK: - Events (VCEvent.mm)

@interface VCEvent ()
+ (VCEvent *)keyEvent:(NSString *)key rawHex:(NSString *)rawHex;
+ (VCEvent *)mouseEvent:(ftxui::Mouse)mouse rawHex:(NSString *)rawHex;
+ (VCEvent *)widgetEvent:(VCEventKind)kind
                widgetId:(NSString *)widgetId
             stringValue:(NSString *)stringValue
            integerValue:(NSInteger)integerValue;
+ (VCEvent *)resizeEventWidth:(NSInteger)width height:(NSInteger)height;
@end

// MARK: - Bridge state (BridgeState.mm)

enum class VCWidgetKind { Unknown, Input, Menu, ScrollFrame };

/// State of one stateful widget. Lives in a std::map node, so its address is stable and FTXUI
/// components can point into it.
struct VCWidget {
  VCWidgetKind kind = VCWidgetKind::Unknown;
  // Input
  std::string content;
  std::string placeholder;
  int cursor = 0;
  bool multiline = false;
  // Menu
  std::vector<std::string> entries;
  int selected = 0;
  int focusedEntry = 0;
  // Scroll frame: written during layout, outside the bridge mutex.
  std::shared_ptr<std::atomic<int>> scrollOffset = std::make_shared<std::atomic<int>>(0);
  // Input/menu value set before the kind was known.
  int pendingInteger = 0;

  ftxui::Component component;  // input and menu only
};

/// Everything the FTXUI thread and callers share, guarded by `mutex`. Kept in a C++ object so
/// the root component can hold it without retaining the ObjC renderer.
struct VCBridgeState {
  // Recursive: Input::Render -> Focused() -> ActiveChild() re-enters the bridge.
  std::recursive_mutex mutex;
  VCNode *root = nil;
  std::map<std::string, VCWidget> widgets;
  /// Bumped whenever the set of components changes, so the root re-adds its children.
  unsigned generation = 0;
  std::string focused;
  ftxui::App *app = nullptr;  // non-null only while the loop runs
  int lastWidth = -1, lastHeight = -1;
  bool trackMouse = false;
  std::atomic<bool> redrawPending{false};
  std::atomic<NSUInteger> framesDrawn{0};
  void (^onEvent)(VCEvent *) = nil;

  // All of the following require `mutex` held.
  VCWidget &Widget(const std::string &widgetId, VCWidgetKind kind);
  /// Creates or updates the state of every widget in the tree, so values and input work
  /// before the first frame is drawn.
  void Register(VCNode *node);
  ftxui::Element Build(VCNode *node);
  void Emit(VCEvent *event);  // call without the mutex held

 private:
  ftxui::Element BuildBase(VCNode *node);
  /// Widget state for a widget node, updated from the node; nullptr for other nodes.
  VCWidget *Update(VCNode *node);
};

/// Root component: routes keys to the focused widget first, everything else to Swift. Swift
/// owns focus; the active child exists so FTXUI's Focused() is true for the focused widget.
class VCRootComponent : public ftxui::ComponentBase {
 public:
  explicit VCRootComponent(std::shared_ptr<VCBridgeState> state) : state_(std::move(state)) {}

  /// Builds the current tree (also used off-screen). Takes the mutex.
  ftxui::Element BuildTree();

  ftxui::Element OnRender() override;
  bool OnEvent(ftxui::Event event) override;
  ftxui::Component ActiveChild() override;
  bool Focusable() const override { return true; }

 private:
  void SyncChildren();  // requires mutex held
  std::shared_ptr<VCBridgeState> state_;
  unsigned syncedGeneration_ = ~0u;
};

/// Private redraw event. Not Event::Custom: that is Special({0}), the same byte Ctrl-Space
/// sends, so using it would swallow the leader key (ADR 0001).
const ftxui::Event &VCRedrawEvent();

/// The scroll viewport node (ScrollFrame.mm).
ftxui::Element VCScrollFrame(ftxui::Element child, std::shared_ptr<std::atomic<int>> offset,
                             bool followEnd);

// MARK: - Crash restore (CrashRestore.mm)

/// While armed, SIGTRAP (Swift runtime traps) restores the terminal before the process dies.
/// Arm before the loop takes the terminal so the saved modes are the original ones.
void VCArmTrapRestore();
void VCDisarmTrapRestore();
