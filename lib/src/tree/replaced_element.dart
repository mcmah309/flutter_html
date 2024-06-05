import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_html/src/style.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:html/dom.dart' as dom;

/// A [ReplacedElement] is a type of [StyledElement] that does not require its [children] to be rendered.
///
/// A [ReplacedElement] may use its children nodes to determine relevant information
/// (e.g. <video>'s <source> tags), but the children nodes will not be saved as [children].
abstract class ReplacedElement extends StyledElement {
  PlaceholderAlignment alignment;

  ReplacedElement({
    required super.name,
    required super.style,
    required super.elementId,
    StyledElement? parent,
    List<StyledElement>? children,
    required super.node,
    this.alignment = PlaceholderAlignment.aboveBaseline,
    super.markStyle,
    super.rebuildAssociatedWidget,
  }) : super(
          parent: parent,
          children: children ?? [],
        );

  static List<String?> parseMediaSources(List<dom.Element> elements) {
    return elements.where((element) => element.localName == 'source').map((element) {
      return element.attributes['src'];
    }).toList();
  }
}

/// [TextContentElement] is a [ContentElement] with plaintext as its content.
class TextContentElement extends ReplacedElement {
  String get text => node.text;

  @override
  dom.Text get node => super.node as dom.Text;

  TextContentElement(
      {required Style style,
      required dom.Text node,
      super.markStyle,
      super.rebuildAssociatedWidget})
      : super(name: "[text]", style: style, node: node, elementId: "[[No ID]]");

  /// splits this [TextContentElement] at the indexes and makes any necessary changes to the
  /// tree. Returns the [TextContentElement]'s acted on.
  /// [start] inclusive, [end] exclusive. Will return [this] is the entire range is covered
  List<TextContentElement> split(int start, [int? end]) {
    int length = text.length;
    if (start >= length) {
      throw ArgumentError("Start of `$start' must be less than length of '$length'.");
    }
    end ??= text.length;
    if (start >= end) {
      throw ArgumentError("Start of `$start' must be less than end of '$end'.");
    }
    final String text1;
    final String text2;
    String? text3;
    if (start == 0) {
      if (end == text.length) {
        return [this];
      } else {
        text1 = node.text.substring(0, end);
        text2 = node.text.substring(end);
      }
    } else {
      if (end == text.length) {
        text1 = node.text.substring(0, start);
        text2 = node.text.substring(start);
      } else {
        text1 = node.text.substring(0, start);
        text2 = node.text.substring(start, end);
        text3 = node.text.substring(end);
      }
    }
    final dom.Text newNodeBefore = dom.Text(text1);
    final TextContentElement newBeforeTextContentElement = _copyWithNoParent(node: newNodeBefore);
    insertBefore(newBeforeTextContentElement);
    if (text3 == null) {
      node.text = text2;
      return [newBeforeTextContentElement, this];
    } else {
      final dom.Text newNodeBefore2 = dom.Text(text2);
      final TextContentElement newBeforeTextContentElement2 =
          _copyWithNoParent(node: newNodeBefore2);
      insertBefore(newBeforeTextContentElement2);
      node.text = text3;
      return [newBeforeTextContentElement, newBeforeTextContentElement2, this];
    }
  }

  String createTextForSpanWidget() {
    TextTransform? transform = style.textTransform;
    String transformedText;
    if (transform == TextTransform.uppercase) {
      transformedText = text.toUpperCase();
    } else if (transform == TextTransform.lowercase) {
      transformedText = text.toLowerCase();
    } else if (transform == TextTransform.capitalize) {
      final stringBuffer = StringBuffer();

      var capitalizeNext = true;
      for (final letter in text.toLowerCase().codeUnits) {
        // UTF-16: A-Z => 65-90, a-z => 97-122.
        if (capitalizeNext && letter >= 97 && letter <= 122) {
          stringBuffer.writeCharCode(letter - 32);
          capitalizeNext = false;
        } else {
          // UTF-16: 32 == space, 46 == period
          if (letter == 32 || letter == 46) capitalizeNext = true;
          stringBuffer.writeCharCode(letter);
        }
      }

      transformedText = stringBuffer.toString();
    } else {
      transformedText = text;
    }
    assert(text.length == transformedText.length, "Should not alter the text of text node");
    return transformedText;
  }

  /// Copies the current element, but without the parent
  TextContentElement _copyWithNoParent({
    Style? style,
    dom.Text? node,
    Style? markStyle,
    void Function()? rebuildAssociatedWidget,
  }) {
    return TextContentElement(
        style: style ?? this.style.copyWith(),
        node: node ?? this.node,
        markStyle: markStyle ?? this.markStyle,
        rebuildAssociatedWidget: rebuildAssociatedWidget ?? this.rebuildAssociatedWidget);
  }

  @override
  String toString() {
    return "\"${text.replaceAll("\n", "\\n")}\"";
  }
}

class LinebreakContentElement extends ReplacedElement {
  LinebreakContentElement({
    required super.style,
    required super.node,
  }) : super(name: 'br', elementId: "[[No ID]]");
}

class EmptyContentElement extends ReplacedElement {
  EmptyContentElement({required super.node, String name = "empty"})
      : super(name: name, style: Style(), elementId: "[[No ID]]");
}

class RubyElement extends ReplacedElement {
  @override
  dom.Element element;

  RubyElement({
    required this.element,
    required List<StyledElement> children,
    String name = "ruby",
    required super.node,
  }) : super(
            name: name,
            alignment: PlaceholderAlignment.middle,
            style: Style(),
            elementId: element.id,
            children: children);
}
