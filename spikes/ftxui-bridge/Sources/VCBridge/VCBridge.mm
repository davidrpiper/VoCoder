// ObjC++ implementation of the spike bridge: maps the VCNode tree to ftxui::Elements and owns
// the FTXUI App on its own thread.
#import "VCBridge.h"

#include <algorithm>
#include <cstdio>
#include <atomic>
#include <chrono>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "ftxui/component/app.hpp"
#include "ftxui/component/component.hpp"
#include "ftxui/component/component_base.hpp"
#include "ftxui/component/event.hpp"
#include "ftxui/dom/elements.hpp"
#include "ftxui/screen/screen.hpp"
#include "ftxui/screen/string.hpp"
#include "ftxui/screen/terminal.hpp"

// MARK: - VCNode

typedef NS_ENUM(NSInteger, VCNodeKind) {
  VCNodeKindText,
  VCNodeKindVBox,
  VCNodeKindHBox,
  VCNodeKindSeparator,
  VCNodeKindFiller,
  VCNodeKindInput,
  VCNodeKindBorder,
};

@interface VCNode ()
@property(nonatomic, readonly) VCNodeKind kind;
@property(nonatomic, readonly, copy) NSString *string;  // text, or input placeholder
@property(nonatomic, readonly, copy) NSString *widgetId;
@property(nonatomic, readonly, copy) NSArray<VCNode *> *children;
@property(nonatomic, readonly) VCStyle style;
@property(nonatomic, readonly) VCColor color;
@end

@implementation VCNode

- (instancetype)initWithKind:(VCNodeKind)kind
                      string:(NSString *)string
                    widgetId:(NSString *)widgetId
                    children:(NSArray<VCNode *> *)children
                       style:(VCStyle)style
                       color:(VCColor)color {
  if ((self = [super init])) {
    _kind = kind;
    _string = [string copy] ?: @"";
    _widgetId = [widgetId copy] ?: @"";
    _children = [children copy] ?: @[];
    _style = style;
    _color = color;
  }
  return self;
}

+ (VCNode *)make:(VCNodeKind)kind string:(NSString *)s children:(NSArray<VCNode *> *)c {
  return [[VCNode alloc] initWithKind:kind string:s widgetId:nil children:c style:VCStyleNone color:VCColorDefault];
}

+ (VCNode *)text:(NSString *)text { return [self make:VCNodeKindText string:text children:nil]; }
+ (VCNode *)vbox:(NSArray<VCNode *> *)children { return [self make:VCNodeKindVBox string:nil children:children]; }
+ (VCNode *)hbox:(NSArray<VCNode *> *)children { return [self make:VCNodeKindHBox string:nil children:children]; }
+ (VCNode *)separator { return [self make:VCNodeKindSeparator string:nil children:nil]; }
+ (VCNode *)filler { return [self make:VCNodeKindFiller string:nil children:nil]; }

+ (VCNode *)inputWithId:(NSString *)widgetId placeholder:(NSString *)placeholder {
  return [[VCNode alloc] initWithKind:VCNodeKindInput string:placeholder widgetId:widgetId children:nil style:VCStyleNone color:VCColorDefault];
}

- (VCNode *)bordered {
  return [VCNode make:VCNodeKindBorder string:nil children:@[ self ]];
}

- (VCNode *)styled:(VCStyle)style {
  return [[VCNode alloc] initWithKind:_kind string:_string widgetId:_widgetId children:_children style:_style | style color:_color];
}

- (VCNode *)color:(VCColor)color {
  return [[VCNode alloc] initWithKind:_kind string:_string widgetId:_widgetId children:_children style:_style color:color];
}

@end

// MARK: - VCEvent

@implementation VCEvent

- (instancetype)initWithKind:(VCEventKind)kind
                         key:(NSString *)key
                      rawHex:(NSString *)rawHex
                    widgetId:(NSString *)widgetId
                       value:(NSString *)value
                       width:(NSInteger)width
                      height:(NSInteger)height {
  if ((self = [super init])) {
    _kind = kind;
    _key = [key copy] ?: @"";
    _rawHex = [rawHex copy] ?: @"";
    _widgetId = [widgetId copy];
    _value = [value copy];
    _width = width;
    _height = height;
  }
  return self;
}

- (NSString *)description {
  switch (_kind) {
    case VCEventKindKey: return [NSString stringWithFormat:@"key %@ [%@]", _key, _rawHex];
    case VCEventKindWidgetChanged: return [NSString stringWithFormat:@"widget %@ = %@", _widgetId, _value];
    case VCEventKindResize: return [NSString stringWithFormat:@"resize %ldx%ld", (long)_width, (long)_height];
  }
}

@end

// MARK: - C++ helpers

namespace {

NSString *ToNS(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

std::string ToStd(NSString *s) {
  const char *utf8 = s.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

NSString *HexOf(const std::string &bytes) {
  NSMutableString *out = [NSMutableString string];
  for (unsigned char c : bytes) [out appendFormat:@"%02x ", c];
  return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// Normalised key name from an FTXUI event. Only what the spike needs; the real bridge will map
// the full FTXUI event table.
NSString *KeyName(const ftxui::Event &e) {
  using ftxui::Event;
  static const std::map<std::string, NSString *> named = {
      {Event::Return.input(), @"Enter"},     {Event::Escape.input(), @"Esc"},
      {Event::Tab.input(), @"Tab"},          {Event::TabReverse.input(), @"Shift-Tab"},
      {Event::Backspace.input(), @"Backspace"}, {Event::Delete.input(), @"Delete"},
      {Event::ArrowLeft.input(), @"ArrowLeft"}, {Event::ArrowRight.input(), @"ArrowRight"},
      {Event::ArrowUp.input(), @"ArrowUp"},  {Event::ArrowDown.input(), @"ArrowDown"},
      {Event::Home.input(), @"Home"},        {Event::End.input(), @"End"},
      {Event::PageUp.input(), @"PageUp"},    {Event::PageDown.input(), @"PageDown"},
  };
  const std::string &in = e.input();
  if (auto it = named.find(in); it != named.end()) return it->second;
  if (in.size() == 1) {
    unsigned char c = in[0];
    if (c == 0x00) return @"Ctrl-Space";
    if (c >= 0x01 && c <= 0x1a) return [NSString stringWithFormat:@"Ctrl-%c", 'a' + c - 1];
  }
  if (in.size() == 2 && in[0] == 0x1b) {
    unsigned char c = in[1];
    if (c == 0x00) return @"Ctrl-Alt-Space";
    if (c >= 0x20 && c < 0x7f) return [NSString stringWithFormat:@"Alt-%c", c];
  }
  // CSI u ("fixterms"/kitty-style): ESC [ codepoint ; modifiers u. Ghostty sends this by default
  // for keys that are otherwise ambiguous (Ctrl-I vs Tab, Ctrl-M vs Enter); FTXUI doesn't parse it.
  if (in.size() > 3 && in[0] == 0x1b && in[1] == '[' && in.back() == 'u') {
    unsigned code = 0, mods = 1;
    if (sscanf(in.c_str() + 2, "%u;%uu", &code, &mods) >= 1 && code > 0 && code < 0x110000) {
      unsigned m = mods > 0 ? mods - 1 : 0;  // xterm encoding: 1 + bitmask(shift=1, alt=2, ctrl=4)
      NSString *base = code == 32 ? @"Space" : code == 9 ? @"Tab" : code == 13 ? @"Enter" : code == 27 ? @"Esc"
                       : [[NSString alloc] initWithBytes:&code length:4 encoding:NSUTF32LittleEndianStringEncoding];
      NSMutableString *name = [NSMutableString string];
      if (m & 4) [name appendString:@"Ctrl-"];
      if (m & 2) [name appendString:@"Alt-"];
      if (m & 1) [name appendString:@"Shift-"];
      [name appendString:base ?: @"?"];
      return name;
    }
  }
  if (e.is_character()) return ToNS(in);
  return [@"?" stringByAppendingString:HexOf(in)];
}

ftxui::Color ToColor(VCColor c) {
  switch (c) {
    case VCColorDefault: return ftxui::Color::Default;
    case VCColorRed: return ftxui::Color::Red;
    case VCColorGreen: return ftxui::Color::Green;
    case VCColorYellow: return ftxui::Color::Yellow;
    case VCColorBlue: return ftxui::Color::Blue;
    case VCColorMagenta: return ftxui::Color::Magenta;
    case VCColorCyan: return ftxui::Color::Cyan;
    case VCColorGray: return ftxui::Color::GrayDark;
  }
  return ftxui::Color::Default;
}

// Private redraw event. Not Event::Custom: that is Special({0}), the same byte Ctrl-Space sends,
// so using it would swallow the leader key.
const ftxui::Event &RedrawEvent() {
  static const ftxui::Event event = ftxui::Event::Special("\x1b[vocoder-redraw]");
  return event;
}

struct Widget {
  std::unique_ptr<std::string> content = std::make_unique<std::string>();
  ftxui::Component component;
};

}  // namespace

// MARK: - Bridge state (shared between threads)

// Everything the FTXUI thread and callers share, guarded by one mutex. Kept in a C++ object so
// the root component can hold it without retaining the ObjC renderer.
struct BridgeState {
  std::recursive_mutex mutex;  // recursive: Input::Render -> Focused() -> ActiveChild() re-enters
  VCNode *root = nil;
  std::map<std::string, Widget> widgets;
  std::string focused;
  ftxui::App *app = nullptr;  // non-null only while the loop runs
  std::atomic<bool> redrawPending{false};
  std::atomic<NSUInteger> framesDrawn{0};
  // setRoot -> drawn latency, for the spike's measurements.
  std::chrono::steady_clock::time_point requestedAt;
  double latencySumMs = 0, latencyMaxMs = 0;
  NSUInteger latencySamples = 0;
  int lastWidth = -1, lastHeight = -1;
  void (^onEvent)(VCEvent *) = nil;

  // Requires mutex held.
  Widget &WidgetFor(const std::string &widgetId, const std::string &placeholder) {
    auto it = widgets.find(widgetId);
    if (it != widgets.end()) return it->second;
    Widget w;
    ftxui::InputOption opt;
    opt.multiline = false;
    w.component = ftxui::Input(w.content.get(), placeholder, opt);
    return widgets.emplace(widgetId, std::move(w)).first->second;
  }

  // Requires mutex held.
  ftxui::Element Build(VCNode *node) {
    // Qualify everything: MacTypes.h declares `bold` etc. at global scope.
    namespace F = ftxui;
    if (!node) return F::text("");
    F::Element el;
    switch (node.kind) {
      case VCNodeKindText: el = F::text(ToStd(node.string)); break;
      case VCNodeKindSeparator: el = F::separator(); break;
      case VCNodeKindFiller: el = F::filler(); break;
      case VCNodeKindVBox:
      case VCNodeKindHBox: {
        F::Elements children;
        for (VCNode *c in node.children) children.push_back(Build(c));
        el = node.kind == VCNodeKindVBox ? F::vbox(std::move(children)) : F::hbox(std::move(children));
        break;
      }
      case VCNodeKindBorder: el = F::border(Build(node.children.firstObject)); break;
      case VCNodeKindInput: {
        auto &w = WidgetFor(ToStd(node.widgetId), ToStd(node.string));
        el = w.component->Render();
        break;
      }
    }
    VCStyle s = node.style;
    if (s & VCStyleBold) el = el | F::bold;
    if (s & VCStyleDim) el = el | F::dim;
    if (s & VCStyleInverted) el = el | F::inverted;
    if (s & VCStyleFlex) el = el | F::flex;
    if (node.color != VCColorDefault) el = el | F::color(ToColor(node.color));
    return el;
  }

  void Emit(VCEvent *event) {
    void (^cb)(VCEvent *) = onEvent;
    if (cb) cb(event);
  }
};

// Root component: routes keys to the focused input first, everything else to Swift. Swift owns
// focus; the active child exists so FTXUI's Focused() is true for the focused input (cursor).
class RootComponent : public ftxui::ComponentBase {
 public:
  explicit RootComponent(std::shared_ptr<BridgeState> state) : state_(std::move(state)) {}

  ftxui::Element OnRender() override {
    auto size = ftxui::Terminal::Size();
    VCEvent *resize = nil;
    ftxui::Element el;
    {
      std::lock_guard<std::recursive_mutex> lock(state_->mutex);
      SyncChildren();
      el = state_->Build(state_->root);
      if (size.dimx != state_->lastWidth || size.dimy != state_->lastHeight) {
        state_->lastWidth = size.dimx;
        state_->lastHeight = size.dimy;
        resize = [[VCEvent alloc] initWithKind:VCEventKindResize key:nil rawHex:nil widgetId:nil value:nil width:size.dimx height:size.dimy];
      }
    }
    if (state_->redrawPending.exchange(false)) {
      std::lock_guard<std::recursive_mutex> lock(state_->mutex);
      double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - state_->requestedAt).count();
      state_->latencySumMs += ms;
      state_->latencyMaxMs = std::max(state_->latencyMaxMs, ms);
      state_->latencySamples++;
    }
    state_->framesDrawn++;
    if (resize) state_->Emit(resize);
    return el;
  }

  bool OnEvent(ftxui::Event event) override {
    if (event == RedrawEvent()) return true;  // redraw request from setRoot
    if (event.is_mouse() || event.is_cursor_position()) return false;
    // FTXUI posts Special({0}) for SIGWINCH (and selection changes); the terminal sends the same
    // byte for Ctrl-Space. Disambiguate by size: a resize changes it, a key press doesn't.
    if (event.input().size() == 1 && event.input()[0] == 0) {
      auto size = ftxui::Terminal::Size();
      std::lock_guard<std::recursive_mutex> lock(state_->mutex);
      if (size.dimx != state_->lastWidth || size.dimy != state_->lastHeight) return true;
    }

    VCEvent *changed = nil;
    bool handled = false;
    {
      std::lock_guard<std::recursive_mutex> lock(state_->mutex);
      auto it = state_->widgets.find(state_->focused);
      // Esc, Tab and Ctrl-C are navigation/commands, never text: always give them to Swift.
      bool navigation = event == ftxui::Event::Escape || event == ftxui::Event::Tab ||
                        event == ftxui::Event::TabReverse || event == ftxui::Event::CtrlC;
      if (it != state_->widgets.end() && !navigation) {
        std::string before = *it->second.content;
        handled = it->second.component->OnEvent(event);
        if (*it->second.content != before) {
          changed = [[VCEvent alloc] initWithKind:VCEventKindWidgetChanged key:nil rawHex:nil
                                         widgetId:ToNS(state_->focused) value:ToNS(*it->second.content) width:0 height:0];
        }
      }
    }
    if (changed) state_->Emit(changed);
    if (handled) return true;
    state_->Emit([[VCEvent alloc] initWithKind:VCEventKindKey key:KeyName(event) rawHex:HexOf(event.input())
                                      widgetId:nil value:nil width:0 height:0]);
    // Every key is handled here; Ctrl-C included (ForceHandleCtrlC(false)), so Swift decides.
    return true;
  }

  ftxui::Component ActiveChild() override {
    std::lock_guard<std::recursive_mutex> lock(state_->mutex);
    auto it = state_->widgets.find(state_->focused);
    return it == state_->widgets.end() ? nullptr : it->second.component;
  }

  bool Focusable() const override { return true; }

 private:
  // Requires mutex held. Inputs must be children so Focused()/Active() resolve.
  void SyncChildren() {
    if (ChildCount() == state_->widgets.size()) return;
    DetachAllChildren();
    for (auto &[id, w] : state_->widgets) Add(w.component);
  }

  std::shared_ptr<BridgeState> state_;
};

// MARK: - VCRenderer

@implementation VCRenderer {
  std::shared_ptr<BridgeState> _state;
  std::thread _thread;
}

- (instancetype)init {
  if ((self = [super init])) {
    _state = std::make_shared<BridgeState>();
  }
  return self;
}

- (void)dealloc {
  if (_thread.joinable()) _thread.detach();
}

- (void)setOnEvent:(void (^)(VCEvent *))onEvent {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->onEvent = [onEvent copy];
}

- (void (^)(VCEvent *))onEvent {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _state->onEvent;
}

- (NSUInteger)framesDrawn {
  return _state->framesDrawn.load();
}

- (NSString *)latencySummary {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  double avg = _state->latencySamples ? _state->latencySumMs / _state->latencySamples : 0;
  return [NSString stringWithFormat:@"redraw latency avg %.2f ms max %.2f ms over %lu", avg, _state->latencyMaxMs,
                                    (unsigned long)_state->latencySamples];
}

- (void)setRoot:(VCNode *)root {
  ftxui::App *app = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(_state->mutex);
    _state->root = root;
    app = _state->app;
    // Coalesce: one pending redraw at most, no matter how often setRoot is called.
    if (app && _state->redrawPending.exchange(true)) return;
    _state->requestedAt = std::chrono::steady_clock::now();
    if (app) app->PostEvent(RedrawEvent());  // thread-safe since FTXUI 7.0.2
  }
}

- (void)setFocusedWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->focused = widgetId ? ToStd(widgetId) : std::string();
}

- (NSString *)valueForWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  auto it = _state->widgets.find(ToStd(widgetId));
  return it == _state->widgets.end() ? nil : ToNS(*it->second.content);
}

- (void)setValue:(NSString *)value forWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  *_state->WidgetFor(ToStd(widgetId), "").content = ToStd(value);
}

- (void)start {
  auto state = _state;
  void (^onExit)(void) = self.onExit;
  _thread = std::thread([state, onExit] {
    auto app = ftxui::App::Fullscreen();
    app.TrackMouse(false);
    // Ctrl-C is a key for Swift (e.g. interrupt the agent), not a SIGINT raised by FTXUI.
    app.ForceHandleCtrlC(false);
    auto root = std::make_shared<RootComponent>(state);
    {
      std::lock_guard<std::recursive_mutex> lock(state->mutex);
      state->app = &app;
    }
    app.Loop(root);
    {
      std::lock_guard<std::recursive_mutex> lock(state->mutex);
      state->app = nullptr;
    }
    if (onExit) onExit();
  });
}

- (void)stop {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  if (_state->app) _state->app->Exit();
}

- (NSString *)renderToStringWidth:(NSInteger)width height:(NSInteger)height ansi:(BOOL)ansi {
  ftxui::Element el;
  {
    std::lock_guard<std::recursive_mutex> lock(_state->mutex);
    el = _state->Build(_state->root);
  }
  auto screen = ftxui::Screen::Create(ftxui::Dimension::Fixed((int)width), ftxui::Dimension::Fixed((int)height));
  ftxui::Render(screen, el);
  if (ansi) return ToNS(screen.ToString());
  std::string out;
  for (int y = 0; y < screen.dimy(); ++y) {
    std::string line;
    // Mirrors Screen::ToString: empty cells are spaces; the cell after a full-width glyph is skipped.
    bool previousFullwidth = false;
    for (int x = 0; x < screen.dimx(); ++x) {
      const std::string &c = screen.CellAt(x, y).character;
      if (!previousFullwidth) line += c.empty() ? std::string(" ") : c;
      previousFullwidth = c.size() > 1 && ftxui::string_width(c) == 2;
    }
    while (!line.empty() && line.back() == ' ') line.pop_back();
    out += line;
    out += '\n';
  }
  return ToNS(out);
}

@end
