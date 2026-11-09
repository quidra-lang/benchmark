using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Orientation {
    public static bool Directed(ObjIo.Face f, int a, int b) {
        for (int i = 0; i < 3; i++)
            if (f.v[i] == a && f.v[(i + 1) % 3] == b)
                return true;
        return false;
    }
    public static void Flip(ObjIo.Face f) {
        int t = f.v[1];
        f.v[1] = f.v[2];
        f.v[2] = t;
    }
    public static List<Topology.Edge> Inconsistent(List<ObjIo.Face> f,
                                                   SortedDictionary<Topology.Edge, List<int>> edges) {
        List<Topology.Edge> result = new();
        foreach (var entry in edges)
            if (entry.Value.Count == 2) {
                Topology.Edge e = entry.Key;
                if (Directed(f[entry.Value[0] - 1], e.a, e.b) == Directed(f[entry.Value[1] - 1], e.a, e.b))
                    result.Add(e);
            }
        return result;
    }
    public static void Repair(List<ObjIo.Face> faces, SortedDictionary<Topology.Edge, List<int>> edges) {
        bool[] visited = new bool[faces.Count + 1];
        for (int seed = 1; seed <= faces.Count; seed++) {
            if (visited[seed])
                continue;
            visited[seed] = true;
            Queue<int> queue = new();
            queue.Enqueue(seed);
            while (queue.Count != 0) {
                int current = queue.Dequeue();
                ObjIo.Face f = faces[current - 1];
                for (int k = 0; k < 3; k++) {
                    int a = f.v[k], b = f.v[(k + 1) % 3];
                    List<int> ids = edges[Topology.KeyEdge(a, b)];
                    if (ids.Count != 2)
                        continue;
                    int other = ids[0] == current ? ids[1] : ids[0];
                    if (visited[other])
                        continue;
                    if (Directed(faces[other - 1], a, b))
                        Flip(faces[other - 1]);
                    visited[other] = true;
                    queue.Enqueue(other);
                }
            }
        }
    }
    public static bool[] Orientable(List<ObjIo.Face> faces, Topology.Mesh mesh) {
        List<ObjIo.Face> copied = new();
        foreach (ObjIo.Face f in faces)
            copied.Add(f.Copy());
        Repair(copied, mesh.edges);
        List<Topology.Edge> errors = Inconsistent(copied, mesh.edges);
        bool[] result = new bool[mesh.components.Count + 1];
        Array.Fill(result, true);
        foreach (Topology.Edge e in errors)
            result[mesh.faceComponent[mesh.edges[e][0]]] = false;
        return result;
    }
}
