import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_html/src/style.dart';
import 'package:html/dom.dart' as dom;
//TODO(Sub6Resources): don't use the internal code of the html package as it may change unexpectedly.
//ignore: implementation_imports
import 'package:html/src/query_selector.dart';
import 'package:list_counter/list_counter.dart';
import 'package:rust/rust.dart';

import '../processing/node_order.dart';

/// A [StyledElement] applies a style to all of its children.
class StyledElement {
  final String name;
  final String elementId;
  late final List<String> elementClasses;
  /// The parent of this element. Set when this is assigned as a child of another element.
  StyledElement? parent;
  late final List<StyledElement> children;
  Style style;
  final dom.Node node;
  final ListQueue<Counter> counters = ListQueue<Counter>();

  /// A callback function that can rebuild the widget that is associated with the element.
  /// Only provided if this element has been built.
  void Function()? rebuildAssociatedWidget;

  StyledElement({
    this.name = "[[No name]]",
    this.elementId = "[[No ID]]",
    List<String>? elementClasses,
    List<StyledElement>? children,
    required this.style,
    required this.node,
    this.rebuildAssociatedWidget,
  }) {
    this.elementClasses = elementClasses ?? [];
    this.children = children ?? [];
    for (final e in this.children) {
      assert(e.parent == null);
      e.parent = this;
    }
  }

  /// Note: I believe this checks if a css selector applies to this node. Usually used to then apply the selector properties
  /// to the node
  bool matchesSelector(String selector) {
    if (name == selector) {
      return true;
    }
    if (element == null) {
      return false;
    }
    final isMatch = guard(() => matches(element!, selector))
        .isOkAnd((p0) => p0); // issue https://github.com/Sub6Resources/flutter_html/issues/1298
    return isMatch;
  }

  // static void resetSelectorMatchMemoization(){
  //   _memoizeSelectorMatch = Expando();
  // }

  static Expando<bool> _memoizeSelectorMatch = Expando();

  /// Note: Given [matches] speed an the number of times this is called, [matchesSelector] is an extreme performance bottleneck.
  /// memoizing gives an observed 10x speedup. The drawback is that if something about the node changes, this will not be picked up.
  bool matchesSelectorMemoized(String selector) {
    if (element == null) {
      return false;
    }
    if (name == selector) {
      return true;
    }
    final input = MemoizedMatchInput(element!, selector);
    var isMatch = _memoizeSelectorMatch[input];
    while (isMatch == null) {
      isMatch = guard(() => matches(element!, selector))
          .isOkAnd((p0) => p0); // issue https://github.com/Sub6Resources/flutter_html/issues/1298
      _memoizeSelectorMatch[input] = isMatch;
    }
    return isMatch;
  }

  Map<String, String> get attributes => node.attributes.map((key, value) {
        return MapEntry(key.toString(), value);
      });

  dom.Element? get element {
    if (node is dom.Element) {
      return node as dom.Element;
    }
    return null;
  }

  /// Inserts the element before, assumes the new element and its node have not been connected yet
  void insertBefore(StyledElement element) {
    assert(node.parent != null && element.parent == null);
    assert(parent != null && element.parent == null);
    node.parentNode!.insertBefore(element.node, node);
    parent!.children.insert(parent!.children.indexOf(this), element);
    element.parent = parent!;
  }

  /// Inserts the element before, does not touch the elements node
  void insertBeforeDoNotConnectNode(StyledElement element) {
    parent!.children.insert(parent!.children.indexOf(this), element);
    element.parent = parent!;
  }

  /// Inserts the element after, does not touch the elements node
  void insertAfterDoNotConnectNode(StyledElement element) {
    parent!.children.insert(parent!.children.indexOf(this) + 1, element);
    element.parent = parent!;
  }

  /// Disconnects this from the parent tree.
  void disconnectFromParent() {
    if (parent != null) {
      var hasRemoved = parent!.children.remove(this);
      assert(hasRemoved);
      hasRemoved = node.parent!.nodes.remove(node);
      assert(hasRemoved);
      parent = null;
      node.parentNode = null;
    } else {
      assert(node.parent == null);
    }
  }

  bool isAncestorOf(StyledElement element) {
    StyledElement? parent = element.parent;
    while (parent != null) {
      if (parent == this) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  StyledElement root() {
    StyledElement element = this;
    while (element.parent != null) {
      element = element.parent!;
    }
    return element;
  }

  @override
  String toString() {
    String selfData =
        "[$name] ${children.length} ${elementClasses.isNotEmpty == true ? 'C:${elementClasses.toString()}' : ''}${elementId.isNotEmpty == true ? 'ID: $elementId' : ''}";
    for (var child in children) {
      selfData += ("\n${child.toString()}").replaceAll(RegExp("^", multiLine: true), "-");
    }
    return selfData;
  }

  //************************************************************************//

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is StyledElement && other.node == node;
  }

  @override
  int get hashCode => node.hashCode;
}

FontSize numberToFontSize(String num) {
  switch (num) {
    case "1":
      return FontSize.xxSmall;
    case "2":
      return FontSize.xSmall;
    case "3":
      return FontSize.small;
    case "4":
      return FontSize.medium;
    case "5":
      return FontSize.large;
    case "6":
      return FontSize.xLarge;
    case "7":
      return FontSize.xxLarge;
  }
  if (num.startsWith("+")) {
    final relativeNum = double.tryParse(num.substring(1)) ?? 0;
    return numberToFontSize((3 + relativeNum).toString());
  }
  if (num.startsWith("-")) {
    final relativeNum = double.tryParse(num.substring(1)) ?? 0;
    return numberToFontSize((3 - relativeNum).toString());
  }
  return FontSize.medium;
}

extension DeepCopy on ListQueue<Counter> {
  ListQueue<Counter> deepCopy() {
    return ListQueue<Counter>.from(map((counter) {
      return Counter(counter.name, counter.value);
    }));
  }
}

class MemoizedMatchInput {
  dom.Node node;
  String text;

  MemoizedMatchInput(this.node, this.text);

  @override
  bool operator ==(Object other) =>
      other is MemoizedMatchInput && node == other.node && text == other.text;

  @override
  int get hashCode => node.hashCode ^ text.hashCode;
}
