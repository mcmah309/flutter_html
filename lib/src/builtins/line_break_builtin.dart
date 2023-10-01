import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// Handles rendering of <br> tags.
class LineBreakBuiltIn extends HtmlExtension {
  const LineBreakBuiltIn();

  @override
  bool matches(ExtensionContext context) {
    return supportedTags.contains(context.elementName);
  }

  @override
  Set<String> get supportedTags => {
        "br",
      };

  @override
  StyledElement prepare(ExtensionContext context, List<StyledElement> children) {
    return LinebreakContentElement(style: Style(), node: context.node, nodeToIndex: context.nodeToIndex);
  }

  @override
  InlineSpan build(ExtensionContext context) {
    return const WidgetSpan(
        child: Row(children: [
      Expanded(
        child: SizedBox(),
      )
    ]));
  }
}
