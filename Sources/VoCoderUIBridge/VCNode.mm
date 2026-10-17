#import "BridgeInternal.h"

@implementation VCNode {
  std::vector<VCDecorator> _decorators;
}

- (instancetype)initWithKind:(VCNodeKind)kind {
  if ((self = [super init])) {
    _kind = kind;
    _string = @"";
    _widgetId = @"";
    _children = @[];
    _rows = @[];
    _strings = @[];
  }
  return self;
}

- (VCNode *)copyAdding:(VCDecorator)decorator {
  VCNode *copy = [[VCNode alloc] initWithKind:_kind];
  copy->_string = _string;
  copy->_widgetId = _widgetId;
  copy->_children = _children;
  copy->_rows = _rows;
  copy->_strings = _strings;
  copy->_integer = _integer;
  copy->_integer2 = _integer2;
  copy->_number = _number;
  copy->_flag = _flag;
  copy->_decorators = _decorators;
  copy->_decorators.push_back(decorator);
  return copy;
}

- (const std::vector<VCDecorator> &)decorators {
  return _decorators;
}

// MARK: Layout

+ (VCNode *)container:(VCNodeKind)kind children:(NSArray<VCNode *> *)children {
  VCNode *node = [[VCNode alloc] initWithKind:kind];
  node->_children = [children copy];
  return node;
}

+ (VCNode *)vbox:(NSArray<VCNode *> *)children {
  return [self container:VCNodeKindVBox children:children];
}

+ (VCNode *)hbox:(NSArray<VCNode *> *)children {
  return [self container:VCNodeKindHBox children:children];
}

+ (VCNode *)dbox:(NSArray<VCNode *> *)children {
  return [self container:VCNodeKindDBox children:children];
}

+ (VCNode *)filler {
  return [[VCNode alloc] initWithKind:VCNodeKindFiller];
}

+ (VCNode *)separator {
  return [[VCNode alloc] initWithKind:VCNodeKindSeparator];
}

// MARK: Content

+ (VCNode *)text:(NSString *)text {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindText];
  node->_string = [text copy];
  return node;
}

+ (VCNode *)paragraph:(NSString *)text {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindParagraph];
  node->_string = [text copy];
  return node;
}

+ (VCNode *)gauge:(float)progress axis:(VCAxis)axis {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindGauge];
  node->_number = progress;
  node->_integer = axis;
  return node;
}

+ (VCNode *)spinnerWithCharset:(NSInteger)charset frame:(NSInteger)frame {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindSpinner];
  node->_integer = charset;
  node->_integer2 = frame;
  return node;
}

+ (VCNode *)tableWithRows:(NSArray<NSArray<VCNode *> *> *)rows options:(VCTableOptions)options {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindTable];
  node->_rows = [rows copy];
  node->_integer = (NSInteger)options;
  return node;
}

+ (VCNode *)tabBarWithTitles:(NSArray<NSString *> *)titles selected:(NSInteger)selected {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindTabBar];
  node->_strings = [titles copy];
  node->_integer = selected;
  return node;
}

+ (VCNode *)strip:(NSArray<VCNode *> *)children keepingVisible:(NSInteger)index {
  VCNode *node = [self container:VCNodeKindStrip children:children];
  node->_integer = index;
  return node;
}

// MARK: Widgets

+ (VCNode *)inputWithId:(NSString *)widgetId
            placeholder:(NSString *)placeholder
              multiline:(BOOL)multiline {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindInput];
  node->_widgetId = [widgetId copy];
  node->_string = [placeholder copy];
  node->_flag = multiline;
  return node;
}

+ (VCNode *)menuWithId:(NSString *)widgetId entries:(NSArray<NSString *> *)entries {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindMenu];
  node->_widgetId = [widgetId copy];
  node->_strings = [entries copy];
  return node;
}

+ (VCNode *)scrollFrameWithId:(NSString *)widgetId
                 followingEnd:(BOOL)followingEnd
                        child:(VCNode *)child {
  VCNode *node = [[VCNode alloc] initWithKind:VCNodeKindScrollFrame];
  node->_widgetId = [widgetId copy];
  node->_flag = followingEnd;
  node->_children = @[ child ];
  return node;
}

// MARK: Modifiers

- (VCNode *)styled:(VCTextStyle)style {
  return [self copyAdding:{.type = VCDecorator::Type::Style, .a = (NSInteger)style}];
}

- (VCNode *)foreground:(VCColor *)color {
  return [self copyAdding:{.type = VCDecorator::Type::Foreground, .color = color}];
}

- (VCNode *)background:(VCColor *)color {
  return [self copyAdding:{.type = VCDecorator::Type::Background, .color = color}];
}

- (VCNode *)flex:(VCFlex)flex {
  return [self copyAdding:{.type = VCDecorator::Type::Flex, .a = flex}];
}

- (VCNode *)width:(VCSizeConstraint)constraint value:(NSInteger)value {
  return [self copyAdding:{.type = VCDecorator::Type::Width, .a = constraint, .b = value}];
}

- (VCNode *)height:(VCSizeConstraint)constraint value:(NSInteger)value {
  return [self copyAdding:{.type = VCDecorator::Type::Height, .a = constraint, .b = value}];
}

- (VCNode *)aligned:(VCAlignment)alignment {
  return [self copyAdding:{.type = VCDecorator::Type::Align, .a = alignment}];
}

- (VCNode *)bordered {
  return [self borderedWithStyle:VCBorderStyleLight title:nil];
}

- (VCNode *)borderedWithStyle:(VCBorderStyle)style title:(NSString *)title {
  return [self borderedWithStyle:style title:title color:nil];
}

- (VCNode *)borderedWithStyle:(VCBorderStyle)style title:(NSString *)title color:(VCColor *)color {
  return [self copyAdding:{.type = VCDecorator::Type::Border,
                           .a = style,
                           .color = color,
                           .title = [title copy]}];
}

- (VCNode *)focusMarker {
  return [self copyAdding:{.type = VCDecorator::Type::FocusMarker}];
}

- (VCNode *)clearUnder {
  return [self copyAdding:{.type = VCDecorator::Type::ClearUnder}];
}

@end
