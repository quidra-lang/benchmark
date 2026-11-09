import 'dart:io';
import 'dart:math';
const policies = ['COST', 'NEAREST', 'ROUND', 'ETA'];
const keys = ['FLOORS', 'CARS', 'CAPACITY', 'DOOR', 'START', 'POLICY', 'ZONES', 'PARK', 'PATIENCE', 'BYPASS', 'PERIOD', 'LIMIT', 'COMPARE'];
const argumentCounts = {
  'CALL': 3, 'CANCEL': 1, 'OUT': 1, 'IN': 1, 'HOLD': 2, 'FIRE': 1, 'RESET': 0, 'WHERE': 1, 'STATUS': 0
};
class Invalid implements Exception {
  final String message;
  Invalid(this.message);
}
void requireThat(bool ok, String message) {
  if (!ok) throw Invalid(message);
}
String joined(Iterable<Object> items) {
  final xs = items.toList();
  return xs.isEmpty ? '-' : xs.join(',');
}
String avg(int total, int count) {
  if (count == 0) return '-';
  final n = total * 100 ~/ count;
  return '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
}
int bound(String key, String text, int low, int high) {
  final n = int.parse(text);
  requireThat(n >= low && n <= high, 'bad value for $key');
  return n;
}
class Config {
  int floors = 0, cars = 0, capacity = 0, door = 0, park = -1, patience = -1, bypass = 100, period = -1, limit = 1000;
  List<int> starts = [], homes = [], low = [], high = [];
  String policy = 'COST';
  List<String> compare = [];
  Config(List<List<String>> lines) {
    final entries = <String, List<String>>{
    };
    for (final a in lines) {
      final k = a[0];
      requireThat(keys.contains(k), 'unknown key $k');
      requireThat(!entries.containsKey(k), 'duplicate key $k');
      entries[k] = a.sublist(1);
    }
    for (final k in keys.take(5)) {
      requireThat(entries.containsKey(k), 'missing key $k');
    }
    for (final k in keys) {
      final v = entries[k];
      if (v == null) continue;
      final n = v.length;
      requireThat(k == 'START' || k == 'ZONES' ? n == cars : k == 'PARK' ? n == cars + 1 : k == 'COMPARE' ? n >= 1 && n <= 4 : n == 1, 'wrong number of values for $k');
      switch (k) {
        case 'FLOORS': {
          floors = bound(k, v[0], 2, 50);
        }
        case 'CARS': {
          cars = bound(k, v[0], 1, 8);
        }
        case 'CAPACITY': {
          capacity = bound(k, v[0], 1, 20);
        }
        case 'DOOR': {
          door = bound(k, v[0], 1, 9);
        }
        case 'START': {
          starts = v.map((x) => bound(k, x, 1, floors)).toList();
        }
        case 'POLICY': {
          requireThat(policies.contains(v[0]), 'bad value for $k');
          policy = v[0];
        }
        case 'ZONES': {
          for (final text in v) {
            final z = text.split(':').map(int.parse).toList();
            requireThat(z[0] >= 1 && z[0] < z[1] && z[1] <= floors, 'bad value for $k');
            low.add(z[0]);
            high.add(z[1]);
          }
        }
        case 'PARK': {
          park = bound(k, v[0], 0, 100);
          homes = v.skip(1).map((x) => bound(k, x, 1, floors)).toList();
        }
        case 'PATIENCE': {
          patience = bound(k, v[0], 1, 1000);
        }
        case 'BYPASS': {
          bypass = bound(k, v[0], 50, 100);
        }
        case 'PERIOD': {
          period = bound(k, v[0], 1, 1000);
        }
        case 'LIMIT': {
          limit = bound(k, v[0], 1, 5000);
        }
        case 'COMPARE': {
          requireThat(v.every(policies.contains) && v.toSet().length == v.length, 'bad value for $k');
          compare = v;
        }
      }
    }
    if (low.isEmpty) {
      low = List.filled(cars, 1);
      high = List.filled(cars, floors);
    }
    for (int i = 0; i < cars; i++) {
      requireThat(starts[i] >= low[i] && starts[i] <= high[i], 'car ${i + 1} starts outside its zone');
      requireThat(park < 0 || homes[i] >= low[i] && homes[i] <= high[i], 'car ${i + 1} home outside its zone');
    }
  }
  bool serves(int i, int a, int b) => low[i] <= a && a <= high[i] && low[i] <= b && b <= high[i];
  void header(List<String> out) {
    out.add('config: floors=$floors cars=$cars capacity=$capacity door=$door policy=$policy park=${park < 0 ? 'off' : park} patience=${patience < 0 ? 'off' : patience} bypass=$bypass period=${period < 0 ? 'off' : period} limit=$limit compare=${joined(compare)}');
    for (int i = 0; i < cars; i++) {
      out.add('E${i + 1}: start=${starts[i]} zone=${low[i]}-${high[i]} home=${park < 0 ? '-' : homes[i]}');
    }
  }
}
class Raw {
  final int line;
  final List<String> words;
  Raw(this.line, this.words);
}
class Event {
  final int time;
  final String command;
  final List<int> values;
  Event(this.time, this.command, this.values);
}
List<Event> validate(Config c, List<Raw> raw, List<String> out) {
  final events = <Event>[], gone = <int>{
  };
  int last = 0, groups = 0;
  bool fire = false;
  for (final r in raw) {
    final a = r.words, t = int.parse(r.words[0]), cmd = r.words[1];
    String? problem;
    List<int> v = [];
    if (!argumentCounts.containsKey(cmd)) {
      problem = 'unknown command $cmd';
    }
    else if (a.length - 2 != argumentCounts[cmd]) {
      problem = 'wrong number of arguments for $cmd';
    }
    else if (t < last) {
      problem = 'time goes backwards';
    }
    else {
      v = a.skip(2).map(int.parse).toList();
      final x = v.isEmpty ? 0 : v[0];
      switch (cmd) {
        case 'CALL': {
          if (x < 1 || x > c.floors || v[1] < 1 || v[1] > c.floors) {
            problem = 'bad floor';
          }
          else if (x == v[1]) {
            problem = 'same floor';
          }
          else if (v[2] < 1 || v[2] > 99) {
            problem = 'bad count';
          }
          else if (!List.generate(c.cars, (i) => i).any((i) => c.serves(i, x, v[1]))) {
            problem = 'no car serves $x->${v[1]}';
          }
          else if (fire) {
            problem = 'fire service active';
          }
        }
        case 'CANCEL':
        case 'WHERE': {
          if (x < 1 || x > groups) problem = 'unknown group';
        }
        case 'OUT':
        case 'IN': {
          if (x < 1 || x > c.cars) {
            problem = 'bad car';
          }
          else if (cmd == 'OUT' && gone.contains(x)) {
            problem = 'car $x already out';
          }
          else if (cmd == 'IN' && !gone.contains(x)) {
            problem = 'car $x already in';
          }
        }
        case 'HOLD': {
          if (x < 1 || x > c.cars) {
            problem = 'bad car';
          } else if (v[1] < 1 || v[1] > 9) {
            problem = 'bad ticks';
          }
        }
        case 'FIRE': {
          if (x < 1 || x > c.floors) {
            problem = 'bad floor';
          } else if (fire) {
            problem = 'fire already active';
          }
        }
        case 'RESET': {
          if (!fire) problem = 'fire not active';
        }
      }
    }
    if (problem != null) {
      out.add('line ${r.line}: $problem');
      continue;
    }
    last = t;
    switch (cmd) {
      case 'CALL': {
        groups++;
      }
      case 'OUT': {
        gone.add(v[0]);
      }
      case 'IN': {
        gone.remove(v[0]);
      }
      case 'FIRE': {
        fire = true;
      }
      case 'RESET': {
        fire = false;
      }
    }
    events.add(Event(t, cmd, v));
  }
  return events;
}
class Group {
  final int number, landing, destination, count, time;
  int waiting, boarded = 0, delivered = 0, lost = 0, lastBoard = 0, lastAlight = 0, waitTotal = 0, travelTotal = 0;
  Car? car;
  final Set<int> cars = {};
  Group(this.number, this.landing, this.destination, this.count, this.time) : waiting = count;
  String get label => 'G$number';
  int get direction => (destination - landing).sign;
}
class Passenger {
  final Group group;
  final int count, boarded;
  Passenger(this.group, this.count, this.boarded);
}
class Car {
  final int number;
  int floor, direction = 0, door = 0, idleStart = 0, distance = 0, stops = 0, boarded = 0, busy = 0, energy = 0;
  bool service = true;
  final List<Group> calls = [];
  List<Passenger> passengers = [];
  Car(this.number, this.floor);
  String get label => 'E$number';
  int get load => passengers.fold(0, (n, p) => n + p.count);
  Set<int> get targets => {
    ...passengers.map((p) => p.group.destination), ...calls.map((g) => g.landing)
  };
}
class Simulation {
  final Config c;
  final List<Event> events;
  final String policy;
  late final List<Car> cars;
  final List<Group> groups = [], pending = [];
  final List<String> log = [];
  int time = 0, fireFloor = 0, lastRound = 0, abandoned = 0, evacuated = 0, delivered = 0, maxWait = 0, waitTotal = 0, travelTotal = 0;
  String status = '';
  Simulation(this.c, this.events, this.policy) {
    cars = List.generate(c.cars, (i) => Car(i + 1, c.starts[i]));
  }
  void emit(String s) => log.add('$time $s');
  bool bypass(Car e) => e.load * 100 >= c.capacity * c.bypass;
  int cost(Car e, Group g) {
    final f = e.floor, d = e.direction, x = g.landing;
    if (policy == 'NEAREST' || d == 0) return (f - x).abs();
    final targets = e.targets;
    int distance, via;
    if (g.direction == d && (x - f) * d >= 0) {
      distance = (x - f).abs();
      via = targets.where((y) => (y - f) * d > 0 && (x - y) * d > 0).length;
    }
    else {
      int m = f;
      for (final y in targets) {
        m = d > 0 ? max(m, y) : min(m, y);
      }
      distance = (f - m).abs() + (m - x).abs();
      via = targets.where((y) => (y - f) * d > 0).length;
    }
    return policy == 'COST' ? distance : distance + c.door * via + e.door;
  }
  bool assign(Group g, [Car? excluded]) {
    final candidates = cars.where((e) => e.service && e != excluded && c.serves(e.number - 1, g.landing, g.destination)).toList();
    if (candidates.isEmpty) return false;
    Car chosen = candidates.first;
    if (policy == 'ROUND') {
      for (final e in candidates) {
        if (e.number > lastRound) {
          chosen = e;
          break;
        }
      }
      lastRound = chosen.number;
    }
    else {
      for (final e in candidates) {
        if (cost(e, g) < cost(chosen, g)) chosen = e;
      }
    }
    emit('${chosen.label} ASSIGN ${g.label}${policy == 'ROUND' ? '' : ' cost=${cost(chosen, g)}'}');
    g.car?.calls.remove(g);
    chosen.calls.add(g);
    g.car = chosen;
    return true;
  }
  void dispatch(Group g) {
    if (!assign(g)) {
      pending.add(g);
      emit('PENDING ${g.label}');
    }
  }
  void walk(Group g, String word) {
    if (g.car == null) {
      pending.remove(g);
    } else {
      g.car!.calls.remove(g);
      g.car = null;
    }
    emit('$word ${g.label} x${g.waiting}');
    g.lost += g.waiting;
    abandoned += g.waiting;
    g.waiting = 0;
  }
  void event(Event event) {
    final v = event.values, x = event.values.isEmpty ? 0 : event.values[0];
    switch (event.command) {
      case 'CALL': {
        final g = Group(groups.length + 1, x, v[1], v[2], time);
        groups.add(g);
        emit('CALL ${g.label} $x->${v[1]} x${v[2]}');
        dispatch(g);
      }
      case 'CANCEL': {
        final g = groups[x - 1];
        if (g.waiting > 0) {
          walk(g, 'CANCEL');
        } else {
          emit('CANCEL ${g.label} ignored');
        }
      }
      case 'OUT': {
        final e = cars[x - 1];
        e.service = false;
        emit('${e.label} OUT');
        final old = List<Group>.of(e.calls);
        e.calls.clear();
        for (final g in old) {
          g.car = null;
          dispatch(g);
        }
      }
      case 'IN': {
        final e = cars[x - 1];
        e.service = true;
        e.idleStart = time;
        emit('${e.label} IN');
        final old = List<Group>.of(pending);
        pending.clear();
        for (final g in old) {
          if (!assign(g)) pending.add(g);
        }
      }
      case 'HOLD': {
        final e = cars[x - 1];
        if (e.door > 0) {
          e.door += v[1];
          emit('${e.label} HOLD ${e.door}');
        } else {
          emit('${e.label} HOLD ignored');
        }
      }
      case 'FIRE': {
        fireFloor = x;
        emit('FIRE $x');
        for (final g in groups) {
          if (g.waiting > 0) walk(g, 'ABANDON');
        }
      }
      case 'RESET': {
        fireFloor = 0;
        emit('RESET');
        for (final e in cars) {
          e.idleStart = time;
        }
      }
      case 'WHERE': {
        final g = groups[x - 1], riding = <String>[];
        for (final e in cars) {
          final n = e.passengers.where((p) => p.group == g).fold<int>(0, (n, p) => n + p.count);
          if (n > 0) riding.add('${e.label}x$n');
        }
        emit('WHERE ${g.label} waiting=${g.waiting} car=${g.waiting == 0 ? '-' : g.car?.label ?? 'pending'} riding=${joined(riding)} delivered=${g.delivered} lost=${g.lost}');
      }
      case 'STATUS': {
        for (final e in cars) {
          final stops = e.passengers.map((p) => p.group.destination).toSet().toList()..sort();
          emit('STATUS ${e.label} floor=${e.floor} dir=${e.direction == 0 ? 'idle' : e.direction > 0 ? 'up' : 'down'} door=${e.door} load=${e.load} stops=${joined(stops)} calls=${joined(e.calls.map((g) => g.label))} service=${e.service ? 'in' : 'out'}');
        }
        emit('STATUS pending=${joined(pending.map((g) => g.label))}');
      }
    }
  }
  int direction(Car e) {
    final f = e.floor, d = e.direction, here = bypass(e) ? <Group>[] : e.calls.where((g) => g.landing == e.floor).toList(), targets = e.targets;
    if (d != 0 && (targets.any((y) => (y - f) * d > 0) || here.any((g) => g.direction == d))) return d;
    if (here.isNotEmpty) return here.first.direction;
    if (d != 0 && targets.any((y) => (y - f) * d < 0)) return -d;
    if (d == 0 && e.calls.isNotEmpty) return (e.calls.first.landing - f).sign;
    return 0;
  }
  void deliver(Passenger p) {
    final g = p.group, wait = p.boarded - p.group.time, travel = time - p.group.time;
    g.delivered += p.count;
    g.lastAlight = time;
    g.waitTotal += wait * p.count;
    g.travelTotal += travel * p.count;
    delivered += p.count;
    waitTotal += wait * p.count;
    travelTotal += travel * p.count;
    maxWait = max(maxWait, wait);
  }
  void open(Car e) {
    emit('${e.label} OPEN ${e.floor}');
    e.door = c.door;
    e.stops++;
    e.energy += 2;
    final keep = <Passenger>[];
    for (final p in e.passengers) {
      if (p.group.destination == e.floor) {
        emit('${e.label} ALIGHT ${p.group.label} x${p.count}');
        deliver(p);
      }
      else if (fireFloor != 0) {
        emit('${e.label} EVACUATE ${p.group.label} x${p.count}');
        p.group.lost += p.count;
        evacuated += p.count;
      }
      else {
        keep.add(p);
      }
    }
    e.passengers = keep;
    if (fireFloor != 0) return;
    final n = direction(e);
    if (n != 0) e.direction = n;
    final boarding = e.calls.where((g) => g.landing == e.floor && g.direction == n).toList();
    for (final g in boarding) {
      final k = min(c.capacity - e.load, g.waiting);
      if (k > 0) {
        e.passengers.add(Passenger(g, k, time));
        e.boarded += k;
        g.waiting -= k;
        g.boarded += k;
        g.lastBoard = time;
        g.cars.add(e.number);
        emit('${e.label} BOARD ${g.label} x$k');
      }
      if (g.waiting == 0) {
        e.calls.remove(g);
        g.car = null;
      } else {
        emit('${e.label} LEFT ${g.label} x${g.waiting}');
        assign(g, e);
      }
    }
  }
  void move(Car e, int d) {
    e.energy += d > 0 ? 3 + e.load : 1;
    e.distance++;
    e.floor += d;
  }
  void advance(Car e) {
    final old = e.floor;
    if (e.door > 0) e.door--;
    if (e.door == 0) {
      final n = fireFloor == 0 ? direction(e) : (fireFloor - e.floor).sign;
      final stop = fireFloor != 0 ? n == 0 && e.passengers.isNotEmpty : e.passengers.any((p) => p.group.destination == e.floor) || !bypass(e) && e.calls.any((g) => g.landing == e.floor && g.direction == n);
      if (stop) {
        open(e);
      } else if (n != 0) {
        e.direction = n;
        move(e, n);
      }
      else {
        if (e.direction != 0) {
          emit('${e.label} IDLE ${e.floor}');
          e.direction = 0;
          e.idleStart = time;
        }
        if (fireFloor == 0 && e.service && c.park >= 0 && e.floor != c.homes[e.number - 1] && time - e.idleStart >= c.park) {
          move(e, (c.homes[e.number - 1] - e.floor).sign);
          if (e.floor == c.homes[e.number - 1]) emit('${e.label} PARK ${e.floor}');
        }
      }
    }
    if (e.door > 0 || e.floor != old) e.busy++;
  }
  bool settled(Car e) => e.door == 0 && e.passengers.isEmpty && e.calls.isEmpty && (fireFloor != 0 ? e.floor == fireFloor : !e.service || c.park < 0 || e.floor == c.homes[e.number - 1]);
  void run() {
    int index = 0;
    while (true) {
      if (c.patience >= 0) {
        for (final g in groups) {
          if (g.waiting > 0 && time == g.time + c.patience) walk(g, 'ABANDON');
        }
      }
      while (index < events.length && events[index].time == time) {
        event(events[index++]);
      }
      for (final e in cars) {
        advance(e);
      }
      if (index == events.length && cars.every(settled)) {
        status = 'end';
        emit('END');
        return;
      }
      if (time == c.limit) {
        status = 'abort';
        emit('ABORT');
        return;
      }
      time++;
    }
  }
  String get averages => 'avg_wait=${avg(waitTotal, delivered)} avg_travel=${avg(travelTotal, delivered)} max_wait=${delivered == 0 ? '-' : maxWait}';
  String breakdown(String label, List<Group> gs) {
    final passengers = gs.fold<int>(0, (n, g) => n + g.count), n = gs.fold<int>(0, (n, g) => n + g.delivered), wait = gs.fold<int>(0, (n, g) => n + g.waitTotal);
    return '$label: groups=${gs.length} passengers=$passengers delivered=$n avg_wait=${avg(wait, n)}';
  }
  void report(List<String> out) {
    for (final g in groups) {
      final cs = g.cars.toList()..sort();
      out.add('${g.label} t=${g.time} ${g.landing}->${g.destination} n=${g.count} delivered=${g.delivered} lost=${g.lost} wait=${g.boarded == g.count ? g.lastBoard - g.time : '-'} travel=${g.delivered == g.count ? g.lastAlight - g.time : '-'} cars=${joined(cs)}');
    }
    for (final e in cars) {
      final u = e.busy * 1000 ~/ (time + 1);
      out.add('${e.label} distance=${e.distance} stops=${e.stops} boarded=${e.boarded} busy=${e.busy} util=${u ~/ 10}.${u % 10}% energy=${e.energy}');
    }
    final floors = groups.map((g) => g.landing).toSet().toList()..sort();
    for (final f in floors) {
      out.add(breakdown('F$f', groups.where((g) => g.landing == f).toList()));
    }
    if (c.period > 0) {
      final periods = groups.map((g) => g.time ~/ c.period).toSet().toList()..sort();
      for (final p in periods) {
        out.add(breakdown('P$p ${p * c.period}-${p * c.period + c.period - 1}', groups.where((g) => g.time ~/ c.period == p).toList()));
      }
    }
    out.add('summary: groups=${groups.length} passengers=${groups.fold<int>(0, (n, g) => n + g.count)} delivered=$delivered abandoned=$abandoned evacuated=$evacuated $averages end=$time');
  }
}
class Scenario {
  final String name;
  Config? config;
  Simulation? sim;
  Scenario(this.name);
  String get outcome => sim == null ? 'invalid' : sim!.status == 'abort' ? 'aborted' : sim!.delivered == 0 ? 'empty' : 'ranked';
}
void main() {
  final q = int.parse(stdin.readLineSync()!), scenarios = <Scenario>[], out = <String>[];
  int lineNo = 1;
  for (int i = 0; i < q; i++) {
    final s = Scenario(stdin.readLineSync()!.split(' ')[1]);
    lineNo++;
    scenarios.add(s);
    final settings = <List<String>>[], raw = <Raw>[];
    while (true) {
      final line = stdin.readLineSync()!;
      lineNo++;
      if (line == 'END') break;
      final a = line.split(' ');
      if (int.tryParse(a[0]) != null) {
        raw.add(Raw(lineNo, a));
      } else {
        settings.add(a);
      }
    }
    out.add('== ${s.name} ==');
    try {
      final c = Config(settings);
      s.config = c;
      c.header(out);
      final events = validate(c, raw, out);
      final sim = Simulation(c, events, c.policy);
      s.sim = sim;
      sim.run();
      out.addAll(sim.log);
      sim.report(out);
      for (final p in c.compare) {
        final rerun = Simulation(c, events, p);
        rerun.run();
        out.add('compare $p: delivered=${rerun.delivered} ${rerun.averages} end=${rerun.time} status=${rerun.status}');
      }
    }
    on Invalid catch (e) {
      out.add('error: ${e.message}');
    }
  }
  out.add('== ranking ==');
  final ranked = scenarios.where((s) => s.outcome == 'ranked').toList();
  ranked.sort((a, b) {
    final x = a.sim!, y = b.sim!;
    int r = (x.waitTotal * y.delivered).compareTo(y.waitTotal * x.delivered);
    if (r == 0) r = (x.travelTotal * y.delivered).compareTo(y.travelTotal * x.delivered);
    return r == 0 ? scenarios.indexOf(a).compareTo(scenarios.indexOf(b)) : r;
  });
  for (int i = 0; i < ranked.length; i++) {
    final s = ranked[i];
    out.add('${i + 1}. ${s.name} policy=${s.config!.policy} ${s.sim!.averages}');
  }
  for (final s in scenarios) {
    if (s.outcome != 'ranked') out.add('- ${s.name} ${s.outcome}');
  }
  out.add('== policies ==');
  for (final p in policies) {
    final runs = ranked.where((s) => s.config!.policy == p).map((s) => s.sim!).toList();
    if (runs.isEmpty) continue;
    final n = runs.fold<int>(0, (n, s) => n + s.delivered);
    out.add('$p: runs=${runs.length} avg_wait=${avg(runs.fold<int>(0, (n, s) => n + s.waitTotal), n)} avg_travel=${avg(runs.fold<int>(0, (n, s) => n + s.travelTotal), n)}');
  }
  stdout.writeln(out.join('\n'));
}
