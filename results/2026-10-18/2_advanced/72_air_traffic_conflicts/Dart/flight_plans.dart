part of 'main.dart';

class AircraftType {
  final String name;
  final int climb, descent, minSpeed;
  AircraftType(this.name, this.climb, this.descent, this.minSpeed);
}

class Waypoint {
  final int x, y, level;
  final bool hasLevel;
  Waypoint(this.x, this.y, [this.level = 0, this.hasLevel = false]);
}

class FlightPlan {
  final String callsign;
  final int type, departure, level, originalSpeed;
  int speed, delay, offset;
  final List<Waypoint> waypoints;
  FlightPlan(
    this.callsign,
    this.type,
    this.departure,
    this.level,
    this.originalSpeed,
    this.waypoints, {
    int? speed,
    this.delay = 0,
    this.offset = 0,
  }) : speed = speed ?? originalSpeed;
  FlightPlan copy() => FlightPlan(
    callsign,
    type,
    departure,
    level,
    originalSpeed,
    waypoints,
    speed: speed,
    delay: delay,
    offset: offset,
  );
}

class Sector {
  final String name;
  final int x1, y1, x2, y2, lower, upper, capacity;
  Sector(
    this.name,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.lower,
    this.upper,
    this.capacity,
  );
}

class Settings {
  int dh = 0,
      dv = 0,
      lookahead = 0,
      maxDelay = 0,
      minLevel = 0,
      maxLevel = 0,
      ta = 0,
      tb = 0,
      leader = 0,
      alert = 0;
  final List<int> radar = List.filled(6, 0), snapshots = [];
}

class Input {
  final List<FlightPlan> plans = [];
  final List<AircraftType> types = [];
  final List<Sector> sectors = [];
  final Settings settings = Settings();
}

Input readInput() {
  final input = Input(), types = <String, int>{};
  for (final line in File('input/aircraft.txt').readAsLinesSync()) {
    final a = line.split(' ');
    types[a[0]] = input.types.length;
    input.types.add(
      AircraftType(a[0], int.parse(a[1]), int.parse(a[2]), int.parse(a[3])),
    );
  }
  for (final line in File('input/flights.csv').readAsLinesSync().skip(1)) {
    final a = line.split(','), waypoints = <Waypoint>[];
    for (final wp in a[5].split(' ')) {
      final b = wp.split(':');
      waypoints.add(
        Waypoint(
          int.parse(b[0]),
          int.parse(b[1]),
          b.length == 3 ? int.parse(b[2]) : 0,
          b.length == 3,
        ),
      );
    }
    input.plans.add(
      FlightPlan(
        a[0],
        types[a[1]]!,
        int.parse(a[2]),
        int.parse(a[3]),
        int.parse(a[4]),
        waypoints,
      ),
    );
  }
  input.plans.sort((a, b) => a.callsign.compareTo(b.callsign));
  for (final line in File('input/sectors.txt').readAsLinesSync()) {
    final a = line.split(' ');
    input.sectors.add(
      Sector(
        a[0],
        int.parse(a[1]),
        int.parse(a[2]),
        int.parse(a[3]),
        int.parse(a[4]),
        int.parse(a[5]),
        int.parse(a[6]),
        int.parse(a[7]),
      ),
    );
  }
  final p = input.settings;
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'separation':
        p.dh = int.parse(a[1]);
        p.dv = int.parse(a[2]);
        break;
      case 'lookahead':
        p.lookahead = int.parse(a[1]);
        break;
      case 'max_delay':
        p.maxDelay = int.parse(a[1]);
        break;
      case 'levels':
        p.minLevel = int.parse(a[1]);
        p.maxLevel = int.parse(a[2]);
        break;
      case 'sampling':
        p.ta = int.parse(a[1]);
        p.tb = int.parse(a[2]);
        break;
      case 'radar':
        for (var i = 0; i < 6; i++) {
          p.radar[i] = int.parse(a[i + 1]);
        }
        break;
      case 'snapshots':
        p.snapshots.addAll(a.skip(1).map(int.parse));
        break;
      case 'leader':
        p.leader = int.parse(a[1]);
        break;
      case 'alert':
        p.alert = int.parse(a[1]);
        break;
    }
  }
  return input;
}

List<int> flightLevels(FlightPlan p) => [
  p.level + p.offset,
  for (final w in p.waypoints)
    if (w.hasLevel) w.level + p.offset,
];
