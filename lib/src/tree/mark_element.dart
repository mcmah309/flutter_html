import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';

/// An element that is just mark marker.
class MarkElement extends StyledElement {
  final Mark mark;

  MarkElement({
    required this.mark,
    // Style is needed to know the know the font size to make the marker. Usually the style for the proceeding element is used.
    required super.style,
    required super.node,
  });
}

/// A mark range.
class Mark {
  String id;
  int start;
  int end;
  int get range => end - start;
  String? comment;
  late Color color;

  Mark({required this.id, required this.start, required this.end, this.comment, Color? color})
      : assert(end - start >= 0 && start >= 0 && end >= 0) {
    this.color = color ?? MarkManager.defaultHighlightColor;
  }

  bool overlaps(Mark mark) {
    return (start >= mark.start && start <= mark.end) || (end >= mark.start && end <= mark.end);
  }

  (int, int)? overlappingRange(Mark mark) {
    if (overlaps(mark)) {
      return (max(start, mark.start), min(end, mark.end));
    }
    return null;
  }

  bool isFullyInRange(int start, int end) {
    return this.start >= start && this.end <= end;
  }

  @override
  String toString() {
    return "Mark: id: $id, from: $start, to: $end, comment: $comment, color: $color";
  }

  @override
  bool operator ==(Object other) {
    return other is Mark && id == other.id;
    //comment == other.comment &&
    //color == other.color;
  }

  @override
  int get hashCode => id.hashCode;
  //^ comment.hashCode ^ color.hashCode;
}

String generateUniqueHtmlCompatibleId() {
  final randomGen = Random(DateTime.now().microsecondsSinceEpoch);
  const validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(15, (index) => validChars[randomGen.nextInt(validChars.length)]).join();
}