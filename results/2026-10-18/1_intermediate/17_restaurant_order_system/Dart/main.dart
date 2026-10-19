import 'dart:io';

const stationNames = ['GRILL', 'FRY', 'COLD', 'BAR'];
const courseNames = ['DRINK', 'STARTER', 'MAIN', 'DESSERT'];

class CommandError implements Exception {
  final String message;
  CommandError(this.message);

  @override
  String toString() => message;
}

Never fail(String message) => throw CommandError(message);

int cents(String text) => int.parse(text.replaceAll('.', ''));

String money(int value) =>
    '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

String clock(int elapsed) {
  final minutes = elapsed + 660;
  return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

int rounded(int value, int rate) => (value * rate + 50) ~/ 100;

class DiningTable {
  final int number;
  final int seats;
  Check? check;

  DiningTable(this.number, this.seats);
}

class Server {
  final String name;
  int load = 0;
  int parties = 0;
  int sales = 0;
  int tips = 0;

  Server(this.name);
}

class MenuItem {
  final String name;
  String station;
  int prep;
  int price;
  String course;
  int? stock;

  MenuItem(this.name, this.station, this.prep, this.price, this.course);
}

class Check {
  final String party;
  final int size;
  DiningTable table;
  final Server server;
  final int since;
  final List<OrderLine> lines = [];
  int paid = 0;
  int discount = 0;
  bool closed = false;

  Check(this.party, this.size, this.table, this.server, this.since);

  List<OrderLine> get active =>
      lines.where((line) => line.state != 'VOID').toList();

  List<int> amounts() {
    final subtotal = active.fold<int>(0, (sum, line) => sum + line.amount);
    final reduction = rounded(subtotal, discount);
    final after = subtotal - reduction;
    final service = size >= 6 ? rounded(after, 18) : 0;
    final tax = rounded(after, 8);
    final total = after + service + tax;
    return [subtotal, reduction, service, tax, total, total - paid];
  }
}

class OrderLine {
  final int number;
  final Check check;
  int seat;
  final String name;
  final int quantity;
  final String station;
  final int prep;
  final int price;
  final String course;
  String state = 'ORDERED';
  String? comp;
  int fired = 0;
  int ready = 0;
  bool started = false;

  OrderLine(this.number, this.check, this.seat, MenuItem item,
      this.quantity, this.price)
      : name = item.name,
        station = item.station,
        prep = item.prep,
        course = item.course;

  int get amount => comp == null ? price * quantity : 0;
  String get tag => '#$number';
}

class Station {
  final String name;
  final int capacity;
  bool up = true;
  final List<OrderLine> queue = [];
  final List<OrderLine> cooking = [];
  int tickets = 0;
  int ticketTotal = 0;
  int ticketMax = 0;
  int remakes = 0;

  Station(this.name) : capacity = name == 'BAR' ? 2 : 1;
}

class Waiting {
  final String party;
  final int size;
  final int joined;

  Waiting(this.party, this.size, this.joined);
}

class Restaurant {
  int time = 0;
  final Map<int, DiningTable> tables = {};
  final List<Server> servers = [];
  final Set<String> serverNames = {};
  List<Waiting> waiting = [];
  final Map<String, Check> seated = {};
  final Map<String, MenuItem> menu = {};
  final List<OrderLine> lines = [];
  final Map<String, Station> stations = {
    for (final name in stationNames) name: Station(name),
  };
  int happyRate = 0;
  int? happyUntil;
  int guests = 0;
  int parties = 0;
  int closed = 0;
  int stayTotal = 0;
  final List<int> sales = List.filled(4, 0);
  final List<int> totals = List.filled(5, 0);
  final Map<String, int> payments = {'CASH': 0, 'CARD': 0};
  int tips = 0;
  int comps = 0;
  int compAmount = 0;
  int voids = 0;
  final Map<String, int> served = {};
  final List<String> output = [];

  void emit(Iterable<Object?> parts) {
    output.add(parts.map((part) => part.toString()).join(' '));
  }

  DiningTable table(String text, [bool occupied = false]) {
    final selected = tables[int.parse(text)];
    if (selected == null) fail('unknown table $text');
    if (occupied && selected.check == null) fail('table $text is free');
    return selected;
  }

  OrderLine line(String text) {
    final number = int.parse(text);
    if (number < 1 || number > lines.length) fail('unknown line $text');
    return lines[number - 1];
  }

  void unlocked(Check check) {
    if (check.paid != 0) {
      fail('check for table ${check.table.number} is locked');
    }
  }

  void modification(OrderLine order) {
    if (order.state == 'VOID') fail('${order.tag} is void');
    if (order.check.closed) fail('${order.tag} is on a closed check');
    unlocked(order.check);
  }

  void allServed(Check check) {
    final count = check.active.where((line) => line.state != 'SERVED').length;
    if (count != 0) {
      fail('table ${check.table.number} has $count unserved items');
    }
  }

  DiningTable? selectTable(int size) {
    DiningTable? best;
    for (final table in tables.values) {
      if (table.check == null &&
          table.seats >= size &&
          (best == null ||
              table.seats < best.seats ||
              (table.seats == best.seats && table.number < best.number))) {
        best = table;
      }
    }
    return best;
  }

  Check seatParty(String party, int size, DiningTable table) {
    var server = servers.first;
    for (final candidate in servers) {
      if (candidate.load < server.load) server = candidate;
    }
    final check = Check(party, size, table, server, time);
    table.check = check;
    seated[party] = check;
    server.load++;
    server.parties++;
    guests += size;
    parties++;
    return check;
  }

  void processWaitlist() {
    final remaining = <Waiting>[];
    for (final entry in waiting) {
      final table = selectTable(entry.size);
      if (table == null) {
        remaining.add(entry);
      } else {
        final check = seatParty(entry.party, entry.size, table);
        emit(['SEATED', entry.party, entry.size, 'table', table.number,
          'server', check.server.name, 'waited', time - entry.joined]);
      }
    }
    waiting = remaining;
  }

  void closeCheck(Check check) {
    final amounts = check.amounts();
    for (final line in check.active) {
      sales[courseNames.indexOf(line.course)] += line.amount;
    }
    for (var i = 0; i < totals.length; i++) {
      totals[i] += amounts[i];
    }
    final stayed = time - check.since;
    closed++;
    stayTotal += stayed;
    check.server.sales += amounts[4];
    check.server.load--;
    check.closed = true;
    check.table.check = null;
    seated.remove(check.party);
    emit(['FREE', 'table', check.table.number, check.party, 'stayed', stayed]);
    processWaitlist();
  }

  void startStation(String name, int when) {
    final station = stations[name]!;
    while (station.up &&
        station.queue.isNotEmpty &&
        station.cooking.length < station.capacity) {
      final order = station.queue.removeAt(0);
      order.state = 'COOKING';
      order.started = true;
      order.ready = when + order.prep;
      station.cooking.add(order);
    }
  }

  void startAll(int when) {
    for (final name in stationNames) {
      startStation(name, when);
    }
  }

  Map<int, int> seatSubtotals(Check check) {
    final values = <int, int>{};
    for (final line in check.active) {
      values[line.seat] = (values[line.seat] ?? 0) + line.amount;
    }
    return values;
  }

  Map<int, int> allocate(Map<int, int> values, int rate) {
    final amounts = <int, int>{};
    var total = 0;
    var initiallyAllocated = 0;
    for (final entry in values.entries) {
      final part = entry.value * rate ~/ 100;
      amounts[entry.key] = part;
      total += entry.value;
      initiallyAllocated += part;
    }
    final extra = rounded(total, rate) - initiallyAllocated;
    final ranking = values.keys.toList()
      ..sort((a, b) {
        final left = values[a]! * rate % 100;
        final right = values[b]! * rate % 100;
        return left != right ? right.compareTo(left) : a.compareTo(b);
      });
    for (var i = 0; i < extra; i++) {
      amounts[ranking[i]] = amounts[ranking[i]]! + 1;
    }
    return amounts;
  }

  void cmdTable(List<String> a) {
    final number = int.parse(a[0]);
    final seats = int.parse(a[1]);
    if (tables.containsKey(number)) fail('table $number already exists');
    tables[number] = DiningTable(number, seats);
    emit(['TABLE', number, 'seats', seats]);
    processWaitlist();
  }

  void cmdStaff(List<String> a) {
    if (serverNames.contains(a[0])) fail('${a[0]} is already on duty');
    servers.add(Server(a[0]));
    serverNames.add(a[0]);
    emit(['STAFF', a[0]]);
  }

  void cmdSeat(List<String> a) {
    final party = a[0];
    final size = int.parse(a[1]);
    final existing = seated[party];
    if (existing != null) {
      fail('$party is already seated at table ${existing.table.number}');
    }
    if (waiting.any((entry) => entry.party == party)) {
      fail('$party is already waiting');
    }
    if (!tables.values.any((table) => table.seats >= size)) {
      fail('no table for party of $size');
    }
    if (servers.isEmpty) fail('no server on duty');
    final selected = selectTable(size);
    if (selected == null) {
      waiting.add(Waiting(party, size, time));
      emit(['WAIT', party, size, 'position', waiting.length]);
    } else {
      final check = seatParty(party, size, selected);
      emit(['SEAT', party, size, 'table', selected.number, 'server', check.server.name]);
    }
  }

  void cmdCancel(List<String> a) {
    for (var i = 0; i < waiting.length; i++) {
      final entry = waiting[i];
      if (entry.party == a[0]) {
        waiting.removeAt(i);
        emit(['CANCEL', entry.party, entry.size, 'waited', time - entry.joined]);
        return;
      }
    }
    fail('${a[0]} is not waiting');
  }

  void cmdMove(List<String> a) {
    final source = table(a[0]);
    final destination = table(a[1]);
    final check = source.check;
    if (check == null) fail('table ${a[0]} is free');
    if (destination.check != null) fail('table ${a[1]} is occupied');
    if (destination.seats < check.size) {
      fail('table ${a[1]} is too small for ${check.party}');
    }
    source.check = null;
    destination.check = check;
    check.table = destination;
    emit(['MOVE', check.party, 'table', a[0], '->', a[1]]);
    processWaitlist();
  }

  void cmdMenu(List<String> a) {
    if (!stationNames.contains(a[1])) fail('unknown station ${a[1]}');
    if (!courseNames.contains(a[4])) fail('unknown course ${a[4]}');
    final existing = menu[a[0]];
    final action = existing == null ? 'ADD' : 'UPDATE';
    if (existing == null) {
      menu[a[0]] = MenuItem(a[0], a[1], int.parse(a[2]), cents(a[3]), a[4]);
    } else {
      existing.station = a[1];
      existing.prep = int.parse(a[2]);
      existing.price = cents(a[3]);
      existing.course = a[4];
    }
    emit(['MENU', action, a[0], a[1], a[2], a[3], a[4]]);
  }

  void cmdStock(List<String> a) {
    final item = menu[a[0]];
    if (item == null) fail('unknown item ${a[0]}');
    item.stock = int.parse(a[1]);
    emit(['STOCK', a[0], a[1]]);
  }

  void cmdHappy(List<String> a) {
    happyRate = int.parse(a[0]);
    happyUntil = time + int.parse(a[1]);
    emit(['HAPPY', '${a[0]}%', 'until', clock(happyUntil!)]);
  }

  void cmdItems(List<String> a) {
    emit(['ITEMS', menu.length]);
    final items = menu.values.toList()
      ..sort((a, b) {
        final left = courseNames.indexOf(a.course);
        final right = courseNames.indexOf(b.course);
        return left != right ? left.compareTo(right) : a.name.compareTo(b.name);
      });
    for (final item in items) {
      emit([item.course, item.name, item.station, item.prep, money(item.price),
        item.stock?.toString() ?? '-']);
    }
  }

  void cmdOrder(List<String> a) {
    final check = table(a[0], true).check!;
    unlocked(check);
    final seat = int.parse(a[1]);
    final quantity = int.parse(a[3]);
    if (seat > check.size) fail('seat $seat out of range for table ${a[0]}');
    final item = menu[a[2]];
    if (item == null) fail('unknown item ${a[2]}');
    if (item.stock != null && item.stock! < quantity) {
      fail('only ${item.stock} ${item.name} left');
    }
    final happy = item.course == 'DRINK' &&
        happyUntil != null && time < happyUntil!;
    final price = item.price - (happy ? rounded(item.price, happyRate) : 0);
    final order = OrderLine(lines.length + 1, check, seat, item, quantity, price);
    lines.add(order);
    check.lines.add(order);
    emit(['ORDER', order.tag, 'table', a[0], 'seat', seat, item.name,
      'x$quantity', money(order.amount), if (happy) 'HAPPY']);
    if (item.stock != null) {
      item.stock = item.stock! - quantity;
      if (item.stock == 0) emit(['SOLDOUT', item.name]);
    }
  }

  void cmdFire(List<String> a) {
    final check = table(a[0], true).check!;
    if (!courseNames.contains(a[1])) fail('unknown course ${a[1]}');
    final selected = check.lines
        .where((line) => line.course == a[1] && line.state == 'ORDERED')
        .toList();
    if (selected.isEmpty) fail('nothing to fire for ${a[1]} at table ${a[0]}');
    final course = courseNames.indexOf(a[1]);
    if (course >= 2) {
      for (var earlier = 1; earlier < course; earlier++) {
        if (check.lines.any((line) =>
            line.course == courseNames[earlier] && line.state == 'ORDERED')) {
          fail('fire ${courseNames[earlier]} first');
        }
      }
    }
    for (final order in selected) {
      order.state = 'QUEUED';
      order.fired = time;
      stations[order.station]!.queue.add(order);
    }
    emit(['FIRE', 'table', a[0], a[1], ...selected.map((line) => line.tag)]);
    startAll(time);
  }

  void cmdTick(List<String> a) {
    final target = time + int.parse(a[0]);
    emit(['TICK', clock(target)]);
    while (true) {
      int? completion;
      for (final station in stations.values) {
        for (final line in station.cooking) {
          if (completion == null || line.ready < completion) completion = line.ready;
        }
      }
      if (completion == null || completion > target) break;
      for (final name in stationNames) {
        final station = stations[name]!;
        final finished = station.cooking
            .where((line) => line.ready == completion).toList()
          ..sort((a, b) => a.number.compareTo(b.number));
        for (final order in finished) {
          station.cooking.remove(order);
          order.state = 'READY';
          final ticket = completion - order.fired;
          station.tickets++;
          station.ticketTotal += ticket;
          if (ticket > station.ticketMax) station.ticketMax = ticket;
          emit(['READY', clock(completion), name, order.tag, order.name,
            'x${order.quantity}', 'table', order.check.table.number, 'seat', order.seat]);
        }
      }
      startAll(completion);
    }
    time = target;
  }

  void cmdServe(List<String> a) {
    final check = table(a[0], true).check!;
    final ready = check.lines.where((line) => line.state == 'READY').toList();
    if (ready.isEmpty) fail('nothing ready for table ${a[0]}');
    for (final order in ready) {
      order.state = 'SERVED';
      served[order.name] = (served[order.name] ?? 0) + order.quantity;
    }
    emit(['SERVE', 'table', a[0], ...ready.map((line) => line.tag)]);
  }

  void cmdRush(List<String> a) {
    final order = line(a[0]);
    if (order.state != 'QUEUED') fail('${order.tag} is not queued');
    final station = stations[order.station]!;
    station.queue.remove(order);
    station.queue.insert(0, order);
    emit(['RUSH', order.tag, order.station]);
  }

  void cmdRemake(List<String> a) {
    final order = line(a[0]);
    if (order.check.closed) fail('${order.tag} is on a closed check');
    if (order.state != 'READY' && order.state != 'SERVED') {
      fail('${order.tag} is not ready or served');
    }
    final station = stations[order.station]!;
    order.state = 'QUEUED';
    order.fired = time;
    station.queue.insert(0, order);
    station.remakes++;
    emit(['REMAKE', order.tag, order.name, order.station]);
    startStation(order.station, time);
  }

  void cmdVoid(List<String> a) {
    final order = line(a[0]);
    if (order.state == 'VOID') fail('${order.tag} is already void');
    if (order.started) fail('${order.tag} has already started');
    if (order.state == 'QUEUED') {
      stations[order.station]!.queue.remove(order);
    }
    order.state = 'VOID';
    final item = menu[order.name]!;
    if (item.stock != null) item.stock = item.stock! + order.quantity;
    voids++;
    emit(['VOID', order.tag, order.name, 'x${order.quantity}']);
  }

  void cmdStation(List<String> a) {
    final station = stations[a[0]];
    if (station == null) fail('unknown station ${a[0]}');
    if (a[1] == 'DOWN' && !station.up) {
      fail('station ${a[0]} is already down');
    }
    if (a[1] == 'UP' && station.up) {
      fail('station ${a[0]} is not down');
    }
    station.up = a[1] == 'UP';
    if (station.up) startStation(a[0], time);
    emit(['STATION', a[0], a[1]]);
  }

  void cmdComp(List<String> a) {
    final order = line(a[0]);
    modification(order);
    if (order.comp != null) fail('${order.tag} is already comped');
    final amount = order.amount;
    emit(['COMP', order.tag, order.name, money(amount), a[1]]);
    comps++;
    compAmount += amount;
    order.comp = a[1];
  }

  void cmdTransfer(List<String> a) {
    final order = line(a[0]);
    modification(order);
    final seat = int.parse(a[1]);
    if (seat > order.check.size) {
      fail('seat $seat out of range for table ${order.check.table.number}');
    }
    if (seat == order.seat) fail('${order.tag} is already on seat $seat');
    emit(['TRANSFER', order.tag, 'seat', order.seat, '->', seat]);
    order.seat = seat;
  }

  void cmdDiscount(List<String> a) {
    final check = table(a[0], true).check!;
    unlocked(check);
    check.discount = int.parse(a[1]);
    emit(['DISCOUNT', 'table', a[0], '${a[1]}%']);
  }

  void cmdBill(List<String> a) {
    final check = table(a[0], true).check!;
    emit(['BILL', 'table', a[0], check.party, 'guests', check.size]);
    final subtotals = seatSubtotals(check);
    final seats = subtotals.keys.toList()..sort();
    for (final seat in seats) {
      emit(['SEAT', seat, money(subtotals[seat]!)]);
      for (final order in check.lines) {
        if (order.state == 'VOID' || order.seat != seat) continue;
        emit([order.tag, order.name, 'x${order.quantity}', money(order.amount),
          if (order.comp != null) ...['COMP', order.comp!]]);
      }
    }
    final amounts = check.amounts();
    emit(['SUBTOTAL', money(amounts[0])]);
    if (check.discount != 0) {
      emit(['DISCOUNT', '${check.discount}%', money(amounts[1])]);
    }
    if (check.size >= 6) emit(['SERVICE', money(amounts[2])]);
    emit(['TAX', money(amounts[3])]);
    emit(['TOTAL', money(amounts[4])]);
    if (check.paid != 0) {
      emit(['PAID', money(check.paid)]);
      emit(['DUE', money(amounts[5])]);
    }
  }

  void cmdSplit(List<String> a) {
    final check = table(a[0], true).check!;
    final due = check.amounts()[5];
    if (due == 0) fail('nothing to split for table ${a[0]}');
    if (a[1] == 'EVEN') {
      final count = int.parse(a[2]);
      if (count > check.size) fail('cannot split table ${a[0]} $count ways');
      emit(['SPLIT', 'table', a[0], 'EVEN', count, 'due', money(due)]);
      for (var payer = 1; payer <= count; payer++) {
        emit(['PAYER', payer, money(due ~/ count + (payer <= due % count ? 1 : 0))]);
      }
      return;
    }
    if (check.paid != 0) fail('table ${a[0]} has payments');
    final subtotals = seatSubtotals(check);
    final discounts = allocate(subtotals, check.discount);
    final after = <int, int>{
      for (final entry in subtotals.entries)
        entry.key: entry.value - discounts[entry.key]!,
    };
    final services = check.size >= 6
        ? allocate(after, 18)
        : <int, int>{for (final seat in after.keys) seat: 0};
    final taxes = allocate(after, 8);
    emit(['SPLIT', 'table', a[0], 'BYSEAT', 'total', money(check.amounts()[4])]);
    final seats = subtotals.keys.toList()..sort();
    for (final seat in seats) {
      final total = after[seat]! + services[seat]! + taxes[seat]!;
      emit(['SEAT', seat, 'subtotal', money(subtotals[seat]!),
        'discount', money(discounts[seat]!), 'service', money(services[seat]!),
        'tax', money(taxes[seat]!), 'total', money(total)]);
    }
  }

  void cmdPay(List<String> a) {
    final check = table(a[0], true).check!;
    if (!payments.containsKey(a[1])) fail('unknown method ${a[1]}');
    allServed(check);
    final due = check.amounts()[5];
    if (due == 0) fail('nothing to pay for table ${a[0]}');
    final value = cents(a[2]);
    final applied = value < due ? value : due;
    check.paid += applied;
    payments[a[1]] = payments[a[1]]! + applied;
    if (value < due) {
      emit(['PAY', 'table', a[0], a[1], a[2], 'remaining', money(due - value)]);
    } else {
      final excess = value - due;
      emit(['PAY', 'table', a[0], a[1], a[2],
        a[1] == 'CASH' ? 'change' : 'tip', money(excess)]);
      if (a[1] == 'CARD') {
        tips += excess;
        check.server.tips += excess;
      }
      closeCheck(check);
    }
  }

  void cmdClose(List<String> a) {
    final check = table(a[0], true).check!;
    allServed(check);
    final due = check.amounts()[5];
    if (due != 0) fail('table ${a[0]} still owes ${money(due)}');
    closeCheck(check);
  }

  void cmdStatus(List<String> a) {
    final check = table(a[0], true).check!;
    emit(['STATUS', 'table', a[0], check.party, 'guests', check.size,
      'since', clock(check.since)]);
    for (final order in check.lines) {
      emit([order.tag, 'seat', order.seat, order.name, 'x${order.quantity}',
        order.course, order.state,
        if (order.state == 'COOKING') ...['until', clock(order.ready)],
        if (order.comp != null) ...['COMP', order.comp!]]);
    }
  }

  void cmdKitchen(List<String> a) {
    emit(['KITCHEN', clock(time)]);
    for (final name in stationNames) {
      final station = stations[name]!;
      final cooking = station.cooking.toList()
        ..sort((a, b) {
          final order = a.ready.compareTo(b.ready);
          return order != 0 ? order : a.number.compareTo(b.number);
        });
      final cookingText = cooking.isEmpty
          ? '-'
          : cooking.map((line) => '${line.tag}@${clock(line.ready)}').join(' ');
      final queueText = station.queue.isEmpty
          ? '-'
          : station.queue.map((line) => line.tag).join(' ');
      emit([name, station.up ? 'up' : 'down', 'cooking', cookingText,
        'queue', queueText]);
    }
  }

  void cmdFloor(List<String> a) {
    final occupied = tables.values.where((table) => table.check != null).length;
    emit(['FLOOR', clock(time), 'free', tables.length - occupied,
      'seated', occupied, 'waiting', waiting.length]);
    final numbers = tables.keys.toList()..sort();
    for (final number in numbers) {
      final selected = tables[number]!;
      final check = selected.check;
      if (check == null) {
        emit(['table', number, 'seats', selected.seats, 'free']);
      } else {
        emit(['table', number, 'seats', selected.seats, check.party,
          'guests', check.size, 'server', check.server.name,
          'since', clock(check.since), 'items', check.active.length,
          'total', money(check.amounts()[4]),
          if (check.paid != 0) ...['paid', money(check.paid)]]);
      }
    }
    for (var i = 0; i < waiting.length; i++) {
      final entry = waiting[i];
      emit(['WAITING', i + 1, entry.party, entry.size,
        'since', clock(entry.joined)]);
    }
  }

  void cmdReport(List<String> a) {
    emit(['REPORT', clock(time)]);
    emit(['COVERS', guests, 'parties', parties]);
    emit(['TURNS', closed, 'avg_stay',
      closed == 0 ? '-' : (stayTotal ~/ closed).toString()]);
    emit(['SALES', for (var i = 0; i < courseNames.length; i++) ...[
      courseNames[i], money(sales[i]),
    ]]);
    emit(['TOTALS', 'subtotal', money(totals[0]), 'discount', money(totals[1]),
      'service', money(totals[2]), 'tax', money(totals[3]),
      'total', money(totals[4])]);
    emit(['PAYMENTS', 'cash', money(payments['CASH']!),
      'card', money(payments['CARD']!), 'tips', money(tips)]);
    emit(['COMPS', comps, money(compAmount), 'VOIDS', voids]);
    final top = served.keys.toList()
      ..sort((a, b) {
        final order = served[b]!.compareTo(served[a]!);
        return order != 0 ? order : a.compareTo(b);
      });
    for (var i = 0; i < top.length && i < 3; i++) {
      emit(['TOP', i + 1, top[i], served[top[i]]!]);
    }
    for (final name in stationNames) {
      final station = stations[name]!;
      emit([name, 'tickets', station.tickets, 'avg',
        station.tickets == 0 ? '-' : (station.ticketTotal ~/ station.tickets).toString(),
        'max', station.tickets == 0 ? '-' : station.ticketMax.toString(),
        'remakes', station.remakes]);
    }
    for (final server in servers) {
      emit(['SERVER', server.name, 'tables', server.load, 'parties',
        server.parties, 'sales', money(server.sales), 'tips', money(server.tips)]);
    }
  }

  void execute(String input) {
    final words = input.trim().split(' ');
    final command = words.first;
    final args = words.skip(1).toList();
    try {
      switch (command) {
        case 'TABLE': cmdTable(args); break;
        case 'STAFF': cmdStaff(args); break;
        case 'SEAT': cmdSeat(args); break;
        case 'CANCEL': cmdCancel(args); break;
        case 'MOVE': cmdMove(args); break;
        case 'MENU': cmdMenu(args); break;
        case 'STOCK': cmdStock(args); break;
        case 'HAPPY': cmdHappy(args); break;
        case 'ITEMS': cmdItems(args); break;
        case 'ORDER': cmdOrder(args); break;
        case 'FIRE': cmdFire(args); break;
        case 'TICK': cmdTick(args); break;
        case 'SERVE': cmdServe(args); break;
        case 'RUSH': cmdRush(args); break;
        case 'REMAKE': cmdRemake(args); break;
        case 'VOID': cmdVoid(args); break;
        case 'STATION': cmdStation(args); break;
        case 'COMP': cmdComp(args); break;
        case 'TRANSFER': cmdTransfer(args); break;
        case 'DISCOUNT': cmdDiscount(args); break;
        case 'BILL': cmdBill(args); break;
        case 'SPLIT': cmdSplit(args); break;
        case 'PAY': cmdPay(args); break;
        case 'CLOSE': cmdClose(args); break;
        case 'STATUS': cmdStatus(args); break;
        case 'KITCHEN': cmdKitchen(args); break;
        case 'FLOOR': cmdFloor(args); break;
        case 'REPORT': cmdReport(args); break;
      }
    } on CommandError catch (error) {
      emit(['ERROR', error.message]);
    }
  }

  String result() => output.isEmpty ? '' : '${output.join('\n')}\n';
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final restaurant = Restaurant();
  for (var i = 0; i < count; i++) {
    restaurant.execute(stdin.readLineSync()!);
  }
  stdout.write(restaurant.result());
}
