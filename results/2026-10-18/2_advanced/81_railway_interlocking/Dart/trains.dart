part of 'main.dart';

class Stop {
  final String kind;
  final Section section;
  final int dwell, scheduledArrival, scheduledDeparture;
  int arrival = -1, departure = -1;
  Stop(
    this.kind,
    this.section,
    this.dwell,
    this.scheduledArrival,
    this.scheduledDeparture,
  );
}

class PathSection {
  final Section section;
  final int start;
  PathSection(this.section, this.start);
}

class Train {
  final String name, symbol;
  final int length, acceleration, deceleration, maxSpeed;
  final Boundary entry;
  final int scheduledEntry, entrySpeed;
  int actualEntry = -1;
  final List<Stop> stops = [];
  late Boundary exit;
  int scheduledExit = 0, actualExit = -1;
  String state = 'WAITING', direction = '';
  List<PathSection> path = [];
  int head = 0, speed = 0, nextStop = 0;
  bool dwelling = false;
  Stop? awaitDeparture;
  bool emergency = false, crossed = false;
  int boundaryCoordinate = 0,
      distance = 0,
      recordedMax = 0,
      standing = 0,
      passes = 0;
  Train(
    this.name,
    this.symbol,
    this.length,
    this.acceleration,
    this.deceleration,
    this.maxSpeed,
    this.entry,
    this.scheduledEntry,
    this.entrySpeed,
  );
  PathSection headSection() {
    var out = path[0];
    for (final section in path) {
      if (section.start < head) out = section;
    }
    return out;
  }

  List<PathSection> occupiedSections() => [
    for (final section in path)
      if (section.start < head &&
          section.start + section.section.length > head - length)
        section,
  ];
  Stop? get stop => nextStop >= stops.length ? null : stops[nextStop];
}

class TrainRequest {
  final Train train;
  final Route route;
  final int time;
  TrainRequest(this.train, this.route, this.time);
}

(List<Train>, List<TrainRequest>) readTrains(
  Layout layout,
  Interlocking interlocking,
) {
  final trains = <Train>[],
      requests = <TrainRequest>[],
      byName = <String, Train>{};
  for (final line in readLines('input/trains.txt')) {
    final a = line.split(' ');
    if (a[0] == 'TRAIN') {
      final t = Train(
        a[1],
        String.fromCharCode(97 + trains.length),
        number(a[2]),
        number(a[3]),
        number(a[4]),
        number(a[5]),
        layout.boundaryByName[a[6]]!,
        number(a[7]),
        number(a[8]),
      );
      trains.add(t);
      byName[t.name] = t;
      continue;
    }
    final train = byName[a[1]]!;
    switch (a[0]) {
      case 'REQUEST':
        requests.add(
          TrainRequest(train, interlocking.byName[a[2]]!, number(a[3])),
        );
        break;
      case 'STOP':
      case 'TURN':
        train.stops.add(
          Stop(
            a[0],
            layout.sectionByName[a[2]]!,
            number(a[3]),
            number(a[4]),
            number(a[5]),
          ),
        );
        break;
      case 'EXIT':
        train.exit = layout.boundaryByName[a[2]]!;
        train.scheduledExit = number(a[3]);
        break;
    }
  }
  return (trains, requests);
}

int brakingDistance(int u, int b) {
  final n = u ~/ b;
  return n * u - b * n * (n + 1) ~/ 2;
}

int selectSpeed(Train train, int distance) {
  final lo = max(train.speed - train.deceleration, 0);
  if (train.emergency) return lo;
  for (
    var u = min(train.speed + train.acceleration, train.maxSpeed);
    u >= lo;
    u--
  ) {
    if (distance < 0 || u + brakingDistance(u, train.deceleration) <= distance)
      return u;
  }
  return lo;
}
