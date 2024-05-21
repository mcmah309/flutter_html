import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide RenderParagraph;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/tree/replaced_element.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:tree_traversal/tree_traversal.dart';

import 'widgets/paragraph.dart';

ParentedTreeTraversal<StyledElement> elementTraversal = ParentedTreeTraversal(
    getChildren: (element) => element.children,
    getParent: (element) => element.parent,
    getChildAtIndex: (element, i) => element.children[i],
    getChildsIndex: (parent, element) => parent.children.indexOf(element));

ParentedTreeTraversal<dom.Node> nodeTraversal = ParentedTreeTraversal(
    getChildren: (element) => element.nodes,
    getParent: (element) => element.parent,
    getChildAtIndex: (element, i) => element.nodes[i],
    getChildsIndex: (parent, element) => parent.nodes.indexOf(element));

class HighlightManager {
  List<Selection> currentSelections = [];
  Element? _context;

  void setContext(BuildContext context) {
    _context = context as Element;
  }

  void handleSelection(
      StyledElement styledElement, TextSelection? selection, SelectionEvent event) {
    currentSelections.removeWhere((element) =>
        element.styledElement == styledElement ||
        element.styledElement.isAncestorOf(styledElement));
    if (selection == null ||
        event.type == SelectionEventType.clear ||
        selection.start == selection.end) {
      return;
    }
    currentSelections.add(Selection(styledElement, selection));
  }

  void mark({void Function(StyledElement)? newElementCallback}) {
    currentSelections
        .sortBy<num>((element) => element.styledElement.nodeToIndex[element.styledElement.node]!);
    // for (final x in currentSelections) {
    //   print(x.styledElement.node.text!.substring(x.selection.start, x.selection.end));
    //   print("\n");
    // }
    if (currentSelections.isEmpty) {
      return;
    }
    final startSelection = currentSelections.first;
    final endSelection = currentSelections.last;

    var result =
        _nextTextElementAtOffsetBasedOnViewLogic(startSelection.styledElement, startSelection.selection.start);
    if (result == null) {
      return;
    }
    final (startTextElement, startLeftOver) = result;
    result = _nextTextElementAtOffsetBasedOnViewLogic(endSelection.styledElement, endSelection.selection.end);
    if (result == null) {
      return;
    }
    final (endTextElement, endLeftOver) = result;

    StyledElement highlightMarkerElement;

    /// The selection starts at the start of the element
    if (startLeftOver == 0) {
      int range =
          characterCountUntilStyledElement(startTextElement, endTextElement).last.$1 + endLeftOver - startLeftOver;
      highlightMarkerElement = placeMarkBefore(startTextElement, range);
    }
    // if true, [startTextElement] is actually the element before the element we want to highlight.
    if (startLeftOver == startTextElement.text.length) {
      // really is highlightMarkerElementOrTextElement
      highlightMarkerElement =
          nextHighlightElementBeforeAnyTextElementOrNextTextElement(startTextElement);
      if (highlightMarkerElement is TextContentElement) {
        int range = characterCountUntilStyledElement(highlightMarkerElement, endTextElement).last.$1 +
            endLeftOver -
            startLeftOver;
        highlightMarkerElement = placeMarkBefore(startTextElement, range);
      } else {
        assert(highlightMarkerElement.node.attributes["range"] != null, "If this is actually a highlight marker element, it should have an `range` attribute.");
        int range = characterCountUntilStyledElement(startTextElement, endTextElement).last.$1 +
            endLeftOver -
            startLeftOver;
        highlightMarkerElement.node.attributes["range"] = "$range";
      }
    } else {
      List<TextContentElement> splits = startTextElement.split(0, startLeftOver);
      assert(splits.length == 2);
      int range = characterCountUntilStyledElement(startTextElement, endTextElement).last.$1 +
            endLeftOver -
            startLeftOver;
      highlightMarkerElement = placeMarkBefore(splits[1], range);
    }

    const MarkBuiltIn().addColorForRangeIfPresent(highlightMarkerElement);
    currentSelections.clear();

    _context?.markNeedsBuild();

    newElementCallback?.call(highlightMarkerElement);
  }
}

StyledElement placeMarkBefore(TextContentElement placeBeforeElement, int range,
    {Color? color, bool willConnectInDom = true}) {
  final markNode = dom.Element.tag("o-mark")
    ..attributes["id"] = _generateUniqueHtmlId()
    ..attributes["range"] = "$range";
  Color backgroundColor;
  if (color == null) {
    backgroundColor = MarkBuiltIn.defaultHighlightColor;
  } else {
    backgroundColor = color;
    markNode.attributes["color"] = const ColorConverter().toJson(backgroundColor);
  }
  StyledElement highlightMarkerElement = StyledElement(
    style: placeBeforeElement.style.copyOnlyInherited(Style(backgroundColor: backgroundColor)),
    node: markNode,
    nodeToIndex: placeBeforeElement.nodeToIndex,
  )..attributes["range"] = "$range";
  if (willConnectInDom) {
    placeBeforeElement.insertBefore(highlightMarkerElement);
  } else {
    placeBeforeElement.insertBeforeDoNotConnectNode(highlightMarkerElement);
  }
  return highlightMarkerElement;
}

/// Gets the next [TextContentElement] at the offset and returns any leftover.
/// This is based on view logic, not backing data i.e. how the view determines offset.
/// Line breaks are considered 1 in the offset (since there are counted as 1 in selections as well).
//todo are other elements like an image or another styledelement counted as one as well?
(TextContentElement, int)? _nextTextElementAtOffsetBasedOnViewLogic(StyledElement styledElement, int offset) {
  assert(offset >= 0);
  int currentOffset = 0;
  for (final element in elementTraversal.postOrderIterable(styledElement)) {
    if (element is! TextContentElement) {
      if (element is LinebreakContentElement) {
        currentOffset += 1;
      }
      continue;
    }
    int length = element.node.text.length;
    if (currentOffset + length < offset) {
      currentOffset += length;
      continue;
    }
    final leftOver = offset - currentOffset;
    return (element, leftOver);
  }
  assert(false, "Expected a $TextContentElement to exist with the offset.");
  return null;
}

/// Gets the next highlight elment (element with "range" attribute).
StyledElement nextHighlightElementBeforeAnyTextElementOrNextTextElement(
    StyledElement styledElement) {
  for (final element in elementTraversal.postOrderContinuationIterable(styledElement).skip(1)) {
    if (element.node.attributes.containsKey("range")) {
      return element;
    }
    if (element is TextContentElement) {
      return element;
    }
  }
  throw Exception("There is no next element.");
}

/// This and the above need to be kept in sync
/// Counts the characters in [start,end) range skipping any text nodes that are just a single whitespace - see [Guarentees.md] for why.
//todo delete above?
Iterable<(int,StyledElement)> characterCountUntilStyledElement(StyledElement start, [StyledElement? end]) sync* {
  int count = 0;
  for (final element in elementTraversal.preOrderContinuationIterable(start)) {
    if (element == end) {
      yield (count, element);
      return;
    }
    final node = element.node;
    if (element is! TextContentElement) {
      yield (count, element);
      continue;
    }
    if (element.text == " ") {
      yield (count, element);
      continue;
    }
    count += element.text.length;
    yield (count, element);
  }
  throw ArgumentError("start is not before end in tree.");
}

/// This and the above need to be kept in sync
// Iterable<(int,dom.Node)> characterCountUntilNode(dom.Node start, dom.Node end) sync* {
//   int count = 0;
//   for (final node in nodeTraversal.preOrderContinuationIterable(start)) {
//     if (node == end) {
//       yield (count, node);
//       return;
//     }
//     if (node is! dom.Text) {
//       yield (count, node);
//       continue;
//     }
//     if (node.text == " ") {
//       yield (count, node);
//       continue;
//     }
//     count += node.text.length;
//     yield (count, node);
//   }
//   throw ArgumentError("start is not before end in tree.");
// }

String _generateUniqueHtmlId() {
  final randomGen = Random(DateTime.now().microsecondsSinceEpoch);
  const validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(15, (index) => validChars[randomGen.nextInt(validChars.length)]).join();
}

class Selection {
  StyledElement styledElement;
  TextSelection selection;

  Selection(this.styledElement, this.selection);
}
