using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Quadtree {
    public static readonly List<string> MARKS = ["NW", "NE", "SW", "SE"];
    public sealed class Node {
        public int x, y, size;
        public List<Dataset.Obj> points = new();
        public Node[] children;
        public Node(int x, int y, int size) {
            this.x = x;
            this.y = y;
            this.size = size;
        }
    }
    public static int Destination(Node node, Dataset.Obj point) {
        int half = node.size / 2;
        return (point.box.y1 >= node.y + half ? 2 : 0) + (point.box.x1 >= node.x + half ? 1 : 0);
    }
    public static void Insert(Node node, Dataset.Obj point, int bucket) {
        if (node.children != null) {
            Insert(node.children[Destination(node, point)], point, bucket);
            return;
        }
        node.points.Add(point);
        node.points.Sort(Comparer<Dataset.Obj>.Create((a, b) => a.id.CompareTo(b.id)));
        if (node.points.Count > bucket) {
            int half = node.size / 2;
            node.children =
                new Node[] { new Node(node.x, node.y, half), new Node(node.x + half, node.y, half),
                             new Node(node.x, node.y + half, half),
                             new Node(node.x + half, node.y + half, half) };
            List<Dataset.Obj> held = node.points;
            node.points = new();
            foreach (Dataset.Obj p in held)
                Insert(node, p, bucket);
        }
    }
    public static void Delete(Node node, Dataset.Obj point, int bucket) {
        if (node.children == null) {
            node.points.RemoveAll(p => p.id == point.id);
            return;
        }
        Delete(node.children[Destination(node, point)], point, bucket);
        int total = 0;
        foreach (Node child in node.children) {
            if (child.children != null)
                return;
            total += child.points.Count;
        }
        if (total <= bucket) {
            foreach (Node child in node.children)
                node.points.AddRange(child.points);
            node.points.Sort(Comparer<Dataset.Obj>.Create((a, b) => a.id.CompareTo(b.id)));
            node.children = null;
        }
    }
}
