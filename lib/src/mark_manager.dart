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
  final Map<StyledElement, List<TextSelection>> _currentSelections = {};

  /// List of marks that have already been added to the tree. Needed for so can be removed when a new set of marks
  /// is received.
  final List<MarkElement> _currentMarkElements = [];

  List<MarkElement> get currentMarkElements => _currentMarkElements.toList();

  final List<void Function(MarkEvent event)> _listeners = [];

  //************************************************************************//

  /// Traverses the tree from this element, adding the mark style to all [StyledElement]s in the range and
  /// returning the effected elements.
  static List<StyledElement> addStyleForRange(MarkElement element) {
    List<StyledElement> effectedElements = [];
    final style = Style(backgroundColor: element.mark.color);
    int characterCount = element.mark.range;
    assert(characterCount > 0);
    for (final e in elementTraversal.postOrderContinuationIterable(element)) {
      assert(
          (e.node is dom.Text && e is TextContentElement) ||
              (e.node is! dom.Text && e is! TextContentElement),
          "The only Text nodes and TextContentElements should only be paired together");
      if (e is TextContentElement) {
        String text = e.text;
        int length = text.length;
        if (length > characterCount) {
          final splitElement = e.split(characterCount);
          assert(splitElement.length == 2);
          splitElement[0].markStyle = style;
          characterCount -= characterCount;
          effectedElements.add(splitElement[0]);
          assert(characterCount == 0);
        } else {
          e.markStyle = style;
          characterCount -= length;
          effectedElements.add(e);
        }
        if (characterCount == 0) {
          return effectedElements;
        }
      }
    }
    if (characterCount != 0) {
      Log.e("Never reached the end of the marks range.");
    }
    return effectedElements;
  }

  /// Traverses the tree from this element, removing the mark style from all the [StyledElement]s in the range
  /// where another mark is not applied to that range, and
  /// returns the effected elements.
  List<StyledElement> removeStyleForRange(MarkElement element) {
    List<StyledElement> effectedElements = [];
    // List<(int, int)> rangesToIgnore = _currentMarkElements.fold([], (collection, next) {
    //   final overlap = element.mark.overlappingRange(next.mark);
    //   if (overlap != null) {
    //     collection.add(overlap);
    //   }
    //   return collection;
    // });
    final currentMarkElementsWithoutElement = _currentMarkElements.toList();
    final hasRemoved = currentMarkElementsWithoutElement.remove(element);
    assert(hasRemoved, "Mark was not removed.");
    List<(int, int)> currentMarkRanges = currentMarkElementsWithoutElement
        .map((e) => (e.mark.start, e.mark.end))
        .toList(growable: false);
    List<(int, int)> rangesWithoutAnotherMark =
        removeRangesFromRange(element.mark.start, element.mark.end, currentMarkRanges);
    int characterCount = element.mark.range;
    for (final e in elementTraversal.postOrderContinuationIterable(element)) {
      assert(
          (e.node is dom.Text && e is TextContentElement) ||
              (e.node is! dom.Text && e is! TextContentElement),
          "The only Text nodes and TextContentElements should only be paired together");
      if (e is TextContentElement) {
        String text = e.text;
        int length = text.length;
        final int start = element.mark.end - characterCount;
        final int end = start + length;
        characterCount -= length;
        if (isFullyInRanges(start, end, rangesWithoutAnotherMark)) {
          e.markStyle = null;
          effectedElements.add(e);
        } else {
          assert(!isPartiallyInRanges(start, end, rangesWithoutAnotherMark),
              "Ranges should never partially match. An earlier partition of an StyledElement was incorrect.");
        }
        if (characterCount == 0) {
          return effectedElements;
        }
        assert(characterCount > 0,
            "Slicing up StyledElements for marks did not cut the element off at the right point, went too far.");
      }
    }
    if (characterCount != 0) {
      Log.e("Never reached the end of the marks range.");
    }
    return effectedElements;
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
  void setMarks(List<Mark> marks) {
    clearMarks();
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

  /// Adds the mark and triggers a rebuild on the effected parts.
  void addMark(Mark mark) {
    int characterCount = 0;
    TextContentElement? placementElement;
    assert(!_currentMarkElements.map((e) => e.mark).contains(mark),
        "Mark already exists and is attempted to be added again.");
    for (final element in elementTraversal.postOrderIterable(_root)) {
      if (element is! TextContentElement) {
        continue;
      }
      final length = element.text.length;
      if (characterCount + length <= mark.start) {
        characterCount += length;
        continue;
      }
      placementElement = element;
      break;
    }
    if (placementElement == null) {
      Log.e("The mark is outside the tree. This should not be possible. Not adding mark.");
      return;
    }
    final (markElement, nextTextContentElement) =
        _createMarkElement(placementElement, mark.start - characterCount, mark);
    final effectedElements = addStyleForRange(markElement);
    effectedElements.add(markElement);
    effectedElements.add(placementElement);
    effectedElements.add(nextTextContentElement);
    _triggerRebuildOnElements(effectedElements);
    
    _currentMarkElements.add(markElement);
  }

  void clearMarks() {
    _triggerRebuildOnElements(_currentMarkElements);
    for (final alreadyAddedElement in _currentMarkElements) {
      alreadyAddedElement.disconnectFromParent();
    }
    _currentMarkElements.clear();
  }

  /// Removes the mark and triggers a rebuild for the effected parts.
  void removeMark(Mark mark) {
    final int markToRemoveIndex =
        _currentMarkElements.indexWhere((element) => element.mark == mark);
    if (markToRemoveIndex < 0) {
      Log.e("Could not find the mark to remove:\n$mark");
      return;
    }
    final MarkElement markToRemove = _currentMarkElements[markToRemoveIndex];
    final effectedElements = removeStyleForRange(markToRemove);
    effectedElements.add(markToRemove);
    _triggerRebuildOnElements(effectedElements);
    markToRemove.disconnectFromParent();
    _currentMarkElements.removeAt(markToRemoveIndex);
  }

  void _triggerRebuildOnElements(List<StyledElement> elements) {
    for (var element in elements) {
      void Function()? rebuildCallback = element.rebuildAssociatedWidget;
      while (rebuildCallback == null && element.parent != null) {
        element = element.parent!;
        rebuildCallback = element.rebuildAssociatedWidget;
      }
      if (rebuildCallback != null) {
        rebuildCallback();
      }
    }
  }

  //************************************************************************//

  /// Processes the selection event for the element
  void registerSelectionUpdate(StyledElement styledElement, List<TextSelection>? selections) {
    if (selections == null || selections.isEmpty) {
      _currentSelections.remove(styledElement);
      return;
    }
    selections.removeWhere((element) => element.start == element.end);
    if (selections.isEmpty) {
      _currentSelections.remove(styledElement);
      return;
    }
    _currentSelections[styledElement] = selections;
  }

  // old
  // void registerSelectionEvent(
  //     StyledElement styledElement, TextSelection? selection, SelectionEvent event) {
  //   _currentSelections.removeWhere((element) =>
  //       element.styledElement == styledElement ||
  //       element.styledElement.isAncestorOf(styledElement));
  //   if (selection == null ||
  //       event.type == SelectionEventType.clear ||
  //       selection.start == selection.end) {
  //     return;
  //   }
  //   _currentSelections.add(SelectionPart(styledElement, selection));
  // }

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
    final selection = _calculateSelection();
    var result =
        _nextTextElementAndOffsetBasedOnView(selection.startStyledElement, selection.viewStart);
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
    result = _nextTextElementAndOffsetBasedOnView(selection.endStyledElement, selection.viewEnd);
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
    assert(end > 0);
    assert(end - from > 0);
    final (markMarkerElement, nextTextElement) = _createMarkElement(startTextElement, offsetInStartTextElement,
        Mark(id: generateUniqueHtmlCompatibleId(), start: from, end: end));

    addStyleForRange(markMarkerElement);

    _triggerRebuildOnElements([..._currentSelections.keys, markMarkerElement, nextTextElement]);
    _currentSelections.clear();

    _currentMarkElements.add(markMarkerElement);

    return markMarkerElement;
  }

  Selection _calculateSelection() {
    assert(_currentSelections.isNotEmpty);
    final orderedSelections = _currentSelections.entries.toList(growable: false);
    final nodeOrderMap =
        NodeOrderProcessing.createNodeToIndexMap(orderedSelections.first.key.root().node);
    orderedSelections.sortBy<num>((s) => nodeOrderMap[s.key.node]!);

    final first = orderedSelections.first;
    final selectionsInStartElement = first.value;
    selectionsInStartElement.sortBy<num>((s) => s.start);
    final startSelection = selectionsInStartElement.first;

    final last = orderedSelections.last;
    final selectionsInEndElement = last.value;
    selectionsInEndElement.sortBy<num>((s) => s.end);
    final endSelection = selectionsInEndElement.last;
    return Selection(first.key, startSelection.start, last.key, endSelection.end);
  }

  //************************************************************************//

  @internal
  void setRoot(StyledElement root) {
    _root = root;
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

//************************************************************************//

/// Returns the ranges between [start] and [end] where [rangesToRemove] have been removed.
/// Ranges are [x,y)
@internal
List<(int, int)> removeRangesFromRange(int start, int end, List<(int, int)> rangesToRemove) {
  assert(start >= 0);
  assert(end >= 0);
  assert(end >= start);
  // sort by start
  rangesToRemove.sort((a, b) => a.$1.compareTo(b.$1));

  List<(int, int)> remainingRanges = [];

  int currentStart = start;

  for (var range in rangesToRemove) {
    int rangeStart = range.$1;
    int rangeEnd = range.$2;
    assert(rangeStart >= 0);
    assert(rangeEnd >= 0);
    assert(rangeEnd > rangeStart);
    if (rangeStart >= end) {
      break;
    }

    if (rangeStart > currentStart) {
      remainingRanges.add((currentStart, rangeStart));
      currentStart = rangeEnd;
      continue;
    } else if (rangeEnd > currentStart) {
      currentStart = rangeEnd;
    }
  }

  if (currentStart < end) {
    remainingRanges.add((currentStart, end));
  }

  return remainingRanges;
}

/// Returns true if start and end is fully inside a range in [ranges].
@internal
bool isFullyInRanges(int start, int end, List<(int, int)> ranges) {
  for (var range in ranges) {
    int rangeStart = range.$1;
    int rangeEnd = range.$2;

    if (start >= rangeStart && end <= rangeEnd) {
      return true;
    }
  }

  return false;
}

/// Returns true if start and end is partially inside any range in [ranges].
@internal
bool isPartiallyInRanges(int start, int end, List<(int, int)> ranges) {
  for (var range in ranges) {
    int rangeStart = range.$1;
    int rangeEnd = range.$2;

    if (start < rangeEnd && end > rangeStart) {
      return true;
    }
  }
  return false;
}

//************************************************************************//

class SelectionPart {
  StyledElement styledElement;
  TextSelection selection;

  SelectionPart(this.styledElement, this.selection);
}

class Selection {
  StyledElement startStyledElement;
  int viewStart;
  StyledElement endStyledElement;
  int viewEnd;

  Selection(this.startStyledElement, this.viewStart, this.endStyledElement, this.viewEnd);
}
