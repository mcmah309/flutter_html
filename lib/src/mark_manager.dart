import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide RenderParagraph;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/tree/mark_element.dart';
import 'package:flutter_html/src/tree/replaced_element.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:meta/meta.dart';
import 'package:rewind/rewind.dart';
import 'package:rust_core/cell.dart';
import 'package:rust_core/panic.dart';
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

sealed class MarkEvent {}

class MarkIconTappedEvent extends MarkEvent {
  MarkElement markElement;

  MarkIconTappedEvent(this.markElement);
}

/// Manages interactions with the mark/comment system.
class MarkManager {
  static const defaultHighlightColor = Color.fromARGB(150, 255, 229, 127);

  late StyledElement _root;

  /// Selections this is aware of and can be turned into a [MarkElement] when
  /// [createMarkElementFromCurrentSelections] is called.
  final List<Selection> _currentSelections = [];

  /// List of marks that have already been added to the tree. Needed for so can be removed when a new set of marks
  /// is received.
  final List<MarkElement> _currentMarks = [];

  final List<void Function(MarkEvent event)> _listeners = [];

  //************************************************************************//

  /// Traverses the tree from this element, adding the color style to all [StyledElement]s in the range.
  static void addColorForRange(MarkElement element) {
    _traverseAndAddStyle(element, Style(backgroundColor: element.mark.color), Cell<int>(element.mark.range), 0);
  }

  //************************************************************************//

  void registerMarkListener(void Function(MarkEvent event) callback) {
    _listeners.add(callback);
  }

  void removeMarkListener(void Function(MarkEvent event) callback) {
    _listeners.removeWhere((element) => element == callback);
  }

  void markTapped(MarkElement element) {
    final event = MarkIconTappedEvent(element);
    for (final listener in _listeners) {
      listener(event);
    }
  }

  //************************************************************************//

  /// Clears the old marks and adds the new marks as marks in the tree.
  void setMarks(List<Mark> marks) {
    for (final alreadyAddedElement in _currentMarks) {
      alreadyAddedElement.disconnectFromParent();
    }
    _currentMarks.clear();
    if (marks.isEmpty) {
      return;
    }
    marks.sort((e1, e2) => e1.from - e2.from);
    final Queue<Mark> marksToAdd = Queue()..addAll(marks);

    Mark mark = marksToAdd.removeFirst();
    List<MarkElement> markElements = [];
    // toList() to avoid concurrent modification
    final countsAndElements = _characterCountUntilStyledElement(_root).toList(growable: false);
    i:
    for (int i = 0; i < countsAndElements.length; i++) {
      var (count, element) = countsAndElements[i];
      do {
        if (element is! TextContentElement || count + element.text.length <= mark.from) {
          continue i;
        }
        int startPosition = mark.from - count;
        assert(startPosition < element.text.length,
            "The start position is actually not in this element.");
        final (markElement, nextTextElement) =
            _createMarkElement(element, startPosition, mark);
        _currentMarks.add(markElement);
        if (marksToAdd.isEmpty) {
          return;
        }
        count += startPosition;
        element = nextTextElement;
        mark = marksToAdd.removeFirst();
      } while (true);
    }
    if (marksToAdd.isNotEmpty) {
      Log.e("Could not apply all marks, there are still ${marksToAdd.length} marks to apply.");
    }
    for (final markElement in markElements) {
      addColorForRange(markElement);
    }
  }

  //************************************************************************//

  /// Processes the selection event for the element
  void registerSelectionEvent(
      StyledElement styledElement, TextSelection? selection, SelectionEvent event) {
    _currentSelections.removeWhere((element) =>
        element.styledElement == styledElement ||
        element.styledElement.isAncestorOf(styledElement));
    if (selection == null ||
        event.type == SelectionEventType.clear ||
        selection.start == selection.end) {
      return;
    }
    _currentSelections.add(Selection(styledElement, selection));
  }

  /// Marks all current selections
  MarkElement? createMarkElementFromCurrentSelections() {
    _currentSelections
        .sortBy<num>((element) => element.styledElement.nodeToIndex[element.styledElement.node]!);
    // For debugging
    // for (final x in currentSelections) {
    //   print(x.styledElement.node.text!.substring(x.selection.start, x.selection.end));
    //   print("\n");
    // }
    if (_currentSelections.isEmpty) {
      return null;
    }
    final startSelection = _currentSelections.first;
    final endSelection = _currentSelections.last;

    var result = _nextTextElementAtOffsetBasedOnViewLogic(
        startSelection.styledElement, startSelection.selection.start);
    final (startTextElement, startLeftOver) = result;
    assert(startLeftOver != startTextElement.text.length,
        "This if this is true, then the element should actually be the next element");
    result = _nextTextElementAtOffsetBasedOnViewLogic(
        endSelection.styledElement, endSelection.selection.end);
    final (endTextElement, endLeftOver) = result;
    assert(endLeftOver != endTextElement.text.length,
        "This if this is true, then the element should actually be the next element");

    int from = _characterCountUntilStyledElement(_root, startTextElement).last.$1 - startLeftOver;
    int range = _characterCountUntilStyledElement(startTextElement, endTextElement).last.$1 +
        endLeftOver -
        startLeftOver;
    assert(range > 0);
    final (markMarkerElement, _) =
        _createMarkElement(startTextElement, startLeftOver, Mark(from: from, to: from + range));

    addColorForRange(markMarkerElement);

    _currentSelections.clear();

    return markMarkerElement;
  }

  //************************************************************************//

  @internal
  void setRoot(StyledElement root) {
    _root = root;
  }
}

//************************************************************************//

void _traverseAndAddStyle(StyledElement element, Style style, Cell<int> characterCount, int skip) {
  // add style to this element, if character count is smaller than length, break up and return, otherwise go down until no children, then, start going up
  // good opportunity to publish tree node. then add that as a depends to here and changed styled element to inherit from
  _traverseAndAddStyleDownInclusive(element, style, characterCount, skip);
  if (characterCount.get() > 0 && element.parent != null) {
    int parentShouldSkip = 1;
    for (final parentChildElement in element.parent!.children) {
      if (parentChildElement == element) break;
      parentShouldSkip++;
    }
    _traverseAndAddStyle(element.parent!, style, characterCount, parentShouldSkip);
  }
}

void _traverseAndAddStyleDownInclusive(
    StyledElement element, Style style, Cell<int> characterCount, int skip) {
  if (characterCount.get() > 0) {
    assert(
        (element.node is dom.Text && element is TextContentElement) ||
            (element.node is! dom.Text && element is! TextContentElement),
        "The only Text nodes and TextContentElements should only be paired together");
    if (element is TextContentElement) {
      String text = element.text;
      int length = text.length;
      // // Single string non-empty elements are not counted.
      // if (text == " ") {
      //   // Intentionally empty
      // } else
      if (length > characterCount.get()) {
        final splitElement = element.split(characterCount.get());
        assert(splitElement.length == 2);
        splitElement[0].style = splitElement[0].style.copyOnlyInherited(style);
        characterCount.sub(characterCount.get());
        return;
      } else {
        element.style = element.style.copyOnlyInherited(style);
        characterCount.sub(length);
      }
    }
  }
  for (int i = skip; i < element.children.length && characterCount.get() > 0; ++i) {
    _traverseAndAddStyleDownInclusive(element.children[i], style, characterCount, 0);
  }
}

//************************************************************************//

/// Creates a [MarkElement] and returns with the next [TextContentElement]. The [TextContentElement] will be the [startElement]
/// if [startPosition] is 0, otherwise a split of [startElement] is returned.
///
/// You will likely need to call [addColorForRange] for the returned [MarkElement]. This is not done inside
/// as this can cause concurrent modificaition if [_createMarkElement] is called inside a generator emitting [StyledElement] nodes.
(MarkElement, TextContentElement) _createMarkElement(
    TextContentElement startTextElement, int startPosition, Mark mark) {
  assert(startTextElement.text.length != startPosition,
      "The start element in not correct, it should be the next one with position 0");
  MarkElement markMarkerElement;
  TextContentElement nextTextElement;

  /// The selection starts at the start of the element
  if (startPosition == 0) {
    nextTextElement = startTextElement;
    markMarkerElement = _placeMarkBefore(nextTextElement, mark);
  } else {
    List<TextContentElement> splits = startTextElement.split(0, startPosition);
    assert(splits.length == 2);
    nextTextElement = splits[1];
    markMarkerElement = _placeMarkBefore(nextTextElement, mark);
  }

  return (markMarkerElement, nextTextElement);
}

/// Creates and places the [MarkElement] before the [placeBeforeElement] element.
MarkElement _placeMarkBefore(TextContentElement placeBeforeElement, Mark mark, 
    {bool willConnectInDom = true}) {
  final markNode = dom.Element.tag("o-mark");
    //..attributes["id"] = mark.id;
    // ..attributes["range"] = "${mark.range}"
    // ..attributes["color"] = const ColorConverter().toJson(mark.color);
  MarkElement markMarkerElement = MarkElement(
    mark: mark,
    node: markNode,
    nodeToIndex: placeBeforeElement.nodeToIndex,
  );
  if (willConnectInDom) {
    placeBeforeElement.insertBefore(markMarkerElement);
  } else {
    placeBeforeElement.insertBeforeDoNotConnectNode(markMarkerElement);
  }
  return markMarkerElement;
}

/// Gets the next [TextContentElement] at the offset and returns with any left over offset in the returning element.
/// This is based on view logic, not backing data i.e. how the view determines offset.
(TextContentElement, int) _nextTextElementAtOffsetBasedOnViewLogic(
    StyledElement styledElement, int viewOffset) {
  assert(viewOffset >= 0);
  int currentOffset = 0;
  for (final element in elementTraversal.postOrderIterable(styledElement)) {
    if (element is! TextContentElement) {
      // // todo are other elements like an image or another styledelement counted as one as well?
      // Line breaks are considered 1 in the offset (since there are counted as 1 in selections as well).
      // if (element is LinebreakContentElement) {
      //   currentOffset += 1;
      // }
      continue;
    }
    int length = element.node.text.length;
    if (currentOffset + length <= viewOffset) {
      currentOffset += length;
      continue;
    }
    final offsetInElement = viewOffset - currentOffset;
    return (element, offsetInElement);
  }
  unreachable("Expected a $TextContentElement to exist with the offset.");
}

/// This and the above need to be kept in sync, will yield start and end.
Iterable<(int, StyledElement)> _characterCountUntilStyledElement(StyledElement start,
    [StyledElement? end]) sync* {
  int count = 0;
  for (final element in elementTraversal.preOrderContinuationIterable(start)) {
    if (element == end) {
      yield (count, element);
      return;
    }
    if (element is! TextContentElement) {
      yield (count, element);
      continue;
    }
    // if (element.text == " ") {
    //   yield (count, element);
    //   continue;
    // }
    yield (count, element);
    count += element.text.length;
  }
  if (end != null) {
    throw ArgumentError("start is not before end in tree.");
  }
}

class Selection {
  StyledElement styledElement;
  TextSelection selection;

  Selection(this.styledElement, this.selection);
}