import 'dart:io';
import 'dart:math' as math;

class Station {
  final String id, name;
  final int zone;
  int transfer = 0;
  bool closed = false;
  final Map<String, int> walks = {};
  Station(this.id, this.zone, this.name);
}
class Line {
  final String id;
  final int first, last, headway;
  final List<String> stops;
  final List<int> offsets;
  int delay = 0;
  bool suspended = false;
  Line(this.id, this.first, this.last, this.headway, this.stops, this.offsets);
}
class Direction {
  final Line line;
  final int order;
  final List<String> stops;
  final List<int> offsets;
  Direction(this.line, this.order, this.stops, this.offsets);
}
sealed class Leg {
  final int departure, arrival;
  Leg(this.departure, this.arrival);
}
class Ride extends Leg {
  final String line, terminal, from, to;
  final int stops;
  Ride(this.line, this.terminal, this.from, int departure, this.to,
      int arrival, this.stops) : super(departure, arrival);
}
class Walk extends Leg {
  final String from, to;
  Walk(this.from, int departure, this.to, int arrival) : super(departure, arrival);
}
class Stay extends Leg {
  final String station;
  Stay(this.station, int departure, int arrival) : super(departure, arrival);
}
class Label {
  final int time;
  final List<Leg> journey;
  Label(this.time, this.journey);
}
class Tariff {
  final int discount, window;
  final List<int> prices;
  Tariff(this.discount, this.window, this.prices);
}
class Event {
  final int time, order;
  final String line, terminal, start;
  Event(this.time, this.line, this.order, this.terminal, this.start);
}
class MetroError implements Exception {
  final String message;
  MetroError(this.message);
}
final stations = <String, Station>{};
final lines = <String, Line>{};
final closed = <String>{};
final output = <String>[];
Tariff? tariff;
Never fail(String message) => throw MetroError('ERROR $message');
int time(String word) {
  final parts = word.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}
String clock(int value) => '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
String pair(String a, String b) => a.compareTo(b) < 0 ? '$a-$b' : '$b-$a';
Station station(String id) {
  final result = stations[id];
  if (result == null) fail('unknown station $id');
  return result;
}
Line line(String id) {
  final result = lines[id];
  if (result == null) fail('unknown line $id');
  return result;
}
void openStation(String id) {
  if (stations[id]!.closed) fail('station $id is closed');
}
void common(String origin, String destination) {
  station(origin);
  station(destination);
  if (origin == destination) fail('origin and destination are the same');
  openStation(origin);
  openStation(destination);
}
List<Line> orderedLines() => lines.values.toList()..sort((a, b) => a.id.compareTo(b.id));
List<Direction> directions(Line item) {
  final total = item.offsets.last;
  return [Direction(item, 0, item.stops, item.offsets),
    Direction(item, 1, item.stops.reversed.toList(),
        item.offsets.reversed.map((offset) => total - offset).toList())];
}
int trips(Line item) => (item.last - item.first) ~/ item.headway + 1;
int? nextTrain(Direction direction, int at, int ready) {
  final item = direction.line;
  final q = math.max(0, ((ready - item.first - item.delay - direction.offsets[at]) / item.headway).ceil());
  return q < trips(item) ? q : null;
}
int trainTime(Direction direction, int q, int at) =>
    direction.line.first + direction.line.delay + q * direction.line.headway + direction.offsets[at];
Ride ride(Direction direction, int boarding, int alighting, int q) =>
    Ride(direction.line.id, direction.stops.last, direction.stops[boarding],
        trainTime(direction, q, boarding), direction.stops[alighting],
        trainTime(direction, q, alighting), alighting - boarding);
bool update(Map<String, Label> labels, String id, Label candidate) {
  final old = labels[id];
  if (old == null || old.time > candidate.time) {
    labels[id] = candidate;
    return true;
  }
  return false;
}
Map<String, Label> earliest(String origin, int departure) {
  final labels = <String, Label>{origin: Label(departure, [])};
  final settled = <String>{}, service = orderedLines();
  while (true) {
    final choices = labels.keys.where((id) => !settled.contains(id)).toList();
    if (choices.isEmpty) return labels;
    choices.sort((a, b) {
      final order = labels[a]!.time.compareTo(labels[b]!.time);
      return order == 0 ? a.compareTo(b) : order;
    });
    final u = choices.first, label = labels[choices.first]!, s = stations[choices.first]!;
    settled.add(u);
    final ready = label.time + (u == origin ? 0 : s.transfer);
    for (final item in service) {
      if (item.suspended || !item.stops.contains(u)) continue;
      for (final direction in directions(item)) {
        final i = direction.stops.indexOf(u), last = direction.stops.length - 1;
        if (i == last) continue;
        final q = nextTrain(direction, i, ready);
        if (q == null) continue;
        for (var j = i + 1; j <= last; j++) {
          final v = direction.stops[j];
          if (closed.contains(pair(direction.stops[j - 1], v))) break;
          if (stations[v]!.closed) continue;
          final leg = ride(direction, i, j, q);
          update(labels, v, Label(leg.arrival, [...label.journey, leg]));
        }
      }
    }
    for (final v in s.walks.keys.toList()..sort()) {
      final arrival = label.time + s.walks[v]!;
      if (!stations[v]!.closed && arrival <= 1440) {
        final leg = Walk(u, label.time, v, arrival);
        update(labels, v, Label(arrival, [...label.journey, leg]));
      }
    }
  }
}
void walkStep(Map<String, Label> labels, Set<String> sources, Set<String> marked) {
  final recorded = <String, Label>{for (final id in sources) id: labels[id]!};
  for (final u in sources.toList()..sort()) {
    final label = recorded[u]!, s = stations[u]!;
    for (final v in s.walks.keys.toList()..sort()) {
      final arrival = label.time + s.walks[v]!;
      if (stations[v]!.closed || arrival > 1440) continue;
      final leg = Walk(u, label.time, v, arrival);
      if (update(labels, v, Label(arrival, [...label.journey, leg]))) marked.add(v);
    }
  }
}
List<Map<String, Label>> rounds(String origin, int departure) {
  var labels = <String, Label>{origin: Label(departure, [])};
  var marked = <String>{origin};
  walkStep(labels, {origin}, marked);
  final result = <Map<String, Label>>[labels], service = orderedLines();
  while (marked.isNotEmpty) {
    final previous = labels, previousMarked = marked;
    labels = Map.of(previous);
    marked = {};
    final walking = <String>{};
    for (final item in service) {
      if (item.suspended) continue;
      for (final direction in directions(item)) {
        int? boarded;
        var boarding = 0;
        var journey = <Leg>[];
        for (var j = 0; j < direction.stops.length; j++) {
          final v = direction.stops[j];
          if (j > 0 && closed.contains(pair(direction.stops[j - 1], v))) boarded = null;
          if (stations[v]!.closed) continue;
          if (boarded != null) {
            final leg = ride(direction, boarding, j, boarded);
            if (update(labels, v, Label(leg.arrival, [...journey, leg]))) {
              walking.add(v);
              marked.add(v);
            }
          }
          if (j + 1 < direction.stops.length && previousMarked.contains(v)) {
            final old = previous[v]!;
            final ready = old.time + (v == origin ? 0 : stations[v]!.transfer);
            final q = nextTrain(direction, j, ready);
            if (q != null && (boarded == null || q < boarded)) {
              boarded = q;
              boarding = j;
              journey = old.journey;
            }
          }
        }
      }
    }
    walkStep(labels, walking, marked);
    result.add(labels);
  }
  return result;
}
void printJourney(String heading, int departure, Label label) {
  final rides = label.journey.whereType<Ride>().length, walks = label.journey.whereType<Walk>().length;
  output.add('$heading ${clock(departure)} -> ${clock(label.time)} total ${label.time - departure} rides $rides walks $walks');
  var previous = departure;
  for (final leg in label.journey) {
    if (leg is Ride) {
      output.add('RIDE ${leg.line} toward ${leg.terminal} ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)} wait ${leg.departure - previous} stops ${leg.stops}');
    } else if (leg is Walk) {
      output.add('WALK ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)}');
    } else if (leg is Stay) {
      output.add('STAY ${leg.station} ${clock(leg.departure)} -> ${clock(leg.arrival)}');
    }
    previous = leg.arrival;
  }
}
void printFare(String origin, String destination, String word, String fareClass, Label label) {
  final tickets = <String>[];
  var total = 0;
  Ride? previous;
  int half(int value) => ((value + 19) ~/ 20) * 10;
  for (final leg in label.journey.whereType<Ride>()) {
    final item = lines[leg.line]!;
    final direction = directions(item).firstWhere((d) => d.stops.last == leg.terminal);
    final start = direction.stops.indexOf(leg.from), end = direction.stops.indexOf(leg.to);
    final zones = direction.stops.sublist(start, end + 1).map((id) => stations[id]!.zone).toSet().length;
    final base = tariff!.prices[math.min(zones, tariff!.prices.length) - 1];
    final price = fareClass == 'CHILD' ? half(base) : base;
    final cap = fareClass == 'CHILD' ? half(tariff!.discount) : tariff!.discount;
    final discount = previous != null && leg.departure - previous.arrival <= tariff!.window ? math.min(cap, price) : 0;
    final payment = price - discount;
    total += payment;
    tickets.add('TICKET ${leg.line} ${leg.from} ${leg.to} zones $zones price $price discount $discount pay $payment');
    previous = leg;
  }
  output.add('FARE $origin $destination $word $fareClass rides ${tickets.length} total $total');
  output.addAll(tickets);
}
void execute(String commandLine) {
  final words = commandLine.split(' '), command = words.first, args = words.skip(1).toList();
  final a = args.isEmpty ? '' : args[0], b = args.length < 2 ? '' : args[1];
  switch (command) {
    case 'STATION':
      if (stations.containsKey(a)) fail('station $a already exists');
      stations[a] = Station(a, int.parse(b), args[2]);
      output.add('STATION $a zone $b ${args[2]}');
    case 'LINE':
      if (lines.containsKey(a)) fail('line $a already exists');
      final stops = <String>[], offsets = <int>[0];
      for (var i = 4; i < args.length; i += 2) { stops.add(args[i]); }
      for (final id in stops) { station(id); }
      final seen = <String>{};
      for (final id in stops) {
        if (!seen.add(id)) fail('station $id appears twice on line $a');
      }
      for (var i = 5; i < args.length; i += 2) { offsets.add(offsets.last + int.parse(args[i])); }
      final first = time(b), last = time(args[2]), headway = int.parse(args[3]), total = offsets.last;
      if (first > last) fail('line $a first departure is after last departure');
      if (last + total > 1440) fail('line $a runs past 24:00');
      final item = Line(a, first, last, headway, stops, offsets);
      lines[a] = item;
      output.add('LINE $a stops ${stops.length} time $total trips ${trips(item)}');
    case 'TRANSFER':
      station(a).transfer = int.parse(b);
      output.add('TRANSFER $a $b');
    case 'WALK':
      final x = station(a), y = station(b), duration = int.parse(args[2]);
      if (a == b) fail('walk from $a to itself');
      final old = x.walks[b];
      x.walks[b] = duration;
      y.walks[a] = duration;
      output.add('WALK $a $b $duration${old == null ? '' : ' was $old'}');
    case 'TARIFF':
      final prices = args.skip(2).map(int.parse).toList();
      for (var i = 1; i < prices.length; i++) {
        if (prices[i] < prices[i - 1]) fail('tariff prices must not decrease');
      }
      tariff = Tariff(int.parse(a), int.parse(b), prices);
      output.add('TARIFF zones ${prices.length} discount $a window $b');
    case 'CLOSE':
    case 'OPEN':
      final s = station(a), closing = command == 'CLOSE';
      if (args.length == 1) {
        if (s.closed == closing) fail('station $a is ${closing ? 'already closed' : 'not closed'}');
        s.closed = closing;
        output.add('$command $a');
      } else {
        station(b);
        final key = pair(a, b);
        final affected = orderedLines().where((item) {
          for (var i = 1; i < item.stops.length; i++) {
            if (pair(item.stops[i - 1], item.stops[i]) == key) return true;
          }
          return false;
        }).toList();
        if (closing && affected.isEmpty) fail('no segment $a-$b');
        if (closed.contains(key) == closing) fail('segment $a-$b is ${closing ? 'already closed' : 'not closed'}');
        if (closing) { closed.add(key); } else { closed.remove(key); }
        output.add('$command $a-$b${closing ? ' lines ${affected.map((item) => item.id).join(' ')}' : ''}');
      }
    case 'DELAY':
      final item = line(a), delay = int.parse(b);
      if (item.last + delay + item.offsets.last > 1440) fail('line $a runs past 24:00');
      item.delay = delay;
      output.add('DELAY $a $delay');
    case 'SUSPEND':
    case 'RESUME':
      final item = line(a), suspended = command == 'SUSPEND';
      if (item.suspended == suspended) fail('line $a is ${suspended ? 'already suspended' : 'not suspended'}');
      item.suspended = suspended;
      output.add('$command $a');
    case 'ROUTE':
    case 'FEWEST':
    case 'PARETO':
    case 'FARE':
    case 'LASTTRAIN':
    case 'ARRIVEBY':
    case 'PROFILE':
      common(a, b);
      if (command == 'FARE') {
        if (args[3] != 'ADULT' && args[3] != 'CHILD') fail('unknown fare class ${args[3]}');
        if (tariff == null) fail('no tariff');
      }
      if (command == 'PROFILE' && time(args[2]) > time(args[3])) fail('empty interval ${args[2]} ${args[3]}');
      if (command == 'LASTTRAIN' || command == 'ARRIVEBY') {
        final deadline = command == 'LASTTRAIN' ? 1440 : time(args[2]);
        final heading = '$command $a $b${command == 'ARRIVEBY' ? ' by ${args[2]}' : ''}';
        var found = false;
        for (var departure = deadline - 1; departure >= 0; departure--) {
          final label = earliest(a, departure)[b];
          if (label != null && label.time <= deadline) {
            printJourney(heading, departure, label);
            found = true;
            break;
          }
        }
        if (!found) output.add('$heading none');
      } else if (command == 'PROFILE') {
        final start = time(args[2]), end = time(args[3]), arrivals = <int?>[];
        for (var departure = start; departure <= end; departure++) {
          arrivals.add(earliest(a, departure)[b]?.time);
        }
        final selected = <int>[];
        for (var i = 0; i < arrivals.length; i++) {
          if (arrivals[i] != null && (i == arrivals.length - 1 || arrivals[i + 1] == null || arrivals[i]! < arrivals[i + 1]!)) selected.add(i);
        }
        output.add('PROFILE $a $b ${args[2]} ${args[3]} count ${selected.length}');
        for (final i in selected) {
          output.add('${clock(start + i)} -> ${clock(arrivals[i]!)} total ${arrivals[i]! - start - i}');
        }
      } else if (command == 'FEWEST' || command == 'PARETO') {
        final departure = time(args[2]), all = rounds(a, departure);
        if (command == 'FEWEST') {
          final k = all.indexWhere((labels) => labels.containsKey(b));
          if (k < 0) {
            output.add('FEWEST $a $b ${args[2]} unreachable');
          } else {
            printJourney('FEWEST $a $b trips $k', departure, all[k][b]!);
          }
        } else {
          final selected = <int>[];
          for (var k = 0; k < all.length; k++) {
            if (all[k].containsKey(b) && (k == 0 || !all[k - 1].containsKey(b) || all[k - 1][b]!.time > all[k][b]!.time)) selected.add(k);
          }
          output.add('PARETO $a $b ${args[2]} options ${selected.length}');
          for (final k in selected) {
            printJourney('OPTION trips $k', departure, all[k][b]!);
          }
        }
      } else {
        final departure = time(args[2]), label = earliest(a, departure)[b];
        if (label == null) {
          output.add('$command $a $b ${args[2]}${command == 'FARE' ? ' ${args[3]}' : ''} unreachable');
        } else if (command == 'FARE') {
          printFare(a, b, args[2], args[3], label);
        } else {
          printJourney('ROUTE $a $b', departure, label);
        }
      }
    case 'VIA':
      final via = b, destination = args[2];
      station(a);
      station(via);
      station(destination);
      if (a == destination) fail('origin and destination are the same');
      if (via == a || via == destination) fail('via station $via must differ from origin and destination');
      openStation(a);
      openStation(via);
      openStation(destination);
      final departure = time(args[3]), first = earliest(a, departure)[via];
      final ready = first == null ? 0 : first.time + stations[via]!.transfer;
      final second = first == null ? null : earliest(via, ready)[destination];
      if (first == null || second == null) {
        output.add('VIA $a $via $destination ${args[3]} unreachable');
      } else {
        final stay = Stay(via, first.time, ready);
        printJourney('VIA $a $via $destination', departure,
            Label(second.time, [...first.journey, stay, ...second.journey]));
      }
    case 'REACH':
      station(a);
      openStation(a);
      final departure = time(b), labels = earliest(a, departure), limit = departure + int.parse(args[2]);
      final reached = labels.keys.where((id) => labels[id]!.time <= limit).toList();
      reached.sort((x, y) {
        final order = labels[x]!.time.compareTo(labels[y]!.time);
        return order == 0 ? x.compareTo(y) : order;
      });
      output.add('REACH $a $b ${args[2]} count ${reached.length}');
      for (final id in reached) {
        final label = labels[id]!;
        output.add('$id ${stations[id]!.name} ${clock(label.time)} ${label.time - departure} rides ${label.journey.whereType<Ride>().length}');
      }
    case 'TIMETABLE':
      final s = station(a), item = line(b), toward = args[2];
      if (!item.stops.contains(a)) fail('station $a is not on line $b');
      if (toward != item.stops.first && toward != item.stops.last) fail('$toward is not a terminal of line $b');
      if (a == toward) fail('no departures from $a toward $toward');
      if (item.suspended) fail('line $b is suspended');
      if (s.closed) fail('station $a is closed');
      final direction = directions(item).firstWhere((d) => d.stops.last == toward);
      final at = direction.stops.indexOf(a), q = nextTrain(direction, direction.stops.indexOf(a), time(args[3]));
      final times = <String>[];
      if (q != null) {
        for (var i = q; i < trips(item) && times.length < int.parse(args[4]); i++) {
          times.add(clock(trainTime(direction, i, at)));
        }
      }
      output.add('TIMETABLE $a $b toward $toward ${args[3]} next ${times.length}${times.isEmpty ? '' : ' ${times.join(' ')}'}');
    case 'DEPARTURES':
    case 'ARRIVALS':
      station(a);
      openStation(a);
      final events = <Event>[];
      for (final item in orderedLines()) {
        if (item.suspended || !item.stops.contains(a)) continue;
        for (final direction in directions(item)) {
          final at = direction.stops.indexOf(a), last = direction.stops.length - 1;
          if (command == 'DEPARTURES' ? at == last : at == 0) continue;
          final q = nextTrain(direction, at, time(b));
          if (q != null) {
            for (var i = q; i < trips(item); i++) {
              events.add(Event(trainTime(direction, i, at), item.id,
                  direction.order, direction.stops.last, direction.stops.first));
            }
          }
        }
      }
      events.sort((x, y) {
        var order = x.time.compareTo(y.time);
        if (order == 0) order = x.line.compareTo(y.line);
        return order == 0 ? x.order.compareTo(y.order) : order;
      });
      final selected = events.take(int.parse(args[2])).toList();
      output.add('$command $a $b count ${selected.length}');
      for (final event in selected) {
        output.add('${clock(event.time)} ${event.line} ${command == 'DEPARTURES' ? 'toward ${event.terminal}' : 'from ${event.start}'}');
      }
    case 'TRIP':
      final item = line(a);
      if (b != item.stops.first && b != item.stops.last) fail('$b is not a terminal of line $a');
      if (item.suspended) fail('line $a is suspended');
      final direction = directions(item).firstWhere((d) => d.stops.last == b);
      final q = nextTrain(direction, 0, time(args[2]));
      if (q == null) {
        output.add('TRIP $a toward $b ${args[2]} none');
      } else {
        output.add('TRIP $a toward $b ${args[2]} trip ${q + 1} departs ${clock(trainTime(direction, q, 0))}');
        for (var j = 0; j < direction.stops.length; j++) {
          final id = direction.stops[j];
          output.add('${clock(trainTime(direction, q, j))} $id${stations[id]!.closed ? ' closed' : ''}${j > 0 && closed.contains(pair(direction.stops[j - 1], id)) ? ' blocked' : ''}');
        }
      }
    case 'SHOWLINE':
      final item = line(a);
      output.add('SHOWLINE $a ${item.suspended ? 'suspended' : 'running'} first ${clock(item.first)} last ${clock(item.last)} headway ${item.headway} delay ${item.delay} trips ${trips(item)}');
      for (var i = 0; i < item.stops.length; i++) {
        final id = item.stops[i];
        output.add('${item.offsets[i]} $id zone ${stations[id]!.zone}${stations[id]!.closed ? ' closed' : ''}${i > 0 && closed.contains(pair(item.stops[i - 1], id)) ? ' blocked' : ''}');
      }
    case 'INFO':
      final s = station(a), service = orderedLines().where((item) => item.stops.contains(a)).toList();
      final neighbors = s.walks.keys.toList()..sort();
      output.add('INFO $a ${s.name} zone ${s.zone} transfer ${s.transfer} ${s.closed ? 'closed' : 'open'}');
      output.add('LINES ${service.isEmpty ? 'none' : service.map((item) => item.id).join(' ')}');
      output.add('WALKS ${neighbors.isEmpty ? 'none' : neighbors.map((id) => '$id ${s.walks[id]}').join(' ')}');
    case 'STATUS':
      final walkCount = stations.values.fold<int>(0, (sum, s) => sum + s.walks.length) ~/ 2;
      output.add('STATUS stations ${stations.length} lines ${lines.length} walks $walkCount');
      for (final id in stations.keys.toList()..sort()) {
        if (stations[id]!.closed) output.add('CLOSED $id');
      }
      final segments = closed.toList()..sort((x, y) {
        final a = x.split('-'), b = y.split('-');
        final order = a[0].compareTo(b[0]);
        return order == 0 ? a[1].compareTo(b[1]) : order;
      });
      for (final segment in segments) { output.add('CLOSED $segment'); }
      for (final item in orderedLines()) {
        if (item.suspended) output.add('SUSPENDED ${item.id}');
      }
      for (final item in orderedLines()) {
        if (item.delay != 0) output.add('DELAYED ${item.id} ${item.delay}');
      }
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try {
      execute(stdin.readLineSync()!);
    } on MetroError catch (error) {
      output.add(error.message);
    }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
