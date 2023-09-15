import 'package:flutter/widgets.dart';
import 'package:flutter_html/src/tree/styled_element.dart';

class AnchorKey extends GlobalKey {
  static final Set<AnchorKey> _registry = <AnchorKey>{};

  final Key parentKey;
  final String id;

  const AnchorKey._(this.parentKey, this.id) : super.constructor();

  /// Returns the anchor key if not already created
  static AnchorKey? of(Key parentKey, StyledElement styledElement) {
    final key = createFor(parentKey, styledElement.elementId);
    if (key == null || _registry.contains(key)) {
      // Invalid id or already created a key with this id: silently ignore
      return null;
    }
    _registry.add(key);
    return key;
  }

  /// get anchor key if it already exists
  static AnchorKey? getFor(Key parentKey, String id) {
    final key = createFor(parentKey, id);
    if (key != null && _registry.contains(key)) {
      return key;
    }
    return null;
  }

  /// Create an anchor key if input is valid
  static AnchorKey? createFor(Key parentKey, String id) {
    if (id == "[[No ID]]" || id.isEmpty) {
      return null;
    }
    return AnchorKey._(parentKey, id);
  }

  static void resetRegistry() {
    _registry.clear();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorKey &&
          runtimeType == other.runtimeType &&
          parentKey == other.parentKey &&
          id == other.id;

  @override
  int get hashCode => parentKey.hashCode ^ id.hashCode;

  @override
  String toString() {
    return 'AnchorKey{parentKey: $parentKey, id: #$id}';
  }
}
