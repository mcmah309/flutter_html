import 'dart:isolate';

import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/parser.dart';
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/builtins/line_break_builtin.dart';
import 'package:flutter_html/src/css_parser.dart';
import 'package:flutter_html/src/processing/lists.dart';
import 'package:flutter_html/src/processing/margins.dart';
import 'package:flutter_html/src/processing/node_order.dart';
import 'package:flutter_html/src/processing/relative_sizes.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;

typedef OnTap = void Function(
  String? url,
  Map<String, String> attributes,
  html.Element? element,
);

typedef OnCssParseError = String? Function(
  String css,
  List<css_parser.Message> errors,
);

class HtmlParser {
  final Key parserKey;
  final void Function(StyledElement)? postPrepareTree;
  final void Function(StyledElement)? postStyleTree;
  final OnTap? onAnchorTap;
  final OnTap? onLinkTap;
  final OnCssParseError? onCssParseError;
  final bool shrinkWrap;
  final Map<String, Style> globalStyles;
  final List<HtmlExtension> extensions;
  final Set<String> doNotRenderTheseTags;
  final Set<String> onlyRenderTheseTags;
  final MarkManager markManager;
  final List<Mark> marks;

  HtmlParser({
    required this.parserKey,
    this.postPrepareTree,
    this.postStyleTree,
    this.onAnchorTap,
    this.onLinkTap,
    this.onCssParseError,
    this.shrinkWrap = false,
    required this.globalStyles,
    required this.extensions,
    this.doNotRenderTheseTags = const {},
    this.onlyRenderTheseTags = const {},
    required this.markManager,
    this.marks = const [],
  });

  Widget parseWidget(dom.Element htmlData) {
    // Dev Note: Originally this returned a Future and used `Future.microtask` (would rather prefer `Isolate.run` but this does not work, since much of the code used below pulls in the library 'dart:async').
    // This is now sync since changing _configureTree and _buildTree to async proved to be challenging so it was abandoned, it might be worth while. Adding yields in this function
    // is just not meaningful. Ultimately still most of
    // time is spent on the building the widget tree in the `build` methods and there is nothing that can be done about that.
    StyledElement root = StyledElement(
        name: '[Tree Root]', children: [], node: htmlData, style: globalStyles["html"] ?? Style());
    markManager.setRoot(root);
    String externalCss = htmlData.getElementsByTagName("style").map((e) => e.innerHtml).join();
    final parserConfig = ParserConfig(
        shrinkWrap: shrinkWrap,
        parserKey: parserKey,
        globalStyles: globalStyles,
        internalOnAnchorTap: internalOnTap);

    reConfigFunc(StyledElement root) => _configureTree(
        root, extensions, globalStyles, externalCss, parserConfig, markManager, marks,
        postPrepareTree: postPrepareTree,
        postStyleTree: postStyleTree,
        doNotRenderTheseTags: doNotRenderTheseTags,
        onlyRenderTheseTags: onlyRenderTheseTags);
    reConfigFunc(root);
    final treeBuilt = _buildTree(root, extensions, markManager, reConfigFunc, parserConfig,
        doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
    return _HtmlParseWidgetResultWrapper(
      htmlParser: this,
      child: Builder(builder: (context) {
        return CssBoxWidgetWithInlineSpanChildren(
          rebuild: () {
            if (context.mounted) {
              (context as Element).markNeedsBuild();
            }
          },
          styledElement: root,
          children: [treeBuilt],
          shrinkWrap: shrinkWrap,
          top: true,
          markManager: markManager,
        );
      }),
    );
  }

  static final builtIns = [
    const ImageBuiltIn(),
    const VerticalAlignBuiltIn(),
    const InteractiveElementBuiltIn(),
    const RubyBuiltIn(),
    const DetailsElementBuiltIn(),
    const StyledElementBuiltIn(),
    const MarkBuiltIn(),
    const LineBreakBuiltIn(),
    const TextBuiltIn(),
  ];

  /// [parseHTML] converts a string of HTML to a DOM element using the dart `html` library.
  static html.Element parseHTML(String data) {
    return html_parser.parse(data).documentElement!;
  }

  /// [parseCss] converts a string of CSS to a CSS stylesheet using the dart `csslib` library.
  static css.StyleSheet parseCss(String data) {
    return css_parser.parse(data);
  }

  void internalOnTap(String? url, Map<String, String> attributes, html.Element? element) {
    if (url?.startsWith("#") == true) {
      if (onAnchorTap != null) {
        onAnchorTap!(url, attributes, element);
        return;
      } else {
        final anchorContext = AnchorKey.getFor(parserKey, url!.substring(1))?.currentContext;
        if (anchorContext != null) {
          Scrollable.ensureVisible(anchorContext);
        }
        return;
      }
    } else {
      onLinkTap?.call(url, attributes, element);
    }
  }
}

class _HtmlParseWidgetResultWrapper extends StatefulWidget {
  final HtmlParser htmlParser;
  final Widget child;

  _HtmlParseWidgetResultWrapper({
    required this.htmlParser,
    required this.child,
  }) : super(key: htmlParser.parserKey);

  @override
  State<_HtmlParseWidgetResultWrapper> createState() => _HtmlParseWidgetResultWrapperState();
}

class _HtmlParseWidgetResultWrapperState extends State<_HtmlParseWidgetResultWrapper> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (var e in widget.htmlParser.extensions) {
      e.onDispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

void _configureTree(StyledElement tree, List<HtmlExtension> extensions, Map<String, Style> style,
    String externalCss, ParserConfig parserConfig, MarkManager markManager, List<Mark> marks,
    {String? Function(String, List<Message>)? onCssParseError,
    void Function(StyledElement tree)? postPrepareTree,
    void Function(StyledElement tree)? postStyleTree,
    required Set<String> doNotRenderTheseTags,
    required Set<String> onlyRenderTheseTags}) async {
  // Preparing Step
  _prepareHtmlTree(tree, extensions, parserConfig,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
  markManager.setMarks(marks);
  postPrepareTree?.call(tree);

  // Styling Step
  _beforeStyleTree(tree, null, extensions, parserConfig,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
  _styleTree(tree, style, externalCss, onCssParseError);
  postStyleTree?.call(tree);

  // Processing Step
  _beforeProcessTree(tree, null, extensions, parserConfig,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
  _processTree(tree);
}

/// [_processTree] takes the now-styled [StyleElement] tree and does some final
/// processing steps: removing unnecessary whitespace and empty elements,
/// calculating relative values, processing list markers and counters,
/// processing `before`/`after` generated elements, and collapsing margins
/// according to CSS rules.
void _processTree(StyledElement tree) {
  tree = RelativeSizesProcessing.processRelativeValues(tree);
  tree = ListProcessing.processLists(tree);
  tree = MarginProcessing.processMargins(tree);
}

/// Converts the tree of Html nodes into a StyledElement tree
void _prepareHtmlTree(StyledElement tree, List<HtmlExtension> extensions, ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  for (var node in tree.node.nodes) {
    tree.children.add(_prepareHtmlTreeRecursive(node, null, extensions, parserConfig,
        doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags));
    for (final e in tree.children) {
      e.parent = tree;
    }
  }
}

/// Recursive helper method for [lexHtmlTree]. Builds from the bottom up -
/// children are built first, then passed to the parent for construction
StyledElement _prepareHtmlTreeRecursive(html.Node node, ExtensionContext? parentContext,
    List<HtmlExtension> extensions, ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  // Set the extension context for this node.
  final extensionContext = ExtensionContext(
    node: node,
    parent: parentContext,
    currentStep: CurrentStep.preparing,
    parserConfig: parserConfig,
  );

  // Block the tag from rendering if it is restricted.
  if (_isTagRestricted(extensionContext,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags)) {
    return EmptyContentElement(node: node);
  }

  // Lex this element's children
  final children = node.nodes
      .map((n) => _prepareHtmlTreeRecursive(n, extensionContext, extensions, parserConfig,
          doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags))
      .toList();

  // Prepare the element from one of the extensions
  return _prepareFromExtension(extensionContext, children, extensions);
}

/// Prepares the html node using one of the built-ins or HtmlExtensions
/// available. If none of the extensions matches, returns an
/// EmptyContentElement
StyledElement _prepareFromExtension(ExtensionContext extensionContext, List<StyledElement> children,
    List<HtmlExtension> extensions) {
  // Loop through every extension and see if it can handle this node
  for (final extension in extensions) {
    if (extension.matches(extensionContext)) {
      return extension.prepare(extensionContext, children);
    }
  }

  // Loop through built in elements and see if they can handle this node.
  for (final builtIn in HtmlParser.builtIns) {
    if (builtIn.matches(extensionContext)) {
      return builtIn.prepare(extensionContext, children);
    }
  }

  // If no extension or built-in matches, then return an empty content element.
  return EmptyContentElement(node: extensionContext.node);
}

/// [styleTree] takes the lexed [StyleElement] tree and applies external,
/// inline, and custom CSS/Flutter styles, and then cascades the styles down the tree.
void _styleTree(StyledElement tree, Map<String, Style> style, String externalCss,
    OnCssParseError? onCssParseError) {
  final styleTagDeclarations = parseExternalCss(externalCss, onCssParseError);

  _styleTreeRecursive(tree, styleTagDeclarations, style, onCssParseError);
}

/// Recursive helper method for [styleTree].
void _styleTreeRecursive(StyledElement tree, styleTagDeclarations, Map<String, Style> style,
    OnCssParseError? onCssParseError) {
  // Apply external CSS
  styleTagDeclarations.forEach((selector, style) {
    if (tree.matchesSelectorMemoized(selector)) {
      tree.style = tree.style.merge(declarationsToStyle(style));
    }
  });

  // Apply inline styles
  if (tree.attributes.containsKey("style")) {
    final newStyle = inlineCssToStyle(tree.attributes['style'], onCssParseError);
    if (newStyle != null) {
      tree.style = tree.style.merge(newStyle);
    }
  }

  // Apply custom styles
  style.forEach((selector, style) {
    if (tree.matchesSelectorMemoized(selector)) {
      tree.style = tree.style.merge(style);
    }
  });

  // Cascade applicable styles down the tree. Recurse for all children
  for (final child in tree.children) {
    child.style = tree.style.copyOnlyInherited(child.style);
    _styleTreeRecursive(child, styleTagDeclarations, style, onCssParseError);
  }
}

bool _isTagRestricted(ExtensionContext context,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  // Block the tag from rendering if it is restricted.
  if (context.node is! html.Element) {
    return false;
  }

  if (doNotRenderTheseTags.contains(context.elementName)) {
    return true;
  }

  if (onlyRenderTheseTags.contains(context.elementName)) {
    return true;
  }

  return false;
}

/// Called before any styling is cascaded on the tree
void _beforeStyleTree(StyledElement tree, ExtensionContext? parentContext,
    List<HtmlExtension> extensions, ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  final extensionContext = ExtensionContext(
      node: tree.node,
      parent: parentContext,
      styledElement: tree,
      currentStep: CurrentStep.preStyling,
      parserConfig: parserConfig);

  // Prevent restricted tags from getting sent to extensions.
  if (_isTagRestricted(extensionContext,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags)) {
    return;
  }

  // Loop through every extension and see if it wants to process this element
  for (final extension in extensions) {
    if (extension.matches(extensionContext)) {
      extension.beforeStyle(extensionContext);
    }
  }

  // Loop through built in elements and see if they want to process this element.
  for (final builtIn in HtmlParser.builtIns) {
    if (builtIn.matches(extensionContext)) {
      builtIn.beforeStyle(extensionContext);
    }
  }

  // Do the same recursively
  for (final s in tree.children) {
    _beforeStyleTree(s, extensionContext, extensions, parserConfig,
        doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
  }
}

/// Called before any processing is done on the tree
void _beforeProcessTree(StyledElement tree, ExtensionContext? parentContext,
    List<HtmlExtension> extensions, ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  final extensionContext = ExtensionContext(
    node: tree.node,
    parent: parentContext,
    styledElement: tree,
    currentStep: CurrentStep.preProcessing,
    parserConfig: parserConfig,
  );

  // Prevent restricted tags from getting sent to extensions
  if (_isTagRestricted(extensionContext,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags)) {
    return;
  }

  // Loop through every extension and see if it can process this element
  for (final extension in extensions) {
    if (extension.matches(extensionContext)) {
      extension.beforeProcessing(extensionContext);
    }
  }

  // Loop through built in elements and see if they can process this element.
  for (final builtIn in HtmlParser.builtIns) {
    if (builtIn.matches(extensionContext)) {
      builtIn.beforeProcessing(extensionContext);
    }
  }

  // Do the same recursively.[HighlightBuiltIn] modifies the tree so need to copy the list or will have concurrent modification error.
  tree.children.toList(growable: false).forEach((n) => _beforeProcessTree(
      n, extensionContext, extensions, parserConfig,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags));
}

/// [_buildTree] converts a tree of [StyledElement]s to an [InlineSpan] tree.
InlineSpan _buildTree(StyledElement tree, List<HtmlExtension> extensions, MarkManager markManager,
    void Function(StyledElement tree) reConfigureTree, ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags, required Set<String> onlyRenderTheseTags}) {
  return _buildTreeRecursive(tree, null, extensions, markManager, reConfigureTree, parserConfig,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags);
}

InlineSpan _buildTreeRecursive(
    StyledElement tree,
    ExtensionContext? parentContext,
    List<HtmlExtension> extensions,
    MarkManager markManager,
    void Function(StyledElement tree) reConfigureTree,
    ParserConfig parserConfig,
    {required Set<String> doNotRenderTheseTags,
    required Set<String> onlyRenderTheseTags}) {
  // Generate a function that allows children to be built lazily
  Map<StyledElement, InlineSpan> buildChildren(ExtensionContext currentContext) {
    if (currentContext.willRebuildTree) {
      assert(
          tree.children.isEmpty, "Children should have already been removed if this flag is set.");
      assert(currentContext.builtChildren == null,
          "If `willRebuildTree` is true, then so should this, since that is what the flag implies");
      reConfigureTree(tree);
      currentContext.willRebuildTree = false;
    }
    return Map.fromEntries(tree.children.map((child) {
      return MapEntry(
          child,
          _buildTreeRecursive(
              child, currentContext, extensions, markManager, reConfigureTree, parserConfig,
              doNotRenderTheseTags: doNotRenderTheseTags,
              onlyRenderTheseTags: onlyRenderTheseTags));
    }));
  }

  // Set the extension context for this node.
  final extensionContext = ExtensionContext(
    node: tree.node,
    parent: parentContext,
    styledElement: tree,
    currentStep: CurrentStep.building,
    buildChildrenCallback: buildChildren,
    parserConfig: parserConfig,
  );

  // Block restricted tags from getting sent to extensions
  if (_isTagRestricted(extensionContext,
      doNotRenderTheseTags: doNotRenderTheseTags, onlyRenderTheseTags: onlyRenderTheseTags)) {
    return const TextSpan(text: "");
  }

  return _buildFromExtension(extensionContext, markManager, extensions);
}

/// Builds the StyledElement into an InlineSpan using one of the built-ins
/// or HtmlExtensions available. If none of the extensions matches, returns
/// an empty TextSpan.
InlineSpan _buildFromExtension(
  ExtensionContext extensionContext,
  MarkManager markManager,
  List<HtmlExtension> extensions,
) {
  // Loop through every extension and see if it can handle this node
  for (final extension in extensions) {
    if (extension.matches(extensionContext)) {
      return extension.build(extensionContext, markManager);
    }
  }

  // Loop through built in elements and see if they can handle this node.
  for (final builtIn in HtmlParser.builtIns) {
    if (builtIn.matches(extensionContext)) {
      return builtIn.build(extensionContext, markManager);
    }
  }

  return const TextSpan(text: "");
}
