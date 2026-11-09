import 'dart:io';
import 'dart:math';
part 'layout.dart';
part 'interlocking.dart';
part 'signals.dart';
part 'trains.dart';
part 'safety.dart';

class Event {
  final int time;
  final String kind;
  final List<String> args;
  Event(this.time, this.kind, this.args);
}

class Request {
  final int number, time;
  final Route route;
  String lastReason = '';
  Request(this.number, this.time, this.route);
}

int number(String s) => int.parse(s);
List<String> readLines(String path) => File(path).readAsLinesSync();

class Simulator {
  final Layout layout;
  final Interlocking interlocking;
  final List<Train> trains;
  final List<TrainRequest> trainRequests;
  final List<Event> events = [];
  List<Request> queue = [];
  int time = 0;
  final int end, throwTime, overlapTime;
  final Set<int> snapshotsAt;
  final List<String> log = [], snapshots = [];
  final safety = Safety();
  int requestCount = 0, granted = 0, dropped = 0;
  Simulator(
    this.layout,
    this.interlocking,
    this.trains,
    this.trainRequests,
    this.end,
    this.throwTime,
    this.overlapTime,
    this.snapshotsAt,
  );
  void write(String text) {
    log.add('$time $text');
  }

  void startThrow(Point p, String target) {
    p.moving = true;
    p.target = target;
    p.completion = time + throwTime;
    write('MOVE ${p.name} $target until ${p.completion}');
  }

  void addRequest(Route route, String requester) {
    requestCount++;
    route.requests++;
    queue.add(Request(requestCount, time, route));
    write('REQUEST q$requestCount ${route.name} $requester');
  }

  void cancel(Route route) {
    final remaining = <Request>[];
    var found = false;
    for (final request in queue) {
      if (request.route == route) {
        found = true;
        dropped++;
        write('DROP q${request.number} ${route.name}');
      } else {
        remaining.add(request);
      }
    }
    if (found) {
      queue = remaining;
      return;
    }
    if (route.state == 'LOCKED') {
      route.cancels++;
      if (route.start.aspect != 'RED' && route.start.section.occupied) {
        route.state = 'APPROACH';
        route.releaseTime = time + route.approach;
        write('CANCEL ${route.name} approach until ${route.releaseTime}');
      } else {
        interlocking.release(route);
        write('CANCEL ${route.name} released');
      }
    } else {
      write('CANCEL ${route.name} ${route.state.isEmpty ? 'none' : 'refused'}');
    }
  }

  void event(Event e) {
    final a = e.args;
    switch (e.kind) {
      case 'REQUEST':
        addRequest(interlocking.byName[a[0]]!, 'OPERATOR');
        break;
      case 'CANCEL':
        cancel(interlocking.byName[a[0]]!);
        break;
      case 'THROW':
        final p = layout.pointByName[a[0]]!,
            target = a[1],
            result = p.locks.isNotEmpty
                ? 'locked'
                : p.failed
                ? 'failed'
                : p.moving
                ? 'moving'
                : p.common.occupied
                ? 'occupied'
                : p.position == target
                ? 'none'
                : 'start';
        write('THROW ${p.name} $target $result');
        if (result == 'start') startThrow(p, target);
        break;
      case 'TCFAIL':
      case 'TCFIX':
        final section = layout.sectionByName[a[0]]!;
        section.failed = e.kind == 'TCFAIL';
        write('${e.kind} ${section.name}');
        break;
      case 'POINTFAIL':
        final p = layout.pointByName[a[0]]!;
        p.failed = true;
        if (p.moving) p.completion = -1;
        write('POINTFAIL ${p.name}');
        break;
      case 'POINTFIX':
        final p = layout.pointByName[a[0]]!;
        p.failed = false;
        write('POINTFIX ${p.name}');
        if (p.moving) {
          p.completion = time + throwTime;
          write('MOVE ${p.name} ${p.target} until ${p.completion}');
        }
        break;
    }
  }

  String reason(Route route) {
    if (route.state.isNotEmpty) return 'busy';
    for (final other in route.conflicts) {
      if (other.state == 'LOCKED' || other.state == 'APPROACH')
        return 'conflict ${other.name}';
    }
    bool oppositeOverlap(Section section) =>
        section.overlaps.any((other) => other.direction != route.direction);
    for (final section in route.sections) {
      if (section.occupied) return 'occupied ${section.name}';
      if (section.route != null || oppositeOverlap(section))
        return 'locked ${section.name}';
    }
    for (final section in route.overlap) {
      if (section.occupied) return 'occupied ${section.name}';
      final owner = section.route;
      if (owner != null && owner.direction != route.direction ||
          oppositeOverlap(section))
        return 'locked ${section.name}';
    }
    for (final requirement in route.requirements()) {
      final p = requirement.point, target = requirement.position;
      if (p.locks.any((lock) => lock.position != target))
        return 'point ${p.name} locked';
      if (!p.moving && p.position == target || p.moving && p.target == target)
        continue;
      if (p.failed) return 'point ${p.name} failed';
      if (p.moving) return 'point ${p.name} moving';
      if (p.common.occupied) return 'point ${p.name} occupied';
    }
    return '';
  }

  void requests() {
    final remaining = <Request>[];
    for (final request in queue) {
      final route = request.route, reason = this.reason(route);
      if (reason.isNotEmpty) {
        if (reason != request.lastReason) {
          write('WAIT q${request.number} ${route.name} $reason');
          request.lastReason = reason;
        }
        remaining.add(request);
        continue;
      }
      interlocking.lock(route);
      final wait = time - request.time;
      route.grants++;
      route.wait += wait;
      route.maxwait = max(route.maxwait, wait);
      granted++;
      write('GRANT q${request.number} ${route.name} wait $wait');
      for (final requirement in route.requirements()) {
        final p = requirement.point;
        if (!p.moving && p.position != requirement.position)
          startThrow(p, requirement.position);
      }
    }
    queue = remaining;
  }

  int limit(Train train) {
    if (train.crossed) return -1;
    final head = train.headSection();
    var section = head.section,
        distance = head.start + head.section.length - train.head;
    while (true) {
      final signal = layout.signalAt['${section.name}:${train.direction}'];
      if (signal != null && signal.aspect == 'RED') return distance;
      if (train.stop?.section == section) return distance;
      final next = layout.beyond(section, train.direction);
      switch (next.kind) {
        case 'boundary':
          return -1;
        case 'buffer':
        case 'impassable':
          return distance;
        case 'section':
          section = next.section!;
          distance += section.length;
          break;
      }
    }
  }

  void pass(Train train, Signal signal) {
    Route? route;
    for (final r in interlocking.routes) {
      if (r.start == signal && (r.state == 'LOCKED' || r.state == 'APPROACH')) {
        route = r;
        break;
      }
    }
    write(
      'PASS ${train.name} ${signal.name} ${signal.aspect} ${route?.name ?? '-'}',
    );
    signal.passes++;
    train.passes++;
    if (route != null) {
      route.state = 'USED';
      route.uses++;
    }
    safety.signalPassing(time, train, signal);
    if (signal.aspect == 'RED') {
      write('SPAD ${train.name} ${signal.name}');
      train.emergency = true;
    }
  }

  void runTrain(Train train, Set<Boundary> entered) {
    if (train.state == 'EXITED') return;
    if (train.state == 'WAITING') {
      if (time < train.scheduledEntry ||
          train.entry.section.occupied ||
          entered.contains(train.entry))
        return;
      entered.add(train.entry);
      train.state = 'RUNNING';
      train.direction = train.entry.end == 'R' ? 'DOWN' : 'UP';
      train.path = [PathSection(train.entry.section, 0)];
      train.head = 0;
      train.speed = train.entrySpeed;
      train.actualEntry = time;
      write('ENTER ${train.name} ${train.entry.name}');
    }
    if (train.dwelling) {
      final stop = train.stop!;
      if (time < stop.arrival + stop.dwell || time < stop.scheduledDeparture)
        return;
      train.dwelling = false;
      train.awaitDeparture = stop;
      train.nextStop++;
      if (stop.kind == 'TURN') {
        final head = train.headSection(),
            end = head.start + head.section.length,
            occupied = train.occupiedSections();
        train.path = [
          for (final section in occupied.reversed)
            PathSection(
              section.section,
              end - (section.start + section.section.length),
            ),
        ];
        train.head = end - (train.head - train.length);
        train.direction = train.direction == 'UP' ? 'DOWN' : 'UP';
        write('REVERSE ${train.name} ${stop.section.name}');
      }
    }
    final oldSpeed = train.speed, speed = selectSpeed(train, limit(train));
    var remaining = speed, current = train.headSection();
    while (remaining > 0) {
      if (train.crossed) {
        train.head += remaining;
        break;
      }
      final end = current.start + current.section.length;
      if (train.head + remaining <= end) {
        train.head += remaining;
        break;
      }
      remaining -= end - train.head;
      train.head = end;
      final signal =
          layout.signalAt['${current.section.name}:${train.direction}'];
      if (signal != null) pass(train, signal);
      final stop = train.awaitDeparture;
      if (stop != null && stop.section == current.section) {
        stop.departure = time;
        train.awaitDeparture = null;
        write('DEPART ${train.name} ${stop.section.name}');
      }
      final next = layout.beyond(current.section, train.direction);
      if (next.kind == 'boundary') {
        train.crossed = true;
        train.boundaryCoordinate = end;
      } else if (next.kind == 'section') {
        current = PathSection(next.section!, end);
        train.path.add(current);
      } else {
        throw StateError('impassable movement');
      }
    }
    train.speed = speed;
    train.distance += speed;
    train.recordedMax = max(train.recordedMax, speed);
    if (speed == 0) train.emergency = false;
    var arrived = false;
    final stop = train.stop;
    if (stop != null && speed == 0) {
      final head = train.headSection();
      if (head.section == stop.section &&
          train.head == head.start + head.section.length) {
        train.dwelling = true;
        stop.arrival = time;
        arrived = true;
        write('ARRIVE ${train.name} ${stop.section.name}');
      }
    }
    if (speed == 0 && !arrived) {
      train.standing++;
      if (oldSpeed > 0)
        write('HOLD ${train.name} ${train.headSection().section.name}');
    }
    if (train.crossed &&
        train.head - train.length >= train.boundaryCoordinate) {
      train.state = 'EXITED';
      train.actualExit = time;
      write('EXIT ${train.name} ${train.exit.name}');
    }
  }

  void occupancy() {
    for (final section in layout.sections) {
      section.occupants.clear();
    }
    for (final train in trains) {
      if (train.state != 'RUNNING') continue;
      for (final part in train.occupiedSections()) {
        part.section.occupants.add(train);
      }
    }
  }

  void sectionalRelease() {
    for (final route in interlocking.routes) {
      if (route.state != 'USED') continue;
      for (final section in route.sections) {
        if (section.route == route && section.occupied)
          route.passed.add(section);
      }
      for (final section in route.sections) {
        if (section.route != route) continue;
        if (!route.passed.contains(section) || section.occupied) break;
        interlocking.unlockSection(route, section);
        write('RELEASE ${route.name} ${section.name}');
      }
      final remaining = route.sections.any((section) => section.route == route);
      if (!remaining) {
        interlocking.release(route);
        write('DONE ${route.name}');
      } else if (route.overlap.isNotEmpty && route.overlapLocked) {
        route.overlapCounter = route.sections.last.occupied
            ? route.overlapCounter + 1
            : 0;
        if (route.overlapCounter >= overlapTime) {
          interlocking.unlockOverlap(route);
          write('OVERLAP ${route.name}');
        }
      }
    }
  }

  void statistics() {
    for (final route in interlocking.routes) {
      if (route.state.isNotEmpty) route.lockedTicks++;
    }
    for (final point in layout.points) {
      if (point.locks.isNotEmpty) point.lockedTicks++;
      if (point.moving) point.movingTicks++;
    }
    for (final section in layout.sections) {
      if (section.occupied) section.occupiedTicks++;
      if (section.route != null || section.overlaps.isNotEmpty)
        section.lockedTicks++;
      section.trains.addAll(section.occupants);
    }
    for (final signal in layout.signals) {
      switch (signal.aspect) {
        case 'RED':
          signal.red++;
          break;
        case 'YELLOW':
          signal.yellow++;
          break;
        case 'GREEN':
          signal.green++;
          break;
      }
    }
  }

  void snapshot() {
    final l = layout,
        grid = List.generate(
          layout.height,
          (_) => List.filled(layout.width, ' '),
        );
    for (final label in l.labels) {
      for (var i = 0; i < label.text.length; i++) {
        grid[label.row][label.col + i] = label.text[i];
      }
    }
    for (final section in l.sections) {
      final character = section.failed
          ? '#'
          : section.route != null
          ? '='
          : section.overlaps.isNotEmpty
          ? '~'
          : '-';
      for (var col = section.first; col <= section.last; col++) {
        grid[section.row][col] = character;
      }
    }
    for (final train in trains) {
      if (train.state != 'RUNNING') continue;
      for (final part in train.occupiedSections()) {
        final section = part.section,
            lo = max(train.head - train.length, part.start),
            hi = min(train.head, part.start + section.length);
        var p = lo - part.start, q = hi - part.start;
        if (train.direction == 'DOWN') {
          p = section.length - (hi - part.start);
          q = section.length - (lo - part.start);
        }
        final width = section.last - section.first + 1;
        for (var j = 0; j < width; j++) {
          if (p * width < (j + 1) * section.length &&
              q * width > j * section.length) {
            final old = grid[section.row][section.first + j],
                code = old.codeUnitAt(0);
            grid[section.row][section.first + j] =
                code >= 97 && code <= 122 || old == '*' ? '*' : train.symbol;
          }
        }
      }
    }
    for (final buffer in l.buffers) {
      grid[buffer.row][buffer.col] = '|';
    }
    for (final point in l.points) {
      grid[point.row][point.col] = point.detected ? point.position : '?';
    }
    for (final signal in l.signals) {
      grid[signal.row][signal.col] = signal.aspect == 'RED'
          ? 'X'
          : signal.aspect == 'YELLOW'
          ? 'Y'
          : 'G';
    }
    snapshots.add('SNAPSHOT $time');
    snapshots.addAll(grid.map((row) => row.join().trimRight()));
    for (final train in trains) {
      if (train.state != 'RUNNING') continue;
      final names = train
          .occupiedSections()
          .map((part) => part.section.name)
          .join(',');
      snapshots.add(
        'TRAIN ${train.symbol} ${train.name} ${train.direction} ${train.speed}${names.isEmpty ? '' : ' $names'}',
      );
    }
    final routes = [
      for (final route in interlocking.routes)
        if (route.state.isNotEmpty) '${route.name}/${route.state}',
    ];
    snapshots.add('ROUTES ${routes.isEmpty ? '-' : routes.join(' ')}');
  }

  void run() {
    var eventIndex = 0;
    for (time = 0; time <= end; time++) {
      for (final point in layout.points) {
        if (point.moving && point.completion == time) {
          point.position = point.target;
          point.moving = false;
          point.throws++;
          write('POINT ${point.name} ${point.position}');
        }
      }
      for (final route in interlocking.routes) {
        if (route.state == 'APPROACH' && route.releaseTime == time) {
          interlocking.release(route);
          write('TIMEOUT ${route.name}');
        }
      }
      for (final request in trainRequests) {
        if (request.time == time) addRequest(request.route, request.train.name);
      }
      while (eventIndex < events.length && events[eventIndex].time == time) {
        event(events[eventIndex++]);
      }
      requests();
      final aspects = signalAspects(layout, interlocking.routes);
      for (final signal in layout.signals) {
        if (aspects[signal] != signal.aspect) {
          signal.aspect = aspects[signal]!;
          write('SIGNAL ${signal.name} ${signal.aspect}');
        }
      }
      final entered = <Boundary>{};
      for (final train in trains) {
        runTrain(train, entered);
      }
      occupancy();
      sectionalRelease();
      safety.check(time, layout, interlocking.routes);
      statistics();
      if (snapshotsAt.contains(time)) snapshot();
    }
  }

  (List<String>, List<String>) reports() {
    final csv = ['train,location,scheduled,actual,delay'];
    var onTime = 0, late = 0, missing = 0, totalDelay = 0, maxDelay = 0;
    void add(String name, String location, int scheduled, int actual) {
      if (actual < 0) {
        missing++;
        csv.add('$name,$location,$scheduled,-,-');
        return;
      }
      final delay = actual - scheduled;
      if (delay <= 0) {
        onTime++;
      } else {
        late++;
        totalDelay += delay;
        maxDelay = max(maxDelay, delay);
      }
      csv.add('$name,$location,$scheduled,$actual,$delay');
    }

    for (final train in trains) {
      add(
        train.name,
        'enter:${train.entry.name}',
        train.scheduledEntry,
        train.actualEntry,
      );
      for (final stop in train.stops) {
        add(
          train.name,
          'arr:${stop.section.name}',
          stop.scheduledArrival,
          stop.arrival,
        );
        add(
          train.name,
          'dep:${stop.section.name}',
          stop.scheduledDeparture,
          stop.departure,
        );
      }
      add(
        train.name,
        'exit:${train.exit.name}',
        train.scheduledExit,
        train.actualExit,
      );
    }
    final out = <String>[];
    for (final route in interlocking.routes) {
      out.add(
        'ROUTE ${route.name} ${route.start.name}-${route.finish} requests ${route.requests} grants ${route.grants} uses ${route.uses} cancels ${route.cancels} wait ${route.wait} maxwait ${route.maxwait} locked ${route.lockedTicks}',
      );
    }
    for (final point in layout.points) {
      out.add(
        'POINT ${point.name} throws ${point.throws} locked ${point.lockedTicks} moving ${point.movingTicks} final ${point.detected ? point.position : '?'}',
      );
    }
    for (final section in layout.sections) {
      out.add(
        'SECTION ${section.name} occupied ${section.occupiedTicks} locked ${section.lockedTicks} trains ${section.trains.length}',
      );
    }
    for (final signal in layout.signals) {
      out.add(
        'SIGNAL ${signal.name} red ${signal.red} yellow ${signal.yellow} green ${signal.green} passes ${signal.passes}',
      );
    }
    var exited = 0, running = 0, waiting = 0;
    for (final train in trains) {
      out.add(
        'TRAIN ${train.name} ${train.symbol} ${train.state} distance ${train.distance} maxspeed ${train.recordedMax} standing ${train.standing} passes ${train.passes}',
      );
      switch (train.state) {
        case 'EXITED':
          exited++;
          break;
        case 'RUNNING':
          running++;
          break;
        default:
          waiting++;
      }
    }
    out.addAll([
      'TRAINS total ${trains.length} exited $exited running $running waiting $waiting',
      'PUNCTUALITY on_time $onTime late $late missing $missing total_delay $totalDelay max_delay $maxDelay',
      'REQUESTS total $requestCount granted $granted dropped $dropped pending ${queue.length}',
    ]);
    return (csv, out);
  }
}

void writeLines(String name, List<String> lines) {
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

void main() {
  final layout = readLayout(), interlocking = readInterlocking(layout);
  final (trains, requests) = readTrains(layout, interlocking);
  final p = readLines('input/params.txt'),
      s = Simulator(
        layout,
        interlocking,
        trains,
        requests,
        number(p[0].split(' ')[1]),
        number(p[1].split(' ')[1]),
        number(p[2].split(' ')[1]),
        {for (final t in p[3].split(' ').skip(1)) number(t)},
      );
  for (final line in readLines('input/events.txt')) {
    final a = line.split(' ');
    s.events.add(Event(number(a[0]), a[1], a.sublist(2)));
  }
  s.run();
  final (csv, summary) = s.reports();
  Directory('output').createSync(recursive: true);
  writeLines('events.txt', s.log);
  writeLines('snapshots.txt', s.snapshots);
  writeLines('train_log.csv', csv);
  writeLines('safety.txt', s.safety.lines());
  writeLines('summary.txt', summary);
}
