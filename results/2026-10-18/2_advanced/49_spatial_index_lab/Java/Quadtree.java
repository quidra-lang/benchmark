import java.util.*;

final class Quadtree {
    static final List<String> MARKS = List.of("NW", "NE", "SW", "SE");
    static final class Node {
        int x, y, size;
        List<Dataset.Obj> points = new ArrayList<>();
        Node[] children;
        Node(int x, int y, int size) {
            this.x = x;
            this.y = y;
            this.size = size;
        }
    }
    static int destination(Node node, Dataset.Obj point) {
        int half = node.size / 2;
        return (point.box().y1() >= node.y + half ? 2 : 0) + (point.box().x1() >= node.x + half ? 1 : 0);
    }
    static void insert(Node node, Dataset.Obj point, int bucket) {
        if (node.children != null) {
            insert(node.children[destination(node, point)], point, bucket);
            return;
        }
        node.points.add(point);
        node.points.sort(Comparator.comparingInt(Dataset.Obj::id));
        if (node.points.size() > bucket) {
            int half = node.size / 2;
            node.children = new Node[] {new Node(node.x, node.y, half), new Node(node.x + half, node.y, half),
                                        new Node(node.x, node.y + half, half),
                                        new Node(node.x + half, node.y + half, half)};
            List<Dataset.Obj> held = node.points;
            node.points = new ArrayList<>();
            for (Dataset.Obj p : held)
                insert(node, p, bucket);
        }
    }
    static void delete(Node node, Dataset.Obj point, int bucket) {
        if (node.children == null) {
            node.points.removeIf(p -> p.id() == point.id());
            return;
        }
        delete(node.children[destination(node, point)], point, bucket);
        int total = 0;
        for (Node child : node.children) {
            if (child.children != null)
                return;
            total += child.points.size();
        }
        if (total <= bucket) {
            for (Node child : node.children)
                node.points.addAll(child.points);
            node.points.sort(Comparator.comparingInt(Dataset.Obj::id));
            node.children = null;
        }
    }
}
