import 'package:flutter/material.dart' hide Text;
import 'package:flutter_html/flutter_html.dart';

import 'text.dart';

/// A [RichText] widget that contains a [StyledElement] object that represents
/// where the textSpan came from
class StyledElementWidget extends StatelessWidget {
  const StyledElementWidget(
    this.styledElement,
    this.markManager,
    this.textSpan, {
    super.key,
    this.rebuild,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final StyledElement styledElement;
  final MarkManager markManager;
  final InlineSpan textSpan;
  final void Function()? rebuild;

  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      textSpan,
      onSelectionEvent: (selection, event) =>
          markManager.registerSelectionEvent(styledElement, selection, event),
      key: key,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      //textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
