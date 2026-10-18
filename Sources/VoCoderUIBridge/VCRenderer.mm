// VCRenderer: owns the FTXUI App on its own thread (DESIGN §4.3), the root component and the
// shared bridge state.
#import "VCRenderer.h"

#import "BridgeInternal.h"

#include <algorithm>
#include <mutex>
#include <thread>

#include "ftxui/component/app.hpp"
#include "ftxui/component/terminal_input_parser.hpp"
#include "ftxui/dom/node.hpp"
#include "ftxui/screen/screen.hpp"
#include "ftxui/screen/string.hpp"
#include "ftxui/screen/terminal.hpp"

namespace {

// Height `el` needs at `width`. Dimension::Fit lays out at the terminal's width instead, which
// gets wrapping paragraphs wrong off-screen.
int FitHeight(ftxui::Element &el, int width) {
  ftxui::Node::Status status;
  el->Check(&status);
  int height = 0;
  for (int i = 0; i < 20; ++i) {
    el->ComputeRequirement();
    height = el->requirement().min_y;
    el->SetBox({0, width - 1, 0, std::max(0, height - 1)});
    status.need_iteration = false;
    status.iteration++;
    el->Check(&status);
    if (!status.need_iteration) break;
  }
  return std::max(1, height);
}

ftxui::Terminal::Color ToFTXUI(VCColorDepth depth) {
  switch (depth) {
    case VCColorDepthMonochrome: return ftxui::Terminal::Palette1;
    case VCColorDepthPalette16: return ftxui::Terminal::Palette16;
    case VCColorDepthPalette256: return ftxui::Terminal::Palette256;
    case VCColorDepthTrueColor: return ftxui::Terminal::TrueColor;
  }
  return ftxui::Terminal::TrueColor;
}

VCColorDepth FromFTXUI(ftxui::Terminal::Color color) {
  switch (color) {
    case ftxui::Terminal::Palette1: return VCColorDepthMonochrome;
    case ftxui::Terminal::Palette16: return VCColorDepthPalette16;
    case ftxui::Terminal::Palette256: return VCColorDepthPalette256;
    case ftxui::Terminal::TrueColor: return VCColorDepthTrueColor;
  }
  return VCColorDepthTrueColor;
}

// Plain text of `screen`: trailing spaces trimmed, one "\n" per row.
NSString *VCPlainText(ftxui::Screen &screen) {
  std::string out;
  for (int y = 0; y < screen.dimy(); ++y) {
    std::string line;
    // Mirrors Screen::ToString: empty cells are spaces; the cell after a full-width glyph is
    // skipped.
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
  return VCToNS(out);
}

}  // namespace

namespace {
// Colour support is process-global in FTXUI; ANSI off-screen renders pin it one at a time.
std::mutex gColorPinMutex;
}  // namespace

@implementation VCRenderer {
  std::shared_ptr<VCBridgeState> _state;
  std::shared_ptr<VCRootComponent> _root;
  std::thread _thread;
  void (^_onExit)(void);
  std::atomic<bool> _running;
}

+ (void)initialize {
  if (self == [VCRenderer class]) {
    // FTXUI initialises its terminal quirks lazily and without a lock; do it once, here.
    (void)ftxui::Terminal::ColorSupport();
  }
}

- (instancetype)init {
  if ((self = [super init])) {
    _state = std::make_shared<VCBridgeState>();
    _root = std::make_shared<VCRootComponent>(_state);
    _running = false;
  }
  return self;
}

- (void)dealloc {
  if (_thread.joinable()) _thread.detach();
}

// MARK: Properties

- (void)setOnEvent:(void (^)(VCEvent *))onEvent {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->onEvent = [onEvent copy];
}

- (void (^)(VCEvent *))onEvent {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _state->onEvent;
}

- (void)setOnExit:(void (^)(void))onExit {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _onExit = [onExit copy];
}

- (void (^)(void))onExit {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _onExit;
}

- (void)setTrackMouse:(BOOL)trackMouse {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->trackMouse = trackMouse;
}

- (BOOL)trackMouse {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _state->trackMouse;
}

- (BOOL)isRunning {
  return _running.load();
}

- (NSUInteger)framesDrawn {
  return _state->framesDrawn.load();
}

+ (VCColorDepth)colorDepth {
  std::lock_guard<std::mutex> pin(gColorPinMutex);
  return FromFTXUI(ftxui::Terminal::ColorSupport());
}

+ (void)setColorDepth:(VCColorDepth)colorDepth {
  std::lock_guard<std::mutex> pin(gColorPinMutex);
  ftxui::Terminal::SetColorSupport(ToFTXUI(colorDepth));
}

// MARK: Tree

- (void)setRoot:(VCNode *)root {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->root = root;
  _state->Register(root);
  [self requestRedrawLocked];
}

/// Requires the mutex. At most one redraw is pending, however often this is called.
- (void)requestRedrawLocked {
  if (!_state->app || _state->redrawPending.exchange(true)) return;
  _state->app->PostEvent(VCRedrawEvent());  // thread-safe since FTXUI 7.0.2
}

// MARK: Widgets

- (void)setFocusedWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->focused = widgetId ? VCToStd(widgetId) : std::string();
  [self requestRedrawLocked];
}

- (NSString *)focusedWidget {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _state->focused.empty() ? nil : VCToNS(_state->focused);
}

- (void)setSuspendingKey:(NSString *)key {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  _state->suspendingKey = key ? VCToStd(key) : std::string();
}

- (NSString *)suspendingKey {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  return _state->suspendingKey.empty() ? nil : VCToNS(_state->suspendingKey);
}

- (NSString *)stringValueForWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  auto it = _state->widgets.find(VCToStd(widgetId));
  if (it == _state->widgets.end()) return nil;
  auto kind = it->second.kind;
  if (kind != VCWidgetKind::Input && kind != VCWidgetKind::Unknown) return nil;
  return VCToNS(it->second.content);
}

- (void)setStringValue:(NSString *)value forWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  VCWidget &w = _state->Widget(VCToStd(widgetId), VCWidgetKind::Unknown);
  w.content = VCToStd(value);
  w.cursor = w.pendingInteger = int(w.content.size());
  [self requestRedrawLocked];
}

- (NSInteger)integerValueForWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  auto it = _state->widgets.find(VCToStd(widgetId));
  if (it == _state->widgets.end()) return VCNoValue;
  const VCWidget &w = it->second;
  switch (w.kind) {
    case VCWidgetKind::Input: return w.cursor;
    case VCWidgetKind::Menu: return w.selected;
    case VCWidgetKind::ScrollFrame: return w.scrollOffset->load();
    case VCWidgetKind::Unknown: return w.pendingInteger;
  }
  return VCNoValue;
}

- (void)setIntegerValue:(NSInteger)value forWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  VCWidget &w = _state->Widget(VCToStd(widgetId), VCWidgetKind::Unknown);
  int v = int(std::clamp<NSInteger>(value, 0, INT_MAX));
  switch (w.kind) {
    case VCWidgetKind::Input: w.cursor = std::min(v, int(w.content.size())); break;
    case VCWidgetKind::Menu: w.selected = w.focusedEntry = v; break;  // clamped when built
    case VCWidgetKind::ScrollFrame: w.scrollOffset->store(v); break;  // clamped in layout
    case VCWidgetKind::Unknown: w.pendingInteger = v; break;
  }
  [self requestRedrawLocked];
}

- (void)removeWidget:(NSString *)widgetId {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  if (_state->widgets.erase(VCToStd(widgetId))) _state->generation++;
}

- (NSArray<NSString *> *)widgetIds {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  NSMutableArray<NSString *> *ids = [NSMutableArray array];
  for (auto &[id, w] : _state->widgets) [ids addObject:VCToNS(id)];
  return ids;
}

// MARK: Lifecycle

- (void)start {
  if (_running.exchange(true)) return;
  if (_thread.joinable()) _thread.join();  // a previous loop has finished
  auto state = _state;
  auto root = _root;
  bool trackMouse = self.trackMouse;
  // The block is read at exit, so it may be set or changed after start.
  __weak VCRenderer *weakSelf = self;
  _thread = std::thread([state, root, trackMouse, weakSelf] {
    auto app = ftxui::App::Fullscreen();
    app.TrackMouse(trackMouse);
    // Ctrl-C is a key for Swift (e.g. interrupt the agent), not a SIGINT raised by FTXUI.
    app.ForceHandleCtrlC(false);
    {
      std::lock_guard<std::recursive_mutex> lock(state->mutex);
      state->app = &app;
      state->lastWidth = state->lastHeight = -1;
    }
    state->homeCursorBeforeNextFrame.store(true);
    VCArmTrapRestore();
    app.Loop(root);
    VCDisarmTrapRestore();
    void (^onExit)(void) = nil;
    {
      std::lock_guard<std::recursive_mutex> lock(state->mutex);
      state->app = nullptr;
      state->redrawPending.store(false);
    }
    VCRenderer *strongSelf = weakSelf;
    if (strongSelf) {
      onExit = strongSelf.onExit;
      strongSelf->_running.store(false);
    }
    if (onExit) onExit();
  });
}

- (void)stop {
  std::lock_guard<std::recursive_mutex> lock(_state->mutex);
  if (_state->app) _state->app->Exit();
}

- (void)runSuspended:(void (^)(void))block {
  ftxui::App *app = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(_state->mutex);
    app = _state->app;
    if (app) {
      // Post runs the closure on the loop thread; WithRestoredIO uninstalls the terminal
      // setup around it and redraws afterwards.
      auto state = _state;
      app->Post([app, block, state] {
        app->WithRestoredIO([block, state] {
          block();
          state->homeCursorBeforeNextFrame.store(true);  // FTXUI reinstalls, queries again
        })();
      });
      return;
    }
  }
  block();
}

// MARK: Testing

- (NSString *)renderToStringWidth:(NSInteger)width height:(NSInteger)height ansi:(BOOL)ansi {
  // Pin true colour for ANSI output so snapshots don't depend on the environment ($COLORTERM,
  // no tty).
  if (ansi) return [self renderToStringWidth:width height:height colorDepth:VCColorDepthTrueColor];
  ftxui::Screen screen = [self renderScreenWidth:width height:height];
  return VCPlainText(screen);
}

- (NSString *)renderToStringWidth:(NSInteger)width
                           height:(NSInteger)height
                       colorDepth:(VCColorDepth)depth {
  // FTXUI applies colour support while building, so pin it around the whole render.
  std::lock_guard<std::mutex> pin(gColorPinMutex);
  auto support = ftxui::Terminal::ColorSupport();
  ftxui::Terminal::SetColorSupport(ToFTXUI(depth));
  ftxui::Screen screen = [self renderScreenWidth:width height:height];
  NSString *out = VCToNS(screen.ToString());
  ftxui::Terminal::SetColorSupport(support);
  return out;
}

- (ftxui::Screen)renderScreenWidth:(NSInteger)width height:(NSInteger)height {
  ftxui::Element el = _root->BuildTree();
  int w = int(std::max<NSInteger>(1, width));
  int h = height > 0 ? int(height) : FitHeight(el, w);
  auto screen = ftxui::Screen::Create(ftxui::Dimension::Fixed(w), ftxui::Dimension::Fixed(h));
  ftxui::Render(screen, el);
  return screen;
}


- (void)injectInput:(NSString *)input {
  std::vector<ftxui::Event> events;
  ftxui::TerminalInputParser parser([&events](ftxui::Event event) {
    events.push_back(std::move(event));
  });
  for (char c : VCToStd(input)) parser.Add(c);
  parser.Timeout(1000);  // flush a trailing lone ESC
  {
    std::lock_guard<std::recursive_mutex> lock(_state->mutex);
    if (_state->app) {
      for (auto &event : events) _state->app->PostEvent(event);
      return;
    }
  }
  for (auto &event : events) {
    if (event.is_mouse()) {
      // The loop makes coordinates 0-based (relative to the fullscreen origin); do the same.
      event.mouse().x -= 1;
      event.mouse().y -= 1;
    }
    _root->OnEvent(event);
  }
}

@end
