import 'package:flutter/widgets.dart';
import 'package:flutter_html/src/tree/styled_element.dart';
import 'package:html/dom.dart' as dom;

/// Key used for hashing and retrieving
class _BaseAnchorKey extends GlobalKey {
  const _BaseAnchorKey._(this.parentKey, this.id) : super.constructor();

  final Key parentKey;
  final String id;

  /// Create an anchor key if input is valid
  static _BaseAnchorKey? _createFor(Key parentKey, String id) {
    if (id == "[[No ID]]" || id.isEmpty) {
      return null;
    }
    return _BaseAnchorKey._(parentKey, id);
  }

  AnchorKey downCast(dom.Node node) => AnchorKey._(parentKey, id, node);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BaseAnchorKey && parentKey == other.parentKey && id == other.id;

  @override
  int get hashCode => parentKey.hashCode ^ id.hashCode;
}

/// Full key with all the data
class AnchorKey extends _BaseAnchorKey {
  static final Set<AnchorKey> _registry = <AnchorKey>{};

  final dom.Node node;

  const AnchorKey._(Key parentKey, String id, this.node)
      : super._(parentKey, id);

  /// Returns a unique [AnchorKey]. i.e. The anchor key if not already created.
  static AnchorKey? of(Key parentKey, StyledElement styledElement) {
    final baseKey =
        _BaseAnchorKey._createFor(parentKey, styledElement.elementId);
    if (baseKey == null || _registry.contains(baseKey)) {
      // Invalid id or already created a key with this id: silently ignore
      return null;
    }
    final key = baseKey.downCast(styledElement.node);
    _registry.add(key);
    return key;
  }

  /// get anchor key if it already exists
  static AnchorKey? getFor(Key parentKey, String id) {
    final baseKey = _BaseAnchorKey._createFor(parentKey, id);
    if (baseKey == null || !_registry.contains(baseKey)) {
      return null;
    }
    return _registry.lookup(baseKey)!;
  }

  static void resetRegistry() {
    _registry.clear();
  }

  @override
  String toString() {
    return 'AnchorKey{parentKey: $parentKey, id: #$id}';
  }
}
