library flutter_html;

//export src for advanced custom render uses (e.g. casting context.tree)
export 'package:flutter_html/src/anchor.dart';
// expose for to extend for custom marking
export 'package:flutter_html/src/builtins/builtins.dart';
//export extension api
export 'package:flutter_html/src/extension/html_extension.dart';
//export render context api
export 'package:flutter_html/src/html_parser.dart';
//export style api
export 'package:flutter_html/src/style.dart';
export 'package:flutter_html/src/tree/mark_element.dart';
export 'package:flutter_html/src/tree/interactable_element.dart';
export 'package:flutter_html/src/tree/replaced_element.dart';
export 'package:flutter_html/src/tree/styled_element.dart';
//export css_box_widget for use in extensions.
export 'package:flutter_html/src/widgets/css_box_widget.dart';
export 'package:flutter_html/src/widgets/styled_element_widget.dart';

export 'src/mark_manager.dart';