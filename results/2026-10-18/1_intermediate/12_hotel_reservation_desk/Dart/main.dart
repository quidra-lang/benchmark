import 'dart:io';

const types = ['SINGLE', 'DOUBLE', 'SUITE'];
const weekdays = ['SAT', 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI'];
int amount(String s) {
  final p = s.split('.');
  return int.parse(p[0]) * 100 + int.parse(p[1]);
}
String money(int c) => '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
class HotelError implements Exception {
  final String reason;
  HotelError(this.reason);
}
Never fail(String s) => throw HotelError(s);
bool leap(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
int monthDays(int y, int m) => m == 2 && leap(y) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
int date(String s) {
  final y = int.parse(s.substring(0, 4)), m = int.parse(s.substring(5, 7)), d = int.parse(s.substring(8, 10));
  if (y < 2000 || y > 2099 || m < 1 || m > 12 || d < 1 || d > monthDays(y, m)) fail('invalid date $s');
  var result = d - 1;
  for (var year = 2000; year < y; year++) result += leap(year) ? 366 : 365;
  for (var month = 1; month < m; month++) result += monthDays(y, month);
  return result;
}
String dateText(int n) {
  var y = 2000, m = 1;
  while (n >= (leap(y) ? 366 : 365)) {
    n -= leap(y) ? 366 : 365;
    y++;
  }
  while (n >= monthDays(y, m)) {
    n -= monthDays(y, m);
    m++;
  }
  return '$y-${m.toString().padLeft(2, '0')}-${(n + 1).toString().padLeft(2, '0')}';
}
String dated(int n) => '${dateText(n)} ${weekdays[n % 7]}';
class Room {
  final int number;
  final String type;
  int rate;
  bool clean = true;
  final blocks = <int>{};
  final occupied = <int, Reservation>{};
  Room(this.number, this.type, this.rate);
  bool free(int day, [Reservation? except]) => !blocks.contains(day) && (occupied[day] == null || occupied[day] == except);
}
class Season {
  final int start, end, percent;
  Season(this.start, this.end, this.percent);
}
class Night {
  final int day, rate;
  Room room;
  Night(this.day, this.room, this.rate);
}
class Reservation {
  final String id, guest;
  Room room;
  int start, end;
  String status = 'booked';
  List<Night> nights = [];
  final extras = <(String, int)>[];
  int deposit = 0, paid = 0, fee = 0;
  int? posting;
  Night? penalty;
  List<int>? finalBill;
  Reservation(this.id, this.guest, this.room, this.start, this.end);
  int get lodging => nights.fold(0, (n, night) => n + night.rate);
  int get extraTotal => extras.fold(0, (n, e) => n + e.$2);
}
class Waiting {
  final String id, guest, type;
  final int start, end;
  Waiting(this.id, this.guest, this.type, this.start, this.end);
}
class Hotel {
  int today = date('2026-01-01');
  final rooms = <int, Room>{};
  final reservations = <String, Reservation>{};
  final used = <String>{};
  final seasons = <Season>[];
  final queue = <Waiting>[];
  List<Room> roomList() => rooms.values.toList()..sort((a, b) => a.number.compareTo(b.number));
  List<Reservation> sorted(Iterable<Reservation> rs, {bool departure = false, bool ids = false}) => rs.toList()..sort((a, b) {
    final c = ids ? 0 : (departure ? a.end : a.start).compareTo(departure ? b.end : b.start);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  Room room(String token) => rooms[int.parse(token)] ?? fail('unknown room $token');
  Reservation reservation(String id) => reservations[id] ?? fail('unknown reservation $id');
  void typeCheck(String type) {
    if (!types.contains(type)) fail('invalid type $type');
  }
  void idCheck(String id) {
    if (used.contains(id)) fail('duplicate reservation $id');
  }
  void statusCheck(Reservation r, String s) {
    if (r.status != s) fail('invalid status ${r.id} ${r.status}');
  }
  (int, int) range(String a, String b, {bool stay = false, bool past = false, bool limit = true}) {
    final first = date(a), last = date(b);
    if ((stay || past) && first < today) fail('past date $a');
    if (stay ? last <= first : last < first) fail('invalid range $a $b');
    final count = last - first + (stay ? 0 : 1);
    if (limit && count > (stay ? 30 : 31)) fail('too long $count');
    return (first, last);
  }
  int rate(Room r, int d) {
    final season = seasons.reversed.where((s) => s.start <= d && d <= s.end).firstOrNull;
    return r.rate * (season?.percent ?? 100) ~/ 100;
  }
  List<Night> price(Room room, int a, int b) => [for (var d = a; d < b; d++) Night(d, room, rate(room, d))];
  int? unavailable(Room r, int a, int b, [Reservation? except]) {
    for (var d = a; d < b; d++) {
      if (!r.free(d, except)) return d;
    }
    return null;
  }
  Room? search(String type, int a, int b, [Reservation? except]) => roomList().where((r) => r.type == type && unavailable(r, a, b, except) == null).firstOrNull;
  Reservation? inhouse(Room room) => reservations.values.where((r) => r.status == 'inhouse' && r.room == room).firstOrNull;
  void release(Reservation r) {
    for (final n in r.nights)
      if (n.room.occupied[n.day] == r) n.room.occupied.remove(n.day);
  }
  void occupy(Reservation r) {
    for (final n in r.nights) n.room.occupied[n.day] = r;
  }
  Reservation create(String id, String guest, Room room, int a, int b, StringBuffer out, {String indent = ''}) {
    final r = Reservation(id, guest, room, a, b);
    r.nights = price(room, a, b);
    reservations[id] = r;
    used.add(id);
    occupy(r);
    out.writeln('${indent}BOOK $id $guest room ${room.number} ${room.type} ${dateText(a)} -> ${dateText(b)} nights ${b - a} total ${money(r.lodging)}');
    return r;
  }
  int paid(String guest) => reservations.values.where((r) => r.guest == guest).fold(0, (n, r) => n + r.paid);
  String tier(String guest) {
    final points = paid(guest) ~/ 100;
    return points >= 2000 ? 'GOLD' : points >= 500 ? 'SILVER' : 'BRONZE';
  }
  List<int> bill(Reservation r) {
    final level = tier(r.guest), lodging = r.lodging;
    final discount = lodging * (level == 'GOLD' ? 10 : level == 'SILVER' ? 5 : 0) ~/ 100;
    final penalty = r.penalty?.rate ?? 0, extras = r.extraTotal;
    final subtotal = lodging - discount + penalty + extras;
    final tax = subtotal ~/ 10;
    return [lodging, discount, penalty, extras, tax, subtotal + tax];
  }
  String deposit(Reservation r, int total) => 'deposit ${money(r.deposit)} ${total >= r.deposit ? 'due ${money(total - r.deposit)}' : 'refund ${money(r.deposit - total)}'}';
  void checkout(Reservation r, int day, StringBuffer out, {String indent = ''}) {
    if (day < r.end) {
      r.penalty = r.nights.firstWhere((n) => n.day == day);
      release(r);
      r.nights = r.nights.where((n) => n.day < day).toList();
      r.end = day;
      occupy(r);
    }
    final b = bill(r);
    r.finalBill = b;
    r.paid = b[5];
    r.status = 'checkedout';
    r.posting = day;
    r.room.clean = false;
    out.writeln('${indent}CHECKOUT ${r.id} nights ${r.nights.length} lodging ${money(b[0])} discount ${money(b[1])} penalty ${money(b[2])} extras ${money(b[3])} tax ${money(b[4])} total ${money(b[5])} ${deposit(r, b[5])}');
  }
  void processQueue(StringBuffer out) {
    for (final w in queue.toList()) {
      if (w.start < today) {
        queue.remove(w);
        out.writeln('  WAITLIST ${w.id} expired');
        continue;
      }
      final r = search(w.type, w.start, w.end);
      if (r != null) {
        queue.remove(w);
        create(w.id, w.guest, r, w.start, w.end, out, indent: '  ');
      }
    }
  }
  (int, int, int) metrics(int d) {
    var available = 0, sold = 0, revenue = 0;
    for (final r in rooms.values) {
      if (!r.blocks.contains(d)) available++;
      final guest = r.occupied[d];
      if (guest != null) {
        sold++;
        revenue += guest.nights.firstWhere((n) => n.day == d && n.room == r).rate;
      }
    }
    return (available, sold, revenue);
  }
  String metricText(int s, int k, int v) => 'sold $k/$s rate ${s == 0 ? 'n/a' : '${k * 100 ~/ s}%'} revenue ${money(v)} adr ${k == 0 ? 'n/a' : money(v ~/ k)} revpar ${s == 0 ? 'n/a' : money(v ~/ s)}';
  String occupancy(Iterable<Room> rs, int d) {
    final list = rs.toList(), blocked = list.where((r) => r.blocks.contains(d)).length, occupied = list.where((r) => r.occupied.containsKey(d)).length;
    final available = list.length - blocked;
    return 'rooms ${list.length} blocked $blocked occupied $occupied rate ${available == 0 ? 'n/a' : '${occupied * 100 ~/ available}%'}';
  }
  void execute(List<String> a, StringBuffer out) {
    final op = a[0], id = a.length > 1 ? a[1] : '';
    if (op == 'ROOM') {
      final n = int.parse(id);
      if (rooms.containsKey(n)) fail('duplicate room $id');
      typeCheck(a[2]);
      final r = Room(n, a[2], amount(a[3]));
      rooms[n] = r;
      out.writeln('ROOM $n ${r.type} ${money(r.rate)}');
    } else if (op == 'RATE') {
      final r = room(id);
      final old = r.rate;
      r.rate = amount(a[2]);
      out.writeln('RATE $id ${money(old)} -> ${money(r.rate)}');
    } else if (op == 'SEASON') {
      final (first, last) = range(id, a[2], limit: false);
      seasons.add(Season(first, last, int.parse(a[3])));
      out.writeln('SEASON ${seasons.length} $id -> ${a[2]} ${a[3]}%');
    } else if (op == 'BLOCK' || op == 'UNBLOCK') {
      final r = room(id);
      final (first, last) = range(a[2], a[3], past: true);
      if (op == 'BLOCK') {
        for (var d = first; d <= last; d++) {
          if (r.occupied.containsKey(d)) fail('room unavailable $id ${dateText(d)}');
        }
      }
      var changed = 0;
      for (var d = first; d <= last; d++)
        if (op == 'BLOCK' ? r.blocks.add(d) : r.blocks.remove(d)) changed++;
      out.writeln('$op $id ${a[2]} -> ${a[3]} ${op == 'BLOCK' ? 'added' : 'removed'} $changed');
    } else if (op == 'CLEAN') {
      final r = room(id);
      if (r.clean) fail('already clean $id');
      r.clean = true;
      out.writeln('CLEAN $id');
    } else if (op == 'TODAY') {
      final d = date(id);
      if (d < today) fail('past date $id');
      out.writeln('TODAY ${dated(d)}');
      for (final r in sorted(reservations.values.where((r) => r.status == 'inhouse' && r.end < d), departure: true)) checkout(r, r.end, out, indent: '  ');
      for (final r in sorted(reservations.values.where((r) => r.status == 'booked' && r.start < d))) {
        r.fee = r.nights.first.rate;
        r.paid = r.fee;
        r.status = 'noshow';
        r.posting = r.start;
        release(r);
        out.writeln('  NOSHOW ${r.id} ${r.guest} fee ${money(r.fee)} ${deposit(r, r.fee)}');
      }
      today = d;
    } else if (op == 'BOOK' || op == 'BOOKROOM' || op == 'WAITLIST') {
      idCheck(id);
      Room? selected;
      if (op == 'BOOKROOM') {
        selected = room(a[3]);
      } else {
        typeCheck(a[3]);
      }
      final (first, last) = range(a[4], a[5], stay: true);
      if (op == 'BOOKROOM') {
        final d = unavailable(selected!, first, last);
        if (d != null) fail('room unavailable ${selected.number} ${dateText(d)}');
      } else {
        selected = search(a[3], first, last);
      }
      if (selected != null) {
        create(id, a[2], selected, first, last, out);
      } else if (op == 'WAITLIST') {
        queue.add(Waiting(id, a[2], a[3], first, last));
        used.add(id);
        out.writeln('WAITLIST $id queued position ${queue.length}');
      } else {
        fail('no availability ${a[3]} ${a[4]} ${a[5]}');
      }
    } else if (op == 'CANCEL') {
      final index = queue.indexWhere((w) => w.id == id);
      if (index >= 0) {
        queue.removeAt(index);
        out.writeln('CANCEL $id waitlist removed');
        return;
      }
      final r = reservation(id);
      statusCheck(r, 'booked');
      final days = r.start - today;
      r.fee = days >= 7 ? 0 : days >= 1 ? r.nights.first.rate ~/ 2 : r.nights.first.rate;
      r.paid = r.fee;
      r.status = 'cancelled';
      r.posting = today;
      release(r);
      out.writeln('CANCEL $id days $days fee ${money(r.fee)} ${deposit(r, r.fee)}');
    } else if (['MODIFY', 'CHECKIN', 'MOVE', 'EXTEND', 'CHARGE', 'PAY', 'CHECKOUT', 'INVOICE'].contains(op)) {
      final r = reservation(id);
      if (op == 'MODIFY') {
        statusCheck(r, 'booked');
        final (first, last) = range(a[2], a[3], stay: true);
        final old = r.room, selected = unavailable(r.room, first, last, r) == null ? r.room : search(r.room.type, first, last, r);
        if (selected == null) fail('no availability ${r.room.type} ${a[2]} ${a[3]}');
        release(r);
        r.room = selected;
        r.start = first;
        r.end = last;
        r.nights = price(selected, first, last);
        occupy(r);
        out.writeln('MODIFY $id room ${selected.number} ${selected == old ? 'kept' : 'reassigned'} ${a[2]} -> ${a[3]} nights ${last - first} total ${money(r.lodging)}');
      } else if (op == 'CHECKIN') {
        statusCheck(r, 'booked');
        if (r.start != today) fail('not arrival date $id ${dateText(r.start)}');
        final occupant = inhouse(r.room);
        if (occupant != null) fail('room occupied ${r.room.number} ${occupant.id}');
        if (!r.room.clean) fail('room dirty ${r.room.number}');
        r.status = 'inhouse';
        out.writeln('CHECKIN $id ${r.guest} room ${r.room.number} until ${dateText(r.end)}');
      } else if (op == 'MOVE') {
        statusCheck(r, 'inhouse');
        final dest = room(a[2]);
        if (dest == r.room) fail('same room ${dest.number}');
        final remaining = r.nights.where((n) => n.day >= today).toList();
        if (remaining.isEmpty) fail('no remaining nights $id');
        for (final n in remaining)
          if (!dest.free(n.day, r)) fail('room unavailable ${dest.number} ${dateText(n.day)}');
        final occupant = inhouse(dest);
        if (occupant != null) fail('room occupied ${dest.number} ${occupant.id}');
        if (!dest.clean) fail('room dirty ${dest.number}');
        final old = r.room;
        for (final n in remaining) {
          n.room.occupied.remove(n.day);
          n.room = dest;
          dest.occupied[n.day] = r;
        }
        out.writeln('MOVE $id ${old.number} -> ${dest.number} nights ${remaining.length}');
        old.clean = false;
        r.room = dest;
      } else if (op == 'EXTEND') {
        statusCheck(r, 'inhouse');
        final end = date(a[2]);
        if (end <= r.end) fail('invalid range ${dateText(r.end)} ${a[2]}');
        if (end - r.start > 30) fail('too long ${end - r.start}');
        final d = unavailable(r.room, r.end, end, r);
        if (d != null) fail('room unavailable ${r.room.number} ${dateText(d)}');
        r.nights.addAll(price(r.room, r.end, end));
        r.end = end;
        occupy(r);
        out.writeln('EXTEND $id until ${a[2]} nights ${r.nights.length} total ${money(r.lodging)}');
      } else if (op == 'CHARGE') {
        statusCheck(r, 'inhouse');
        final m = amount(a[2]);
        if (m == 0) fail('invalid amount');
        r.extras.add((a[3], m));
        out.writeln('CHARGE $id ${a[3]} ${money(m)} extras ${money(r.extraTotal)}');
      } else if (op == 'PAY') {
        if (r.status != 'booked' && r.status != 'inhouse') fail('invalid status $id ${r.status}');
        final m = amount(a[2]);
        if (m == 0) fail('invalid amount');
        r.deposit += m;
        out.writeln('PAY $id ${money(m)} deposit ${money(r.deposit)}');
      } else if (op == 'CHECKOUT') {
        statusCheck(r, 'inhouse');
        checkout(r, today, out);
      } else {
        out.writeln('INVOICE $id ${r.guest} room ${r.room.number} ${r.room.type} ${r.status}');
        if (r.status == 'cancelled' || r.status == 'noshow') {
          out.writeln('  ${r.status == 'cancelled' ? 'cancellation' : 'noshow'} fee ${money(r.fee)}');
          out.writeln('  total ${money(r.fee)}');
          out.writeln('  ${deposit(r, r.fee)}');
        } else {
          for (final n in r.nights) out.writeln('  ${dated(n.day)} room ${n.room.number} ${money(n.rate)}');
          final b = r.status == 'checkedout' ? r.finalBill! : bill(r);
          out.writeln('  lodging ${money(b[0])}');
          out.writeln('  discount ${money(b[1])}');
          if (r.penalty != null) out.writeln('  penalty ${dated(r.penalty!.day)} ${money(b[2])}');
          for (final e in r.extras) out.writeln('  extra ${e.$1} ${money(e.$2)}');
          out.writeln('  tax ${money(b[4])}');
          out.writeln('  total ${money(b[5])}');
          out.writeln('  ${deposit(r, b[5])}');
        }
      }
    } else if (op == 'AVAIL') {
      typeCheck(id);
      final (first, last) = range(a[2], a[3]);
      out.writeln('AVAIL $id ${a[2]} -> ${a[3]}');
      final rs = roomList();
      for (var d = first; d <= last; d++) {
        final available = rs.where((r) => r.type == id && r.free(d)).toList();
        out.writeln('  ${dated(d)} free ${available.length}${available.isEmpty ? '' : ' ${available.map((r) => r.number).join(' ')}'}');
      }
    } else if (op == 'OCCUPANCY') {
      final d = date(id);
      out.writeln('OCCUPANCY ${dated(d)} ${occupancy(rooms.values, d)}');
      for (final type in types) {
        final rs = rooms.values.where((r) => r.type == type);
        if (rs.isNotEmpty) out.writeln('  $type ${occupancy(rs, d)}');
      }
    } else if (op == 'STATS') {
      final (first, last) = range(id, a[2]);
      var s = 0, k = 0, value = 0;
      out.writeln('STATS $id -> ${a[2]}');
      for (var d = first; d <= last; d++) {
        final m = metrics(d);
        s += m.$1;
        k += m.$2;
        value += m.$3;
        out.writeln('  ${dated(d)} ${metricText(m.$1, m.$2, m.$3)}');
      }
      out.writeln('  total ${metricText(s, k, value)}');
    } else if (op == 'ROOMS') {
      out.writeln('ROOMS ${dated(today)} rooms ${rooms.length}');
      for (final r in roomList()) {
        final occupant = inhouse(r), next = sorted(reservations.values.where((x) => x.status == 'booked' && x.room == r));
        out.writeln('  ${r.number} ${r.type} base ${money(r.rate)} tonight ${money(rate(r, today))} ${r.clean ? 'clean' : 'dirty'} ${occupant != null ? 'occupied ${occupant.id}' : r.blocks.contains(today) ? 'blocked' : 'vacant'}${next.isEmpty ? '' : ' next ${next.first.id} ${dateText(next.first.start)}'}');
      }
    } else if (op == 'LIST') {
      final rs = sorted(reservations.values.where((r) => r.status == id));
      out.writeln('LIST $id ${rs.length}');
      for (final r in rs) out.writeln('  ${r.id} ${r.guest} room ${r.room.number} ${dateText(r.start)} -> ${dateText(r.end)}');
    } else if (op == 'QUEUE') {
      out.writeln('QUEUE ${queue.length}');
      for (var i = 0; i < queue.length; i++) {
        final w = queue[i];
        out.writeln('  ${i + 1} ${w.id} ${w.guest} ${w.type} ${dateText(w.start)} -> ${dateText(w.end)}');
      }
    } else if (op == 'SCHEDULE') {
      final d = date(id);
      final arrivals = sorted(reservations.values.where((r) => r.start == d && r.status != 'cancelled'), ids: true);
      final departures = sorted(reservations.values.where((r) => r.end == d && ['booked', 'inhouse', 'checkedout'].contains(r.status)), ids: true);
      out.writeln('SCHEDULE ${dated(d)} arrivals ${arrivals.length} departures ${departures.length}');
      for (final r in arrivals) out.writeln('  arrival ${r.id} ${r.guest} room ${r.room.number} ${r.status}');
      for (final r in departures) out.writeln('  departure ${r.id} ${r.guest} room ${r.room.number} ${r.status}');
    } else if (op == 'GUEST') {
      final rs = reservations.values.where((r) => r.guest == id).toList();
      if (rs.isEmpty) fail('unknown guest $id');
      out.writeln('GUEST $id');
      for (final r in rs) out.writeln('  ${r.id} room ${r.room.number} ${r.room.type} ${dateText(r.start)} -> ${dateText(r.end)} ${r.status} ${r.status == 'booked' || r.status == 'inhouse' ? 'deposit ${money(r.deposit)}' : 'paid ${money(r.paid)}'}');
      out.writeln('  total paid ${money(paid(id))} points ${paid(id) ~/ 100} tier ${tier(id)}');
    } else if (op == 'REVENUE') {
      final (first, last) = range(id, a[2], limit: false);
      final totals = List.filled(7, 0), counts = List.filled(3, 0);
      for (final r in reservations.values) {
        if (r.posting == null || r.posting! < first || r.posting! > last) continue;
        if (r.status == 'checkedout') {
          counts[0]++;
          for (var i = 0; i < 5; i++) totals[i] += r.finalBill![i];
        } else if (r.status == 'cancelled') {
          counts[1]++;
          totals[5] += r.fee;
        } else if (r.status == 'noshow') {
          counts[2]++;
          totals[6] += r.fee;
        }
      }
      out.writeln('REVENUE $id -> ${a[2]}');
      final labels = ['lodging', 'discount', 'penalty', 'extras', 'tax', 'cancellation', 'noshow'];
      for (var i = 0; i < 7; i++) out.writeln('  ${labels[i]} ${money(totals[i])}');
      out.writeln('  total ${money(totals[0] - totals[1] + totals[2] + totals[3] + totals[4] + totals[5] + totals[6])}');
      out.writeln('  checkouts ${counts[0]} cancellations ${counts[1]} noshows ${counts[2]}');
    }
  }
}
void main() {
  final hotel = Hotel(), n = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final draft = StringBuffer(), a = stdin.readLineSync()!.split(' ');
    try {
      hotel.execute(a, draft);
      stdout.write(draft);
    } on HotelError catch (e) {
      print('ERROR ${e.reason}');
    }
    draft.clear();
    hotel.processQueue(draft);
    stdout.write(draft);
  }
}
