part of 'main.dart';

class Loss {
  final double lo, hi, time, distance, vertical;
  Loss(this.lo, this.hi, this.time, this.distance, this.vertical);
}

class Piece {
  final int a, b;
  final Loss loss;
  Piece(this.a, this.b, this.loss);
}

class Conflict {
  final int a, b;
  final double start;
  double end;
  final List<Piece> pieces;
  Piece closest;
  Conflict(this.a, this.b, this.start, this.end, this.pieces, this.closest);
}

Loss? lossInterval(Vec p, Vec w, double t1, double t2, Settings settings) {
  final dh = settings.dh.toDouble(),
      dv = settings.dv.toDouble(),
      qa = w.x * w.x + w.y * w.y,
      qb = 2 * (p.x * w.x + p.y * w.y),
      qc = (p.x * p.x + p.y * p.y) - dh * dh;
  var lo = t1, hi = t2;
  if (qa < 1e-12) {
    if (qc >= 0) return null;
  } else {
    final d = qb * qb - 4 * qa * qc;
    if (d <= 0) return null;
    final s = sqrt(d);
    lo = max(lo, t1 + (-qb - s) / (2 * qa));
    hi = min(hi, t1 + (-qb + s) / (2 * qa));
  }
  if (w.z == 0) {
    if (p.z.abs() >= dv) return null;
  } else {
    final r1 = (-dv - p.z) / w.z, r2 = (dv - p.z) / w.z;
    lo = max(lo, t1 + min(r1, r2));
    hi = min(hi, t1 + max(r1, r2));
  }
  if (hi - lo <= 1e-6) return null;
  var tc = qa >= 1e-12 ? t1 + (-qb / (2 * qa)) : t1;
  tc = min(max(tc, lo), hi);
  final tau = tc - t1, ex = p.x + w.x * tau, ey = p.y + w.y * tau;
  return Loss(lo, hi, tc, sqrt(ex * ex + ey * ey), (p.z + w.z * tau).abs());
}

List<Conflict> pairConflicts(
  int a,
  int b,
  Trajectory ta,
  Trajectory tb,
  Settings settings,
) {
  final pieces = <Piece>[];
  for (var i = 0; i < ta.segments.length; i++) {
    final sa = ta.segments[i];
    for (var j = 0; j < tb.segments.length; j++) {
      final sb = tb.segments[j],
          t1 = max(sa.start, sb.start),
          t2 = min(sa.end, sb.end);
      if (t1 >= t2) continue;
      final loss = lossInterval(
        sa.at(t1).subtract(sb.at(t1)),
        sa.velocity.subtract(sb.velocity),
        t1,
        t2,
        settings,
      );
      if (loss != null) pieces.add(Piece(i, j, loss));
    }
  }
  final indexed = pieces.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.loss.lo.compareTo(b.$2.loss.lo);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  final result = <Conflict>[];
  for (final (_, piece) in indexed) {
    if (result.isEmpty || piece.loss.lo - result.last.end > 1e-6) {
      result.add(Conflict(a, b, piece.loss.lo, piece.loss.hi, [piece], piece));
    } else {
      final last = result.last;
      last.pieces.add(piece);
      last.end = piece.loss.hi;
      if (piece.loss.distance < last.closest.loss.distance - 1e-9)
        last.closest = piece;
    }
  }
  return result;
}

int compareConflicts(Conflict a, Conflict b) {
  var c = a.start.compareTo(b.start);
  if (c != 0) return c;
  c = a.a.compareTo(b.a);
  return c != 0 ? c : a.b.compareTo(b.b);
}

List<Conflict> conflicts(List<Trajectory> trajectories, Settings settings) => [
  for (var i = 0; i < trajectories.length; i++)
    for (var j = i + 1; j < trajectories.length; j++)
      ...pairConflicts(i, j, trajectories[i], trajectories[j], settings),
]..sort(compareConflicts);
