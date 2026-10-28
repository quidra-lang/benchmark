using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Measure {
    public static long FloorDiv(long n, long d) => n >= 0 ? n / d : -((-n + d - 1) / d);
    public sealed record Vec(long x, long y, long z) {
        public long At(int i) {
            return i == 0 ? x : i == 1 ? y : z;
        }

        public override string ToString() {
            return x + " " + y + " " + z;
        }
    }
    public static Vec Subtract(Vec a, Vec b) {
        return new Vec(a.x - b.x, a.y - b.y, a.z - b.z);
    }
    public static Vec Add(Vec a, Vec b) {
        return new Vec(a.x + b.x, a.y + b.y, a.z + b.z);
    }
    public static Vec Cross(Vec a, Vec b) {
        return new Vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
    }
    public static long Dot(Vec a, Vec b) {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    public static Vec Normal(ObjIo.Face f, List<Vec> p) {
        return Cross(Subtract(p[f.v[1]], p[f.v[0]]), Subtract(p[f.v[2]], p[f.v[0]]));
    }
    public static long Determinant(ObjIo.Face f, List<Vec> p) {
        return Dot(p[f.v[0]], Cross(p[f.v[1]], p[f.v[2]]));
    }
    public static long Length(Topology.Edge e, List<Vec> p) {
        Vec d = Subtract(p[e.a], p[e.b]);
        return Dot(d, d);
    }
    public static double Area(List<ObjIo.Face> f, List<Vec> p) {
        double sum = 0;
        foreach (ObjIo.Face face in f) {
            Vec n = Normal(face, p);
            sum += Math.Sqrt(Dot(n, n));
        }
        return sum / 2;
    }
    public static long Volume(List<int> ids, List<ObjIo.Face> f, List<Vec> p) {
        long sum = 0;
        foreach (int i in ids)
            sum += Determinant(f[i - 1], p);
        return sum;
    }
    public static string Centroid(List<int> ids, List<ObjIo.Face> f, List<Vec> p, long volume) {
        List<string> result = new();
        for (int axis = 0; axis < 3; axis++) {
            long sum = 0;
            foreach (int i in ids) {
                ObjIo.Face face = f[i - 1];
                long coordinates = 0;
                foreach (int v in face.v)
                    coordinates += p[v].At(axis);
                sum += Determinant(face, p) * coordinates;
            }
            result.Add(Fraction(sum, 4 * volume));
        }
        return string.Join(" ", result);
    }
    public static string Fraction(long n, long d) {
        if (d < 0) {
            n = -n;
            d = -d;
        }
        long a = Math.Abs(n), b = d;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        n /= a;
        d /= a;
        return n + (d == 1 ? "" : "/" + d);
    }
    public static string Real(double value) {
        return (value == 0 ? 0.0 : value).ToString("F3", CultureInfo.InvariantCulture);
    }
    public static string Angle(ObjIo.Face f, List<Vec> p) {
        long minimum = long.MaxValue;
        for (int k = 0; k < 3; k++) {
            Vec a = p[f.v[k]], b = p[f.v[(k + 1) % 3]], c = p[f.v[(k + 2) % 3]];
            minimum = Math.Min(minimum, Dot(Subtract(b, a), Subtract(c, a)));
        }
        return minimum < 0 ? "obtuse" : minimum == 0 ? "right" : "acute";
    }
    public static int Winding(List<int> ids, List<ObjIo.Face> f, List<Vec> p, Vec point) {
        double sum = 0;
        foreach (int i in ids) {
            int[] v = f[i - 1].v;
            Vec a = Subtract(p[v[0]], point), b = Subtract(p[v[1]], point), c = Subtract(p[v[2]], point);
            double la = Math.Sqrt(Dot(a, a)), lb = Math.Sqrt(Dot(b, b)), lc = Math.Sqrt(Dot(c, c));
            double denominator = la * lb * lc + Dot(a, b) * lc + Dot(b, c) * la + Dot(c, a) * lb;
            sum += 2 * Math.Atan2(Dot(a, Cross(b, c)), denominator);
        }
        return (int)Math.Round(sum / (4 * Math.PI));
    }
    public static long[] Bbox(ICollection<int> ids, List<Vec> p) {
        long[] box = { long.MaxValue, long.MaxValue, long.MaxValue,
                       long.MinValue, long.MinValue, long.MinValue };
        foreach (int i in ids)
            for (int k = 0; k < 3; k++) {
                box[k] = Math.Min(box[k], p[i].At(k));
                box[k + 3] = Math.Max(box[k + 3], p[i].At(k));
            }
        return box;
    }
}
