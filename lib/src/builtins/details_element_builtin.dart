import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// The [DetailsElementBuiltIn] handles the default rendering for the
/// `<details>` html tag
class DetailsElementBuiltIn extends HtmlExtension {
  const DetailsElementBuiltIn();

  @override
  Set<String> get supportedTags => {
        "details",
      };

  @override
  StyledElement prepare(
      ExtensionContext context, List<StyledElement> children) {
    return StyledElement(
      name: context.elementName,
      children: children,
      style: Style(),
      node: context.node,
      nodeToIndex: context.nodeToIndex,
    );
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final childList = context.buildChildrenMapMemoized!;
    final children = childList.values;

    InlineSpan? firstChild = children.isNotEmpty ? children.first : null;
    return WidgetSpan(
      child: ExpansionTile(
          key: context.parser.key == null || context.styledElement == null
              ? null
              : AnchorKey.of(context.parser.key!, context.styledElement!),
          expandedAlignment: Alignment.centerLeft,
          title: childList.keys.isNotEmpty &&
              childList.keys.first.name == "summary"
              ? CssBoxWidget.withInlineSpanChildren(
            children: firstChild == null ? [] : [firstChild],
            style: context.styledElement!.style,
          )
              : const Text("Details"),
          children: [
            CssBoxWidget.withInlineSpanChildren(
              children: childList.keys.isNotEmpty &&
                      childList.keys.first.name == "summary"
                  ? children.skip(1).toList()
                  : children.toList(),
              style: context.styledElement!.style,
            ),
          ]),
    );
  }
}
