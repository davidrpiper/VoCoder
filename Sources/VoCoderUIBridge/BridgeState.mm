// Node → ftxui::Element mapping, the widget registry and the root component that routes input.
#import "BridgeInternal.h"

#include <algorithm>

#include "ftxui/component/app.hpp"
#include "ftxui/dom/table.hpp"
#include "ftxui/screen/terminal.hpp"

// MARK: - Conversions

NSString *VCToNS(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]
             ?: @"";
}

std::string VCToStd(NSString *s) {
  NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
  return data ? std::string(static_cast<const char *>(data.bytes), data.length) : std::string();
}

NSString *VCHexOf(const std::string &bytes) {
  NSMutableString *out = [NSMutableString string];
  for (unsigned char c : bytes) [out appendFormat:out.length ? @" %02x" : @"%02x", c];
  return out;
}

const ftxui::Event &VCRedrawEvent() {
  static const ftxui::Event event = ftxui::Event::Special("\x1b[vocoder-redraw]");
  return event;
}

// MARK: - Widgets

VCWidget &VCBridgeState::Widget(const std::string &widgetId, VCWidgetKind kind) {
  auto it = widgets.find(widgetId);
  if (it == widgets.end()) {
    it = widgets.emplace(widgetId, VCWidget{}).first;
  }
  VCWidget &w = it->second;
  if (kind == VCWidgetKind::Unknown || w.kind == kind) return w;
  if (w.kind != VCWidgetKind::Unknown) {
    // The id now names a different kind of widget: start from fresh state.
    w = VCWidget{};
  }
  w.kind = kind;
  switch (kind) {
    case VCWidgetKind::Input: {
      w.cursor = std::clamp(w.pendingInteger, 0, int(w.content.size()));
      ftxui::InputOption option = ftxui::InputOption::Default();
      option.content = &w.content;
      option.placeholder = &w.placeholder;
      option.multiline = &w.multiline;
      option.cursor_position = &w.cursor;
      w.component = ftxui::Input(option);
      break;
    }
    case VCWidgetKind::Menu: {
      w.selected = w.focusedEntry = std::max(0, w.pendingInteger);
      ftxui::MenuOption option = ftxui::MenuOption::Vertical();
      option.entries = &w.entries;
      option.selected = &w.selected;
      option.focused_entry = &w.focusedEntry;
      w.component = ftxui::Menu(option);
      break;
    }
    case VCWidgetKind::ScrollFrame:
      w.scrollOffset->store(std::max(0, w.pendingInteger));
      break;
    case VCWidgetKind::Unknown:
      break;
  }
  generation++;
  return w;
}

// MARK: - Building

namespace {

namespace F = ftxui;  // qualify everything: MacTypes.h declares `bold` etc. globally

F::BorderStyle ToBorderStyle(NSInteger style) {
  switch (style) {
    case VCBorderStyleRounded: return F::ROUNDED;
    case VCBorderStyleHeavy: return F::HEAVY;
    case VCBorderStyleDouble: return F::DOUBLE;
    case VCBorderStyleDashed: return F::DASHED;
    case VCBorderStyleEmpty: return F::EMPTY;
    default: return F::LIGHT;
  }
}

F::Decorator SizeDecorator(F::WidthOrHeight direction, NSInteger constraint, NSInteger value) {
  F::Constraint c = constraint == VCSizeConstraintLessThan  ? F::LESS_THAN
                    : constraint == VCSizeConstraintEqual ? F::EQUAL
                                                          : F::GREATER_THAN;
  return F::size(direction, c, int(std::max<NSInteger>(0, value)));
}

F::Element Apply(F::Element el, const VCDecorator &d) {
  switch (d.type) {
    case VCDecorator::Type::Style: {
      auto s = VCTextStyle(d.a);
      if (s & VCTextStyleBold) el = el | F::bold;
      if (s & VCTextStyleDim) el = el | F::dim;
      if (s & VCTextStyleItalic) el = el | F::italic;
      if (s & VCTextStyleUnderlined) el = el | F::underlined;
      if (s & VCTextStyleInverted) el = el | F::inverted;
      if (s & VCTextStyleStrikethrough) el = el | F::strikethrough;
      return el;
    }
    case VCDecorator::Type::Foreground: return el | F::color([d.color ftxuiColor]);
    case VCDecorator::Type::Background: return el | F::bgcolor([d.color ftxuiColor]);
    case VCDecorator::Type::Flex:
      switch (d.a) {
        case VCFlexHorizontal: return el | F::xflex;
        case VCFlexVertical: return el | F::yflex;
        case VCFlexNone: return el | F::notflex;
        default: return el | F::flex;
      }
    case VCDecorator::Type::Width: return el | SizeDecorator(F::WIDTH, d.a, d.b);
    case VCDecorator::Type::Height: return el | SizeDecorator(F::HEIGHT, d.a, d.b);
    case VCDecorator::Type::Align:
      switch (d.a) {
        case VCAlignmentCenterHorizontally: return el | F::hcenter;
        case VCAlignmentCenterVertically: return el | F::vcenter;
        default: return el | F::center;
      }
    case VCDecorator::Type::Border: {
      F::BorderStyle style = ToBorderStyle(d.a);
      if (!d.color) {
        return d.title.length ? F::window(F::text(VCToStd(d.title)), el, style)
                              : el | F::borderStyled(style);
      }
      // A colour decorator would also colour the content, and window() has no colour; draw a
      // coloured border and lay the title over its top edge where window() puts it.
      F::Color color = [d.color ftxuiColor];
      el = el | F::borderStyled(style, color);
      if (!d.title.length) return el;
      auto gap = [] { return F::text("") | F::size(F::WIDTH, F::EQUAL, 1); };
      F::Element title =
          F::hbox({gap(), F::text(VCToStd(d.title)) | F::xflex_shrink | F::color(color), gap()});
      // vbox + filler keeps the title's box (and its colour) to one row; size() doesn't clip.
      return F::dbox({el, F::vbox({title, F::filler()})});
    }
    case VCDecorator::Type::FocusMarker: return el | F::focus;
    case VCDecorator::Type::ClearUnder: return el | F::clear_under;
  }
  return el;
}

}  // namespace

F::Element VCBridgeState::Build(VCNode *node) {
  if (!node) return F::text("");
  F::Element el = BuildBase(node);
  for (const VCDecorator &d : node.decorators) el = Apply(el, d);
  return el;
}

F::Element VCBridgeState::BuildBase(VCNode *node) {
  auto buildChildren = [this](NSArray<VCNode *> *nodes) {
    F::Elements out;
    out.reserve(nodes.count);
    for (VCNode *child in nodes) out.push_back(Build(child));
    return out;
  };
  switch (node.kind) {
    case VCNodeKindVBox: return F::vbox(buildChildren(node.children));
    case VCNodeKindHBox: return F::hbox(buildChildren(node.children));
    case VCNodeKindDBox: return F::dbox(buildChildren(node.children));
    case VCNodeKindFiller: return F::filler();
    case VCNodeKindSeparator: return F::separator();
    case VCNodeKindText: return F::text(VCToStd(node.string));
    case VCNodeKindParagraph: return F::paragraphAlignLeft(VCToStd(node.string));
    case VCNodeKindGauge: {
      float progress = std::clamp(node.number, 0.0f, 1.0f);
      return node.integer == VCAxisVertical ? F::gaugeUp(progress) : F::gauge(progress);
    }
    case VCNodeKindSpinner:
      return F::spinner(int(node.integer), size_t(std::max<NSInteger>(0, node.integer2)));
    case VCNodeKindTable: {
      auto options = VCTableOptions(node.integer);
      size_t columns = 0;
      for (NSArray<VCNode *> *row in node.rows) columns = std::max<size_t>(columns, row.count);
      if (node.rows.count == 0 || columns == 0) return F::text("");
      bool gap = !(options & VCTableOptionsColumnSeparators);
      std::vector<F::Elements> cells;
      for (NSArray<VCNode *> *row in node.rows) {
        F::Elements line;
        for (size_t x = 0; x < columns; ++x) {
          F::Element cell = x < row.count ? Build(row[x]) : F::text("");
          // Without separators, keep one space between columns.
          if (gap && x + 1 < columns) cell = F::hbox({cell, F::text(" ")});
          line.push_back(cell);
        }
        cells.push_back(std::move(line));
      }
      F::Table table(std::move(cells));
      if (options & VCTableOptionsColumnSeparators) table.SelectAll().SeparatorVertical(F::LIGHT);
      if (options & VCTableOptionsRowSeparators) table.SelectAll().SeparatorHorizontal(F::LIGHT);
      if (options & VCTableOptionsHeader) {
        table.SelectRow(0).Decorate(F::bold);
        if (node.rows.count > 1) table.SelectRow(0).BorderBottom(F::LIGHT);
      }
      if (options & VCTableOptionsBorder) table.SelectAll().Border(F::LIGHT);
      return table.Render();
    }
    case VCNodeKindTabBar: {
      F::Elements tabs;
      NSInteger index = 0;
      for (NSString *title in node.strings) {
        F::Element tab = F::text(" " + VCToStd(title) + " ");
        if (index++ == node.integer) tab = tab | F::inverted | F::bold;
        tabs.push_back(tab);
      }
      return F::hbox(std::move(tabs));
    }
    case VCNodeKindInput:
    case VCNodeKindMenu: return Update(node)->component->Render();
    case VCNodeKindScrollFrame:
      return VCScrollFrame(Build(node.children.firstObject), Update(node)->scrollOffset, node.flag);
  }
  return F::text("");
}

VCWidget *VCBridgeState::Update(VCNode *node) {
  switch (node.kind) {
    case VCNodeKindInput: {
      VCWidget &w = Widget(VCToStd(node.widgetId), VCWidgetKind::Input);
      w.placeholder = VCToStd(node.string);
      w.multiline = node.flag;
      return &w;
    }
    case VCNodeKindMenu: {
      VCWidget &w = Widget(VCToStd(node.widgetId), VCWidgetKind::Menu);
      w.entries.clear();
      for (NSString *entry in node.strings) w.entries.push_back(VCToStd(entry));
      int last = std::max(0, int(w.entries.size()) - 1);
      w.selected = std::clamp(w.selected, 0, last);
      w.focusedEntry = std::clamp(w.focusedEntry, 0, last);
      return &w;
    }
    case VCNodeKindScrollFrame:
      return &Widget(VCToStd(node.widgetId), VCWidgetKind::ScrollFrame);
    default:
      return nullptr;
  }
}

void VCBridgeState::Register(VCNode *node) {
  if (!node) return;
  Update(node);
  for (VCNode *child in node.children) Register(child);
  for (NSArray<VCNode *> *row in node.rows) {
    for (VCNode *cell in row) Register(cell);
  }
}

void VCBridgeState::Emit(VCEvent *event) {
  void (^callback)(VCEvent *) = nil;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex);
    callback = onEvent;
  }
  if (callback) callback(event);
}

// MARK: - Root component

void VCRootComponent::SyncChildren() {
  // Widgets must be children so Focused()/Active() resolve for the focused one.
  if (syncedGeneration_ == state_->generation) return;
  syncedGeneration_ = state_->generation;
  DetachAllChildren();
  for (auto &[id, w] : state_->widgets) {
    if (w.component) Add(w.component);
  }
}

F::Element VCRootComponent::BuildTree() {
  std::lock_guard<std::recursive_mutex> lock(state_->mutex);
  // Build first: it may create widgets, which must be children before they render focused.
  // Building twice when the set changed keeps the first frame's focus styling right.
  unsigned before = state_->generation;
  F::Element el = state_->Build(state_->root);
  if (state_->generation != before || syncedGeneration_ != state_->generation) {
    SyncChildren();
    el = state_->Build(state_->root);
  }
  return el;
}

F::Element VCRootComponent::OnRender() {
  state_->redrawPending.store(false);
  F::Element el = BuildTree();
  auto size = F::Terminal::Size();
  VCEvent *resize = nil;
  {
    std::lock_guard<std::recursive_mutex> lock(state_->mutex);
    if (size.dimx != state_->lastWidth || size.dimy != state_->lastHeight) {
      state_->lastWidth = size.dimx;
      state_->lastHeight = size.dimy;
      resize = [VCEvent resizeEventWidth:size.dimx height:size.dimy];
    }
  }
  state_->framesDrawn++;
  if (resize) state_->Emit(resize);
  return el;
}

bool VCRootComponent::OnEvent(F::Event event) {
  if (event == VCRedrawEvent()) return true;  // redraw request from setRoot
  if (event.is_cursor_position() || event.is_cursor_shape() || event.IsTerminalNameVersion() ||
      event.IsTerminalEmulator() || event.IsTerminalCapabilities() || event.input().empty()) {
    return false;  // terminal replies are FTXUI's business
  }
  if (event.is_mouse()) {
    bool track = false;
    {
      std::lock_guard<std::recursive_mutex> lock(state_->mutex);
      track = state_->trackMouse;
    }
    if (track) state_->Emit([VCEvent mouseEvent:event.mouse() rawHex:VCHexOf(event.input())]);
    return track;
  }

  const bool isNul = event.input().size() == 1 && event.input()[0] == 0;
  if (isNul) {
    // FTXUI posts Special({0}) for SIGWINCH (and selection changes); the terminal sends the
    // same byte for Ctrl-Space. While the loop runs, a resize changes the size; a key doesn't.
    std::lock_guard<std::recursive_mutex> lock(state_->mutex);
    if (state_->app) {
      auto size = F::Terminal::Size();
      if (size.dimx != state_->lastWidth || size.dimy != state_->lastHeight) return true;
    }
  }

  VCEvent *widgetEvent = nil;
  bool handled = false;
  {
    std::lock_guard<std::recursive_mutex> lock(state_->mutex);
    auto it = state_->widgets.find(state_->focused);
    // Navigation and command keys are never text: always give them to Swift.
    bool command = isNul || event == F::Event::Escape || event == F::Event::Tab ||
                   event == F::Event::TabReverse || event == F::Event::CtrlC;
    if (it != state_->widgets.end() && it->second.component && !command) {
      VCWidget &w = it->second;
      NSString *widgetId = VCToNS(it->first);
      bool isInput = w.kind == VCWidgetKind::Input;
      if (event == F::Event::Return && (w.kind == VCWidgetKind::Menu || !w.multiline)) {
        widgetEvent = [VCEvent widgetEvent:VCEventKindWidgetSubmitted
                                  widgetId:widgetId
                               stringValue:isInput ? VCToNS(w.content) : nil
                              integerValue:isInput ? w.cursor : w.selected];
        handled = true;
      } else {
        std::string contentBefore = w.content;
        int selectedBefore = w.selected;
        handled = w.component->OnEvent(event);
        if (w.content != contentBefore || w.selected != selectedBefore) {
          widgetEvent = [VCEvent widgetEvent:VCEventKindWidgetChanged
                                    widgetId:widgetId
                                 stringValue:isInput ? VCToNS(w.content) : nil
                                integerValue:isInput ? w.cursor : w.selected];
        }
      }
    }
  }
  if (widgetEvent) state_->Emit(widgetEvent);
  if (handled) return true;
  state_->Emit([VCEvent keyEvent:VCKeyName(event.input()) rawHex:VCHexOf(event.input())]);
  // Every key is handled here, Ctrl-C included (ForceHandleCtrlC(false)): Swift decides.
  return true;
}

F::Component VCRootComponent::ActiveChild() {
  std::lock_guard<std::recursive_mutex> lock(state_->mutex);
  auto it = state_->widgets.find(state_->focused);
  return it == state_->widgets.end() ? nullptr : it->second.component;
}
