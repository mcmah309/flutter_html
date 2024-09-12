import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide WidgetSpan;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/widgets/styled_element_widget.dart';
import 'package:html/dom.dart' as dom;

/// Handles the rendering of rp, rt, and ruby tags.
class RubyBuiltIn extends HtmlExtension {
  const RubyBuiltIn();

  @override
  Set<String> get supportedTags => {
        "rp",
        "rt",
        "ruby",
      };

  @override
  StyledElement prepare(ExtensionContext context, List<StyledElement> children) {
    if (context.elementName == "ruby") {
      return RubyElement(
        element: context.node as dom.Element,
        children: children,
        node: context.node,
      );
    }

    //TODO we'll probably need specific styling for rp and rt
    return StyledElement(
      children: children,
      elementId: context.id,
      elementClasses: context.classes.toList(),
      name: context.elementName,
      node: context.node,
      style: Style(),
    );
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    return WidgetSpan(
      alignment: (context.styledElement! as ReplacedElement).alignment,
      baseline: TextBaseline.alphabetic,
      child: Builder(builder: (buildContext) {
        StyledElement? styledElement;
        List<Widget> widgets = <Widget>[];
        final rubySize = context.parserConfig.globalStyles['rt']?.fontSize?.value ??
            max(9.0, context.styledElement!.style.fontSize!.value / 2);
        final rubyYPos = rubySize + rubySize / 2;
        List<StyledElement> children = [];
        context.styledElement!.children.forEachIndexed((index, element) {
          if (!((element is TextContentElement) &&
              (element.text ?? "").trim().isEmpty &&
              index > 0 &&
              index + 1 < context.styledElement!.children.length &&
              context.styledElement!.children[index - 1] is! TextContentElement &&
              context.styledElement!.children[index + 1] is! TextContentElement)) {
            children.add(element);
          }
        });
        for (var childStyledElement in children) {
          if (childStyledElement.name == "rt" && styledElement != null) {
            final widget = Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  alignment: Alignment.bottomCenter,
                  child: Center(
                    child: Transform(
                      transform: Matrix4.translationValues(0, -(rubyYPos), 0),
                      child: CssBoxWidget(
                        styledElement: childStyledElement,
                        markManager: markManager,
                        child: Text(
                          childStyledElement.element!.innerHtml,
                          style: childStyledElement.style
                              .generateTextStyle()
                              .copyWith(fontSize: rubySize),
                        ),
                      ),
                    ),
                  ),
                ),
                CssBoxWidget(
                  styledElement: context.styledElement!,
                  markManager: markManager,
                  child: styledElement is TextContentElement
                      ? StyledElementWidget(
                          rebuild: () {
                            if (buildContext.mounted) {
                              context.resetBuiltChildren();
                              (buildContext as Element).markNeedsBuild();
                            }
                          },
                          styledElement,
                          markManager,
                          TextSpan(text: styledElement.text?.trim() ?? ""),
                          style: context.styledElement!.style.generateTextStyle(),
                        )
                      : StyledElementWidget(
                          rebuild: () {
                            if (buildContext.mounted) {
                              context.resetBuiltChildren();
                              (buildContext as Element).markNeedsBuild();
                            }
                          },
                          styledElement,
                          markManager,
                          const TextSpan(text: '!rc!'),
                        ), // TODO was context.parser.parseTree(context, node)),
                ),
              ],
            );
            widgets.add(widget);
          } else {
            styledElement = childStyledElement;
          }
        }
        return Padding(
          padding: EdgeInsets.only(top: rubySize),
          child: Wrap(
            key: context.parserConfig.parserKey == null || context.styledElement == null
                ? null
                : AnchorKey.of(context.parserConfig.parserKey!, context.styledElement!),
            runSpacing: rubySize,
            children: widgets.map((e) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [e],
              );
            }).toList(),
          ),
        );
      }),
    );
  }
}
