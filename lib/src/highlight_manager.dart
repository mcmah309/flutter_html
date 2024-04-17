import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_tools/dart_tools.dart';
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

  void handleSelection(StyledElement styledElement, void Function() rebuild,
      TextSelection? selection, SelectionEvent event) {
    currentSelections.removeWhere((element) =>
        element.styledElement == styledElement ||
        element.styledElement.isAncestorOf(styledElement));
    if (selection == null ||
        event.type == SelectionEventType.clear ||
        selection.start == selection.end) {
      return;
    }
    currentSelections.add(Selection(styledElement, selection, rebuild));
  }

  void mark() {
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
    // late TextContentElement startTextElement;
    // int startRelativeToStyledElement = startSelection.selection.start;
    // int offsetInStyledElementUntilTextContentElement = 0;
    // for (final e in nodeTraversal.postOrderIterable(startSelection.styledElement)) {
    //   if (e is! TextContentElement) {
    //     continue;
    //   }
    //   int length = e.node.text.length;
    //   if (offsetInStyledElementUntilTextContentElement + length < startRelativeToStyledElement) {
    //     offsetInStyledElementUntilTextContentElement += length;
    //     continue;
    //   }
    //   startTextElement = e;
    //   break;
    // }
    // int start = startRelativeToStyledElement - offsetInStyledElementUntilTextContentElement;

    // late TextContentElement endTextElement;
    // int endRelativeToStyledElement = endSelection.selection.end;
    // offsetInStyledElementUntilTextContentElement = 0;
    // for (final e in nodeTraversal.postOrderIterable(endSelection.styledElement)) {
    //   if (e is! TextContentElement) {
    //     continue;
    //   }
    //   int length = e.node.text.length;
    //   if (offsetInStyledElementUntilTextContentElement + length < endRelativeToStyledElement) {
    //     offsetInStyledElementUntilTextContentElement += length;
    //     continue;
    //   }
    //   endTextElement = e;
    //   break;
    // }
    // int end = endRelativeToStyledElement - offsetInStyledElementUntilTextContentElement;

    List<TextContentElement> splits = startTextElement.split(0, start);
    final StyledElement highlightMarkerElement;
    // The node already has a highlight, so we adjust it.
    if (splits.length == 1) {
      highlightMarkerElement = _nextHighlightElementBeforeAnyTextElement(splits[0]);
      int range;
      if (startTextElement == endTextElement) {
        range = end - start;
      } else {
        range = characterCountUntilNode(splits[0].node, endTextElement.node) + end - start;
      }
      highlightMarkerElement.node.attributes["range"] = "$range";
    } else {
      assert(splits.length == 2);
      int range;
      if (startTextElement == endTextElement) {
        range = end - start;
      } else {
        range = characterCountUntilNode(splits[1].node, endTextElement.node) + end;
      }
      final markNode = dom.Element.tag("o-mark")
        ..attributes["id"] = _generateUniqueHtmlId()
        ..attributes["range"] = "$range";
      Color backgroundColor = MarkBuiltIn.defaultHighlightColor;
      highlightMarkerElement = StyledElement(
        style: splits[1].style.copyOnlyInherited(Style(backgroundColor: backgroundColor)),
        node: markNode,
        nodeToIndex: splits[1].nodeToIndex,
      )..attributes["range"] = "$range";
      splits[1].insertBefore(highlightMarkerElement);
    }

    const MarkBuiltIn().addColorForRangeIfPresent(highlightMarkerElement);

    for (final selection in currentSelections) {
      selection.rebuild();
    }
    currentSelections.clear();
  }
}

(TextContentElement, int)? _nextTextElementAtOffset(StyledElement styledElement, int offset) {
  assert(offset >= 0);
  int currentOffset = 0;
  for (final element in nodeTraversal.postOrderIterable(styledElement)) {
    if (element is! TextContentElement) {
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

StyledElement _nextHighlightElementBeforeAnyTextElement(StyledElement styledElement) {
  for (final element in nodeTraversal.postOrderContinuationIterable(styledElement).skip(1)) {
    if (element.node.attributes.containsKey("range")) {
      return element;
    }
    if (element is TextContentElement) {
      break;
    }
  }
  throw Exception(
      "Expected next element before any text to be a highlight one, but this was not the case");
}

String _generateUniqueHtmlId() {
  final randomGen = Random(DateTime.now().microsecondsSinceEpoch);
  const validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(15, (index) => validChars[randomGen.nextInt(validChars.length)]).join();
}

class Selection {
  StyledElement styledElement;
  TextSelection selection;
  void Function() rebuild;

  Selection(this.styledElement, this.selection, this.rebuild);
}
