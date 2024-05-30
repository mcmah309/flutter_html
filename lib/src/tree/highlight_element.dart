import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';

/// An element that is just highlight marker.
class HighlightElement extends StyledElement {
  int range;
  Color color;

  HighlightElement({
    required this.range,
    this.color = const Color.fromARGB(150, 255, 229, 127),
    super.parent,
    required super.node,
    required super.nodeToIndex,
  })  : assert(int.parse(node.attributes["range"]!) == range),
        super(style: Style());
}
