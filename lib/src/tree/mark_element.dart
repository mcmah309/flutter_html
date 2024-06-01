import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';

/// An element that is just mark marker.
class MarkElement extends StyledElement {
  final Mark mark;

  MarkElement({
    required this.mark,
    super.parent,
    required super.node,
    required super.nodeToIndex,
  })  : //assert(int.parse(node.attributes["range"]!) >= 0),
        super(style: Style());
}


/// A mark range.
class Mark {
  int from;
  int to;
  int get range => to - from;
  String? comment;
  late Color color;

  Mark({required this.from, required this.to, this.comment, Color? color}){
    this.color = color ?? MarkManager.defaultHighlightColor;
  }

  @override
  String toString() {
    return "Mark: from: $from, to: $to, comment: $comment, color: $color";
  }

  @override
  bool operator ==(Object other) {
    if (other is Mark) {
      return from == other.from && to == other.to && comment == other.comment && color == other.color;
    }
    return false;
  }

  @override
  int get hashCode => from.hashCode ^ to.hashCode ^ comment.hashCode ^ color.hashCode;
}

// String _generateUniqueHtmlId() {
//   final randomGen = Random(DateTime.now().microsecondsSinceEpoch);
//   const validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
//   return List.generate(15, (index) => validChars[randomGen.nextInt(validChars.length)]).join();
// }