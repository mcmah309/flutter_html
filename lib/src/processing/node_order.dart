import 'package:html/dom.dart' as dom;
import 'package:rust/cell.dart';

/// {@template nodeToIndex}
/// Creates a map of nodes to node index in order. Can be useful when ordering.
/// {@endtemplate}
class NodeOrderProcessing {
  static Map<dom.Node, int> createNodeToIndexMap(dom.Node node) {
    Cell<int> index = Cell<int>(-1);
    Map<dom.Node, int> accumulator = {};
    _createNodeToIndexMapRecursive(node, accumulator, index);
    return accumulator;
  }

  static void _createNodeToIndexMapRecursive(dom.Node node, Map<dom.Node, int> accumulator, Cell<int> index) {
    index.inc();
    accumulator[node] = index.get();
    for (final child in node.nodes) {
      _createNodeToIndexMapRecursive(child, accumulator, index);
    }
  }

  static void reIndexNodeToIndexMapWith(
      Map<dom.Node, int> nodeToIndex, dom.Node node) {
    dom.Node root = node;
    while (root.parent != null) {
      root = root.parent!;
    }
    assert(nodeToIndex[root] == 0, "$node is not in nodeToIndex");
    nodeToIndex.clear();
    Cell<int> index = Cell<int>(-1);
    _createNodeToIndexMapRecursive(root, nodeToIndex, index);
  }
}
