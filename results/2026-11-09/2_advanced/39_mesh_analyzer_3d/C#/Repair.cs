using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Repair {
    public sealed record Snap(int number, Measure.Vec before, Measure.Vec after);
    public sealed record Removed(ObjIo.Face face, string reason);
    public static List<ObjIo.Face> Split(List<ObjIo.Polygon> polygons) {
        List<ObjIo.Face> result = new();
        foreach (ObjIo.Polygon p in polygons)
            for (int i = 1; i < p.v.Length - 1; i++)
                result.Add(new ObjIo.Face(result.Count + 1, p.number, p.line, p.group,
                                          new int[] { p.v[0], p.v[i], p.v[i + 1] }));
        return result;
    }
    public static List<Measure.Vec> SnapVertices(List<Measure.Vec> vertices, int spacing,
                                                 List<Snap> changes) {
        List<Measure.Vec> result = new();
        result.Add(vertices[0]);
        for (int i = 1; i < vertices.Count; i++) {
            Measure.Vec p = vertices[i];
            Measure.Vec q = new Measure.Vec(spacing * Measure.FloorDiv(2 * p.x + spacing, 2L * spacing),
                                            spacing * Measure.FloorDiv(2 * p.y + spacing, 2L * spacing),
                                            spacing * Measure.FloorDiv(2 * p.z + spacing, 2L * spacing));
            result.Add(q);
            if (!p.Equals(q))
                changes.Add(new Snap(i, p, q));
        }
        return result;
    }
    public static int[] Representatives(List<Measure.Vec> points, bool merge) {
        int[] result = new int[points.Count];
        Dictionary<Measure.Vec, int> owner = new();
        for (int i = 1; i < points.Count; i++) {
            if (merge) {
                owner.TryAdd(points[i], i);
                result[i] = owner[points[i]];
            } else
                result[i] = i;
        }
        return result;
    }
    public static List<ObjIo.Face> Clean(List<ObjIo.Face> triangles, List<Measure.Vec> points,
                                         int[] representatives, bool zero, bool duplicate,
                                         List<Removed> removed) {
        List<ObjIo.Face> result = new();
        HashSet<string> seen = new();
        foreach (ObjIo.Face triangle in triangles) {
            ObjIo.Face f = triangle.Copy();
            for (int i = 0; i < 3; i++)
                f.v[i] = representatives[f.v[i]];
            string reason = null;
            if (f.v[0] == f.v[1] || f.v[1] == f.v[2] || f.v[2] == f.v[0])
                reason = "repeated";
            else if (zero) {
                Measure.Vec n = Measure.Normal(f, points);
                if (n.x == 0 && n.y == 0 && n.z == 0)
                    reason = "zero_area";
            }
            if (reason == null) {
                int[] sorted = f.v.ToArray();
                Array.Sort(sorted);
                string key = Program.Numbers(sorted);
                if (duplicate && seen.Contains(key))
                    reason = "duplicate";
                else
                    seen.Add(key);
            }
            if (reason != null)
                removed.Add(new Removed(triangle, reason));
            else
                result.Add(f);
        }
        return result;
    }
    public static int Fill(List<ObjIo.Face> faces, List<Topology.Loop> loops, int maximum,
                           HashSet<int> permitted) {
        int count = 0;
        foreach (Topology.Loop loop in loops) {
            List<int> v = loop.vertices;
            if (!loop.kind.Equals("coherent") || loop.length < 3 || loop.length > maximum ||
                new HashSet<int>(v).Count != loop.length || !permitted.Contains(loop.component))
                continue;
            loop.filled = true;
            for (int i = 2; i < loop.length; i++) {
                faces.Add(new ObjIo.Face(0, 0, 0, "fill", new int[] { v[0], v[i], v[i - 1] }));
                count++;
            }
        }
        return count;
    }
}
