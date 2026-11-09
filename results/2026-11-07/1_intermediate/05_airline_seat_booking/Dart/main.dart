import 'dart:io';

const classes = ['F', 'J', 'Y'];
const tiers = ['PLATINUM', 'GOLD', 'SILVER', 'NONE'];
class BookingError implements Exception {
  final String message;
  BookingError(this.message);
}
Never fail(String message) => throw BookingError(message);

class Seat {
  final int row, cabin, block;
  final String letter, kind;
  Seat(this.row, this.letter, this.cabin, this.block, this.kind);
  String get code => '$row$letter';
}
class Cabin {
  final int first, last;
  final List<String> blocks;
  Cabin(this.first, this.last, this.blocks);
}
class Aircraft {
  final String name;
  final int base, limit;
  final cabins = <int, Cabin>{}, rows = <int, List<List<int>>>{};
  final seats = <Seat>[], exits = <int>{}, blocked = <int>{};
  final byCode = <String, int>{};
  Aircraft(this.name, this.base, this.limit);
  void addCabin(int cabin, int first, int last, List<String> blocks) {
    cabins[cabin] = Cabin(first, last, blocks);
    for (var row = first; row <= last; row++) {
      final groups = <List<int>>[];
      for (var b = 0; b < blocks.length; b++) {
        final group = <int>[];
        for (var x = 0; x < blocks[b].length; x++) {
          final kind = b == 0 && x == 0 || b == blocks.length - 1 && x == blocks[b].length - 1 ? 'W' :
              x == 0 || x == blocks[b].length - 1 ? 'A' : 'M';
          final seat = Seat(row, blocks[b][x], cabin, b, kind);
          byCode[seat.code] = seats.length;
          group.add(seats.length);
          seats.add(seat);
        }
        groups.add(group);
      }
      rows[row] = groups;
    }
  }
  int capacity(int cabin) => seats.asMap().entries.where((e) => e.value.cabin == cabin && !blocked.contains(e.key)).length;
}
class Passenger {
  final String name, type, preference;
  late final Booking booking;
  int cabin, seat = -1;
  bool active = true;
  Passenger? infant, guardian;
  Passenger(this.name, this.type, this.preference, this.cabin);
  bool get needsSeat => type != 'INFANT';
  bool get carrying => infant != null && infant!.active;
}
class Booking {
  final String pnr;
  final Flight flight;
  final List<Passenger> listed;
  bool checked = false;
  Booking(this.pnr, this.flight, this.listed) {
    for (final p in listed) p.booking = this;
  }
  List<Passenger> get passengers => listed.where((p) => p.active).toList();
}
class Flight {
  final String name;
  final Aircraft aircraft;
  final List<int> limits;
  final Set<int> blocked;
  final List<Passenger?> occupied;
  final bookings = <Booking>[], volunteers = <Passenger>[];
  bool closed = false;
  Flight(this.name, this.aircraft, int overbook) :
      limits = [for (var c = 0; c < 3; c++) aircraft.capacity(c) * (100 + overbook) ~/ 100],
      blocked = Set.of(aircraft.blocked), occupied = List.filled(aircraft.seats.length, null);
  List<Passenger> get passengers => bookings.expand((b) => b.passengers).toList();
  int booked(int cabin) => passengers.where((p) => p.needsSeat && p.cabin == cabin).length;
  void place(Passenger p, int seat) {
    if (p.seat >= 0) occupied[p.seat] = null;
    p.seat = seat;
    if (seat >= 0) occupied[seat] = p;
  }
  bool fits(List<Passenger> ps, List<int> ss, int cabin, [Set<Passenger> vacated = const {}]) {
    final moving = ps.toSet(), targets = <int>{};
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i], index = ss[i], s = aircraft.seats[index];
      final occupant = occupied[index];
      if (!targets.add(index) || s.cabin != cabin || blocked.contains(index) ||
          occupant != null && !moving.contains(occupant) && !vacated.contains(occupant)) return false;
      if ((p.type == 'CHILD' || p.carrying) && aircraft.exits.contains(s.row)) return false;
      if (p.carrying) {
        for (final otherSeat in aircraft.rows[s.row]![s.block]) {
          final other = occupied[otherSeat];
          if (other != null && other != p && !moving.contains(other) && !vacated.contains(other) && other.carrying) return false;
        }
        for (var j = 0; j < ps.length; j++) {
          final other = aircraft.seats[ss[j]];
          if (j != i && ps[j].carrying && s.row == other.row && s.block == other.block) return false;
        }
      }
    }
    return true;
  }
  int choose(Passenger p, int cabin) {
    var first = -1;
    for (var s = 0; s < aircraft.seats.length; s++) {
      if (!fits([p], [s], cabin)) continue;
      if (first < 0) first = s;
      if (p.preference == aircraft.seats[s].kind) return s;
    }
    return first;
  }
  String assign(Booking b, int cabin) {
    final ps = b.passengers.where((p) => p.needsSeat).toList();
    final k = ps.length;
    if (k == 1) {
      place(ps[0], choose(ps[0], cabin));
      return 'SINGLE';
    }
    final layout = aircraft.cabins[cabin]!;
    bool adopt(List<int> ss) {
      if (!fits(ps, ss, cabin)) return false;
      for (var i = 0; i < k; i++) place(ps[i], ss[i]);
      return true;
    }
    for (var row = layout.first; row <= layout.last; row++) {
      for (final block in aircraft.rows[row]!) {
        for (var x = 0; x + k <= block.length; x++) {
          if (adopt(block.sublist(x, x + k))) return 'BLOCK';
        }
      }
    }
    for (var row = layout.first; row <= layout.last; row++) {
      final line = aircraft.rows[row]!.expand((b) => b).toList();
      for (var x = 0; x + k <= line.length; x++) {
        if (adopt(line.sublist(x, x + k))) return 'ROW';
      }
    }
    for (var h = 2; h <= k; h++) {
      final width = (k + h - 1) ~/ h, height = (k + width - 1) ~/ width;
      for (var row = layout.first; row + height - 1 <= layout.last; row++) {
        for (var b = 0; b < layout.blocks.length; b++) {
          for (var x = 0; x + width <= layout.blocks[b].length; x++) {
            final ss = [for (var j = 0; j < k; j++) aircraft.rows[row + j ~/ width]![b][x + j % width]];
            if (adopt(ss)) return 'STACK';
          }
        }
      }
    }
    for (final p in ps) place(p, choose(p, cabin));
    return 'SPLIT';
  }
  String result(Passenger p) => !p.needsSeat ? 'LAP' : p.seat < 0 ? 'UNASSIGNED' : aircraft.seats[p.seat].code;
  void reassign(StringBuffer out) {
    for (final p in passengers) {
      if (!p.needsSeat || p.seat >= 0) continue;
      final seat = choose(p, p.cabin);
      if (seat >= 0) {
        place(p, seat);
        out.writeln('REASSIGNED ${p.booking.pnr} ${p.name} ${result(p)}');
      }
    }
  }
  void remove(Passenger p) {
    if (!p.active) return;
    if (p.carrying) remove(p.infant!);
    if (p.guardian != null) {
      p.guardian!.infant = null;
      p.guardian = null;
    }
    place(p, -1);
    p.active = false;
    volunteers.remove(p);
  }
}

class Airline {
  final models = <String, Aircraft>{}, flights = <String, Flight>{}, bookings = <String, Booking>{};
  final status = <String, int>{};
  Aircraft? defining;
  int tier(Passenger p) => status[p.name] ?? 3;
  Flight flight(String name, [bool open = false]) {
    final f = flights[name];
    if (f == null) fail('unknown flight $name');
    if (open && f.closed) fail('flight $name is closed');
    return f;
  }
  Booking booking(String pnr, [bool open = false]) {
    final b = bookings[pnr];
    if (b == null || b.passengers.isEmpty) fail('unknown PNR $pnr');
    if (open && b.flight.closed) fail('flight ${b.flight.name} is closed');
    return b;
  }
  Passenger passenger(Booking b, String name) => b.passengers.firstWhere((p) => p.name == name,
      orElse: () => fail('no passenger $name in ${b.pnr}'));
  void hasCabin(Flight f, int c) {
    if (!f.aircraft.cabins.containsKey(c)) fail('no cabin ${classes[c]} on ${f.name}');
  }
  String execute(String line) {
    final a = line.split(' '), op = a[0], out = StringBuffer();
    if (op == 'AIRCRAFT') {
      defining = Aircraft(a[1], int.parse(a[2]), int.parse(a[3]));
      return '';
    }
    if (op == 'CABIN') {
      defining!.addCabin(classes.indexOf(a[1]), int.parse(a[2]), int.parse(a[3]), a.sublist(4));
      return '';
    }
    if (op == 'EXIT') {
      defining!.exits.addAll(a.skip(1).map(int.parse));
      return '';
    }
    if (op == 'BLOCKED') {
      defining!.blocked.addAll(a.skip(1).map((s) => defining!.byCode[s]!));
      return '';
    }
    if (op == 'END') {
      final model = defining!;
      models[model.name] = model;
      defining = null;
      out.writeln('AIRCRAFT ${model.name}${[for (var c = 0; c < 3; c++) if (model.cabins.containsKey(c)) ' ${classes[c]} ${model.capacity(c)}'].join()}');
    } else if (op == 'FLIGHT') {
      if (flights.containsKey(a[1])) fail('duplicate flight ${a[1]}');
      final model = models[a[2]];
      if (model == null) fail('unknown aircraft ${a[2]}');
      final f = Flight(a[1], model, int.parse(a[3]));
      flights[f.name] = f;
      out.writeln('FLIGHT ${f.name} ${model.name}${[for (var c = 0; c < 3; c++) if (model.cabins.containsKey(c)) ' ${classes[c]} ${model.capacity(c)}/${f.limits[c]}'].join()}');
    } else if (op == 'STATUS') {
      status[a[1]] = tiers.indexOf(a[2]);
      out.writeln('STATUS ${a[1]} ${a[2]}');
    } else if (op == 'BOOK') {
      if (bookings.containsKey(a[1])) fail('duplicate PNR ${a[1]}');
      final f = flight(a[2], true), c = classes.indexOf(a[3]);
      hasCabin(f, c);
      final ps = a.skip(4).map((token) {
        final s = token.split(':');
        return Passenger(s[0], s[1], s.length == 3 ? s[2] : '', c);
      }).toList();
      final seen = <String>{};
      for (final p in ps) if (!seen.add(p.name)) fail('duplicate name ${p.name} in ${a[1]}');
      for (final p in ps) if (f.passengers.any((q) => q.name == p.name)) fail('${p.name} already on ${f.name}');
      final adults = ps.where((p) => p.type == 'ADULT').toList(), infants = ps.where((p) => !p.needsSeat).toList();
      if (adults.isEmpty) fail('no adult in ${a[1]}');
      if (infants.length > adults.length) fail('too many infants in ${a[1]}');
      if (f.booked(c) + ps.where((p) => p.needsSeat).length > f.limits[c]) fail('limit exceeded for ${f.name} ${classes[c]}');
      for (var i = 0; i < infants.length; i++) {
        adults[i].infant = infants[i];
        infants[i].guardian = adults[i];
      }
      final b = Booking(a[1], f, ps);
      bookings[b.pnr] = b;
      f.bookings.add(b);
      final method = f.assign(b, c);
      out.writeln('BOOKED ${b.pnr} ${f.name} ${classes[c]} $method ${ps.map((p) => '${p.name}:${f.result(p)}').join(' ')}');
    } else if (op == 'SEAT') {
      final b = booking(a[1], true), p = passenger(b, a[2]), f = b.flight;
      if (!p.needsSeat) fail('infant ${p.name} has no seat');
      final s = f.aircraft.byCode[a[3]];
      if (s == null || f.aircraft.seats[s].cabin != p.cabin) fail('no seat ${a[3]} in cabin ${classes[p.cabin]}');
      if (f.blocked.contains(s)) fail('seat ${a[3]} is blocked');
      if (f.occupied[s] != null) fail('seat ${a[3]} is occupied');
      if ((p.type == 'CHILD' || p.carrying) && f.aircraft.exits.contains(f.aircraft.seats[s].row)) fail('exit row ${f.aircraft.seats[s].row} not allowed for ${p.name}');
      if (!f.fits([p], [s], p.cabin)) fail('infant limit reached at ${a[3]}');
      final old = f.result(p);
      f.place(p, s);
      out.writeln('MOVED ${b.pnr} ${p.name} $old -> ${a[3]}');
      f.reassign(out);
    } else if (op == 'SWAP') {
      final b = booking(a[1], true), p = passenger(b, a[2]);
      final d = booking(a[3], true), q = passenger(d, a[4]);
      if (p == q) fail('cannot swap ${p.name} with itself');
      for (final person in [p, q]) if (!person.needsSeat) fail('infant ${person.name} has no seat');
      if (b.flight != d.flight) fail('${b.pnr} and ${d.pnr} are on different flights');
      if (p.cabin != q.cabin) fail('${p.name} and ${q.name} are in different cabins');
      for (final person in [p, q]) if (person.seat < 0) fail('${person.name} has no seat');
      final f = b.flight, old = p.seat, other = q.seat;
      if (!f.fits([p, q], [other, old], p.cabin)) fail('swap of ${p.name} and ${q.name} breaks seating rules');
      f.place(p, -1);
      f.place(q, -1);
      f.place(p, other);
      f.place(q, old);
      out.writeln('SWAPPED ${b.pnr} ${p.name} ${f.result(p)} ${d.pnr} ${q.name} ${f.result(q)}');
      f.reassign(out);
    } else if (op == 'CANCEL') {
      final b = booking(a[1], true), f = b.flight;
      final target = a.length == 2 ? null : passenger(b, a[2]);
      final removed = b.passengers.where((p) => target == null || p == target || target.infant == p).toList();
      final remaining = b.passengers.where((p) => !removed.contains(p)).toList();
      if (target != null && remaining.isNotEmpty && !remaining.any((p) => p.type == 'ADULT')) fail('${b.pnr} would have no adult');
      out.writeln('CANCELLED ${b.pnr} ${removed.map((p) => p.name).join(' ')}');
      for (final p in removed) f.remove(p);
      f.reassign(out);
    } else if (op == 'CHECKIN' || op == 'VOLUNTEER') {
      final b = booking(a[1], true), f = b.flight;
      if (op == 'CHECKIN') {
        if (b.checked) fail('${b.pnr} already checked in');
        b.checked = true;
        out.writeln('CHECKIN ${b.pnr} ${b.passengers.length}');
      } else {
        final p = passenger(b, a[2]);
        if (p.type != 'ADULT' || p.carrying) fail('${p.name} cannot volunteer');
        if (p.seat < 0) fail('${p.name} has no seat');
        if (f.volunteers.contains(p)) fail('${p.name} already volunteered');
        f.volunteers.add(p);
        out.writeln('VOLUNTEER ${b.pnr} ${p.name} ${f.result(p)}');
      }
    } else if (op == 'UPGRADE') {
      final f = flight(a[1], true), cs = [for (var c = 0; c < 3; c++) if (f.aircraft.cabins.containsKey(c)) c];
      var count = 0;
      for (var i = 0; i + 1 < cs.length; i++) {
        final higher = cs[i], lower = cs[i + 1];
        final targets = [
          for (final (index, p) in f.passengers.indexed)
            if (p.cabin == lower && p.type == 'ADULT' && !p.carrying && tier(p) < 3)
              (passenger: p, index: index, tier: tier(p))
        ]..sort((a, b) => a.tier != b.tier ? a.tier.compareTo(b.tier) : a.index.compareTo(b.index));
        for (final target in targets) {
          final p = target.passenger;
          if (f.booked(higher) >= f.limits[higher]) break;
          final seat = f.choose(p, higher);
          if (seat < 0) break;
          final old = f.result(p);
          f.place(p, seat);
          p.cabin = higher;
          count++;
          out.writeln('UPGRADED ${p.booking.pnr} ${p.name} ${classes[lower]} $old -> ${classes[higher]} ${f.result(p)}');
        }
      }
      f.reassign(out);
      out.writeln('UPGRADE ${f.name} $count');
    } else if (op == 'CLOSE') {
      final f = flight(a[1], true);
      var denied = 0, compensation = 0;
      for (final b in f.bookings) {
        if (b.passengers.isEmpty || b.checked) continue;
        out.writeln('NOSHOW ${b.pnr} ${b.passengers.length}');
        for (final p in b.passengers) f.remove(p);
      }
      f.reassign(out);
      void deny(Passenger p, bool voluntary) {
        var value = [500, 300, 150][p.cabin] * (voluntary ? 1 : 2);
        if (p.type == 'CHILD') value ~/= 2;
        out.writeln('DENIED ${voluntary ? 'VOLUNTARY' : 'INVOLUNTARY'} ${p.booking.pnr} ${p.name} ${classes[p.cabin]} $value');
        denied++;
        compensation += value;
        f.remove(p);
      }
      for (var c = 0; c < 3; c++) {
        final targets = f.volunteers.where((p) => p.active && p.seat >= 0 && p.cabin == c).toList();
        for (final p in targets) {
          if (f.passengers.any((q) => q.needsSeat && q.seat < 0 && q.cabin == c && f.fits([q], [p.seat], c, {p}))) {
            deny(p, true);
            f.reassign(out);
          }
        }
      }
      for (final p in f.passengers) if (p.needsSeat && p.seat < 0) deny(p, false);
      f.closed = true;
      out.writeln('CLOSED ${f.name} denied $denied compensation $compensation');
    } else if (op == 'BLOCK' || op == 'UNBLOCK') {
      final f = flight(a[1], true), seat = f.aircraft.byCode[a[2]];
      if (seat == null) fail('no seat ${a[2]} on ${f.name}');
      if (op == 'BLOCK' && f.blocked.contains(seat)) fail('seat ${a[2]} is blocked');
      if (op == 'UNBLOCK' && !f.blocked.contains(seat)) fail('seat ${a[2]} is not blocked');
      out.writeln('$op ${f.name} ${a[2]}');
      if (op == 'BLOCK') {
        f.blocked.add(seat);
        final p = f.occupied[seat];
        if (p != null) {
          f.place(p, -1);
          f.place(p, f.choose(p, p.cabin));
          out.writeln('DISPLACED ${p.booking.pnr} ${p.name} ${a[2]} -> ${f.result(p)}');
        }
      } else f.blocked.remove(seat);
      f.reassign(out);
    } else if (op == 'INFO') {
      final b = booking(a[1]), f = b.flight;
      out.writeln('INFO ${b.pnr} ${f.name} ${b.passengers.length} ${b.checked ? 'CHECKED' : 'NOT-CHECKED'}');
      for (final p in b.passengers) out.writeln('${p.name} ${p.type} ${classes[p.cabin]} ${f.result(p)}');
    } else if (op == 'FIND') {
      final found = [for (final f in flights.values) for (final p in f.passengers) if (p.name == a[1]) p];
      out.writeln('FIND ${a[1]} ${tiers[status[a[1]] ?? 3]} ${found.length}');
      for (final p in found) out.writeln('${p.booking.flight.name} ${p.booking.pnr} ${classes[p.cabin]} ${p.booking.flight.result(p)} ${p.booking.flight.closed ? 'CLOSED' : 'OPEN'}');
    } else {
      final f = flight(a[1]), model = f.aircraft;
      if (op == 'MAP') {
        out.writeln('MAP ${f.name}');
        for (var c = 0; c < 3; c++) {
          final cabin = model.cabins[c];
          if (cabin == null) continue;
          out.writeln('CABIN ${classes[c]}');
          out.writeln('   ${cabin.blocks.join(' ')}');
          for (var row = cabin.first; row <= cabin.last; row++) {
            out.writeln('${row.toString().padLeft(2)} ${model.rows[row]!.map((block) => block.map((s) => f.blocked.contains(s) ? '#' : f.occupied[s] != null ? 'X' : model.exits.contains(row) ? 'E' : '.').join()).join(' ')}');
          }
        }
      } else if (op == 'MANIFEST') {
        final ps = f.passengers, seated = ps.where((p) => p.needsSeat && p.seat >= 0).toList()..sort((p, q) => p.seat.compareTo(q.seat));
        final waiting = ps.where((p) => p.needsSeat && p.seat < 0).toList();
        out.writeln('MANIFEST ${f.name} seated ${seated.length} unassigned ${waiting.length} infants ${ps.where((p) => !p.needsSeat).length}');
        for (final p in [...seated, ...waiting]) out.writeln('${p.seat < 0 ? '---' : f.result(p)} ${classes[p.cabin]} ${p.booking.pnr} ${p.name} ${p.type}${p.carrying ? ' +${p.infant!.name}' : ''}${tier(p) < 3 ? ' ${tiers[tier(p)]}' : ''}${p.booking.checked ? ' CHECKED' : ''}${f.volunteers.contains(p) ? ' VOL' : ''}');
      } else if (op == 'LOADFACTOR') {
        out.writeln('LOADFACTOR ${f.name}');
        var totalSeated = 0, totalSeats = 0;
        String load(int count, int seats) {
          final q = count * 1000 ~/ seats;
          return '${q ~/ 10}.${q % 10}%';
        }
        for (var c = 0; c < 3; c++) {
          if (!model.cabins.containsKey(c)) continue;
          final seats = model.seats.asMap().entries.where((e) => e.value.cabin == c && !f.blocked.contains(e.key)).length;
          final seated = f.passengers.where((p) => p.needsSeat && p.cabin == c && p.seat >= 0).length;
          totalSeats += seats;
          totalSeated += seated;
          out.writeln('${classes[c]} $seated/$seats ${load(seated, seats)} booked ${f.booked(c)}/${f.limits[c]}');
        }
        out.writeln('ALL $totalSeated/$totalSeats ${load(totalSeated, totalSeats)}');
      } else if (op == 'BALANCE') {
        var weight = 0, moment = 0;
        for (final p in f.passengers.where((p) => p.needsSeat && p.seat >= 0)) {
          final w = (p.type == 'ADULT' ? 80 : 40) + (p.carrying ? 10 : 0);
          weight += w;
          moment += w * (model.seats[p.seat].row - model.base);
        }
        out.writeln('BALANCE ${f.name} weight $weight moment $moment limit ${model.limit} ${moment < -model.limit ? 'NOSE-HEAVY' : moment > model.limit ? 'TAIL-HEAVY' : 'OK'}');
      } else if (op == 'AVAIL') {
        final c = classes.indexOf(a[2]);
        hasCabin(f, c);
        final ss = [for (var i = 0; i < model.seats.length; i++) if (model.seats[i].cabin == c && !f.blocked.contains(i) && f.occupied[i] == null) model.seats[i]];
        out.writeln('AVAIL ${f.name} ${classes[c]} free ${ss.length} W ${ss.where((s) => s.kind == 'W').length} M ${ss.where((s) => s.kind == 'M').length} A ${ss.where((s) => s.kind == 'A').length} EXIT ${ss.where((s) => model.exits.contains(s.row)).length}');
      } else if (op == 'BOARDING') {
        final ps = f.passengers.where((p) => p.needsSeat && p.seat >= 0).toList();
        (int, int, int, int, String) key(Passenger p) {
          final s = model.seats[p.seat];
          if (p.booking.passengers.any((q) => !q.needsSeat)) return (0, 0, s.row, 0, s.letter);
          if (p.cabin < 2) return (1, 0, s.row, 0, s.letter);
          if (tier(p) < 2) return (2, 0, s.row, 0, s.letter);
          return (3, -((s.row - model.cabins[2]!.first) ~/ 5 + 1), 'WMA'.indexOf(s.kind), -s.row, s.letter);
        }
        final ordered = ps.map((p) => (passenger: p, key: key(p))).toList()
          ..sort((a, b) {
            final x = a.key, y = b.key, xs = [x.$1, x.$2, x.$3, x.$4], ys = [y.$1, y.$2, y.$3, y.$4];
            for (var i = 0; i < 4; i++)
              if (xs[i] != ys[i]) return xs[i].compareTo(ys[i]);
            return x.$5.compareTo(y.$5);
          });
        out.writeln('BOARDING ${f.name} ${ordered.length}');
        for (var i = 0; i < ordered.length; i++) {
          final p = ordered[i].passenger, k = ordered[i].key;
          final group = k.$1 == 3 ? 'ZONE${-k.$2}' : ['PRE', 'CABIN', 'TIER'][k.$1];
          out.writeln('${i + 1} $group ${f.result(p)} ${p.booking.pnr} ${p.name}');
        }
      }
    }
    return out.toString();
  }
}
void main() {
  final airline = Airline(), count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      stdout.write(airline.execute(line));
    } on BookingError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
