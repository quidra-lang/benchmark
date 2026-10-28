using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Topology {
    public static TValue GetOrAdd<TKey, TValue>(this IDictionary<TKey, TValue> map, TKey key,
                                                Func<TKey, TValue> factory) {
        if (!map.TryGetValue(key, out TValue value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }
    public sealed record Edge(int a, int b) : IComparable<Edge> {

        public int CompareTo(Edge other) {
            int c = a.CompareTo(other.a);
            return c != 0 ? c : b.CompareTo(other.b);
        }

        public override string ToString() {
            return a + " " + b;
        }
    }
    public static Edge KeyEdge(int a, int b) {
        return new Edge(Math.Min(a, b), Math.Max(a, b));
    }
    public sealed class Component {
        public int number;
        public List<int> faces = new();
        public SortedSet<int> vertices = new SortedSet<int>();
        public List<Edge> edges = new(), boundary = new(), nonmanifold = new();
        public List<int> nonmanifoldVertices = new();
    }
    public sealed class Mesh {
        public SortedDictionary<Edge, List<int>> edges = new();
        public List<Component> components = new();
        public int[] faceComponent;
        public SortedDictionary<int, List<List<int>>> fans = new();
        public List<int> nonmanifoldVertices = new();
        public SortedDictionary<int, SortedSet<int>> neighbors = new();
    }
    public static List<List<int>> Parts(SortedSet<int> remaining, Dictionary<int, SortedSet<int>> neighbors) {
        List<List<int>> result = new();
        while (remaining.Count != 0) {
            int seed = remaining.Min;
            remaining.Remove(seed);
            Queue<int> queue = new();
            queue.Enqueue(seed);
            List<int> part = new();
            while (queue.Count != 0) {
                int f = queue.Dequeue();
                part.Add(f);
                foreach (int n in neighbors.GetValueOrDefault(f, new SortedSet<int>()))
                    if (remaining.Remove(n))
                        queue.Enqueue(n);
            }
            part.Sort();
            result.Add(part);
        }
        return result;
    }
    public static Mesh Analyze(List<ObjIo.Face> faces) {
        Mesh mesh = new Mesh();
        Dictionary<int, SortedSet<int>> adjacency = new();
        SortedSet<int> remaining = new SortedSet<int>();
        for (int i = 1; i <= faces.Count; i++) {
            remaining.Add(i);
            adjacency[i] = new SortedSet<int>();
            int[] v = faces[i - 1].v;
            for (int k = 0; k < 3; k++)
                mesh.edges.GetOrAdd(KeyEdge(v[k], v[(k + 1) % 3]), key => new()).Add(i);
        }
        foreach (var entry in mesh.edges) {
            Edge e = entry.Key;
            mesh.neighbors.GetOrAdd(e.a, key => new SortedSet<int>()).Add(e.b);
            mesh.neighbors.GetOrAdd(e.b, key => new SortedSet<int>()).Add(e.a);
            foreach (int f in entry.Value)
                adjacency[f].UnionWith(entry.Value);
        }
        mesh.faceComponent = new int[faces.Count + 1];
        foreach (List<int> ids in Parts(remaining, adjacency)) {
            Component c = new Component();
            c.number = mesh.components.Count + 1;
            c.faces = ids;
            foreach (int i in ids) {
                mesh.faceComponent[i] = c.number;
                foreach (int v in faces[i - 1].v)
                    c.vertices.Add(v);
            }
            foreach (var entry in mesh.edges)
                if (ids.Contains(entry.Value[0])) {
                    c.edges.Add(entry.Key);
                    if (entry.Value.Count == 1)
                        c.boundary.Add(entry.Key);
                    if (entry.Value.Count >= 3)
                        c.nonmanifold.Add(entry.Key);
                }
            mesh.components.Add(c);
        }
        foreach (int v in mesh.neighbors.Keys) {
            Dictionary<int, SortedSet<int>> links = new();
            SortedSet<int> incident = new SortedSet<int>();
            for (int i = 1; i <= faces.Count; i++)
                foreach (int u in faces[i - 1].v)
                    if (u == v) {
                        incident.Add(i);
                        links[i] = new SortedSet<int>();
                        break;
                    }
            foreach (var entry in mesh.edges)
                if (entry.Key.a == v || entry.Key.b == v)
                    foreach (int f in entry.Value)
                        links[f].UnionWith(entry.Value);
            List<List<int>> fans = Parts(incident, links);
            mesh.fans[v] = fans;
            if (fans.Count >= 2)
                mesh.nonmanifoldVertices.Add(v);
        }
        foreach (Component c in mesh.components)
            foreach (int v in c.vertices) {
                int count = 0;
                foreach (List<int> fan in mesh.fans[v])
                    if (mesh.faceComponent[fan[0]] == c.number)
                        count++;
                if (count >= 2)
                    c.nonmanifoldVertices.Add(v);
            }
        return mesh;
    }
    public sealed class Loop {
        public int number, component, length;
        public string kind;
        public bool filled;
        public List<int> vertices;
    }
    public static List<Loop> Loops(List<ObjIo.Face> faces, Mesh mesh) {
        List<Loop> result = new();
        foreach (Component c in mesh.components) {
            SortedSet<Edge> unused = new SortedSet<Edge>(c.boundary);
            while (unused.Count != 0) {
                Edge first = unused.Min;
                unused.Remove(first);
                List<int> sequence = [first.a, first.b];
                int current = first.b;
                while (current != first.a) {
                    Edge chosen = null;
                    int other = int.MaxValue;
                    foreach (Edge e in unused) {
                        int n = e.a == current ? e.b : e.b == current ? e.a : int.MaxValue;
                        if (n < other) {
                            other = n;
                            chosen = e;
                        }
                    }
                    if (chosen == null)
                        break;
                    unused.Remove(chosen);
                    sequence.Add(other);
                    current = other;
                }
                Loop loop = new Loop();
                loop.number = result.Count + 1;
                loop.component = c.number;
                loop.vertices = sequence;
                if (current != first.a) {
                    loop.kind = "open";
                    loop.length = sequence.Count - 1;
                } else {
                    sequence.RemoveAt(sequence.Count - 1);
                    loop.length = sequence.Count;
                    int forward = 0;
                    for (int i = 0; i < loop.length; i++) {
                        int a = sequence[i], b = sequence[(i + 1) % loop.length];
                        int f = mesh.edges[KeyEdge(a, b)][0];
                        if (Orientation.Directed(faces[f - 1], a, b))
                            forward++;
                    }
                    loop.kind = forward == 0 || forward == loop.length ? "coherent" : "mixed";
                    if (forward == 0)
                        sequence.Reverse(1, sequence.Count - 1);
                }
                result.Add(loop);
            }
        }
        return result;
    }
}
