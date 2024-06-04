import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide RenderParagraph;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/processing/node_order.dart';
import 'package:flutter_html/src/tree/mark_element.dart';
import 'package:flutter_html/src/tree/replaced_element.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:meta/meta.dart';
import 'package:rewind/rewind.dart';
import 'package:rust_core/cell.dart';
import 'package:rust_core/panic.dart';
import 'package:rust_core/result.dart';
import 'package:tree_traversal/tree_traversal.dart';

import 'widgets/paragraph.dart';

ParentedTreeTraversal<StyledElement> elementTraversal = ParentedTreeTraversal(
    getChildren: (element) => element.children,
    getParent: (element) => element.parent,
    getChildAtIndex: (element, i) => element.children[i],
    getChildsIndex: (parent, element) => parent.children.indexOf(element));

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
  final List<MarkElement> _currentMarkElements = [];

  final List<void Function(MarkEvent event)> _listeners = [];

  //************************************************************************//

  /// Traverses the tree from this element, adding the color style to all [StyledElement]s in the range.
  static void addColorForRange(MarkElement element) {
    _traverseAndAddStyle(
        element, Style(backgroundColor: element.mark.color), Cell<int>(element.mark.range), 0);
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

  /// Clears the old marks and adds the new marks as marks in the tree. You will need to trigger a rebuild
  /// later as this will not do that and does not apply highlighting styles. This just places the mark.
  /// See [MarkBuiltin] for application.
  void setMarks(List<Mark> marks) {
    for (final alreadyAddedElement in _currentMarkElements) {
      alreadyAddedElement.disconnectFromParent();
    }
    _currentMarkElements.clear();
    if (marks.isEmpty) {
      return;
    }
    marks.sort((e1, e2) => e1.start - e2.start);
    final Queue<Mark> marksToAdd = Queue()..addAll(marks);

    Mark mark = marksToAdd.removeFirst();
    // toList() to avoid concurrent modification
    final countsAndElements = _characterCountUntilStyledElement(_root).toList(growable: false);
    i:
    for (int i = 0; i < countsAndElements.length; i++) {
      var (count, element) = countsAndElements[i];
      do {
        if (element is! TextContentElement || count + element.text.length <= mark.start) {
          continue i;
        }
        int startPosition = mark.start - count;
        assert(startPosition < element.text.length,
            "The start position is actually not in this element.");
        final (markElement, nextTextElement) = _createMarkElement(element, startPosition, mark);
        _currentMarkElements.add(markElement);
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
  }

  //************************************************************************//

  /// Processes the selection event for the element
  void registerSelectionEvent(
      StyledElement styledElement, TextSelection? selection, SelectionEvent event) {
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
      case SelectionEventType.selectAll:
      case SelectionEventType.selectWord:
      case SelectionEventType.granularlyExtendSelection:
      case SelectionEventType.directionallyExtendSelection:
        break;
      case SelectionEventType.clear:
        _currentSelections.removeWhere((element) => element.styledElement == styledElement);
    }
    // Events like this should be ignore, flutter will randomly fire ones like these that are outside the actual selection.
    if (selection == null || selection.start == selection.end) {
      return;
    }
    _currentSelections.add(Selection(styledElement, selection));
  }

  /// Marks all current selections
  MarkElement? createMarkElementFromCurrentSelections() {
    if (_currentSelections.isEmpty) {
      return null;
    }
    // For debugging
    // for (final x in currentSelections) {
    //   print(x.styledElement.node.text!.substring(x.selection.start, x.selection.end));
    //   print("\n");
    // }
    final nodeOrderMap = NodeOrderProcessing.createNodeToIndexMap(
        _currentSelections.first.styledElement.root().node);
    _currentSelections.sortBy<num>((s) => nodeOrderMap[s.styledElement.node]!);

    final first = _currentSelections.first;
    final selectionsInStartElement = _currentSelections.takeWhile((e) => e == first).toList();
    selectionsInStartElement.sortBy<num>((s) => s.selection.start);
    final startSelection = selectionsInStartElement.first;

    final last = _currentSelections.last;
    final selectionsInEndElement = _currentSelections.reversed.takeWhile((e) => e == last).toList();
    selectionsInEndElement.sortBy<num>((s) => s.selection.end);
    final endSelection = selectionsInEndElement.last;

    var result = _nextTextElementAndOffsetBasedOnView(
        startSelection.styledElement, startSelection.selection.start);
    TextContentElement startTextElement;
    int offsetInStartTextElement;
    switch (result) {
      case Ok(:final ok):
        (startTextElement, offsetInStartTextElement) = ok;
      case Err(:final err):
        Log.e(err, append: "Some selection may have been corrupted. Resetting..");
        _currentSelections.clear();
        return null;
    }
    assert(offsetInStartTextElement != startTextElement.text.length,
        "The element should actually be the next element");
    result = _nextTextElementAndOffsetBasedOnView(
        endSelection.styledElement, endSelection.selection.end);
    TextContentElement endTextElement;
    int offsetInEndTextElement;
    switch (result) {
      case Ok(:final ok):
        (endTextElement, offsetInEndTextElement) = ok;
      case Err(:final err):
        Log.e(err, append: "Some selection may have been corrupted. Resetting..");
        _currentSelections.clear();
        return null;
    }
    assert(offsetInEndTextElement != endTextElement.text.length,
        "The element should actually be the next element");

    int from = _characterCountUntilStyledElement(_root, startTextElement).last.$1 +
        offsetInStartTextElement;
    assert(from >= 0);
    int end =
        _characterCountUntilStyledElement(_root, endTextElement).last.$1 + offsetInEndTextElement;
    assert(end >= 0);
    assert(end - from >= 0);
    final (markMarkerElement, _) =
        _createMarkElement(startTextElement, offsetInStartTextElement, Mark(start: from, end: end));

    addColorForRange(markMarkerElement);

    for (final selection in _currentSelections) {
      selection.styledElement.rebuildAssociatedWidget?.call();
    }
    _currentSelections.clear();

    _currentMarkElements.add(markMarkerElement);

    return markMarkerElement;
  }

  //************************************************************************//

  @internal
  void setRoot(StyledElement root) {
    _root = root;
  }
}

//************************************************************************//

/// Traversing the html changing the style to the highlight and collecting the string being highlighted.
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
  final markNode = dom.Element.tag(const MarkBuiltIn().supportedTags.first);
  //..attributes["id"] = mark.id;
  // ..attributes["range"] = "${mark.range}"
  // ..attributes["color"] = const ColorConverter().toJson(mark.color);
  MarkElement markMarkerElement = MarkElement(
    mark: mark,
    style: placeBeforeElement.style,
    node: markNode,
  );
  if (willConnectInDom) {
    placeBeforeElement.insertBefore(markMarkerElement);
  } else {
    placeBeforeElement.insertBeforeDoNotConnectNode(markMarkerElement);
  }
  return markMarkerElement;
}

/// Gets the next [TextContentElement] at the offset and returns with the start offset in the returning element.
/// [viewOffset] is based on view logic, not backing data i.e. how the view determines offset.
Result<(TextContentElement, int), Exception> _nextTextElementAndOffsetBasedOnView(
    StyledElement styledElement, int viewOffset) {
  assert(viewOffset >= 0);
  int currentOffsetInView = 0;
  for (final element in elementTraversal.preOrderIterable(styledElement)) {
    if (element is MarkElement) {
      currentOffsetInView += 1;
      continue;
    }
    if (element is! TextContentElement) {
      continue;
    }
    int length = element.node.text.length;
    if (currentOffsetInView + length <= viewOffset) {
      currentOffsetInView += length;
      continue;
    }
    final offsetInElement = viewOffset - currentOffsetInView;
    return Ok((element, offsetInElement));
  }
  return Err(Exception("Expected a $TextContentElement to exist with the offset."));
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
