part of 'main.dart';

class KDNode {
  SpatialObject point;
  final int axis;
  KDNode? left, right;
  KDNode(this.point, this.axis, [this.left, this.right]);
}

bool keyLess(SpatialObject a, SpatialObject b, int axis) {
  final first = axis == 0 ? 0 : 1, second = axis == 0 ? 1 : 0;
  if (a.box[first] != b.box[first]) {
    return a.box[first] < b.box[first];
  }
  if (a.box[second] != b.box[second]) {
    return a.box[second] < b.box[second];
  }
  return a.id < b.id;
}

KDNode? buildKD(List<SpatialObject> points, int depth) {
  if (points.isEmpty) {
    return null;
  }
  final axis = depth % 2,
      ordered = List<SpatialObject>.of(points)
        ..sort(
          (a, b) => keyLess(a, b, axis)
              ? -1
              : keyLess(b, a, axis)
              ? 1
              : 0,
        );
  final middle = ordered.length ~/ 2;
  return KDNode(
    ordered[middle],
    axis,
    buildKD(ordered.sublist(0, middle), depth + 1),
    buildKD(ordered.sublist(middle + 1), depth + 1),
  );
}

KDNode insertKD(KDNode? root, SpatialObject point) {
  if (root == null) {
    return KDNode(point, 0);
  }
  var node = root;
  while (true) {
    final left = keyLess(point, node.point, node.axis),
        child = left ? node.left : node.right;
    if (child == null) {
      final next = KDNode(point, 1 - node.axis);
      if (left) {
        node.left = next;
      } else {
        node.right = next;
      }
      return root;
    }
    node = child;
  }
}

SpatialObject minimumKD(KDNode node, int axis) {
  if (node.axis == axis) {
    return node.left == null ? node.point : minimumKD(node.left!, axis);
  }
  var best = node.point;
  for (final child in [node.left, node.right]) {
    if (child != null) {
      final candidate = minimumKD(child, axis);
      if (keyLess(candidate, best, axis)) {
        best = candidate;
      }
    }
  }
  return best;
}

KDNode? deleteKD(KDNode? node, SpatialObject point) {
  if (node == null) {
    return null;
  }
  if (node.point.id == point.id) {
    if (node.right != null) {
      final replacement = minimumKD(node.right!, node.axis);
      node.point = replacement;
      node.right = deleteKD(node.right, replacement);
    } else if (node.left != null) {
      final replacement = minimumKD(node.left!, node.axis);
      node.point = replacement;
      node.right = deleteKD(node.left, replacement);
      node.left = null;
    } else {
      return null;
    }
  } else if (keyLess(point, node.point, node.axis)) {
    node.left = deleteKD(node.left, point);
  } else {
    node.right = deleteKD(node.right, point);
  }
  return node;
}
