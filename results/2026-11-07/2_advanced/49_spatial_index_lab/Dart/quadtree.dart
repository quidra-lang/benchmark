part of 'main.dart';

const childNames = ['NW', 'NE', 'SW', 'SE'];

class QuadNode {
  final int x, y, size;
  List<SpatialObject> points = [];
  List<QuadNode> children = [];
  QuadNode(this.x, this.y, this.size);
}

int destination(QuadNode node, SpatialObject point) =>
    (point.box.x1 >= node.x + node.size ~/ 2 ? 1 : 0) +
    (point.box.y1 >= node.y + node.size ~/ 2 ? 2 : 0);
void insertQuad(QuadNode node, SpatialObject point, int capacity) {
  if (node.children.isNotEmpty) {
    insertQuad(node.children[destination(node, point)], point, capacity);
    return;
  }
  node.points.add(point);
  node.points.sort((a, b) => a.id.compareTo(b.id));
  if (node.points.length <= capacity) {
    return;
  }
  final h = node.size ~/ 2;
  node.children = [
    QuadNode(node.x, node.y, h),
    QuadNode(node.x + h, node.y, h),
    QuadNode(node.x, node.y + h, h),
    QuadNode(node.x + h, node.y + h, h),
  ];
  final previous = node.points;
  node.points = [];
  for (final p in previous) {
    insertQuad(node, p, capacity);
  }
}

void deleteQuad(QuadNode node, SpatialObject point, int capacity) {
  if (node.children.isEmpty) {
    node.points.removeWhere((p) => p.id == point.id);
    return;
  }
  deleteQuad(node.children[destination(node, point)], point, capacity);
  if (node.children.any((c) => c.children.isNotEmpty)) {
    return;
  }
  final points = node.children.expand((c) => c.points).toList();
  if (points.length <= capacity) {
    points.sort((a, b) => a.id.compareTo(b.id));
    node.points = points;
    node.children = [];
  }
}

QuadNode buildQuad(List<SpatialObject> points, int world, int capacity) {
  final root = QuadNode(0, 0, world);
  for (final p in points) {
    insertQuad(root, p, capacity);
  }
  return root;
}
