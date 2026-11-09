import java.util.*;
final class Conflict {
    record Pair(String first, String second) {
        static Pair of(String a, String b) {
            return a.compareTo(b) < 0 ? new Pair(a, b) : new Pair(b, a);
        }
        String name() { return first + "-" + second; }
    }
    record Loss(double lo, double hi, double tc, double distance, double vertical) {}
    record Piece(Trajectory.Segment a, Trajectory.Segment b, Loss loss) {}
    static final class Event {
        Pair pair;
        double start, end;
        List<Piece> pieces = new ArrayList<>();
        Piece closest;
        double levelA, levelB, trackA, trackB, angle;
        String geometry, severity, sector, outcome;
        Event(Pair pair, Piece piece) {
            this.pair = pair;
            start = piece.loss().lo();
            end = piece.loss().hi();
            pieces.add(piece);
            closest = piece;
        }
    }
    static final Comparator<Event> ORDER = Comparator.comparingDouble((Event event) -> event.start)
                                               .thenComparing(event -> event.pair.first())
                                               .thenComparing(event -> event.pair.second());
    static Loss loss(Trajectory.Vec position, Trajectory.Vec velocity, double t1, double t2,
                     double horizontal, double vertical) {
        double px = position.x(), py = position.y(), pz = position.z(), wx = velocity.x(),
               wy = velocity.y(), wz = velocity.z(), qa = wx * wx + wy * wy,
               qb = 2 * (px * wx + py * wy), qc = (px * px + py * py) - horizontal * horizontal,
               lo = t1, hi = t2;
        if (qa < 1e-12) {
            if (qc >= 0)
                return null;
        } else {
            double d = qb * qb - 4 * qa * qc;
            if (d <= 0)
                return null;
            double root = Math.sqrt(d);
            lo = Math.max(lo, t1 + (-qb - root) / (2 * qa));
            hi = Math.min(hi, t1 + (-qb + root) / (2 * qa));
        }
        if (wz == 0) {
            if (Math.abs(pz) >= vertical)
                return null;
        } else {
            double r1 = (-vertical - pz) / wz, r2 = (vertical - pz) / wz;
            lo = Math.max(lo, t1 + Math.min(r1, r2));
            hi = Math.min(hi, t1 + Math.max(r1, r2));
        }
        if (hi - lo <= 1e-6)
            return null;
        double tc = qa >= 1e-12 ? t1 + (-qb / (2 * qa)) : t1;
        tc = Math.min(Math.max(tc, lo), hi);
        double elapsed = tc - t1, ex = px + wx * elapsed, ey = py + wy * elapsed;
        return new Loss(lo, hi, tc, Math.sqrt(ex * ex + ey * ey), Math.abs(pz + wz * elapsed));
    }
    static List<Event> pair(String nameA, Trajectory.Built first, String nameB,
                            Trajectory.Built second, double dh, double dv) {
        List<Piece> pieces = new ArrayList<>();
        for (Trajectory.Segment a : first.segments())
            for (Trajectory.Segment b : second.segments()) {
                double t1 = Math.max(a.ts(), b.ts()), t2 = Math.min(a.te(), b.te());
                if (t1 >= t2)
                    continue;
                Loss loss = loss(Trajectory.position(a, t1).minus(Trajectory.position(b, t1)),
                                 a.velocity().minus(b.velocity()), t1, t2, dh, dv);
                if (loss != null)
                    pieces.add(new Piece(a, b, loss));
            }
        pieces.sort(Comparator.comparingDouble(piece -> piece.loss().lo()));
        List<Event> conflicts = new ArrayList<>();
        Pair pair = new Pair(nameA, nameB);
        for (Piece piece : pieces) {
            if (conflicts.isEmpty() || piece.loss().lo() - conflicts.getLast().end > 1e-6)
                conflicts.add(new Event(pair, piece));
            else {
                Event conflict = conflicts.getLast();
                conflict.pieces.add(piece);
                conflict.end = piece.loss().hi();
                if (piece.loss().distance() < conflict.closest.loss().distance() - 1e-9)
                    conflict.closest = piece;
            }
        }
        return conflicts;
    }
    static List<Event> all(Map<String, Trajectory.Built> trajectories, double dh, double dv) {
        List<String> names = new ArrayList<>(trajectories.keySet());
        Collections.sort(names);
        List<Event> result = new ArrayList<>();
        for (int i = 0; i < names.size(); i++)
            for (int j = i + 1; j < names.size(); j++) {
                String a = names.get(i), b = names.get(j);
                result.addAll(pair(a, trajectories.get(a), b, trajectories.get(b), dh, dv));
            }
        result.sort(ORDER);
        return result;
    }
}
