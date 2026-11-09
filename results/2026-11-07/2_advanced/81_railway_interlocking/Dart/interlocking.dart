part of 'main.dart';

class Requirement {
  final Point point;
  final String position;
  Requirement(this.point, this.position);
}

class Route {
  final String name, finish, direction;
  String state = '';
  final Signal start;
  final List<Requirement> points, flank;
  final List<Section> sections, overlap;
  final List<String> conflictNames;
  final List<Route> conflicts = [];
  final int approach;
  int releaseTime = -1, overlapCounter = 0;
  bool overlapLocked = false;
  final Set<Section> passed = {};
  int requests = 0,
      grants = 0,
      uses = 0,
      cancels = 0,
      wait = 0,
      maxwait = 0,
      lockedTicks = 0;
  Route(
    this.name,
    this.start,
    this.finish,
    this.points,
    this.sections,
    this.overlap,
    this.flank,
    this.conflictNames,
    this.approach,
  ) : direction = start.direction;
  List<Requirement> requirements() => [...points, ...flank];
}

List<String> nameList(String s) => s == '-' ? [] : s.split(',');

class Interlocking {
  final Layout layout;
  final List<Route> routes = [];
  final Map<String, Route> byName = {};
  Interlocking(this.layout);
  void lock(Route r) {
    r.state = 'LOCKED';
    r.passed.clear();
    for (final s in r.sections) {
      s.route = r;
    }
    for (final s in r.overlap) {
      s.overlaps.add(r);
    }
    for (final requirement in r.requirements()) {
      requirement.point.locks.add(PointLock(r, requirement.position));
    }
    r.overlapLocked = true;
    r.overlapCounter = 0;
    r.releaseTime = -1;
  }

  void unlockSection(Route r, Section s) {
    if (s.route == r) s.route = null;
    for (final point in layout.points) {
      if (point.common == s) point.locks.removeWhere((lock) => lock.route == r);
    }
  }

  void unlockOverlap(Route r) {
    for (final s in r.overlap) {
      s.overlaps.remove(r);
      for (final point in layout.points) {
        if (point.common == s)
          point.locks.removeWhere((lock) => lock.route == r);
      }
    }
    r.overlapLocked = false;
  }

  void release(Route r) {
    for (final s in r.sections) {
      if (s.route == r) s.route = null;
    }
    if (r.overlapLocked) unlockOverlap(r);
    for (final point in layout.points) {
      point.locks.removeWhere((lock) => lock.route == r);
    }
    r.state = '';
  }
}

Interlocking readInterlocking(Layout layout) {
  final i = Interlocking(layout);
  List<Requirement> requirements(String text) => [
    for (final item in nameList(text)) parseRequirement(item, layout),
  ];
  for (final line in readLines('input/routes.txt')) {
    final a = line.split(' '),
        r = Route(
          a[1],
          layout.signalByName[a[2]]!,
          a[3],
          requirements(a[4]),
          [for (final s in nameList(a[5])) layout.sectionByName[s]!],
          [for (final s in nameList(a[6])) layout.sectionByName[s]!],
          requirements(a[7]),
          nameList(a[8]),
          number(a[9]),
        );
    i.routes.add(r);
    i.byName[r.name] = r;
  }
  for (final r in i.routes) {
    r.conflicts.addAll([for (final name in r.conflictNames) i.byName[name]!]);
  }
  return i;
}

Requirement parseRequirement(String text, Layout layout) {
  final parts = text.split(':');
  return Requirement(layout.pointByName[parts[0]]!, parts[1]);
}
