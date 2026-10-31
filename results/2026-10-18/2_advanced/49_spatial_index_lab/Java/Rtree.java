import java.util.*;

final class Rtree {
    static long area(Dataset.Box b) {
        return (b.x2() - b.x1()) * (b.y2() - b.y1());
    }
    static Dataset.Box mbr(Dataset.Box a, Dataset.Box b) {
        return new Dataset.Box(Math.min(a.x1(), b.x1()), Math.min(a.y1(), b.y1()), Math.max(a.x2(), b.x2()),
                               Math.max(a.y2(), b.y2()));
    }
    static long enlargement(Dataset.Box a, Dataset.Box b) {
        return area(mbr(a, b)) - area(a);
    }
    static boolean contains(Dataset.Box a, Dataset.Box b) {
        return a.x1() <= b.x1() && b.x2() <= a.x2() && a.y1() <= b.y1() && b.y2() <= a.y2();
    }
    static boolean intersects(Dataset.Box a, Dataset.Box b) {
        return a.x1() <= b.x2() && b.x1() <= a.x2() && a.y1() <= b.y2() && b.y1() <= a.y2();
    }
    static long overlap(Dataset.Box a, Dataset.Box b) {
        long w = Math.min(a.x2(), b.x2()) - Math.max(a.x1(), b.x1()),
             h = Math.min(a.y2(), b.y2()) - Math.max(a.y1(), b.y1());
        return w > 0 && h > 0 ? w * h : 0;
    }
    static final class Entry {
        Dataset.Box box;
        int id;
        Node child;
        Entry(Dataset.Obj object) {
            box = object.box();
            id = object.id();
        }
        Entry(Node child) {
            this.child = child;
            box = child.box();
        }
    }
    static final class Node {
        int level;
        List<Entry> entries;
        Node parent;
        Node(int level, List<Entry> entries, Node parent) {
            this.level = level;
            this.entries = new ArrayList<>(entries);
            this.parent = parent;
            adopt();
        }
        Dataset.Box box() {
            Dataset.Box result = entries.get(0).box;
            for (int i = 1; i < entries.size(); i++)
                result = mbr(result, entries.get(i).box);
            return result;
        }
        void adopt() {
            if (level > 0)
                for (Entry entry : entries)
                    entry.child.parent = this;
        }
    }
    record Location(Node node, int index) {}
    static final class Tree {
        int maximum, minimum;
        Node root = new Node(0, new ArrayList<>(), null);
        Tree(int maximum, int minimum) {
            this.maximum = maximum;
            this.minimum = minimum;
        }
        Node choose(Dataset.Box box, int level) {
            Node node = root;
            while (node.level > level) {
                Entry best = node.entries.get(0);
                for (Entry entry : node.entries) {
                    long a = enlargement(entry.box, box), b = enlargement(best.box, box);
                    if (a < b || a == b && area(entry.box) < area(best.box))
                        best = entry;
                }
                node = best.child;
            }
            return node;
        }
        Node split(Node node) {
            List<Entry> entries = node.entries;
            long greatest = Long.MIN_VALUE;
            int first = 0, second = 1;
            for (int i = 0; i < entries.size() - 1; i++)
                for (int j = i + 1; j < entries.size(); j++) {
                    long waste = area(mbr(entries.get(i).box, entries.get(j).box)) -
                                 area(entries.get(i).box) - area(entries.get(j).box);
                    if (waste > greatest) {
                        greatest = waste;
                        first = i;
                        second = j;
                    }
                }
            List<Entry> group1 = new ArrayList<>(List.of(entries.get(first))),
                        group2 = new ArrayList<>(List.of(entries.get(second))), rest = new ArrayList<>();
            Dataset.Box b1 = entries.get(first).box, b2 = entries.get(second).box;
            for (int i = 0; i < entries.size(); i++)
                if (i != first && i != second)
                    rest.add(entries.get(i));
            while (!rest.isEmpty()) {
                if (group1.size() + rest.size() == minimum) {
                    group1.addAll(rest);
                    break;
                }
                if (group2.size() + rest.size() == minimum) {
                    group2.addAll(rest);
                    break;
                }
                int selected = 0;
                long difference = -1, d1 = 0, d2 = 0;
                for (int i = 0; i < rest.size(); i++) {
                    long a = enlargement(b1, rest.get(i).box), b = enlargement(b2, rest.get(i).box),
                         candidate = Math.abs(a - b);
                    if (candidate > difference) {
                        difference = candidate;
                        selected = i;
                        d1 = a;
                        d2 = b;
                    }
                }
                Entry entry = rest.remove(selected);
                boolean one = d1 < d2 || d1 == d2 && (area(b1) < area(b2) ||
                                                      area(b1) == area(b2) && group1.size() <= group2.size());
                if (one) {
                    group1.add(entry);
                    b1 = mbr(b1, entry.box);
                } else {
                    group2.add(entry);
                    b2 = mbr(b2, entry.box);
                }
            }
            node.entries = group1;
            node.adopt();
            return new Node(node.level, group2, node.parent);
        }
        void insert(Entry entry, int level) {
            Node node = choose(entry.box, level);
            node.entries.add(entry);
            if (level > 0)
                entry.child.parent = node;
            while (true) {
                Node sibling = node.entries.size() > maximum ? split(node) : null, parent = node.parent;
                if (parent == null) {
                    if (sibling != null)
                        root = new Node(node.level + 1, List.of(new Entry(node), new Entry(sibling)), null);
                    return;
                }
                for (Entry parentEntry : parent.entries)
                    if (parentEntry.child == node) {
                        parentEntry.box = node.box();
                        break;
                    }
                if (sibling != null) {
                    parent.entries.add(new Entry(sibling));
                    sibling.parent = parent;
                }
                node = parent;
            }
        }
        Location find(Node node, int id, Dataset.Box box) {
            if (node.level == 0) {
                for (int i = 0; i < node.entries.size(); i++)
                    if (node.entries.get(i).id == id)
                        return new Location(node, i);
            } else
                for (Entry entry : node.entries)
                    if (contains(entry.box, box)) {
                        Location found = find(entry.child, id, box);
                        if (found != null)
                            return found;
                    }
            return null;
        }
        void delete(Dataset.Obj point) {
            Location found = find(root, point.id(), point.box());
            Node node = found.node();
            node.entries.remove(found.index());
            List<Node> removed = new ArrayList<>();
            while (node != root) {
                Node parent = node.parent;
                for (int i = 0; i < parent.entries.size(); i++)
                    if (parent.entries.get(i).child == node) {
                        if (node.entries.size() < minimum) {
                            parent.entries.remove(i);
                            removed.add(node);
                            node.parent = null;
                        } else
                            parent.entries.get(i).box = node.box();
                        break;
                    }
                node = parent;
            }
            for (Node old : removed)
                for (Entry entry : old.entries)
                    insert(entry, old.level);
            while (root.level > 0 && root.entries.size() == 1) {
                root = root.entries.get(0).child;
                root.parent = null;
            }
        }
    }
    record Numbered(int number, Entry entry) {}
    static Node bulk(List<Entry> entries, int maximum) {
        List<Numbered> numbered = new ArrayList<>();
        for (Entry entry : entries)
            numbered.add(new Numbered(entry.id, entry));
        int level = 0;
        while (true) {
            int pages = (numbered.size() + maximum - 1) / maximum, slabs = 1;
            while (slabs * slabs < pages)
                slabs++;
            numbered.sort((a, b) -> compare(a, b, false));
            List<Node> nodes = new ArrayList<>();
            int slabSize = slabs * maximum;
            for (int start = 0; start < numbered.size(); start += slabSize) {
                List<Numbered> slab =
                    new ArrayList<>(numbered.subList(start, Math.min(start + slabSize, numbered.size())));
                slab.sort((a, b) -> compare(a, b, true));
                for (int offset = 0; offset < slab.size(); offset += maximum) {
                    List<Entry> group = new ArrayList<>();
                    for (int i = offset; i < Math.min(offset + maximum, slab.size()); i++)
                        group.add(slab.get(i).entry());
                    nodes.add(new Node(level, group, null));
                }
            }
            if (nodes.size() == 1)
                return nodes.get(0);
            numbered = new ArrayList<>();
            for (int i = 0; i < nodes.size(); i++)
                numbered.add(new Numbered(i, new Entry(nodes.get(i))));
            level++;
        }
    }
    static int compare(Numbered a, Numbered b, boolean swapped) {
        Dataset.Box x = a.entry().box, y = b.entry().box;
        long ax = swapped ? x.y1() + x.y2() : x.x1() + x.x2(),
             bx = swapped ? y.y1() + y.y2() : y.x1() + y.x2(),
             ay = swapped ? x.x1() + x.x2() : x.y1() + x.y2(),
             by = swapped ? y.x1() + y.x2() : y.y1() + y.y2();
        int c = Long.compare(ax, bx);
        if (c == 0)
            c = Long.compare(ay, by);
        return c != 0 ? c : Integer.compare(a.number(), b.number());
    }
    static Tree build(List<Dataset.Obj> objects, int maximum, int minimum, boolean bulk) {
        Tree tree = new Tree(maximum, minimum);
        List<Entry> entries = new ArrayList<>();
        for (Dataset.Obj object : objects)
            entries.add(new Entry(object));
        if (bulk)
            tree.root = bulk(entries, maximum);
        else
            for (Entry entry : entries)
                tree.insert(entry, 0);
        return tree;
    }
}
