import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/extension/html_extension.dart';
import 'package:flutter_html/src/style.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:flutter_html/src/widgets/css_box_widget.dart';
import 'package:html/dom.dart' as html;

class TagWrapExtension extends HtmlExtension {
  final Set<String> tagsToWrap;
  final Widget Function(Widget child) builder;

  /// [TagWrapExtension] allows you to easily wrap a specific tag (or tags)
  /// in another element. For example, you could wrap `<table>` in a
  /// `SingleChildScrollView`:
  ///
  /// ```dart
  /// extensions: [
  ///   WrapperExtension(
  ///     tagsToWrap: {"table"},
  ///     builder: (child) {
  ///       return SingleChildScrollView(
  ///         scrollDirection: Axis.horizontal,
  ///         child: child,
  ///       );
  ///     },
  ///   ),
  /// ],
  /// ```
  TagWrapExtension({
    required this.tagsToWrap,
    required this.builder,
  });

  @override
  Set<String> get supportedTags => tagsToWrap;

  @override
  bool matches(ExtensionContext context) {
    switch (context.currentStep) {
      case CurrentStep.preparing:
      case CurrentStep.preStyling:
      case CurrentStep.preProcessing:
        return false;
      case CurrentStep.building:
        return super.matches(context);
    }
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    return WidgetSpan(
      child: Builder(builder: (buildContext) {
        final child = CssBoxWidgetWithInlineSpanChildren(
          rebuild: () {
            if (buildContext.mounted) {
              context.resetBuiltChildren();
              (buildContext as Element).markNeedsBuild();
            }
          },
          children: context.buildInlineSpanChildrenMemoized!,
          styledElement: context.styledElement!,
          markManager: markManager,
        );
        return builder.call(child);
      }),
    );
  }
}
