import java.util.*;

final class Topology {
    record Edge(int a, int b) implements Comparable<Edge> {
        @Override
        public int compareTo(Edge other) {
            int c = Integer.compare(a, other.a);
            return c != 0 ? c : Integer.compare(b, other.b);
        }
        @Override
        public String toString() {
            return a + " " + b;
        }
    }
    static Edge edge(int a, int b) {
        return new Edge(Math.min(a, b), Math.max(a, b));
    }
    static final class Component {
        int number;
        List<Integer> faces = new ArrayList<>();
        SortedSet<Integer> vertices = new TreeSet<>();
        List<Edge> edges = new ArrayList<>(), boundary = new ArrayList<>(), nonmanifold = new ArrayList<>();
        List<Integer> nonmanifoldVertices = new ArrayList<>();
    }
    static final class Mesh {
        SortedMap<Edge, List<Integer>> edges = new TreeMap<>();
        List<Component> components = new ArrayList<>();
        int[] faceComponent;
        SortedMap<Integer, List<List<Integer>>> fans = new TreeMap<>();
        List<Integer> nonmanifoldVertices = new ArrayList<>();
        SortedMap<Integer, SortedSet<Integer>> neighbors = new TreeMap<>();
    }
    static List<List<Integer>> parts(SortedSet<Integer> remaining,
                                     Map<Integer, SortedSet<Integer>> neighbors) {
        List<List<Integer>> result = new ArrayList<>();
        while (!remaining.isEmpty()) {
            int seed = remaining.first();
            remaining.remove(seed);
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(seed);
            List<Integer> part = new ArrayList<>();
            while (!queue.isEmpty()) {
                int f = queue.remove();
                part.add(f);
                for (int n : neighbors.getOrDefault(f, new TreeSet<>()))
                    if (remaining.remove(n))
                        queue.add(n);
            }
            Collections.sort(part);
            result.add(part);
        }
        return result;
    }
    static Mesh analyze(List<ObjIo.Face> faces) {
        Mesh mesh = new Mesh();
        Map<Integer, SortedSet<Integer>> adjacency = new HashMap<>();
        SortedSet<Integer> remaining = new TreeSet<>();
        for (int i = 1; i <= faces.size(); i++) {
            remaining.add(i);
            adjacency.put(i, new TreeSet<>());
            int[] v = faces.get(i - 1).v;
            for (int k = 0; k < 3; k++)
                mesh.edges.computeIfAbsent(edge(v[k], v[(k + 1) % 3]), key -> new ArrayList<>()).add(i);
        }
        for (var entry : mesh.edges.entrySet()) {
            Edge e = entry.getKey();
            mesh.neighbors.computeIfAbsent(e.a, key -> new TreeSet<>()).add(e.b);
            mesh.neighbors.computeIfAbsent(e.b, key -> new TreeSet<>()).add(e.a);
            for (int f : entry.getValue())
                adjacency.get(f).addAll(entry.getValue());
        }
        mesh.faceComponent = new int[faces.size() + 1];
        for (List<Integer> ids : parts(remaining, adjacency)) {
            Component c = new Component();
            c.number = mesh.components.size() + 1;
            c.faces = ids;
            for (int i : ids) {
                mesh.faceComponent[i] = c.number;
                for (int v : faces.get(i - 1).v)
                    c.vertices.add(v);
            }
            for (var entry : mesh.edges.entrySet())
                if (ids.contains(entry.getValue().get(0))) {
                    c.edges.add(entry.getKey());
                    if (entry.getValue().size() == 1)
                        c.boundary.add(entry.getKey());
                    if (entry.getValue().size() >= 3)
                        c.nonmanifold.add(entry.getKey());
                }
            mesh.components.add(c);
        }
        for (int v : mesh.neighbors.keySet()) {
            Map<Integer, SortedSet<Integer>> links = new HashMap<>();
            SortedSet<Integer> incident = new TreeSet<>();
            for (int i = 1; i <= faces.size(); i++)
                for (int u : faces.get(i - 1).v)
                    if (u == v) {
                        incident.add(i);
                        links.put(i, new TreeSet<>());
                        break;
                    }
            for (var entry : mesh.edges.entrySet())
                if (entry.getKey().a == v || entry.getKey().b == v)
                    for (int f : entry.getValue())
                        links.get(f).addAll(entry.getValue());
            List<List<Integer>> fans = parts(incident, links);
            mesh.fans.put(v, fans);
            if (fans.size() >= 2)
                mesh.nonmanifoldVertices.add(v);
        }
        for (Component c : mesh.components)
            for (int v : c.vertices) {
                int count = 0;
                for (List<Integer> fan : mesh.fans.get(v))
                    if (mesh.faceComponent[fan.get(0)] == c.number)
                        count++;
                if (count >= 2)
                    c.nonmanifoldVertices.add(v);
            }
        return mesh;
    }
    static final class Loop {
        int number, component, length;
        String kind;
        boolean filled;
        List<Integer> vertices;
    }
    static List<Loop> loops(List<ObjIo.Face> faces, Mesh mesh) {
        List<Loop> result = new ArrayList<>();
        for (Component c : mesh.components) {
            SortedSet<Edge> unused = new TreeSet<>(c.boundary);
            while (!unused.isEmpty()) {
                Edge first = unused.first();
                unused.remove(first);
                List<Integer> sequence = new ArrayList<>(List.of(first.a, first.b));
                int current = first.b;
                while (current != first.a) {
                    Edge chosen = null;
                    int other = Integer.MAX_VALUE;
                    for (Edge e : unused) {
                        int n = e.a == current ? e.b : e.b == current ? e.a : Integer.MAX_VALUE;
                        if (n < other) {
                            other = n;
                            chosen = e;
                        }
                    }
                    if (chosen == null)
                        break;
                    unused.remove(chosen);
                    sequence.add(other);
                    current = other;
                }
                Loop loop = new Loop();
                loop.number = result.size() + 1;
                loop.component = c.number;
                loop.vertices = sequence;
                if (current != first.a) {
                    loop.kind = "open";
                    loop.length = sequence.size() - 1;
                } else {
                    sequence.removeLast();
                    loop.length = sequence.size();
                    int forward = 0;
                    for (int i = 0; i < loop.length; i++) {
                        int a = sequence.get(i), b = sequence.get((i + 1) % loop.length);
                        int f = mesh.edges.get(edge(a, b)).get(0);
                        if (Orientation.directed(faces.get(f - 1), a, b))
                            forward++;
                    }
                    loop.kind = forward == 0 || forward == loop.length ? "coherent" : "mixed";
                    if (forward == 0)
                        Collections.reverse(sequence.subList(1, sequence.size()));
                }
                result.add(loop);
            }
        }
        return result;
    }
}
