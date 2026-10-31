part of 'main.dart';

class Crossing {
  final Point point;
  late GHNode first, second;
  Crossing(this.point) {
    first = GHNode(point, 0, this);
    second = GHNode(point, 1, this);
    first.other = second;
    second.other = first;
  }
}

class GHNode {
  final Point point;
  final int side;
  final Crossing? crossing;
  bool entering = false;
  GHNode? next, previous, other;
  GHNode(this.point, this.side, [this.crossing]);
}

class Inserted {
  final Rational position;
  final GHNode node;
  Inserted(this.position, this.node);
}

class GHGraph {
  final List<List<Ring>> rings;
  final List<List<List<GHNode>>> nodes = [[], []];
  final List<List<bool>> initialInside = [[], []];
  final List<Crossing> crossings = [];
  int nA = 0, nB = 0;
  GHGraph(List<Ring> first, List<Ring> second) : rings = [first, second] {
    final slots = List.generate(
      2,
      (side) => List.generate(
        rings[side].length,
        (i) => List.generate(rings[side][i].length, (_) => <Inserted>[]),
      ),
    );
    for (var i = 0; i < first.length; i++) {
      final ring = first[i];
      for (var e = 0; e < ring.length; e++) {
        final a = ring[e], b = ring[(e + 1) % ring.length];
        for (var j = 0; j < second.length; j++) {
          final other = second[j];
          for (var f = 0; f < other.length; f++) {
            final found = crossing(
              a,
              b,
              other[f],
              other[(f + 1) % other.length],
            );
            if (found == null) continue;
            final (t, u, p) = found;
            final record = Crossing(p);
            slots[0][i][e].add(Inserted(t, record.first));
            slots[1][j][f].add(Inserted(u, record.second));
          }
        }
      }
    }
    for (var side = 0; side < 2; side++) {
      final sequence = rings[side];
      for (var i = 0; i < sequence.length; i++) {
        final ring = sequence[i], list = <GHNode>[];
        for (var e = 0; e < ring.length; e++) {
          list.add(GHNode(ring[e], side));
          final inserted = slots[side][i][e]
            ..sort((a, b) => a.position.compare(b.position));
          list.addAll(inserted.map((x) => x.node));
        }
        for (var k = 0; k < list.length; k++) {
          list[k].previous = list[(k + list.length - 1) % list.length];
          list[k].next = list[(k + 1) % list.length];
        }
        var state = interior(ring.first, rings[1 - side]);
        initialInside[side].add(state);
        for (final node in list) {
          final record = node.crossing;
          if (record != null) {
            node.entering = !state;
            state = !state;
            if (side == 0) crossings.add(record);
          }
        }
        nodes[side].add(list);
      }
    }
    nA = initialInside[0].where((v) => v).length;
    nB = initialInside[1].where((v) => v).length;
  }
  List<Ring> traverse(bool invertFirst, bool invertSecond) {
    final inverted = [invertFirst, invertSecond],
        visited = <Crossing>{},
        out = <Ring>[];
    for (final start in crossings) {
      if (visited.contains(start)) continue;
      final points = <Point>[];
      var current = start.first;
      while (true) {
        visited.add(current.crossing!);
        points.add(current.point);
        final forward = current.entering != inverted[current.side];
        var stopped = forward ? current.next! : current.previous!;
        while (stopped.crossing == null) {
          points.add(stopped.point);
          stopped = forward ? stopped.next! : stopped.previous!;
        }
        if (stopped.crossing == start) break;
        current = stopped.other!;
      }
      out.add(points);
    }
    for (var side = 0; side < 2; side++) {
      for (var i = 0; i < rings[side].length; i++) {
        final hasCrossing = nodes[side][i].any((node) => node.crossing != null);
        if (!hasCrossing && initialInside[side][i] != inverted[side])
          out.add(rings[side][i]);
      }
    }
    return out;
  }
}
