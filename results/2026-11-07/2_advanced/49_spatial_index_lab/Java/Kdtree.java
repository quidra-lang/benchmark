import java.util.*;

final class Kdtree {
    static final class Node {
        Dataset.Obj point;
        int axis;
        Node left, right;
        Node(Dataset.Obj point, int depth) {
            this.point = point;
            axis = depth % 2;
        }
    }
    static int compare(Dataset.Obj a, Dataset.Obj b, int axis) {
        long first = axis == 0 ? a.box().x1() : a.box().y1(), second =
                                                                  axis == 0 ? b.box().x1() : b.box().y1();
        int result = Long.compare(first, second);
        if (result == 0)
            result = Long.compare(axis == 0 ? a.box().y1() : a.box().x1(),
                                  axis == 0 ? b.box().y1() : b.box().x1());
        return result != 0 ? result : Integer.compare(a.id(), b.id());
    }
    static Node build(List<Dataset.Obj> points, int depth) {
        if (points.isEmpty())
            return null;
        List<Dataset.Obj> sorted = new ArrayList<>(points);
        sorted.sort((a, b) -> compare(a, b, depth % 2));
        int middle = sorted.size() / 2;
        Node node = new Node(sorted.get(middle), depth);
        node.left = build(sorted.subList(0, middle), depth + 1);
        node.right = build(sorted.subList(middle + 1, sorted.size()), depth + 1);
        return node;
    }
    static Node insert(Node node, Dataset.Obj point, int depth) {
        if (node == null)
            return new Node(point, depth);
        if (compare(point, node.point, node.axis) < 0)
            node.left = insert(node.left, point, depth + 1);
        else
            node.right = insert(node.right, point, depth + 1);
        return node;
    }
    static Dataset.Obj minimum(Node node, int axis) {
        if (node.axis == axis)
            return node.left == null ? node.point : minimum(node.left, axis);
        Dataset.Obj best = node.point;
        if (node.left != null) {
            Dataset.Obj candidate = minimum(node.left, axis);
            if (compare(candidate, best, axis) < 0)
                best = candidate;
        }
        if (node.right != null) {
            Dataset.Obj candidate = minimum(node.right, axis);
            if (compare(candidate, best, axis) < 0)
                best = candidate;
        }
        return best;
    }
    static Node delete(Node node, Dataset.Obj point) {
        if (node.point.id() == point.id()) {
            if (node.right != null) {
                Dataset.Obj replacement = minimum(node.right, node.axis);
                node.point = replacement;
                node.right = delete(node.right, replacement);
                return node;
            }
            if (node.left != null) {
                Dataset.Obj replacement = minimum(node.left, node.axis);
                node.point = replacement;
                node.right = delete(node.left, replacement);
                node.left = null;
                return node;
            }
            return null;
        }
        if (compare(point, node.point, node.axis) < 0)
            node.left = delete(node.left, point);
        else
            node.right = delete(node.right, point);
        return node;
    }
}
