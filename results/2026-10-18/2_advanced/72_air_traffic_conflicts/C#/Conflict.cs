using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Conflict {
    public record Pair(string first, string second) {
        public static Pair Of(string a, string b) {
            return string.CompareOrdinal(a, b) < 0 ? new Pair(a, b) : new Pair(b, a);
        }
        public string name => first + "-" + second;
    }
    public record Loss(double lo, double hi, double tc, double distance, double vertical) {}
    public record Piece(Trajectory.Segment a, Trajectory.Segment b, Loss loss) {}
    public sealed class Event {
        public Pair pair;
        public double start, end;
        public List<Piece> pieces = new();
        public Piece closest;
        public double levelA, levelB, trackA, trackB, angle;
        public string geometry, severity, sector, outcome;
        public Event(Pair pair, Piece piece) {
            this.pair = pair;
            start = piece.loss.lo;
            end = piece.loss.hi;
            pieces.Add(piece);
            closest = piece;
        }
    }
    public static readonly Comparison<Event> ORDER = (a, b) => {
        int c = a.start.CompareTo(b.start);
        if (c == 0)
            c = string.CompareOrdinal(a.pair.first, b.pair.first);
        return c != 0 ? c : string.CompareOrdinal(a.pair.second, b.pair.second);
    };
    public static Loss LossInterval(Trajectory.Vec position, Trajectory.Vec velocity, double t1,
                                    double t2, double horizontal, double vertical) {
        double px = position.x, py = position.y, pz = position.z, wx = velocity.x, wy = velocity.y,
               wz = velocity.z, qa = wx * wx + wy * wy, qb = 2 * (px * wx + py * wy),
               qc = (px * px + py * py) - horizontal * horizontal, lo = t1, hi = t2;
        if (qa < 1e-12) {
            if (qc >= 0)
                return null;
        } else {
            double d = qb * qb - 4 * qa * qc;
            if (d <= 0)
                return null;
            double root = Math.Sqrt(d);
            lo = Math.Max(lo, t1 + (-qb - root) / (2 * qa));
            hi = Math.Min(hi, t1 + (-qb + root) / (2 * qa));
        }
        if (wz == 0) {
            if (Math.Abs(pz) >= vertical)
                return null;
        } else {
            double r1 = (-vertical - pz) / wz, r2 = (vertical - pz) / wz;
            lo = Math.Max(lo, t1 + Math.Min(r1, r2));
            hi = Math.Min(hi, t1 + Math.Max(r1, r2));
        }
        if (hi - lo <= 1e-6)
            return null;
        double tc = qa >= 1e-12 ? t1 + (-qb / (2 * qa)) : t1;
        tc = Math.Min(Math.Max(tc, lo), hi);
        double elapsed = tc - t1, ex = px + wx * elapsed, ey = py + wy * elapsed;
        return new Loss(lo, hi, tc, Math.Sqrt(ex * ex + ey * ey), Math.Abs(pz + wz * elapsed));
    }
    public static List<Event> FindPair(string nameA, Trajectory.Built first, string nameB,
                                       Trajectory.Built second, double dh, double dv) {
        List<Piece> pieces = new();
        foreach (Trajectory.Segment a in first.segments)
            foreach (Trajectory.Segment b in second.segments) {
                double t1 = Math.Max(a.ts, b.ts), t2 = Math.Min(a.te, b.te);
                if (t1 >= t2)
                    continue;
                Loss loss =
                    LossInterval(Trajectory.Position(a, t1).Minus(Trajectory.Position(b, t1)),
                                 a.velocity.Minus(b.velocity), t1, t2, dh, dv);
                if (loss != null)
                    pieces.Add(new Piece(a, b, loss));
            }
        pieces = pieces.OrderBy(piece => piece.loss.lo).ToList();
        List<Event> conflicts = new();
        Pair pair = new Pair(nameA, nameB);
        foreach (Piece piece in pieces) {
            if (conflicts.Count == 0 || piece.loss.lo - conflicts[^1].end > 1e-6)
                conflicts.Add(new Event(pair, piece));
            else {
                Event conflict = conflicts[^1];
                conflict.pieces.Add(piece);
                conflict.end = piece.loss.hi;
                if (piece.loss.distance < conflict.closest.loss.distance - 1e-9)
                    conflict.closest = piece;
            }
        }
        return conflicts;
    }
    public static List<Event> All(IDictionary<string, Trajectory.Built> trajectories, double dh,
                                  double dv) {
        List<string> names = new(trajectories.Keys);
        names.Sort(StringComparer.Ordinal);
        List<Event> result = new();
        for (int i = 0; i < names.Count; i++)
            for (int j = i + 1; j < names.Count; j++) {
                string a = names[i], b = names[j];
                result.AddRange(FindPair(a, trajectories[a], b, trajectories[b], dh, dv));
            }
        result.Sort(ORDER);
        return result;
    }
}
