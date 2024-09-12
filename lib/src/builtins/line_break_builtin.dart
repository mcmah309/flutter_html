import 'package:flutter/material.dart' hide WidgetSpan;
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
    return LinebreakContentElement(style: Style(), node: context.node);
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    // return const WidgetSpan(
    //     child: Row(children: [
    //   Expanded(
    //     child: SizedBox(),
    //   )
    // ]));
    // Note: "\n" will appear if selection is converted to plaintext, but not character count/offset. Otherwise, we
    // would have to use widget like above, but this in its current state creates line breaks that are too long.
    return TextSpan(text: "\n");
  }
}
