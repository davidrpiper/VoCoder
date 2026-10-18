// Word-wrapping flow (FTXUI `hflow`) whose words never get clipped. FTXUI's flexbox clips a
// child wider than its line; `BreakableWord` wraps each child and, when its box is narrower than
// the child, draws it in line-wide slices on consecutive rows (long paths and URLs in agent
// output). Like the flexbox it lives in, it learns its width from the previous layout pass and
// asks for another pass (`Check`) when that width changes.
#import "BridgeInternal.h"

#include <algorithm>

#include "ftxui/dom/flexbox_config.hpp"
#include "ftxui/dom/node.hpp"
#include "ftxui/dom/requirement.hpp"
#include "ftxui/screen/box.hpp"
#include "ftxui/screen/screen.hpp"
#include "ftxui/util/autoreset.hpp"

namespace {

class BreakableWord : public ftxui::Node {
 public:
  explicit BreakableWord(ftxui::Element child) : ftxui::Node({std::move(child)}) {}

  void ComputeRequirement() override {
    ftxui::Node::ComputeRequirement();
    natural_ = requirement_.min_x;
    rowHeight_ = requirement_.min_y;
    if (limit_ > 0 && natural_ > limit_) {
      requirement_.min_x = limit_;
      requirement_.min_y = rowHeight_ * Slices();
    }
  }

  void SetBox(ftxui::Box box) override {
    ftxui::Node::SetBox(box);
    const int width = std::max(1, box.x_max - box.x_min + 1);
    // Only a box narrower than the word (the line clipped it) sets a limit.
    const int limit = width < natural_ ? width : 0;
    needIteration_ = limit != limit_;
    limit_ = limit;
    if (limit_ == 0) children_[0]->SetBox(box);
  }

  void Check(Status *status) override {
    ftxui::Node::Check(status);
    if (status->iteration == 0) limit_ = 0;
    status->need_iteration |= needIteration_;
  }

  void Render(ftxui::Screen &screen) override {
    if (limit_ == 0) {
      children_[0]->Render(screen);
      return;
    }
    for (int i = 0; i < Slices(); ++i) {
      ftxui::Box row = box_;
      row.y_min = box_.y_min + i * rowHeight_;
      row.y_max = row.y_min + rowHeight_ - 1;
      ftxui::Box shifted = row;
      shifted.x_min = box_.x_min - i * limit_;
      shifted.x_max = shifted.x_min + natural_ - 1;
      const ftxui::AutoReset<ftxui::Box> stencil(&screen.stencil,
                                                 ftxui::Box::Intersection(row, screen.stencil));
      children_[0]->SetBox(shifted);
      children_[0]->Render(screen);
    }
  }

 private:
  int Slices() const { return (natural_ + limit_ - 1) / limit_; }

  int natural_ = 0;
  int rowHeight_ = 1;
  int limit_ = 0;  // 0: no limit, drawn whole
  bool needIteration_ = false;
};

}  // namespace

ftxui::Element VCFlow(ftxui::Elements children) {
  static const auto config = ftxui::FlexboxConfig().SetGap(1, 0);
  for (auto &child : children) child = std::make_shared<BreakableWord>(std::move(child));
  return ftxui::flexbox(std::move(children), config) | ftxui::xflex;
}
