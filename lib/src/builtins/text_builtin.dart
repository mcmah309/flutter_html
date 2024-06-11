import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;

/// Handles rendering of [dom.Text] nodes.
class TextBuiltIn extends HtmlExtension {
  const TextBuiltIn();

  @override
  bool matches(ExtensionContext context) {
    return context.node is dom.Text;
  }

  @override
  Set<String> get supportedTags => {};

  @override
  StyledElement prepare(ExtensionContext context, List<StyledElement> children) {
    // if(context.node is! dom.Text) {
    //   assert(false);
    //   return EmptyContentElement(
    //     node: context.node,
    //   );
    // }
    return TextContentElement(
      style: Style(),
      node: context.node as dom.Text,
    );
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    final element = context.styledElement! as TextContentElement;
    final Style style;
    final markColor = element.calculateMarkColor();
    if (markColor == null) {
      style = element.style;
    } else {
      style = element.style.copyWith(backgroundColor: markColor);
    }
    return TextSpan(
      style: style.generateTextStyle(),
      text: element.createTextForSpanWidget(),
    );
  }
}
