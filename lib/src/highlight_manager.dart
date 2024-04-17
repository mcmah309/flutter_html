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

ParentedTreeTraversal<StyledElement> nodeTraversal = ParentedTreeTraversal(
    getChildren: (element) => element.children,
    getParent: (element) => element.parent,
    getChildAtIndex: (element, i) => element.children[i],
    getChildsIndex: (parent, element) => parent.children.indexOf(element));

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
        _nextTextElementAtOffset(startSelection.styledElement, startSelection.selection.start);
    if (result == null) {
      return;
    }
    final (startTextElement, start) = result;
    result = _nextTextElementAtOffset(endSelection.styledElement, endSelection.selection.end);
    if (result == null) {
      return;
    }
    final (endTextElement, end) = result;

    StyledElement highlightMarkerElement;

    /// The selection starts at the start of the element
    if (start == 0) {
      highlightMarkerElement = _placeMarkBefore(startTextElement, endTextElement, start, end);
    } else {
      List<TextContentElement> splits = startTextElement.split(0, start);
      // Split encompassed the whole range, so [startTextElement] is actually the element before the element we want to highlight.
      if (splits.length == 1) {
        // The next element may already have a highlight, so we check and adjust it if so, if not, we create a new one.
        highlightMarkerElement =
            _nextHighlightElementBeforeAnyTextElementOrNextTextElement(splits[0]);
        if (highlightMarkerElement is TextContentElement) {
          throw StateError(
              "I think this should be possible if the previous comments hold, but I may be wrong in the previous comments. If this is thrown, then obviously this is possible, so replicate and fix.");
        } else {
          int range;
          if (startTextElement == endTextElement) {
            range = end - start;
          } else {
            range = _characterCountUntilNode(splits[0], endTextElement) + end - start;
          }
          highlightMarkerElement.node.attributes["range"] = "$range";
        }
      } else {
        assert(splits.length == 2);
        highlightMarkerElement = _placeMarkBefore(splits[1], endTextElement, start, end);
      }
    }

    const MarkBuiltIn().addColorForRangeIfPresent(highlightMarkerElement);
    currentSelections.clear();

    _context?.markNeedsBuild();

    newElementCallback?.call(highlightMarkerElement);
  }
}

StyledElement _placeMarkBefore(
    TextContentElement placeBeforeElement, TextContentElement endTextElement, int start, int end) {
  int range;
  if (placeBeforeElement == endTextElement) {
    range = end - start;
  } else {
    range = _characterCountUntilNode(placeBeforeElement, endTextElement) + end;
  }
  final markNode = dom.Element.tag("o-mark")
    ..attributes["id"] = _generateUniqueHtmlId()
    ..attributes["range"] = "$range";
  Color backgroundColor = MarkBuiltIn.defaultHighlightColor;
  StyledElement highlightMarkerElement = StyledElement(
    style: placeBeforeElement.style.copyOnlyInherited(Style(backgroundColor: backgroundColor)),
    node: markNode,
    nodeToIndex: placeBeforeElement.nodeToIndex,
  )..attributes["range"] = "$range";
  placeBeforeElement.insertBefore(highlightMarkerElement);
  return highlightMarkerElement;
}

/// Gets the next [TextContentElement]. Also returns the number of line breaks, since these, count as a item during selection.
/// Line breaks are considered 1 in the offset (since there are counted as 1 in selections as well).
//todo are other elements like an image or another styledelement counted as one as well?
(TextContentElement, int)? _nextTextElementAtOffset(StyledElement styledElement, int offset) {
  assert(offset >= 0);
  int currentOffset = 0;
  for (final element in nodeTraversal.postOrderIterable(styledElement)) {
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
StyledElement _nextHighlightElementBeforeAnyTextElementOrNextTextElement(
    StyledElement styledElement) {
  for (final element in nodeTraversal.postOrderContinuationIterable(styledElement).skip(1)) {
    if (element.node.attributes.containsKey("range")) {
      return element;
    }
    if (element is TextContentElement) {
      return element;
    }
  }
  throw Exception("There is no next element.");
}

/// Counts the characters in [start,end) range skipping any text nodes that are just a single whitespace - see [Guarentees.md] for why.
int _characterCountUntilNode(StyledElement start, StyledElement end) {
  bool isFound = false;
  int count = 0;
  for (final element in nodeTraversal.preOrderContinuationIterable(start)) {
    if (element == end) {
      isFound = true;
      break;
    }
    final node = element.node;
    if (node is! dom.Text) {
      continue;
    }
    if (node.text == " ") {
      continue;
    }
    count += node.text.length;
  }
  if (isFound) {
    return count;
  }
  throw ArgumentError("start is not before end in tree.");
}

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
