import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:rewind/rewind.dart';
import 'package:rust_core/cell.dart';

/// Adds Mark to the to the Text elements for the specified range and color. A mark consists of highlighting and
/// adding a comment annotation widget
class MarkBuiltIn extends HtmlExtension {
  const MarkBuiltIn();

  static const defaultHighlightColor = Color.fromARGB(150, 255, 229, 127);

  @override
  bool matches(ExtensionContext context) {
    return supportedTags.contains(context.elementName);
  }

  @override
  Set<String> get supportedTags => {
        "o-mark",
      };

  /// Traverse each element and add highlighting for the range, if the range
  /// stops in the middle of an element, split the stylized element
  @override
  void beforeProcessing(ExtensionContext context) {
    addColorForRangeIfPresent(context.styledElement!);
  }

  void addColorForRangeIfPresent(StyledElement element){
    String? rangeStr = element.attributes["range"];
    if (rangeStr == null) {
      return;
    }
    final int? range = int.tryParse(rangeStr);
    if (range == null) {
      return;
    }
    String? colorStr = element.attributes["color"];
    Color color;
    if (colorStr == null) {
      // Colors.amberAccent.shade100 with 150 transparency
      color = defaultHighlightColor;
    } else {
      color = const ColorConverter().fromJson(colorStr);
      if (color == const Color.fromARGB(0, 0, 0, 0)) {
        color = defaultHighlightColor;
      }
    }
    _traverseAndAddStyle(element, Style(backgroundColor: color), Cell<int>(range), 0);
  }

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

  void _traverseAndAddStyleDownInclusive(StyledElement element, Style style, Cell<int> characterCount, int skip) {
    if (characterCount.get() > 0) {
      assert(
          (element.node is dom.Text && element is TextContentElement) ||
              (element.node is! dom.Text && element is! TextContentElement),
          "The only Text nodes and TextContentElements should only be paired together");
      if (element is TextContentElement) {
        String text = element.text;
        int length = text.length;
        // Single string non-empty elements are not counted. See [Guarentees.md] for more.
        if (text == " ") {
          // Intentionally empty
        } else if (length > characterCount.get()) {
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

  /// Adds a marker to the highlight that a comment can be attached to
  @override
  InlineSpan build(ExtensionContext context, HighlightManager highlightManager) {
    double markerWidth = context.styledElement!.style.fontSize!.value; //todo remove null check, log, return nada
    double markerHeight = markerWidth;
    // return WidgetSpan(
    //     child: Mark(
    //   markerHeight: markerHeight,
    //   markerWidth: markerWidth,
    //   lineHeight: markerHeight,
    // ));
    return TextSpan();
  }
}

/// Widget that creates a "mark" (annotation).
///
/// Developer Notes: Gesture detection was not working, even with the custom gesture detector when using a regular
/// stack. Using just an overlay
/// resulted in when scrolling, the overlay mark would appear over the app and bottom bar. Therefore, the two approaches
/// where combined, the icon is visible as an in page element (that gets covered on scroll) and the tap action is an
/// overlay exactly on top of the icon. Unfortunately, this does mean that the tap action is available when the mark is
/// under either of the bars though. The ideal solution would be just to have the in element stack pick up gestures.
class Mark extends StatefulWidget {
  const Mark({
    super.key,
    required this.markerHeight,
    required this.markerWidth,
    required this.lineHeight,
    this.child,
  });

  final double markerHeight;
  final double markerWidth;
  final double lineHeight;
  final Widget? child;

  @override
  State<StatefulWidget> createState() => MarkState();
}

class MarkState extends State<Mark> {
  final OverlayPortalController _controller = OverlayPortalController();
  final LayerLink layerLink = LayerLink();

  GlobalKey mark = GlobalKey();
  GlobalKey mark2 = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.endOfFrame.then((_) {
      _controller.show();
    });
    final icon = Icon(Icons.bookmark,
        size: widget.markerHeight,
        color: const Color.fromARGB(255, 128, 0, 32), // burgundy
        shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: widget.markerWidth / 5, offset: const Offset(1, 1))]);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -(widget.lineHeight + widget.markerHeight / 2),
          // position outside the stack
          left: -widget.markerWidth / 2,
          child: SizedBox.shrink(
            child: CustomTapDetector(
                onTap: (duration, offset) {
                  Log.w("taasgaed"); //todo
                },
                child: icon),
          ),
        ),
        CompositedTransformTarget(
          link: layerLink,
          child: SizedBox.shrink(
            child: OverlayPortal(
              controller: _controller,
              overlayChildBuilder: (BuildContext context) {
                return Positioned(
                  width: widget.markerWidth,
                  child: CompositedTransformFollower(
                    offset: Offset(-widget.markerWidth / 2, -widget.lineHeight - widget.markerHeight / 2),
                    link: layerLink,
                    child: GestureDetector(
                        onTap: () {
                          Log.w("taasgaed"); //todo
                        },
                        child: Opacity(
                          opacity: 0,
                          child: icon,
                        )),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
