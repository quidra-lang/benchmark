part of 'main.dart';

const properties = ['OCCUPANCY', 'POINT_MOTION', 'CONFLICT', 'SIGNAL_PASSING'];

class Safety {
  final checks = List.filled(4, 0), violations = List.filled(4, 0);
  final List<String> records = [];
  void violation(int time, int property, String details) {
    violations[property]++;
    records.add('VIOLATION $time ${properties[property]} $details');
  }

  void signalPassing(int time, Train train, Signal signal) {
    checks[3]++;
    if (signal.aspect == 'RED')
      violation(time, 3, '${train.name} ${signal.name}');
  }

  void check(int time, Layout layout, List<Route> routes) {
    for (final section in layout.sections) {
      checks[0]++;
      if (section.occupants.length >= 2)
        violation(
          time,
          0,
          '${section.name} ${section.occupants.map((t) => t.name).join(',')}',
        );
    }
    for (final point in layout.points) {
      if (!point.moving) continue;
      checks[1]++;
      if (point.common.occupants.isNotEmpty) {
        violation(time, 1, '${point.name} occupied');
      } else if (point.locks.any(
        (lock) => lock.route.state == 'USED' || lock.route.state == 'APPROACH',
      )) {
        violation(time, 1, '${point.name} locked');
      }
    }
    bool active(Route r) => r.state == 'LOCKED' || r.state == 'APPROACH';
    for (var i = 0; i < routes.length; i++) {
      final a = routes[i];
      if (!active(a)) continue;
      for (final b in routes.skip(i + 1)) {
        if (!active(b)) continue;
        checks[2]++;
        if (a.conflicts.contains(b) || b.conflicts.contains(a))
          violation(time, 2, '${a.name} ${b.name}');
      }
    }
  }

  List<String> lines() => [
    for (var i = 0; i < 4; i++)
      '${properties[i]} ${violations[i] == 0 ? 'OK' : 'FAIL'} checks ${checks[i]} violations ${violations[i]}',
    ...records,
    violations.any((n) => n > 0) ? 'RESULT UNSAFE' : 'RESULT SAFE',
  ];
}
