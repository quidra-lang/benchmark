import java.util.*;

final class Measure {
    record Vec(long x, long y, long z) {
        long at(int i) {
            return i == 0 ? x : i == 1 ? y : z;
        }
        @Override
        public String toString() {
            return x + " " + y + " " + z;
        }
    }
    static Vec subtract(Vec a, Vec b) {
        return new Vec(a.x - b.x, a.y - b.y, a.z - b.z);
    }
    static Vec add(Vec a, Vec b) {
        return new Vec(a.x + b.x, a.y + b.y, a.z + b.z);
    }
    static Vec cross(Vec a, Vec b) {
        return new Vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
    }
    static long dot(Vec a, Vec b) {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    static Vec normal(ObjIo.Face f, List<Vec> p) {
        return cross(subtract(p.get(f.v[1]), p.get(f.v[0])), subtract(p.get(f.v[2]), p.get(f.v[0])));
    }
    static long determinant(ObjIo.Face f, List<Vec> p) {
        return dot(p.get(f.v[0]), cross(p.get(f.v[1]), p.get(f.v[2])));
    }
    static long length(Topology.Edge e, List<Vec> p) {
        Vec d = subtract(p.get(e.a()), p.get(e.b()));
        return dot(d, d);
    }
    static double area(List<ObjIo.Face> f, List<Vec> p) {
        double sum = 0;
        for (ObjIo.Face face : f) {
            Vec n = normal(face, p);
            sum += Math.sqrt(dot(n, n));
        }
        return sum / 2;
    }
    static long volume(List<Integer> ids, List<ObjIo.Face> f, List<Vec> p) {
        long sum = 0;
        for (int i : ids)
            sum += determinant(f.get(i - 1), p);
        return sum;
    }
    static String centroid(List<Integer> ids, List<ObjIo.Face> f, List<Vec> p, long volume) {
        List<String> result = new ArrayList<>();
        for (int axis = 0; axis < 3; axis++) {
            long sum = 0;
            for (int i : ids) {
                ObjIo.Face face = f.get(i - 1);
                long coordinates = 0;
                for (int v : face.v)
                    coordinates += p.get(v).at(axis);
                sum += determinant(face, p) * coordinates;
            }
            result.add(fraction(sum, 4 * volume));
        }
        return String.join(" ", result);
    }
    static String fraction(long n, long d) {
        if (d < 0) {
            n = -n;
            d = -d;
        }
        long a = Math.abs(n), b = d;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        n /= a;
        d /= a;
        return n + (d == 1 ? "" : "/" + d);
    }
    static String real(double value) {
        return String.format(Locale.ROOT, "%.3f", value == 0 ? 0.0 : value);
    }
    static String angle(ObjIo.Face f, List<Vec> p) {
        long minimum = Long.MAX_VALUE;
        for (int k = 0; k < 3; k++) {
            Vec a = p.get(f.v[k]), b = p.get(f.v[(k + 1) % 3]), c = p.get(f.v[(k + 2) % 3]);
            minimum = Math.min(minimum, dot(subtract(b, a), subtract(c, a)));
        }
        return minimum < 0 ? "obtuse" : minimum == 0 ? "right" : "acute";
    }
    static int winding(List<Integer> ids, List<ObjIo.Face> f, List<Vec> p, Vec point) {
        double sum = 0;
        for (int i : ids) {
            int[] v = f.get(i - 1).v;
            Vec a = subtract(p.get(v[0]), point), b = subtract(p.get(v[1]), point),
                c = subtract(p.get(v[2]), point);
            double la = Math.sqrt(dot(a, a)), lb = Math.sqrt(dot(b, b)), lc = Math.sqrt(dot(c, c));
            double denominator = la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb;
            sum += 2 * Math.atan2(dot(a, cross(b, c)), denominator);
        }
        return (int)Math.round(sum / (4 * Math.PI));
    }
    static long[] bbox(Collection<Integer> ids, List<Vec> p) {
        long[] box = {Long.MAX_VALUE, Long.MAX_VALUE, Long.MAX_VALUE,
                      Long.MIN_VALUE, Long.MIN_VALUE, Long.MIN_VALUE};
        for (int i : ids)
            for (int k = 0; k < 3; k++) {
                box[k] = Math.min(box[k], p.get(i).at(k));
                box[k + 3] = Math.max(box[k + 3], p.get(i).at(k));
            }
        return box;
    }
}
