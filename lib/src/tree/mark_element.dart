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
    super.parent,
    required super.node,
    required super.nodeToIndex,
  });
}

/// A mark range.
class Mark {
  int start;
  int end;
  int get range => end - start;
  String? comment;
  late Color color;

  Mark({required this.start, required this.end, this.comment, Color? color})
      : assert(end - start >= 0 && start >= 0 && end >= 0) {
    this.color = color ?? MarkManager.defaultHighlightColor;
  }

  @override
  String toString() {
    return "Mark: from: $start, to: $end, comment: $comment, color: $color";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is Mark) {
      return start == other.start &&
          end == other.end &&
          comment == other.comment &&
          color == other.color;
    }
    return false;
  }

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ comment.hashCode ^ color.hashCode;
}

// String _generateUniqueHtmlId() {
//   final randomGen = Random(DateTime.now().microsecondsSinceEpoch);
//   const validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
//   return List.generate(15, (index) => validChars[randomGen.nextInt(validChars.length)]).join();
// }