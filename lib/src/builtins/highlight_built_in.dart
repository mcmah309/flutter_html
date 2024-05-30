import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:rewind/rewind.dart';
import 'package:rust_core/cell.dart';

/// Adds a highlight mark to the to the Text elements for the specified range and color. A mark consists of highlighting and
/// adding a comment annotation widget
class HighlightBuiltIn extends HtmlExtension {
  const HighlightBuiltIn();

  @override
  bool matches(ExtensionContext context) {
    return supportedTags.contains(context.elementName) && context.styledElement is HighlightElement;
  }

  @override
  Set<String> get supportedTags => {
        "o-mark",
      };

  /// Traverse each element and add highlighting for the range, if the range
  /// stops in the middle of an element, split the stylized element
  @override
  void beforeProcessing(ExtensionContext context) {
    HighlightManager.addColorForRange(context.styledElement! as HighlightElement);
  }

  /// Adds a marker to the highlight that a comment can be attached to
  @override
  InlineSpan build(ExtensionContext context, HighlightManager highlightManager) {
    // double markerWidth = context.styledElement!.style.fontSize!.value; //todo remove null check, log, return nada
    // double markerHeight = markerWidth;
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
class MarkWidget extends StatefulWidget {
  const MarkWidget({
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
  State<StatefulWidget> createState() => MarkWidgetState();
}

class MarkWidgetState extends State<MarkWidget> {
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
        shadows: <Shadow>[
          Shadow(
              color: Colors.black, blurRadius: widget.markerWidth / 5, offset: const Offset(1, 1))
        ]);
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
                    offset: Offset(
                        -widget.markerWidth / 2, -widget.lineHeight - widget.markerHeight / 2),
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
