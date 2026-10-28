using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Kdtree {
    public sealed class Node {
        public Dataset.Obj point;
        public int axis;
        public Node left, right;
        public Node(Dataset.Obj point, int depth) {
            this.point = point;
            axis = depth % 2;
        }
    }
    public static int Compare(Dataset.Obj a, Dataset.Obj b, int axis) {
        long first = axis == 0 ? a.box.x1 : a.box.y1, second = axis == 0 ? b.box.x1 : b.box.y1;
        int result = first.CompareTo(second);
        if (result == 0)
            result = axis == 0 ? a.box.y1 : a.box.x1.CompareTo(axis == 0 ? b.box.y1 : b.box.x1);
        return result != 0 ? result : a.id.CompareTo(b.id);
    }
    public static Node Build(List<Dataset.Obj> points, int depth) {
        if (points.Count == 0)
            return null;
        List<Dataset.Obj> sorted = new(points);
        sorted.Sort((a, b) => Compare(a, b, depth % 2));
        int middle = sorted.Count / 2;
        Node node = new Node(sorted[middle], depth);
        node.left = Build(sorted.GetRange(0, middle - (0)), depth + 1);
        node.right = Build(sorted.GetRange(middle + 1, sorted.Count - (middle + 1)), depth + 1);
        return node;
    }
    public static Node Insert(Node node, Dataset.Obj point, int depth) {
        if (node == null)
            return new Node(point, depth);
        if (Compare(point, node.point, node.axis) < 0)
            node.left = Insert(node.left, point, depth + 1);
        else
            node.right = Insert(node.right, point, depth + 1);
        return node;
    }
    public static Dataset.Obj Minimum(Node node, int axis) {
        if (node.axis == axis)
            return node.left == null ? node.point : Minimum(node.left, axis);
        Dataset.Obj best = node.point;
        if (node.left != null) {
            Dataset.Obj candidate = Minimum(node.left, axis);
            if (Compare(candidate, best, axis) < 0)
                best = candidate;
        }
        if (node.right != null) {
            Dataset.Obj candidate = Minimum(node.right, axis);
            if (Compare(candidate, best, axis) < 0)
                best = candidate;
        }
        return best;
    }
    public static Node Delete(Node node, Dataset.Obj point) {
        if (node.point.id == point.id) {
            if (node.right != null) {
                Dataset.Obj replacement = Minimum(node.right, node.axis);
                node.point = replacement;
                node.right = Delete(node.right, replacement);
                return node;
            }
            if (node.left != null) {
                Dataset.Obj replacement = Minimum(node.left, node.axis);
                node.point = replacement;
                node.right = Delete(node.left, replacement);
                node.left = null;
                return node;
            }
            return null;
        }
        if (Compare(point, node.point, node.axis) < 0)
            node.left = Delete(node.left, point);
        else
            node.right = Delete(node.right, point);
        return node;
    }
}
