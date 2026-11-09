import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'minstd.dart';
import 'road.dart';
import 'vehicles.dart';
import 'signals.dart';
import 'stats.dart';

String timeText(int step) => step.toString().padLeft(4, '0');
String flagText(bool value) => value ? 'Y' : 'N';
class Rational {
  final int numerator, denominator;
  Rational(int numerator, [int denominator = 1]) : numerator = numerator ~/ numerator.gcd(denominator), denominator = denominator ~/ numerator.gcd(denominator);
  Rational multiply(int n, int d) => Rational(numerator * n, denominator * d);
  Rational add(Rational other) => Rational(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator);
  String text() => '$numerator/$denominator';
}
class Source {
  final String node;
  final List<(int, int)> rates;
  final Segment segment;
  final queue = Queue<Vehicle>();
  int queueStart = 0, queueMax = 0;
  Source(this.node, this.rates, this.segment);
  int rate(int step) { for (final (rate, end) in rates) { if (step <= end) return rate; } return 0; }
}
class Detector {
  final String name;
  final Segment segment;
  final int cell, width;
  Detector(this.name, this.segment, this.cell, this.width);
  bool covers(int position) => cell <= position && position < cell + width;
}
class Diagram {
  final Segment segment;
  final int lane, start, end;
  final lines = <String>[];
  Diagram(this.segment, this.lane, this.start, this.end);
}
class Ring {
  final int number, length, vmax, warmup, measure, seed;
  final List<int> counts;
  Ring(this.number, List<int> values) : length = values[0], vmax = values[1], warmup = values[2], measure = values[3], seed = values[4], counts = values.sublist(5);
}
class Interval {
  int arrivals = 0, insertions = 0, exits = 0, vehicleSteps = 0, speedSum = 0;
  final List<int> passing, occupancy, occupancySpeed;
  Interval(int count) : passing = List.filled(count, 0), occupancy = List.filled(count, 0), occupancySpeed = List.filled(count, 0);
}
class Move {
  final Vehicle vehicle;
  final Segment segment;
  final int cell;
  int speed = 0;
  Move(this.vehicle) : segment = vehicle.segment!, cell = vehicle.cell;
}
int runRing(Ring ring, int count, int dawdle, int dawdleStopped) {
  final rng = Minstd(ring.seed), positions = List.generate(count, (j) => j * ring.length ~/ count); var speeds = List.filled(count, 0), total = 0;
  for (var step = 1; step <= ring.warmup + ring.measure; step++) {
    final order = List.generate(count, (j) => j)..sort((a, b) => positions[b].compareTo(positions[a])); final next = List.filled(count, 0);
    for (var rank = 0; rank < count; rank++) { final j = order[rank], ahead = order[rank == 0 ? count - 1 : rank - 1]; final gap = (positions[ahead] - positions[j] - 1) % ring.length; next[j] = randomSlowdown(min(min(speeds[j] + 1, ring.vmax), gap), speeds[j], rng.draw(), dawdle, dawdleStopped); }
    for (var j = 0; j < count; j++) { positions[j] = (positions[j] + next[j]) % ring.length; } speeds = next;
    if (step > ring.warmup) { for (final speed in next) { total += speed; } }
  }
  return total;
}
class Simulation {
  final segments = <Segment>[], byId = <String, Segment>{}, junctions = <Junction>[], incidents = <Incident>[], stops = <BusStop>[], classes = <VehicleClass>[], sources = <Source>[], sinks = <String>[];
  final detectors = <Detector>[], diagrams = <Diagram>[], rings = <Ring>[], vehicles = <Vehicle>[], intervals = <Interval>[], events = <String>[], tracks = <int, List<String>>{};
  List<int> trackNumbers = [];
  int seed = 1, steps = 0, dawdle = 0, dawdleStopped = 0, intervalLength = 1, binWidth = 1;
  late final Minstd rng;
  Simulation() {
    for (final file in ['network.txt', 'demand.txt', 'params.txt']) {
      for (final line in File('input/$file').readAsLinesSync()) {
        final tokens = line.split(' '); final kind = tokens.first, p = tokens.sublist(1);
        switch (kind) {
          case 'SEGMENT': { final s = Segment(p[0], p[1], p[2], int.parse(p[3]), int.parse(p[4]), int.parse(p[5])); segments.add(s); byId[p[0]] = s; break; }
          case 'JUNCTION': { final junction = Junction(p[0], int.parse(p[1]), p.sublist(2)); for (final s in segments) { if (s.end == p[0]) { s.junction = junction; junction.incoming.add(s); } } junctions.add(junction); break; }
          case 'INCIDENT': incidents.add(Incident(byId[p[0]]!, int.parse(p[1]), int.parse(p[2]), int.parse(p[3]), int.parse(p[4]))); break;
          case 'STOP': { final s = byId[p[0]]!; final stop = BusStop(s, int.parse(p[1]), int.parse(p[2])); s.stop = stop; stops.add(stop); break; }
          case 'CLASS': classes.add(VehicleClass(p[0], int.parse(p[1]), int.parse(p[2]), p[3] == 'Y', p[4] == 'Y')); break;
          case 'SOURCE': { final rates = <(int, int)>[]; for (final period in p.skip(1)) { final parts = period.split(':'); rates.add((int.parse(parts[0]), int.parse(parts[1]))); } sources.add(Source(p[0], rates, segments.firstWhere((s) => s.start == p[0]))); break; }
          case 'SINK': sinks.add(p[0]); break;
          case 'TURN': byId[p[0]]!.turns.add(Turn(byId[p[1]]!, int.parse(p[2]))); break;
          case 'seed': seed = int.parse(p[0]); break;
          case 'steps': steps = int.parse(p[0]); break;
          case 'dawdle': dawdle = int.parse(p[0]); dawdleStopped = int.parse(p[1]); break;
          case 'interval': intervalLength = int.parse(p[0]); break;
          case 'bin': binWidth = int.parse(p[0]); break;
          case 'detector': detectors.add(Detector(p[0], byId[p[1]]!, int.parse(p[2]), int.parse(p[3]))); break;
          case 'diagram': diagrams.add(Diagram(byId[p[0]]!, int.parse(p[1]), int.parse(p[2]), int.parse(p[3]))); break;
          case 'track': trackNumbers = p.map(int.parse).toList(); for (final number in trackNumbers) { tracks[number] = []; } break;
          case 'ring': rings.add(Ring(rings.length + 1, p.map(int.parse).toList())); break;
        }
      }
    }
    rng = Minstd(seed);
  }
  void record(int step, String event) => events.add('${timeText(step)} $event');
  Interval get interval => intervals.last;
  bool green(Segment s, int step) => s.junction!.green(s.id, step);
  List<Vehicle> vehiclesOn(Segment s) => [for (var lane = 1; lane <= s.lanes; lane++) for (final number in s.vehicleNumbers(lane)) vehicles[number - 1]];
  void enter(Vehicle vehicle, Segment s) { vehicle.route.add(s.id); s.entered++; vehicle.turn = s.junction == null ? null : s.turns[selectWeighted(s.turns.map((turn) => turn.weight).toList(), rng.draw())]; }
  void updateIncidents(int step) { for (final incident in incidents) { final event = incident.update(step); if (event != null) record(step, '$event ${incident.segment.id} lane ${incident.lane} cell ${incident.cell}'); } }
  void arrive(int step) {
    final weights = classes.map((kind) => kind.weight).toList();
    for (final source in sources) { if (rng.draw() % 1000 < source.rate(step)) { final kind = classes[selectWeighted(weights, rng.draw())]; final vehicle = Vehicle(vehicles.length + 1, kind, source.node, step); vehicles.add(vehicle); source.queue.addLast(vehicle); interval.arrivals++; } }
  }
  int? entryLane(Segment s) {
    int? best; var first = -1;
    for (var lane = 1; lane <= s.lanes; lane++) { if (s.empty(lane, 0) && s.first(lane) > first) { best = lane; first = s.first(lane); } } return best;
  }
  void insert(int step) {
    for (final source in sources) {
      while (source.queue.isNotEmpty) { final lane = entryLane(source.segment); if (lane == null) break; final vehicle = source.queue.removeFirst(); vehicle.place(source.segment, lane, 0); vehicle.inserted = step; enter(vehicle, source.segment); interval.insertions++; }
      if (source.queue.isNotEmpty && source.queueStart == 0) { source.queueStart = step; source.queueMax = 0; }
      if (source.queueStart != 0) { source.queueMax = max(source.queueMax, source.queue.length); if (source.queue.isEmpty) { record(step, 'QUEUE ${source.node} from ${source.queueStart} max ${source.queueMax}'); source.queueStart = 0; } }
    }
  }
  (int, String?) desiredLane(Vehicle v) {
    final s = v.segment!, lane = v.lane, cell = v.cell, top = v.maxSpeed(); final here = s.free(lane, cell, top + 1), want = min(v.speed + 1, top); final ahead = cell + here + 1;
    if (here < top + 1 && ahead < s.length && s.obstacle(lane, ahead)) { for (final target in [lane + 1, lane - 1]) { if (1 <= target && target <= s.lanes && s.free(target, cell, top + 1) > here && s.safe(target, cell)) return (target, 'avoidance'); } }
    if (v.headingForStop()) return lane >= 2 && s.safe(lane - 1, cell) ? (lane - 1, 'return') : (lane, null);
    if (v.kind.overtakes && lane + 1 <= s.lanes && here < want && s.free(lane + 1, cell, top + 1) > here && s.safe(lane + 1, cell)) return (lane + 1, 'overtaking');
    if (lane >= 2 && s.free(lane - 1, cell, top + 1) > want && s.safe(lane - 1, cell)) return (lane - 1, 'return'); return (lane, null);
  }
  void changeLanes() {
    final changes = <(Vehicle, int, String)>[];
    for (final s in segments) {
      if (s.lanes < 2) continue; final reserved = <(int, int)>{};
      for (var lane = 1; lane <= s.lanes; lane++) { for (final number in s.vehicleNumbers(lane)) { final v = vehicles[number - 1]; if (v.dwell > 0) continue; final (target, kind) = desiredLane(v); if (target != lane && reserved.add((target, v.cell))) changes.add((v, target, kind!)); } }
    }
    for (final (v, target, kind) in changes) { final s = v.segment!; v.place(s, target, v.cell); v.laneChanges++; s.changes[kind] = s.changes[kind]! + 1; }
  }
  List<Move> processingOrder() => [for (final s in segments) for (var lane = 1; lane <= s.lanes; lane++) for (final number in s.vehicleNumbers(lane).reversed) Move(vehicles[number - 1])];
  int determineSpeed(Vehicle v, int step) {
    final s = v.segment!, lane = v.lane, cell = v.cell, accelerated = min(v.speed + 1, v.maxSpeed()); var gap = s.free(lane, cell, accelerated);
    if (gap < accelerated && cell + gap == s.length - 1) { if (s.junction == null) { gap = accelerated; } else if (green(s, step)) { final target = v.turn!.target; gap += target.free(min(lane, target.lanes), -1, accelerated - gap); } }
    if (v.headingForStop()) gap = min(gap, s.stop!.cell - cell); var speed = randomSlowdown(min(accelerated, gap), v.speed, rng.draw(), dawdle, dawdleStopped);
    if (v.dwell > 0) { speed = 0; v.dwell--; } return speed;
  }
  List<Move> moveVehicles(List<Move> moves, int step) {
    final passing = <Move>[];
    for (final move in moves) { final v = move.vehicle, s = move.segment; if (move.cell + move.speed < s.length) { v.place(s, v.lane, move.cell + move.speed); } else if (s.junction == null) { v.leave(); v.exited = step; v.sink = s.end; interval.exits++; } else { passing.add(move); } } return passing;
  }
  void passJunctions(List<Move> passing) {
    for (final move in passing) {
      final v = move.vehicle, s = move.segment, turn = move.vehicle.turn!, target = move.vehicle.turn!.target; final lane = min(v.lane, target.lanes), overshoot = move.cell + move.speed - s.length;
      final cell = min(overshoot, target.first(lane) - 1); if (cell < overshoot) s.blocked++;
      if (cell >= 0) { v.place(target, lane, cell); move.speed = s.length - move.cell + cell; s.passed++; turn.vehicles++; enter(v, target); }
      else { v.place(s, v.lane, s.length - 1); move.speed = s.length - 1 - move.cell; }
    }
  }
  String trackLine(Vehicle v, int step) => '${timeText(step)}${v.segment == null ? ' EXIT ${v.speed}' : ' ${v.segment!.id} ${v.lane} ${v.cell} ${v.speed}'}';
  void aggregateVehicle(Move move, int step) {
    final v = move.vehicle, speed = move.speed; v.steps++; v.distance += speed; if (speed == 0) { v.stoppedSteps++; if (v.speed > 0) v.stopCount++; } v.speed = speed; interval.vehicleSteps++; interval.speedSum += speed;
    if (v.headingForStop() && v.lane == 1 && v.cell == v.segment!.stop!.cell) { final stop = v.segment!.stop!; v.completedStops.add(v.segment!.id); v.dwell = stop.dwell; stop.buses++; record(step, 'BUS_STOP ${v.number} ${v.segment!.id} cell ${stop.cell}'); }
    if (tracks.containsKey(v.number)) tracks[v.number]!.add(trackLine(v, step));
    for (var j = 0; j < detectors.length; j++) { final detector = detectors[j]; if (move.segment == detector.segment && move.cell < detector.cell && (v.segment != detector.segment || v.cell >= detector.cell)) interval.passing[j]++; }
  }
  String signalText(Segment s, int step) => s.junction == null ? 'E' : green(s, step) ? 'G' : 'R';
  void aggregateState(int step) {
    for (var j = 0; j < detectors.length; j++) { final detector = detectors[j]; for (final v in vehiclesOn(detector.segment)) { if (detector.covers(v.cell)) { interval.occupancy[j]++; interval.occupancySpeed[j] += v.speed; } } }
    for (final s in segments) {
      final present = vehiclesOn(s); s.vehicleSum += present.length; for (final v in present) { s.speedSum += v.speed; } s.maxVehicles = max(s.maxVehicles, present.length);
      if (s.junction == null) continue; final isGreen = green(s, step), queued = present.where((v) => v.speed == 0).length;
      if (isGreen) s.greenSteps++; s.queueSum += queued; s.maxQueue = max(s.maxQueue, queued); if (step < steps && queued > 0 && isGreen && !green(s, step + 1)) s.failures++;
    }
    for (final diagram in diagrams) { if (diagram.start <= step && step <= diagram.end) diagram.lines.add('${timeText(step)} ${diagram.segment.cellsText(diagram.lane, vehicles)} ${signalText(diagram.segment, step)}'); }
  }
  void run() {
    for (var step = 1; step <= steps; step++) { updateIncidents(step); if ((step - 1) % intervalLength == 0) intervals.add(Interval(detectors.length)); arrive(step); insert(step); changeLanes(); final moves = processingOrder(); for (final move in moves) { move.speed = determineSpeed(move.vehicle, step); } passJunctions(moveVehicles(moves, step)); for (final move in moves) { aggregateVehicle(move, step); } aggregateState(step); }
    for (final source in sources) { if (source.queueStart != 0) record(steps, 'QUEUE ${source.node} from ${source.queueStart} max ${source.queueMax} open'); }
  }
  List<(List<String>, Rational)> enumerateRoutes(Segment s) {
    if (s.junction == null) return [([s.id], Rational(1))]; var total = 0; for (final turn in s.turns) { total += turn.weight; }
    return [for (final turn in s.turns) for (final (route, share) in enumerateRoutes(turn.target)) ([s.id, ...route], share.multiply(turn.weight, total))];
  }
  List<String> spacetimeLines() => [for (final diagram in diagrams) ...['DIAGRAM ${diagram.segment.id} lane ${diagram.lane} steps ${diagram.start}-${diagram.end}', ...diagram.lines]];
  List<String> detectorLines() {
    final lines = ['detector,interval,flow,density,speed'];
    for (var j = 0; j < detectors.length; j++) { final detector = detectors[j]; final capacity = intervalLength * detector.width * detector.segment.lanes;
      for (var k = 0; k < intervals.length; k++) { final v = intervals[k]; lines.add('${detector.name},${k + 1},${v.passing[j]},${dec(v.occupancy[j], capacity, 4)},${dec(v.occupancySpeed[j], v.occupancy[j], 2)}'); }
    } return lines;
  }
  List<String> travelBlock(String heading, List<Vehicle> group) {
    final times = group.map((v) => v.travelTime()).toList()..sort(); if (times.isEmpty) return ['$heading exited 0']; var total = 0; for (final time in times) { total += time; }
    return ['$heading exited ${times.length} min ${times.first} p50 ${percentile(times, 50)} p90 ${percentile(times, 90)} max ${times.last} mean ${dec(total, times.length, 2)}', ...histogramLines(times, binWidth)];
  }
  String outcomeText(List<Vehicle> group, int exited) { var total = 0; for (final v in group) { total += v.travelTime(); } return 'vehicles ${group.length} share ${frac(group.length, exited)} mean ${dec(total, group.length, 2)}'; }
  bool sameRoute(List<String> first, List<String> second) { if (first.length != second.length) return false; for (var j = 0; j < first.length; j++) { if (first[j] != second[j]) return false; } return true; }
  List<String> sourceLines(Source source, List<Vehicle> exited) {
    final group = exited.where((v) => v.source == source.node).toList(), routes = enumerateRoutes(source.segment); final lines = ['SOURCE ${source.node} exited ${group.length}'];
    for (final (route, share) in routes) { final matched = group.where((v) => sameRoute(v.route, route)).toList(); lines.add('  ROUTE ${route.join(',')} expected ${share.text()} ${outcomeText(matched, group.length)}'); }
    for (final sink in sinks) {
      var share = Rational(0), found = false; for (final (route, expected) in routes) { if (byId[route.last]!.end == sink) { share = share.add(expected); found = true; } }
      if (!found) continue; lines.add('  SINK $sink expected ${share.text()} ${outcomeText(group.where((v) => v.sink == sink).toList(), group.length)}');
    } return lines;
  }
  List<String> travelTimeLines() {
    final exited = vehicles.where((v) => v.exited != null).toList();
    return [for (final kind in classes) ...travelBlock('CLASS ${kind.name}', exited.where((v) => identical(v.kind, kind)).toList()), ...travelBlock('ALL', exited), for (final source in sources) ...sourceLines(source, exited)];
  }
  List<String> classBlock(String heading, List<Vehicle> group) {
    var inserted = 0, steps = 0, distance = 0, travel = 0, delay = 0, stopped = 0, stops = 0, changes = 0; final exited = <Vehicle>[];
    for (final v in group) { if (v.inserted != null) inserted++; if (v.exited != null) exited.add(v); steps += v.steps; distance += v.distance; }
    for (final v in exited) { travel += v.travelTime(); delay += v.inserted! - v.arrival; stopped += v.stoppedSteps; stops += v.stopCount; changes += v.laneChanges; } final count = exited.length;
    return [heading, '  generated ${group.length} inserted $inserted exited $count in_network ${inserted - count} queued ${group.length - inserted}', '  vehicle_steps $steps distance $distance mean_speed ${frac(distance, steps)} = ${dec(distance, steps, 3)}', '  travel ${dec(travel, count, 2)} entry_delay ${dec(delay, count, 2)} stopped ${dec(stopped, count, 2)} stops ${dec(stops, count, 2)} lane_changes ${dec(changes, count, 2)}'];
  }
  List<String> classStatsLines() => [for (final kind in classes) ...classBlock('CLASS ${kind.name} vmax ${kind.vmax} weight ${kind.weight} overtake ${flagText(kind.overtakes)} stops ${flagText(kind.stops)}', vehicles.where((v) => identical(v.kind, kind)).toList()), ...classBlock('ALL', vehicles)];
  List<String> networkStatsLines() {
    final lines = <String>[];
    for (final s in segments) { lines.add('SEGMENT ${s.id} ${s.start} ${s.end} length ${s.length} lanes ${s.lanes} limit ${s.limit} entered ${s.entered} mean_vehicles ${dec(s.vehicleSum, steps, 3)} density ${dec(s.vehicleSum, steps * s.length * s.lanes, 4)} mean_speed ${dec(s.speedSum, s.vehicleSum, 2)} max_vehicles ${s.maxVehicles} changes ${s.changes.values.join('/')}'); }
    for (final junction in junctions) { lines.addAll(junction.planLines()); for (final s in junction.incoming) { lines.add('  IN ${s.id} green ${s.greenSteps} passed ${s.passed} blocked ${s.blocked} max_queue ${s.maxQueue} mean_queue ${dec(s.queueSum, steps, 3)} failures ${s.failures}'); for (final turn in s.turns) { lines.add('    TURN ${turn.target.id} weight ${turn.weight} vehicles ${turn.vehicles}'); } } }
    for (final stop in stops) { lines.add('STOP ${stop.segment.id} cell ${stop.cell} dwell ${stop.dwell} buses ${stop.buses}'); }
    for (final incident in incidents) { lines.add('INCIDENT ${incident.segment.id} lane ${incident.lane} cell ${incident.cell} planned ${incident.start}-${incident.end} active ${incident.activeStart == null ? 'none' : '${incident.activeStart}-${incident.activeEnd}'}'); } return lines;
  }
  List<String> timelineLines() {
    final lines = ['interval,arrived,inserted,exited,in_network,queued,mean_speed']; var arrived = 0, inserted = 0, exited = 0;
    for (var j = 0; j < intervals.length; j++) { final v = intervals[j]; arrived += v.arrivals; inserted += v.insertions; exited += v.exits; lines.add('${j + 1},${v.arrivals},${v.insertions},${v.exits},${inserted - exited},${arrived - inserted},${dec(v.speedSum, v.vehicleSteps, 2)}'); } return lines;
  }
  List<String> trackLines() {
    final lines = <String>[];
    for (final number in trackNumbers) { if (number > vehicles.length) { lines.add('VEHICLE $number none'); continue; } final v = vehicles[number - 1]; lines.add('VEHICLE $number class ${v.kind.name} source ${v.source} arrival ${v.arrival} inserted ${v.inserted ?? '-'} exited ${v.exited ?? '-'} sink ${v.sink ?? '-'}'); lines.add('ROUTE ${v.route.isEmpty ? '-' : v.route.join(' ')}'); lines.addAll(tracks[number]!); } return lines;
  }
  List<String> fundamentalLines() {
    final lines = ['ring,vehicles,density,flow,speed']; for (final ring in rings) { for (final count in ring.counts) { final total = runRing(ring, count, dawdle, dawdleStopped); lines.add('${ring.number},$count,${dec(count, ring.length, 4)},${dec(total, ring.length * ring.measure, 4)},${dec(total, count * ring.measure, 3)}'); } } return lines;
  }
  void write() {
    Directory('output').createSync(recursive: true); final outputs = {'spacetime.txt': spacetimeLines(), 'detectors.csv': detectorLines(), 'travel_times.txt': travelTimeLines(), 'class_stats.txt': classStatsLines(), 'network_stats.txt': networkStatsLines(), 'timeline.csv': timelineLines(), 'tracks.txt': trackLines(), 'fundamental.csv': fundamentalLines(), 'events.txt': events};
    for (final entry in outputs.entries) { File('output/${entry.key}').writeAsStringSync(entry.value.isEmpty ? '' : '${entry.value.join('\n')}\n'); }
  }
}

void main() { final simulation = Simulation(); simulation.run(); simulation.write(); }
