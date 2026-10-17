// Vertical scroll viewport with an explicit, persistent offset. FTXUI's yframe centres the focused
// element and has no offset of its own; lists and agent output need "keep the selection visible
// with minimal movement", "follow the end" and "stay where the user scrolled" instead.
#import "BridgeInternal.h"

#include <algorithm>

#include "ftxui/dom/node.hpp"
#include "ftxui/dom/requirement.hpp"
#include "ftxui/screen/box.hpp"
#include "ftxui/screen/screen.hpp"
#include "ftxui/util/autoreset.hpp"

namespace {

class ScrollFrameNode : public ftxui::Node {
 public:
  ScrollFrameNode(ftxui::Element child, std::shared_ptr<std::atomic<int>> offset, bool followEnd)
      : ftxui::Node({std::move(child)}), offset_(std::move(offset)), followEnd_(followEnd) {}

  void ComputeRequirement() override {
    ftxui::Node::ComputeRequirement();
    // Ask for the content's height but accept less: that's the point of a viewport.
    contentHeight_ = requirement_.min_y;
    requirement_.flex_shrink_y = 1;
  }

  void SetBox(ftxui::Box box) override {
    ftxui::Node::SetBox(box);
    const int height = std::max(0, box.y_max - box.y_min + 1);
    const int content = std::max(contentHeight_, height);
    const int maxOffset = content - height;
    int offset = offset_->load();
    const auto &focused = requirement_.focused;
    if (focused.enabled) {
      // Minimal movement that brings the focused box into view.
      if (focused.box.y_max >= offset + height) offset = focused.box.y_max - height + 1;
      if (focused.box.y_min < offset) offset = focused.box.y_min;
    } else if (followEnd_) {
      offset = maxOffset;
    }
    offset = std::clamp(offset, 0, maxOffset);
    offset_->store(offset);

    ftxui::Box childBox = box;
    childBox.y_min = box.y_min - offset;
    childBox.y_max = childBox.y_min + content - 1;
    children_[0]->SetBox(childBox);
  }

  void Render(ftxui::Screen &screen) override {
    const ftxui::AutoReset<ftxui::Box> stencil(&screen.stencil,
                                               ftxui::Box::Intersection(box_, screen.stencil));
    children_[0]->Render(screen);
  }

 private:
  std::shared_ptr<std::atomic<int>> offset_;
  bool followEnd_;
  int contentHeight_ = 0;
};

}  // namespace

ftxui::Element VCScrollFrame(ftxui::Element child, std::shared_ptr<std::atomic<int>> offset,
                             bool followEnd) {
  return std::make_shared<ScrollFrameNode>(std::move(child), std::move(offset), followEnd);
}
