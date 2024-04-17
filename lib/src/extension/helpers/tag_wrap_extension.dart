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
        return super.matches(context);
      case CurrentStep.preStyling:
      case CurrentStep.preProcessing:
        return false;
      case CurrentStep.building:
        return context.styledElement is WrapperElement;
    }
  }

  @override
  StyledElement prepare(
      ExtensionContext context, List<StyledElement> children) {
    return WrapperElement(
      parent: context.styledElement?.parent,
      child: context.parser.prepareFromExtension(
        context,
        children,
        extensionsToIgnore: {this},
      ),
    );
  }

  @override
  InlineSpan build(ExtensionContext context, HighlightManager highlightManager) {
    final child = CssBoxWidgetWithInlineSpanChildren(
      children: context.buildInlineSpanChildrenMemoized!,
      styledElement: context.styledElement!,
      highlightManager: highlightManager,
    );

    return WidgetSpan(
      child: builder.call(child),
    );
  }
}

class WrapperElement extends StyledElement {
  WrapperElement({
    required StyledElement? parent,
    required StyledElement child,
  }) : super(
          node: html.Element.tag("wrapper-element"),
          nodeToIndex: child.nodeToIndex,
          style: Style(),
          parent: parent,
          children: [child],
          name: "[wrapper-element]",
        );
}
