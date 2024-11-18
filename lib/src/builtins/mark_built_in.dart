import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tools/flutter_tools.dart';
import 'package:html/dom.dart' as dom;
import 'package:rewind/rewind.dart';

/// Adds a mark mark to the to the Text elements for the specified range and color. A mark consists of marking and
/// adding a comment annotation widget
class MarkBuiltIn extends HtmlExtension {
  const MarkBuiltIn();

  @override
  bool matches(ExtensionContext context) {
    return supportedTags.contains(context.elementName) && context.styledElement is MarkElement;
  }

  @override
  Set<String> get supportedTags => {
        "o-mark",
      };

  /// Traverse each element and add marking for the range, if the range
  /// stops in the middle of an element, split the stylized element
  @override
  void beforeProcessing(ExtensionContext context) {
    MarkManager.addStyleForRange(context.styledElement! as MarkElement);
  }

  /// Adds a marker to the mark that a comment can be attached to
  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    double? markerWidth = context.styledElement?.style.fontSize?.value;
    if (markerWidth == null) {
      Log.e("There must be a set font size otherwise the size of markers is unknown");
      return const TextSpan();
    }
    //return const TextSpan();
    double markerHeight = markerWidth;
    return WidgetSpan(
        child: MarkWidget(
      markManager: markManager,
      markElement: context.styledElement as MarkElement,
      markerHeight: markerHeight,
      markerWidth: markerWidth,
      lineHeight: markerHeight,
    ));
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
    required this.markManager,
    required this.markElement,
    required this.markerHeight,
    required this.markerWidth,
    required this.lineHeight,
    this.child,
  });

  final MarkManager markManager;
  final MarkElement markElement;
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
    final gestureWidth = widget.markerWidth * 1.3;
    final gestureHieght = gestureWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -(widget.lineHeight + widget.markerHeight / 2),
          // position outside the stack
          left: -widget.markerWidth / 2,
          child: SizedBox.shrink(
            key: MarkGlobalKey(widget.markElement.mark),
            child: icon,
          ),
        ),
        CompositedTransformTarget(
          link: layerLink,
          child: SizedBox.shrink(
            child: OverlayPortal(
              controller: _controller,
              overlayChildBuilder: (BuildContext context) {
                return Positioned(
                  width: gestureWidth,
                  height: gestureHieght,
                  child: CompositedTransformFollower(
                    offset: Offset(-(gestureWidth) / 2, -widget.lineHeight - gestureHieght / 2),
                    link: layerLink,
                    // ignore: sized_box_for_whitespace
                    child: Container(
                      width: gestureWidth,
                      height: gestureHieght,
                      //color: Colors.red,
                      child: GestureDetector(
                        onTap: () {
                          widget.markManager.markTapped(widget.markElement);
                        },
                      ),
                    ),
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

class MarkGlobalKey<T extends State<StatefulWidget>> extends GlobalKey<T> {
  const MarkGlobalKey(this.mark) : super.constructor();

  final Mark mark;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is MarkGlobalKey<T> && mark == other.mark;
  }

  @override
  int get hashCode => mark.hashCode;
}
