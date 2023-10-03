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
    //     nodeToIndex: context.nodeToIndex,
    //   );
    // }
    return TextContentElement(
      style: Style(),
      element: context.node.parent,
      node: context.node as dom.Text,
      nodeToIndex: context.nodeToIndex,
    );
  }

  @override
  InlineSpan build(ExtensionContext context) {
    // if (context.styledElement! is EmptyContentElement) {
    //   assert(false);
    //   return const TextSpan();
    // }
    final element = context.styledElement! as TextContentElement;
    // Blank text elements are kept to follow html rules where in some situations spaces between elements can determine
    // how they are organized on the screen, but do not appear as elements themselves. These [Text] nodes are
    // skipped when counting characters as well. This is highly tied
    // to the obelisk implementation, since whitespace processing is done before. If this was not the case, we would
    // need to check for any number of white space characters.
    if (element.text == " ") {
      return const TextSpan();
    }
    return TextSpan(
      style: element.style.generateTextStyle(),
      text: element.createTextForSpanWidget(),
    );
  }
}
