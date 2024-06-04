import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/extension/html_extension.dart';
import 'package:flutter_html/src/style.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:flutter_html/src/widgets/css_box_widget.dart';

/// [VerticalAlignBuiltin] handles rendering of sub/sup tags with a vertical
/// alignment off of the normal text baseline
class VerticalAlignBuiltIn extends HtmlExtension {
  const VerticalAlignBuiltIn();

  @override
  Set<String> get supportedTags => {
        "sub",
        "sup",
      };

  @override
  bool matches(ExtensionContext context) {
    return context.styledElement?.style.verticalAlign != null &&
        (context.styledElement!.style.verticalAlign == VerticalAlign.sub ||
            context.styledElement!.style.verticalAlign == VerticalAlign.sup);
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    return WidgetSpan(
      child: Builder(builder: (buildContext) {
        return Transform.translate(
          offset: Offset(0, _getVerticalOffset(context.styledElement!)),
          child: CssBoxWidgetWithInlineSpanChildren(
            children: context.buildInlineSpanChildrenMemoized!,
            styledElement: context.styledElement!,
            markManager: markManager,
            rebuild: () {
              if (buildContext.mounted) {
                context.resetBuiltChildren();
                (buildContext as Element).markNeedsBuild();
              }
            },
          ),
        );
      }),
    );
  }

  double _getVerticalOffset(StyledElement tree) {
    switch (tree.style.verticalAlign) {
      case VerticalAlign.sub:
        return tree.style.fontSize!.value / 2.5;
      case VerticalAlign.sup:
        return tree.style.fontSize!.value / -2.5;
      default:
        return 0;
    }
  }
}
