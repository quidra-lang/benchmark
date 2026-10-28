import java.util.*;

final class Orientation {
    static boolean directed(ObjIo.Face f, int a, int b) {
        for (int i = 0; i < 3; i++)
            if (f.v[i] == a && f.v[(i + 1) % 3] == b)
                return true;
        return false;
    }
    static void flip(ObjIo.Face f) {
        int t = f.v[1];
        f.v[1] = f.v[2];
        f.v[2] = t;
    }
    static List<Topology.Edge> inconsistent(List<ObjIo.Face> f,
                                            SortedMap<Topology.Edge, List<Integer>> edges) {
        List<Topology.Edge> result = new ArrayList<>();
        for (var entry : edges.entrySet())
            if (entry.getValue().size() == 2) {
                Topology.Edge e = entry.getKey();
                if (directed(f.get(entry.getValue().get(0) - 1), e.a(), e.b()) ==
                    directed(f.get(entry.getValue().get(1) - 1), e.a(), e.b()))
                    result.add(e);
            }
        return result;
    }
    static void repair(List<ObjIo.Face> faces, SortedMap<Topology.Edge, List<Integer>> edges) {
        boolean[] visited = new boolean[faces.size() + 1];
        for (int seed = 1; seed <= faces.size(); seed++) {
            if (visited[seed])
                continue;
            visited[seed] = true;
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(seed);
            while (!queue.isEmpty()) {
                int current = queue.remove();
                ObjIo.Face f = faces.get(current - 1);
                for (int k = 0; k < 3; k++) {
                    int a = f.v[k], b = f.v[(k + 1) % 3];
                    List<Integer> ids = edges.get(Topology.edge(a, b));
                    if (ids.size() != 2)
                        continue;
                    int other = ids.get(0) == current ? ids.get(1) : ids.get(0);
                    if (visited[other])
                        continue;
                    if (directed(faces.get(other - 1), a, b))
                        flip(faces.get(other - 1));
                    visited[other] = true;
                    queue.add(other);
                }
            }
        }
    }
    static boolean[] orientable(List<ObjIo.Face> faces, Topology.Mesh mesh) {
        List<ObjIo.Face> copied = new ArrayList<>();
        for (ObjIo.Face f : faces)
            copied.add(f.copy());
        repair(copied, mesh.edges);
        List<Topology.Edge> errors = inconsistent(copied, mesh.edges);
        boolean[] result = new boolean[mesh.components.size() + 1];
        Arrays.fill(result, true);
        for (Topology.Edge e : errors)
            result[mesh.faceComponent[mesh.edges.get(e).get(0)]] = false;
        return result;
    }
}
