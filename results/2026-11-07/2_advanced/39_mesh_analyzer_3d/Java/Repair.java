import java.util.*;

final class Repair {
    record Snap(int number, Measure.Vec before, Measure.Vec after) {}
    record Removed(ObjIo.Face face, String reason) {}
    static List<ObjIo.Face> split(List<ObjIo.Polygon> polygons) {
        List<ObjIo.Face> result = new ArrayList<>();
        for (ObjIo.Polygon p : polygons)
            for (int i = 1; i < p.v().length - 1; i++)
                result.add(new ObjIo.Face(result.size() + 1, p.number(), p.line(), p.group(),
                                          new int[] {p.v()[0], p.v()[i], p.v()[i + 1]}));
        return result;
    }
    static List<Measure.Vec> snap(List<Measure.Vec> vertices, int spacing, List<Snap> changes) {
        List<Measure.Vec> result = new ArrayList<>();
        result.add(vertices.get(0));
        for (int i = 1; i < vertices.size(); i++) {
            Measure.Vec p = vertices.get(i);
            Measure.Vec q = new Measure.Vec(spacing * Math.floorDiv(2 * p.x() + spacing, 2L * spacing),
                                            spacing * Math.floorDiv(2 * p.y() + spacing, 2L * spacing),
                                            spacing * Math.floorDiv(2 * p.z() + spacing, 2L * spacing));
            result.add(q);
            if (!p.equals(q))
                changes.add(new Snap(i, p, q));
        }
        return result;
    }
    static int[] representatives(List<Measure.Vec> points, boolean merge) {
        int[] result = new int[points.size()];
        Map<Measure.Vec, Integer> owner = new HashMap<>();
        for (int i = 1; i < points.size(); i++) {
            if (merge) {
                owner.putIfAbsent(points.get(i), i);
                result[i] = owner.get(points.get(i));
            } else
                result[i] = i;
        }
        return result;
    }
    static List<ObjIo.Face> clean(List<ObjIo.Face> triangles, List<Measure.Vec> points, int[] representatives,
                                  boolean zero, boolean duplicate, List<Removed> removed) {
        List<ObjIo.Face> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (ObjIo.Face triangle : triangles) {
            ObjIo.Face f = triangle.copy();
            for (int i = 0; i < 3; i++)
                f.v[i] = representatives[f.v[i]];
            String reason = null;
            if (f.v[0] == f.v[1] || f.v[1] == f.v[2] || f.v[2] == f.v[0])
                reason = "repeated";
            else if (zero) {
                Measure.Vec n = Measure.normal(f, points);
                if (n.x() == 0 && n.y() == 0 && n.z() == 0)
                    reason = "zero_area";
            }
            if (reason == null) {
                int[] sorted = f.v.clone();
                Arrays.sort(sorted);
                String key = Main.numbers(sorted);
                if (duplicate && seen.contains(key))
                    reason = "duplicate";
                else
                    seen.add(key);
            }
            if (reason != null)
                removed.add(new Removed(triangle, reason));
            else
                result.add(f);
        }
        return result;
    }
    static int fill(List<ObjIo.Face> faces, List<Topology.Loop> loops, int maximum, Set<Integer> permitted) {
        int count = 0;
        for (Topology.Loop loop : loops) {
            List<Integer> v = loop.vertices;
            if (!loop.kind.equals("coherent") || loop.length < 3 || loop.length > maximum ||
                new HashSet<>(v).size() != loop.length || !permitted.contains(loop.component))
                continue;
            loop.filled = true;
            for (int i = 2; i < loop.length; i++) {
                faces.add(new ObjIo.Face(0, 0, 0, "fill", new int[] {v.get(0), v.get(i), v.get(i - 1)}));
                count++;
            }
        }
        return count;
    }
}
