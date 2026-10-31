import java.util.*;
final class GreinerHormann {
    static final class Node {
        Rational.Point point;
        int side;
        Crossing crossing;
        boolean entering;
        Node next, previous, other;
        Node(Rational.Point point, int side, Crossing crossing) {
            this.point = point;
            this.side = side;
            this.crossing = crossing;
        }
    }
    static final class Crossing {
        Rational.Point point;
        Node first, second;
        Crossing(Rational.Point point) {
            this.point = point;
            first = new Node(point, 0, this);
            second = new Node(point, 1, this);
            first.other = second;
            second.other = first;
        }
    }
    record Slot(Rational.Fraction position, Node node) {}
    static final class Graph {
        List<List<List<Rational.Point>>> rings;
        List<List<List<Node>>> nodes = new ArrayList<>();
        List<List<Boolean>> initialInside = new ArrayList<>();
        List<Crossing> crossings = new ArrayList<>();
        int nA, nB;
        Graph(List<List<Rational.Point>> first, List<List<Rational.Point>> second) {
            rings = List.of(first, second);
            List<List<List<List<Slot>>>> slots = new ArrayList<>();
            for (List<List<Rational.Point>> sequence : rings) {
                List<List<List<Slot>>> side = new ArrayList<>();
                for (List<Rational.Point> ring : sequence) {
                    List<List<Slot>> edges = new ArrayList<>();
                    for (Rational.Point point : ring)
                        edges.add(new ArrayList<>());
                    side.add(edges);
                }
                slots.add(side);
            }
            for (int i = 0; i < first.size(); i++)
                for (int e = 0; e < first.get(i).size(); e++)
                    for (int j = 0; j < second.size(); j++)
                        for (int f = 0; f < second.get(j).size(); f++) {
                            List<Rational.Point> a = first.get(i), b = second.get(j);
                            Intersections.Crossing found =
                                Intersections.crossing(a.get(e), a.get((e + 1) % a.size()),
                                                       b.get(f), b.get((f + 1) % b.size()));
                            if (found != null) {
                                Crossing record = new Crossing(found.point());
                                slots.get(0).get(i).get(e).add(
                                    new Slot(found.first(), record.first));
                                slots.get(1).get(j).get(f).add(
                                    new Slot(found.second(), record.second));
                            }
                        }
            for (int side = 0; side < 2; side++) {
                List<List<Node>> sideNodes = new ArrayList<>();
                List<Boolean> inside = new ArrayList<>();
                for (int ringIndex = 0; ringIndex < rings.get(side).size(); ringIndex++) {
                    List<Rational.Point> ring = rings.get(side).get(ringIndex);
                    List<Node> list = new ArrayList<>();
                    for (int edge = 0; edge < ring.size(); edge++) {
                        list.add(new Node(ring.get(edge), side, null));
                        List<Slot> inserted = slots.get(side).get(ringIndex).get(edge);
                        inserted.sort(Comparator.comparing(Slot::position));
                        for (Slot slot : inserted)
                            list.add(slot.node());
                    }
                    for (int index = 0; index < list.size(); index++) {
                        Node node = list.get(index);
                        node.previous = list.get((index + list.size() - 1) % list.size());
                        node.next = list.get((index + 1) % list.size());
                    }
                    boolean state = Rings.interior(rings.get(1 - side), ring.getFirst());
                    inside.add(state);
                    for (Node node : list)
                        if (node.crossing != null) {
                            node.entering = !state;
                            state = !state;
                        }
                    sideNodes.add(list);
                }
                nodes.add(sideNodes);
                initialInside.add(inside);
            }
            for (List<Node> ring : nodes.get(0))
                for (Node node : ring)
                    if (node.crossing != null)
                        crossings.add(node.crossing);
            for (boolean inside : initialInside.get(0))
                if (inside)
                    nA++;
            for (boolean inside : initialInside.get(1))
                if (inside)
                    nB++;
        }
        List<List<Rational.Point>> traverse(boolean invertFirst, boolean invertSecond) {
            boolean[] inverted = {invertFirst, invertSecond};
            Set<Crossing> visited = new HashSet<>();
            List<List<Rational.Point>> result = new ArrayList<>();
            for (Crossing start : crossings) {
                if (visited.contains(start))
                    continue;
                List<Rational.Point> points = new ArrayList<>();
                Node current = start.first;
                while (true) {
                    visited.add(current.crossing);
                    points.add(current.point);
                    boolean forward = current.entering != inverted[current.side];
                    Node stopped = forward ? current.next : current.previous;
                    while (stopped.crossing == null) {
                        points.add(stopped.point);
                        stopped = forward ? stopped.next : stopped.previous;
                    }
                    if (stopped.crossing == start)
                        break;
                    current = stopped.other;
                }
                result.add(points);
            }
            for (int side = 0; side < 2; side++)
                for (int index = 0; index < rings.get(side).size(); index++) {
                    boolean hasCrossing = false;
                    for (Node node : nodes.get(side).get(index))
                        if (node.crossing != null)
                            hasCrossing = true;
                    if (!hasCrossing && initialInside.get(side).get(index) != inverted[side])
                        result.add(new ArrayList<>(rings.get(side).get(index)));
                }
            return result;
        }
    }
}
