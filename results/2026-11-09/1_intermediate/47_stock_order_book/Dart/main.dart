import 'dart:io';
import 'dart:math';
class Rejection implements Exception {
  final String message;
  Rejection(this.message);
}
void check(bool bad, String reason) {
  if (bad) throw Rejection(reason);
}
String decimal(int n) => '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
class Order {
  final String id, trader, type, side;
  String condition = '', status = 'OPEN';
  int price = 0, trigger = 0, peak = 0, quantity, left, visible = 0, filled = 0, value = 0, priority = 0;
  final List<String> history = ['ACCEPT'];
  Order(this.id, this.trader, this.type, this.side, this.quantity) : left = quantity;
  bool get resting => status == 'OPEN' || status == 'PARTIAL';
  bool get active => resting || status == 'PENDING';
  bool matches(int p) => price == 0 || (side == 'BUY' ? p <= price : p >= price);
  bool triggered(int p) => side == 'BUY' ? p >= trigger : p <= trigger;
  String get line => 'ORDER $id $status $filled/$quantity';
  String get details => '$id $trader $type $side ${price == 0 ? '-' : price} $status $filled/$quantity avg ${filled == 0 ? '-' : decimal(value * 100 ~/ filled)}${trigger == 0 ? '' : ' trigger $trigger'}';
  void fill(int number, int p, int q) {
    left -= q;
    filled += q;
    value += p * q;
    history.add('FILL $number $p $q');
  }
}
class Trader {
  final String name;
  int bought = 0, sold = 0, cash = 0, fees = 0;
  int? limit;
  Trader(this.name);
  int get net => bought - sold;
  int get volume => bought + sold;
  int pnl(int mark) => cash + net * mark;
  String position(int mark) => 'POSITION $name bought $bought sold $sold net $net cash $cash fees $fees pnl ${pnl(mark)}';
}
class Trade {
  final int number, price, quantity, buyFee, sellFee;
  final Order buy, sell, taker;
  Trade(this.number, this.price, this.quantity, this.buy, this.sell, this.taker, this.buyFee, this.sellFee);
  String get line => 'TRADE $number $price $quantity ${buy.id} ${buy.trader} ${sell.id} ${sell.trader}';
}
class Level {
  final int price;
  int quantity = 0, count = 0;
  Level(this.price);
}
class Engine {
  final Map<String, Order> orders = {};
  final Map<String, Trader> traders = {};
  final List<Order> pending = [], buys = [], sells = [];
  final List<Trade> trades = [];
  final StringBuffer output = StringBuffer();
  int makerFee = 0, takerFee = 0, band = 0, tick = 1, lot = 1, priority = 0;
  bool halted = false;
  void emit(List<Object> parts) => output.writeln(parts.join(' '));
  List<Order> book(String side) => side == 'BUY' ? buys : sells;
  List<Order> opposite(String side) => side == 'BUY' ? sells : buys;
  int compare(Order a, Order b, String side) {
    final p = side == 'BUY' ? b.price.compareTo(a.price) : a.price.compareTo(b.price);
    return p == 0 ? a.priority.compareTo(b.priority) : p;
  }
  Order? best(List<Order> b) {
    Order? result;
    for (final o in b) {
      if (result == null || compare(o, result, identical(b, buys) ? 'BUY' : 'SELL') < 0) result = o;
    }
    return result;
  }
  int get last => trades.isEmpty ? 0 : trades.last.price;
  Trader register(String name) => traders.putIfAbsent(name, () => Trader(name));
  Trader trader(String name) {
    check(!traders.containsKey(name), 'unknown trader');
    return traders[name]!;
  }
  Order order(String id) {
    check(!orders.containsKey(id), 'unknown order');
    return orders[id]!;
  }
  List<Order> active(String name) => orders.values.where((o) => o.trader == name && o.active).toList();
  int exposure(String name, String side, [Order? excluded]) {
    int n = side == 'BUY' ? traders[name]!.net : -traders[name]!.net;
    for (final o in active(name)) {
      if (o != excluded && o.side == side) n += o.left;
    }
    return n;
  }
  void risk(String name, String side, int q, [Order? excluded]) {
    final limit = traders[name]?.limit;
    if (limit != null) check(exposure(name, side, excluded) + q > limit, 'risk limit');
  }
  void checkBand(int p) => check(band > 0 && last != 0 && (p - last).abs() > band, 'outside band');
  void match(Order x) {
    final b = opposite(x.side);
    while (x.left > 0) {
      final y = best(b);
      if (y == null || !x.matches(y.price)) break;
      if (x.trader == y.trader) {
        emit(['STP', y.id, y.left]);
        y.history.add('STP ${y.left}');
        b.remove(y);
        y.left = 0;
        y.status = 'CANCELLED';
        continue;
      }
      final q = min(x.left, y.visible), p = y.price;
      final buy = x.side == 'BUY' ? x : y, sell = x.side == 'BUY' ? y : x;
      final xf = q * takerFee, yf = q * makerFee;
      final t = Trade(trades.length + 1, p, q, buy, sell, x, buy == x ? xf : yf, sell == x ? xf : yf);
      trades.add(t);
      x.fill(t.number, p, q);
      y.fill(t.number, p, q);
      y.visible -= q;
      final bt = traders[buy.trader]!, st = traders[sell.trader]!;
      bt.bought += q;
      bt.cash -= p * q + t.buyFee;
      bt.fees += t.buyFee;
      st.sold += q;
      st.cash += p * q - t.sellFee;
      st.fees += t.sellFee;
      emit([t.line]);
      if (y.left == 0) {
        b.remove(y);
        y.status = 'FILLED';
      }
      else {
        y.status = 'PARTIAL';
        if (y.visible == 0) {
          y.priority = ++priority;
          y.visible = min(y.peak, y.left);
          y.history.add('REFRESH ${y.visible} ${y.left - y.visible}');
          emit(['REFRESH', y.id, y.visible, y.left - y.visible]);
        }
      }
    }
  }
  void post(Order o, [bool forceRest = false]) {
    if (o.left == 0) {
      o.status = 'FILLED';
    }
    else if (forceRest || o.type == 'ICEBERG' || o.type == 'STOPLIMIT' || (o.type == 'LIMIT' && o.condition != 'IOC')) {
      o.priority = ++priority;
      o.visible = o.peak == 0 ? o.left : min(o.peak, o.left);
      book(o.side).add(o);
      o.status = o.filled > 0 ? 'PARTIAL' : 'OPEN';
      o.history.add('REST ${o.price} ${o.visible}');
    } else {
      o.history.add('EXPIRE ${o.left}');
      o.left = 0;
      o.status = 'CANCELLED';
    }
    emit([o.line]);
  }
  void trigger() {
    while (trades.isNotEmpty) {
      final p = last, batch = pending.where((o) => o.triggered(last)).toList();
      if (batch.isEmpty) return;
      pending.removeWhere((o) => o.triggered(p));
      for (final o in batch) {
        emit(['TRIGGER', o.id]);
        o.history.add('TRIGGER');
        match(o);
        post(o);
      }
    }
  }
  void cancel(Order o) {
    if (o.status == 'PENDING') {
      pending.remove(o);
    } else {
      book(o.side).remove(o);
    }
    o.history.add('CANCEL ${o.left}');
    o.left = 0;
    o.status = 'CANCELLED';
    emit([o.line]);
  }
  void newOrder(List<String> a) {
    final kind = a[0], market = a[0] == 'MARKET', stop = a[0] == 'STOP', sl = a[0] == 'STOPLIMIT', ice = a[0] == 'ICEBERG';
    final p = market || stop ? 0 : int.parse(a[sl ? 5 : 4]), tr = stop || sl ? int.parse(a[4]) : 0;
    final q = int.parse(a[market ? 4 : sl ? 6 : 5]);
    final o = Order(a[1], a[2], kind, a[3], q)..price = p..trigger = tr;
    if (ice) o.peak = int.parse(a[6]);
    if (kind == 'LIMIT' && a.length == 7) o.condition = a[6];
    check(halted, 'halted');
    check(orders.containsKey(o.id), 'duplicate id');
    check((!market && !stop && p == 0) || ((stop || sl) && tr == 0), 'invalid price');
    check(q == 0, 'invalid quantity');
    check(p % tick != 0 || tr % tick != 0, 'invalid tick');
    check(q % lot != 0, 'invalid lot');
    if (ice) check(o.peak == 0 || o.peak > q || o.peak % lot != 0, 'invalid peak');
    if (stop || sl) check(last != 0 && o.triggered(last), 'invalid trigger');
    if (p != 0) checkBand(p);
    risk(o.trader, o.side, q);
    final b = best(opposite(o.side));
    if (o.condition == 'POSTONLY') check(b != null && o.matches(b.price), 'would cross');
    if (o.condition == 'FOK') {
      int total = 0;
      for (final y in opposite(o.side)) {
        if (y.trader != o.trader && o.matches(y.price)) total += y.left;
      }
      check(total < q, 'unfillable');
    }
    register(o.trader);
    orders[o.id] = o;
    if (stop || sl) {
      o.status = 'PENDING';
      pending.add(o);
      emit([o.line]);
    }
    else {
      if (o.condition != 'POSTONLY') match(o);
      post(o);
      trigger();
    }
  }
  List<Level> levels(String side) {
    final sorted = List<Order>.of(book(side))..sort((a, b) => compare(a, b, side));
    final result = <Level>[];
    for (final o in sorted) {
      if (result.isEmpty || result.last.price != o.price) result.add(Level(o.price));
      result.last.quantity += o.visible;
      result.last.count++;
    }
    return result;
  }
  int positive(String text, String reason) {
    final n = int.parse(text);
    check(n == 0, reason);
    return n;
  }
  String bar(List<Trade> ts) {
    int high = ts.first.price, low = high, volume = 0;
    for (final t in ts) {
      high = max(high, t.price);
      low = min(low, t.price);
      volume += t.quantity;
    }
    return 'open ${ts.first.price} high $high low $low close ${ts.last.price} volume $volume';
  }
  void execute(String line) {
    final a = line.split(' '), c = line.split(' ')[0];
    try {
      switch (c) {
        case 'LIMIT':
        case 'MARKET':
        case 'STOP':
        case 'STOPLIMIT':
        case 'ICEBERG': {
          newOrder(a);
        }
        case 'CANCEL': {
          final o = order(a[1]);
          check(!o.active, 'not open');
          cancel(o);
        }
        case 'REPLACE': {
          check(halted, 'halted');
          final o = order(a[1]);
          check(!o.resting, 'not open');
          final p = int.parse(a[2]), q = int.parse(a[3]), moved = int.parse(a[2]) != o.price;
          check(p == 0, 'invalid price');
          check(q == 0, 'invalid quantity');
          check(moved && p % tick != 0, 'invalid tick');
          check(q % lot != 0, 'invalid lot');
          check(!moved && q == o.left, 'no change');
          if (moved) checkBand(p);
          if (q > o.left) risk(o.trader, o.side, q, o);
          o.quantity = o.filled + q;
          final kept = !moved && q < o.left;
          o.history.add('REPLACE $p $q ${kept ? 'kept' : 'lost'}');
          emit(['REPLACE', o.id, kept ? 'kept' : 'lost']);
          if (kept) {
            o.left = q;
            o.visible = min(o.visible, q);
            emit([o.line]);
          }
          else {
            book(o.side).remove(o);
            o.price = p;
            o.left = q;
            match(o);
            post(o, true);
            trigger();
          }
        }
        case 'CANCELALL': {
          trader(a[1]);
          final xs = active(a[1]);
          emit([c, a[1], xs.length]);
          for (final o in xs) {
            cancel(o);
          }
        }
        case 'HALT': {
          check(halted, 'already halted');
          halted = true;
          emit([c]);
        }
        case 'RESUME': {
          check(!halted, 'not halted');
          halted = false;
          emit([c]);
        }
        case 'RISK': {
          register(a[1]).limit = int.parse(a[2]);
          emit([c, a[1], a[2], 'exposure buy', exposure(a[1], 'BUY'), 'sell', exposure(a[1], 'SELL')]);
        }
        case 'FEE': {
          final m = int.parse(a[1]), t = int.parse(a[2]);
          check(m + t < 0, 'invalid fee');
          makerFee = m;
          takerFee = t;
          emit(['FEE maker', m, 'taker', t]);
        }
        case 'BAND': {
          band = int.parse(a[1]);
          emit([c, band]);
        }
        case 'TICK':
        case 'LOT': {
          final v = positive(a[1], 'invalid size');
          if (c == 'TICK') {
            tick = v;
          } else {
            lot = v;
          }
          emit([c, v]);
        }
        case 'BOOK': {
          final n = positive(a[1], 'invalid depth'), bids = levels('BUY'), asks = levels('SELL');
          emit(['BOOK bids', bids.length, 'asks', asks.length]);
          for (final l in asks.take(n).toList().reversed) {
            emit(['ASK', l.price, l.quantity, l.count]);
          }
          for (final l in bids.take(n)) {
            emit(['BID', l.price, l.quantity, l.count]);
          }
        }
        case 'ORDERS': {
          trader(a[1]);
          final xs = active(a[1]);
          emit([c, a[1], xs.length]);
          for (final o in xs) {
            emit([o.details]);
          }
        }
        case 'STATUS': {
          emit([c, order(a[1]).details]);
        }
        case 'HISTORY': {
          final o = order(a[1]);
          emit([c, o.id, o.history.length]);
          for (final h in o.history) {
            emit([h]);
          }
        }
        case 'POSITION': {
          emit([trader(a[1]).position(last)]);
        }
        case 'FILLS': {
          trader(a[1]);
          final ts = trades.where((t) => t.buy.trader == a[1] || t.sell.trader == a[1]).toList();
          emit([c, a[1], ts.length]);
          int net = 0;
          for (final t in ts) {
            final buy = t.buy.trader == a[1], o = t.buy.trader == a[1] ? t.buy : t.sell;
            net += buy ? t.quantity : -t.quantity;
            emit([t.number, o.side, t.price, t.quantity, o.id, t.taker == o ? 'TAKER' : 'MAKER', 'fee', buy ? t.buyFee : t.sellFee, 'net', net]);
          }
        }
        case 'LAST': {
          if (trades.isEmpty) {
            emit([c, 'none']);
          } else {
            emit([c, last, trades.last.quantity]);
          }
        }
        case 'VWAP': {
          int v = 0, amount = 0;
          for (final t in trades) {
            v += t.quantity;
            amount += t.price * t.quantity;
          }
          if (v == 0) {
            emit([c, 'none']);
          } else {
            emit([c, decimal(amount * 100 ~/ v), 'volume', v, 'trades', trades.length]);
          }
        }
        case 'SPREAD': {
          final b = best(buys), s = best(sells);
          if (b == null || s == null) {
            emit(['SPREAD bid', b?.price ?? 'none', 'ask', s?.price ?? 'none']);
          } else {
            final sum = b.price + s.price;
            emit(['SPREAD bid', b.price, 'ask', s.price, 'spread', s.price - b.price, 'mid', '${sum ~/ 2}.${sum % 2 == 0 ? 0 : 5}']);
          }
        }
        case 'IMPACT': {
          final q = positive(a[2], 'invalid quantity');
          int left = q, cost = 0, worst = 0, used = 0, total = 0;
          for (final l in levels(a[1] == 'BUY' ? 'SELL' : 'BUY')) {
            total += l.quantity;
            if (left > 0) {
              final u = min(left, l.quantity);
              left -= u;
              cost += u * l.price;
              worst = l.price;
              used++;
            }
          }
          if (left > 0) {
            emit([c, a[1], q, 'insufficient', total]);
          } else {
            emit([c, a[1], q, 'avg', decimal(cost * 100 ~/ q), 'worst', worst, 'levels', used]);
          }
        }
        case 'TRADES': {
          final n = positive(a[1], 'invalid count'), m = min(n, trades.length);
          emit([c, m, 'of', trades.length]);
          for (final t in trades.skip(trades.length - m)) {
            emit([t.line]);
          }
        }
        case 'BARS': {
          final k = positive(a[1], 'invalid count');
          emit([c, (trades.length + k - 1) ~/ k]);
          for (int i = 0; i < trades.length; i += k) {
            emit([i ~/ k + 1, bar(trades.sublist(i, min(i + k, trades.length)))]);
          }
        }
        case 'RANK': {
          final ts = traders.values.toList()..sort((a, b) {
            int r = b.pnl(last).compareTo(a.pnl(last));
            if (r == 0) r = b.volume.compareTo(a.volume);
            return r == 0 ? a.name.compareTo(b.name) : r;
          });
          emit([c, ts.length]);
          for (int i = 0; i < ts.length; i++) {
            final t = ts[i];
            emit([i + 1, t.name, 'pnl', t.pnl(last), 'volume', t.volume]);
          }
        }
        case 'FLOW': {
          int buy = 0, sell = 0;
          for (final t in trades) {
            if (t.taker == t.buy) {
              buy += t.quantity;
            } else {
              sell += t.quantity;
            }
          }
          emit(['FLOW buy', buy, 'sell', sell, 'net', buy - sell]);
        }
        case 'SUMMARY': {
          if (trades.isEmpty) {
            emit(['SUMMARY trades 0']);
          } else {
            int volume = 0, fees = 0;
            for (final t in trades) {
              volume += t.quantity;
              fees += t.buyFee + t.sellFee;
            }
            final b = bar(trades);
            emit(['SUMMARY trades', trades.length, 'volume', volume, b.substring(0, b.lastIndexOf(' volume')), 'fees', fees]);
          }
          final names = traders.keys.toList()..sort();
          for (final name in names) {
            emit([traders[name]!.position(last)]);
          }
        }
      }
    }
    on Rejection catch (e) {
      emit([if (['LIMIT', 'MARKET', 'STOP', 'STOPLIMIT', 'ICEBERG', 'CANCEL', 'REPLACE'].contains(c)) 'REJECT ${a[1]}' else 'ERROR', e.message]);
    }
  }
}
void main() {
  final e = Engine(), n = int.parse(stdin.readLineSync()!);
  for (int i = 0; i < n; i++) {
    e.execute(stdin.readLineSync()!);
  }
  stdout.write(e.output);
}
