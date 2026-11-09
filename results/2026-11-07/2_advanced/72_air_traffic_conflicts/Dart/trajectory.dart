part of 'main.dart';

class Vec {
  final double x, y, z;
  const Vec(this.x, this.y, this.z);
  Vec subtract(Vec b) => Vec(x - b.x, y - b.y, z - b.z);
}

class Segment {
  final int number, leg;
  final String phase;
  final double start, end;
  final Vec position, velocity, finalPosition;
  Segment(
    this.number,
    this.leg,
    this.phase,
    this.start,
    this.end,
    this.position,
    this.velocity,
    this.finalPosition,
  );
  Vec at(double time) {
    final dt = time - start;
    return Vec(
      position.x + velocity.x * dt,
      position.y + velocity.y * dt,
      position.z + velocity.z * dt,
    );
  }
}

class Trajectory {
  final List<Segment> segments = [];
  double length = 0;
  double get arrival => segments.last.end;
  (Vec, Segment)? at(double time) {
    if (time < segments.first.start || time >= segments.last.end) return null;
    for (final s in segments) {
      if (s.start <= time && time < s.end) return (s.at(time), s);
    }
    return null;
  }
}

Trajectory buildTrajectory(FlightPlan p, AircraftType aircraft) {
  final result = Trajectory();
  var t = (p.departure + p.delay).toDouble(), level = p.level + p.offset;
  for (var k = 1; k < p.waypoints.length; k++) {
    final a = p.waypoints[k - 1], b = p.waypoints[k];
    final dx = b.x - a.x, dy = b.y - a.y, length = sqrt(dx * dx + dy * dy) / 10;
    final duration = length * 3600 / p.speed;
    final vx = (dx / 10) / duration,
        vy = (dy / 10) / duration,
        xp = a.x / 10,
        yp = a.y / 10,
        xq = b.x / 10,
        yq = b.y / 10,
        target = b.hasLevel ? b.level + p.offset : level;
    if (target == level) {
      result.segments.add(
        Segment(
          result.segments.length + 1,
          k,
          'LVL',
          t,
          t + duration,
          Vec(xp, yp, (level * 100).toDouble()),
          Vec(vx, vy, 0),
          Vec(xq, yq, (level * 100).toDouble()),
        ),
      );
    } else {
      final rate = target > level ? aircraft.climb : aircraft.descent,
          phase = target > level ? 'CLB' : 'DES';
      final vz = target > level ? rate / 60 : -(rate / 60),
          change = (target - level).abs() * 6000 / rate;
      final xc = xp + vx * change, yc = yp + vy * change;
      result.segments.add(
        Segment(
          result.segments.length + 1,
          k,
          phase,
          t,
          t + change,
          Vec(xp, yp, (level * 100).toDouble()),
          Vec(vx, vy, vz),
          Vec(xc, yc, (target * 100).toDouble()),
        ),
      );
      result.segments.add(
        Segment(
          result.segments.length + 1,
          k,
          'LVL',
          t + change,
          t + duration,
          Vec(xc, yc, (target * 100).toDouble()),
          Vec(vx, vy, 0),
          Vec(xq, yq, (target * 100).toDouble()),
        ),
      );
    }
    result.length += length;
    t = t + duration;
    level = target;
  }
  return result;
}
