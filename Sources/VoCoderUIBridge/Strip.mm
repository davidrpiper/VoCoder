// Horizontal strip that keeps one child visible when the children don't fit (the tab bar).
// Only layout knows the width, so the window is chosen here: as many neighbours of the kept child
// as fit, preferring those after it, with "‹n" / "n›" markers counting the hidden children.
#import "BridgeInternal.h"

#include <algorithm>
#include <string>

#include "ftxui/dom/node.hpp"
#include "ftxui/dom/requirement.hpp"
#include "ftxui/screen/box.hpp"
#include "ftxui/screen/screen.hpp"

namespace {

class StripNode : public ftxui::Node {
 public:
  StripNode(ftxui::Elements children, int keepVisible)
      : ftxui::Node(std::move(children)), keep_(keepVisible) {}

  void ComputeRequirement() override {
    requirement_ = {};
    widths_.clear();
    for (auto &child : children_) {
      child->ComputeRequirement();
      widths_.push_back(child->requirement().min_x);
      requirement_.min_x += child->requirement().min_x;
      requirement_.min_y = std::max(requirement_.min_y, child->requirement().min_y);
    }
    // Wants the room for every child but accepts less: hidden children become markers.
    requirement_.flex_shrink_x = 1;
  }

  void SetBox(ftxui::Box box) override {
    ftxui::Node::SetBox(box);
    const int n = int(children_.size());
    const int width = std::max(0, box.x_max - box.x_min + 1);
    first_ = 0;
    last_ = n - 1;
    left_ = right_ = nullptr;
    markers_ = true;
    if (n == 0) return;
    if (requirement_.min_x > width) ChooseWindow(width);

    int x = box.x_min;
    if (markers_ && first_ > 0) {
      left_ = Place(Marker("‹" + std::to_string(first_) + " "), x, box);
      x += left_->requirement().min_x;
    }
    for (int i = first_; i <= last_; ++i) {
      ftxui::Box child = box;
      child.x_min = x;
      child.x_max = x + widths_[i] - 1;
      children_[i]->SetBox(child);
      x += widths_[i];
    }
    if (markers_ && last_ < n - 1) {
      auto marker = Marker(" " + std::to_string(n - 1 - last_) + "›");
      int markerX = box.x_max - marker->requirement().min_x + 1;
      right_ = Place(std::move(marker), std::max(x, markerX), box);
    }
  }

  void Render(ftxui::Screen &screen) override {
    if (left_) left_->Render(screen);
    for (int i = first_; i <= last_ && i < int(children_.size()); ++i) {
      children_[i]->Render(screen);
    }
    if (right_) right_->Render(screen);
  }

 private:
  static int Digits(int value) { return int(std::to_string(value).size()); }

  /// The widest window around the kept child that fits with its markers.
  void ChooseWindow(int width) {
    const int n = int(children_.size());
    const int keep = std::clamp(keep_, 0, n - 1);
    auto fits = [&](int first, int last) {
      int total = 0;
      for (int i = first; i <= last; ++i) total += widths_[i];
      if (first > 0) total += Digits(first) + 2;
      if (last < n - 1) total += Digits(n - 1 - last) + 2;
      return total <= width;
    };
    first_ = last_ = keep;
    // Not even room for the kept child and its markers: show it alone, clipped.
    markers_ = fits(keep, keep);
    if (!markers_) return;
    for (bool grew = true; grew;) {
      grew = false;
      if (last_ < n - 1 && fits(first_, last_ + 1)) {
        ++last_;
        grew = true;
      }
      if (first_ > 0 && fits(first_ - 1, last_)) {
        --first_;
        grew = true;
      }
    }
  }

  static ftxui::Element Marker(const std::string &label) {
    auto marker = ftxui::text(label) | ftxui::dim;
    marker->ComputeRequirement();
    return marker;
  }

  static ftxui::Element Place(ftxui::Element element, int x, ftxui::Box box) {
    box.x_min = x;
    box.x_max = std::min(box.x_max, x + element->requirement().min_x - 1);
    element->SetBox(box);
    return element;
  }

  int keep_;
  std::vector<int> widths_;
  int first_ = 0, last_ = -1;
  bool markers_ = true;
  ftxui::Element left_, right_;
};

}  // namespace

ftxui::Element VCStrip(ftxui::Elements children, int keepVisible) {
  return std::make_shared<StripNode>(std::move(children), keepVisible);
}
