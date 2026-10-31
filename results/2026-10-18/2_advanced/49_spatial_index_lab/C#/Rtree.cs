using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Rtree {
    public static long Area(Dataset.Box b) {
        return (b.x2 - b.x1) * (b.y2 - b.y1);
    }
    public static Dataset.Box Mbr(Dataset.Box a, Dataset.Box b) {
        return new Dataset.Box(Math.Min(a.x1, b.x1), Math.Min(a.y1, b.y1), Math.Max(a.x2, b.x2),
                               Math.Max(a.y2, b.y2));
    }
    public static long Enlargement(Dataset.Box a, Dataset.Box b) {
        return Area(Mbr(a, b)) - Area(a);
    }
    public static bool Contains(Dataset.Box a, Dataset.Box b) {
        return a.x1 <= b.x1 && b.x2 <= a.x2 && a.y1 <= b.y1 && b.y2 <= a.y2;
    }
    public static bool Intersects(Dataset.Box a, Dataset.Box b) {
        return a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2;
    }
    public static long Overlap(Dataset.Box a, Dataset.Box b) {
        long w = Math.Min(a.x2, b.x2) - Math.Max(a.x1, b.x1), h = Math.Min(a.y2, b.y2) - Math.Max(a.y1, b.y1);
        return w > 0 && h > 0 ? w * h : 0;
    }
    public sealed class Entry {
        public Dataset.Box box;
        public int id;
        public Node child;
        public Entry(Dataset.Obj obj) {
            box = obj.box;
            id = obj.id;
        }
        public Entry(Node child) {
            this.child = child;
            box = child.Box();
        }
    }
    public sealed class Node {
        public int level;
        public List<Entry> entries;
        public Node parent;
        public Node(int level, List<Entry> entries, Node parent) {
            this.level = level;
            this.entries = new(entries);
            this.parent = parent;
            Adopt();
        }
        public Dataset.Box Box() {
            Dataset.Box result = entries[0].box;
            for (int i = 1; i < entries.Count; i++)
                result = Mbr(result, entries[i].box);
            return result;
        }
        public void Adopt() {
            if (level > 0)
                foreach (Entry entry in entries)
                    entry.child.parent = this;
        }
    }
    public record Location(Node node, int index) {
    }
    public sealed class Tree {
        public int maximum, minimum;
        public Node root = new Node(0, new(), null);
        public Tree(int maximum, int minimum) {
            this.maximum = maximum;
            this.minimum = minimum;
        }
        public Node Choose(Dataset.Box box, int level) {
            Node node = root;
            while (node.level > level) {
                Entry best = node.entries[0];
                foreach (Entry entry in node.entries) {
                    long a = Enlargement(entry.box, box), b = Enlargement(best.box, box);
                    if (a < b || a == b && Area(entry.box) < Area(best.box))
                        best = entry;
                }
                node = best.child;
            }
            return node;
        }
        public Node Split(Node node) {
            List<Entry> entries = node.entries;
            long greatest = long.MinValue;
            int first = 0, second = 1;
            for (int i = 0; i < entries.Count - 1; i++)
                for (int j = i + 1; j < entries.Count; j++) {
                    long waste = Area(Mbr(entries[i].box, entries[j].box)) - Area(entries[i].box) -
                                 Area(entries[j].box);
                    if (waste > greatest) {
                        greatest = waste;
                        first = i;
                        second = j;
                    }
                }
            List<Entry> group1 = new([entries[first]]), group2 = new([entries[second]]), rest = new();
            Dataset.Box b1 = entries[first].box, b2 = entries[second].box;
            for (int i = 0; i < entries.Count; i++)
                if (i != first && i != second)
                    rest.Add(entries[i]);
            while (rest.Count != 0) {
                if (group1.Count + rest.Count == minimum) {
                    group1.AddRange(rest);
                    break;
                }
                if (group2.Count + rest.Count == minimum) {
                    group2.AddRange(rest);
                    break;
                }
                int selected = 0;
                long difference = -1, d1 = 0, d2 = 0;
                for (int i = 0; i < rest.Count; i++) {
                    long a = Enlargement(b1, rest[i].box), b = Enlargement(b2, rest[i].box),
                         candidate = Math.Abs(a - b);
                    if (candidate > difference) {
                        difference = candidate;
                        selected = i;
                        d1 = a;
                        d2 = b;
                    }
                }
                Entry entry = rest[selected];
                rest.RemoveAt(selected);
                bool one = d1 < d2 || d1 == d2 && (Area(b1) < Area(b2) ||
                                                   Area(b1) == Area(b2) && group1.Count <= group2.Count);
                if (one) {
                    group1.Add(entry);
                    b1 = Mbr(b1, entry.box);
                } else {
                    group2.Add(entry);
                    b2 = Mbr(b2, entry.box);
                }
            }
            node.entries = group1;
            node.Adopt();
            return new Node(node.level, group2, node.parent);
        }
        public void Insert(Entry entry, int level) {
            Node node = Choose(entry.box, level);
            node.entries.Add(entry);
            if (level > 0)
                entry.child.parent = node;
            while (true) {
                Node sibling = node.entries.Count > maximum ? Split(node) : null, parent = node.parent;
                if (parent == null) {
                    if (sibling != null)
                        root = new Node(node.level + 1, [new Entry(node), new Entry(sibling)], null);
                    return;
                }
                foreach (Entry parentEntry in parent.entries)
                    if (parentEntry.child == node) {
                        parentEntry.box = node.Box();
                        break;
                    }
                if (sibling != null) {
                    parent.entries.Add(new Entry(sibling));
                    sibling.parent = parent;
                }
                node = parent;
            }
        }
        public Location Find(Node node, int id, Dataset.Box box) {
            if (node.level == 0) {
                for (int i = 0; i < node.entries.Count; i++)
                    if (node.entries[i].id == id)
                        return new Location(node, i);
            } else
                foreach (Entry entry in node.entries)
                    if (Contains(entry.box, box)) {
                        Location found = Find(entry.child, id, box);
                        if (found != null)
                            return found;
                    }
            return null;
        }
        public void Delete(Dataset.Obj point) {
            Location found = Find(root, point.id, point.box);
            Node node = found.node;
            node.entries.RemoveAt(found.index);
            List<Node> removed = new();
            while (node != root) {
                Node parent = node.parent;
                for (int i = 0; i < parent.entries.Count; i++)
                    if (parent.entries[i].child == node) {
                        if (node.entries.Count < minimum) {
                            parent.entries.RemoveAt(i);
                            removed.Add(node);
                            node.parent = null;
                        } else
                            parent.entries[i].box = node.Box();
                        break;
                    }
                node = parent;
            }
            foreach (Node old in removed)
                foreach (Entry entry in old.entries)
                    Insert(entry, old.level);
            while (root.level > 0 && root.entries.Count == 1) {
                root = root.entries[0].child;
                root.parent = null;
            }
        }
    }
    public record Numbered(int number, Entry entry) {
    }
    public static Node Bulk(List<Entry> entries, int maximum) {
        List<Numbered> numbered = new();
        foreach (Entry entry in entries)
            numbered.Add(new Numbered(entry.id, entry));
        int level = 0;
        while (true) {
            int pages = (numbered.Count + maximum - 1) / maximum, slabs = 1;
            while (slabs * slabs < pages)
                slabs++;
            numbered.Sort((a, b) => Compare(a, b, false));
            List<Node> nodes = new();
            int slabSize = slabs * maximum;
            for (int start = 0; start < numbered.Count; start += slabSize) {
                List<Numbered> slab =
                    new(numbered.GetRange(start, Math.Min(start + slabSize, numbered.Count) - (start)));
                slab.Sort((a, b) => Compare(a, b, true));
                for (int offset = 0; offset < slab.Count; offset += maximum) {
                    List<Entry> group = new();
                    for (int i = offset; i < Math.Min(offset + maximum, slab.Count); i++)
                        group.Add(slab[i].entry);
                    nodes.Add(new Node(level, group, null));
                }
            }
            if (nodes.Count == 1)
                return nodes[0];
            numbered = new();
            for (int i = 0; i < nodes.Count; i++)
                numbered.Add(new Numbered(i, new Entry(nodes[i])));
            level++;
        }
    }
    public static int Compare(Numbered a, Numbered b, bool swapped) {
        Dataset.Box x = a.entry.box, y = b.entry.box;
        long ax = swapped ? x.y1 + x.y2 : x.x1 + x.x2, bx = swapped ? y.y1 + y.y2 : y.x1 + y.x2,
             ay = swapped ? x.x1 + x.x2 : x.y1 + x.y2, by = swapped ? y.x1 + y.x2 : y.y1 + y.y2;
        int c = ax.CompareTo(bx);
        if (c == 0)
            c = ay.CompareTo(by);
        return c != 0 ? c : a.number.CompareTo(b.number);
    }
    public static Tree Build(List<Dataset.Obj> objects, int maximum, int minimum, bool bulk) {
        Tree tree = new Tree(maximum, minimum);
        List<Entry> entries = new();
        foreach (Dataset.Obj obj in objects)
            entries.Add(new Entry(obj));
        if (bulk)
            tree.root = Bulk(entries, maximum);
        else
            foreach (Entry entry in entries)
                tree.Insert(entry, 0);
        return tree;
    }
}
