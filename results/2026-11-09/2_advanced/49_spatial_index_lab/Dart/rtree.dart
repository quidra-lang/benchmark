part of 'main.dart';

class Box {
  final int x1, y1, x2, y2;
  const Box(this.x1, this.y1, this.x2, this.y2);
  int operator [](int index) => switch (index) {
    0 => x1,
    1 => y1,
    2 => x2,
    _ => y2,
  };
}

int area(Box b) => (b.x2 - b.x1) * (b.y2 - b.y1);
Box mbr(Box a, Box b) =>
    Box(min(a.x1, b.x1), min(a.y1, b.y1), max(a.x2, b.x2), max(a.y2, b.y2));
int enlargement(Box a, Box b) => area(mbr(a, b)) - area(a);
bool contains(Box a, Box b) =>
    a.x1 <= b.x1 && b.x2 <= a.x2 && a.y1 <= b.y1 && b.y2 <= a.y2;
bool intersects(Box a, Box b) =>
    a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2;
int overlap(Box a, Box b) {
  final w = min(a.x2, b.x2) - max(a.x1, b.x1),
      h = min(a.y2, b.y2) - max(a.y1, b.y1);
  return w > 0 && h > 0 ? w * h : 0;
}

class Entry {
  Box box;
  final int id, number;
  final RNode? child;
  Entry(this.box, {this.id = 0, this.child, this.number = 0});
}

class RNode {
  final int level;
  List<Entry> entries;
  RNode? parent;
  RNode(this.level, this.entries, [this.parent]) {
    adoptChildren();
  }
  Box get box {
    var result = entries.first.box;
    for (final e in entries.skip(1)) {
      result = mbr(result, e.box);
    }
    return result;
  }

  void adoptChildren() {
    if (level > 0) {
      for (final e in entries) {
        e.child!.parent = this;
      }
    }
  }
}

class RTree {
  final int maximum, minimum;
  RNode root = RNode(0, []);
  RTree(this.maximum, this.minimum);
  RNode chooseSubtree(Box box, int level) {
    var node = root;
    while (node.level > level) {
      var best = node.entries.first;
      for (final e in node.entries.skip(1)) {
        final a = enlargement(e.box, box), b = enlargement(best.box, box);
        if (a < b || a == b && area(e.box) < area(best.box)) {
          best = e;
        }
      }
      node = best.child!;
    }
    return node;
  }

  RNode split(RNode node) {
    final entries = node.entries;
    var first = 0, second = 1;
    int? bestWaste;
    for (var i = 0; i + 1 < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i].box,
            b = entries[j].box,
            waste = area(mbr(a, b)) - area(a) - area(b);
        if (bestWaste == null || waste > bestWaste) {
          first = i;
          second = j;
          bestWaste = waste;
        }
      }
    }
    final group1 = <Entry>[entries[first]],
        group2 = <Entry>[entries[second]],
        rest = [
          for (var i = 0; i < entries.length; i++)
            if (i != first && i != second) entries[i],
        ];
    var box1 = entries[first].box, box2 = entries[second].box;
    while (rest.isNotEmpty) {
      if (group1.length + rest.length == minimum) {
        group1.addAll(rest);
        break;
      }
      if (group2.length + rest.length == minimum) {
        group2.addAll(rest);
        break;
      }
      var selected = 0, greatest = -1, d1 = 0, d2 = 0;
      for (var i = 0; i < rest.length; i++) {
        final a = enlargement(box1, rest[i].box),
            b = enlargement(box2, rest[i].box),
            difference = (a - b).abs();
        if (difference > greatest) {
          selected = i;
          greatest = difference;
          d1 = a;
          d2 = b;
        }
      }
      final e = rest.removeAt(selected),
          choice1 =
              d1 < d2 ||
              d1 == d2 &&
                  (area(box1) < area(box2) ||
                      area(box1) == area(box2) &&
                          group1.length <= group2.length);
      if (choice1) {
        group1.add(e);
        box1 = mbr(box1, e.box);
      } else {
        group2.add(e);
        box2 = mbr(box2, e.box);
      }
    }
    node.entries = group1;
    node.adoptChildren();
    return RNode(node.level, group2, node.parent);
  }

  void insert(Entry entry, [int level = 0]) {
    var node = chooseSubtree(entry.box, level);
    node.entries.add(entry);
    if (level > 0) {
      entry.child!.parent = node;
    }
    while (true) {
      final sibling = node.entries.length > maximum ? split(node) : null,
          parent = node.parent;
      if (parent == null) {
        if (sibling != null) {
          root = RNode(node.level + 1, [
            Entry(node.box, child: node),
            Entry(sibling.box, child: sibling),
          ]);
        }
        return;
      }
      for (final e in parent.entries) {
        if (identical(e.child, node)) {
          e.box = node.box;
          break;
        }
      }
      if (sibling != null) {
        parent.entries.add(Entry(sibling.box, child: sibling));
        sibling.parent = parent;
      }
      node = parent;
    }
  }

  void delete(SpatialObject point) {
    final located = findLeaf(root, point)!;
    var node = located.$1;
    node.entries.removeAt(located.$2);
    final removed = <RNode>[];
    while (!identical(node, root)) {
      final parent = node.parent!;
      for (var i = 0; i < parent.entries.length; i++) {
        final e = parent.entries[i];
        if (!identical(e.child, node)) {
          continue;
        }
        if (node.entries.length < minimum) {
          parent.entries.removeAt(i);
          removed.add(node);
          node.parent = null;
        } else {
          e.box = node.box;
        }
        break;
      }
      node = parent;
    }
    for (final n in removed) {
      for (final e in n.entries) {
        insert(e, n.level);
      }
    }
    while (root.level > 0 && root.entries.length == 1) {
      root = root.entries.first.child!;
      root.parent = null;
    }
  }
}

(RNode, int)? findLeaf(RNode node, SpatialObject point) {
  for (var i = 0; i < node.entries.length; i++) {
    final e = node.entries[i];
    if (node.level == 0) {
      if (e.id == point.id) {
        return (node, i);
      }
    } else if (contains(e.box, point.box)) {
      final found = findLeaf(e.child!, point);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

RNode strRoot(List<Entry> entries, int maximum) {
  var level = 0;
  while (true) {
    final pages = (entries.length + maximum - 1) ~/ maximum;
    var slabs = 1;
    while (slabs * slabs < pages) {
      slabs++;
    }
    int compare(Entry a, Entry b, bool vertical) {
      final first = vertical ? a.box.y1 + a.box.y2 : a.box.x1 + a.box.x2,
          otherFirst = vertical ? b.box.y1 + b.box.y2 : b.box.x1 + b.box.x2;
      final second = vertical ? a.box.x1 + a.box.x2 : a.box.y1 + a.box.y2,
          otherSecond = vertical ? b.box.x1 + b.box.x2 : b.box.y1 + b.box.y2;
      final c = first.compareTo(otherFirst), d = second.compareTo(otherSecond);
      return c != 0
          ? c
          : d != 0
          ? d
          : a.number.compareTo(b.number);
    }

    entries.sort((a, b) => compare(a, b, false));
    final nodes = <RNode>[], slabSize = slabs * maximum;
    for (var start = 0; start < entries.length; start += slabSize) {
      final slab = entries.sublist(start, min(start + slabSize, entries.length))
        ..sort((a, b) => compare(a, b, true));
      for (var offset = 0; offset < slab.length; offset += maximum) {
        nodes.add(
          RNode(
            level,
            slab.sublist(offset, min(offset + maximum, slab.length)),
          ),
        );
      }
    }
    if (nodes.length == 1) {
      return nodes.first;
    }
    entries = [
      for (var i = 0; i < nodes.length; i++)
        Entry(nodes[i].box, child: nodes[i], number: i),
    ];
    level++;
  }
}

RTree buildRTree(
  List<SpatialObject> objects,
  int maximum,
  int minimum,
  bool bulk,
) {
  final tree = RTree(maximum, minimum),
      entries = [for (final o in objects) Entry(o.box, id: o.id, number: o.id)];
  if (bulk) {
    tree.root = strRoot(entries, maximum);
  } else {
    for (final e in entries) {
      tree.insert(e);
    }
  }
  return tree;
}
