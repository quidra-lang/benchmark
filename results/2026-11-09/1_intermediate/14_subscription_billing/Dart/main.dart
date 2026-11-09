import 'dart:io';

const periodLengths = {'WEEKLY': 7, 'MONTHLY': 30, 'YEARLY': 360};

int cents(String text) => int.parse(text.replaceAll('.', ''));

String money(int amount) {
  final absolute = amount.abs();
  return '${amount < 0 ? '-' : ''}${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}

String signedMoney(int amount) => '${amount > 0 ? '+' : ''}${money(amount)}';
String percentage(int amount) => '${money(amount)}%';

class CommandError implements Exception {
  final String reason;
  CommandError(this.reason);
  @override
  String toString() => reason;
}

class Tier {
  final int? upper;
  final int unitPrice;
  final int flatFee;
  Tier(this.upper, this.unitPrice, this.flatFee);
}

class Plan {
  final String name;
  final int price;
  final String cycle;
  late final int length = periodLengths[cycle]!;
  int trial = 0;
  int setup = 0;
  bool perSeat = false;
  String? mode;
  final tiers = <Tier>[];
  Plan(this.name, this.price, this.cycle);

  int fee(int seats) => price * (perSeat ? seats : 1);

  int usageCharge(int units) {
    var total = 0;
    var lower = 0;
    for (var i = 0; i < tiers.length; ++i) {
      final tier = tiers[i];
      final last = i + 1 == tiers.length;
      if (mode == 'VOLUME') {
        if (last || tier.upper == null || units <= tier.upper!) {
          return units * tier.unitPrice + tier.flatFee;
        }
      } else {
        if (units <= lower) break;
        final end = last || tier.upper == null
            ? units : (units < tier.upper! ? units : tier.upper!);
        total += (end - lower) * tier.unitPrice + tier.flatFee;
        if (last || tier.upper == null) break;
        lower = tier.upper!;
      }
    }
    return total;
  }
}

class BalanceEntry {
  final int day;
  final String description;
  final int change;
  final int balance;
  BalanceEntry(this.day, this.description, this.change, this.balance);
}

class Customer {
  final String name;
  final String region;
  String method = 'OK';
  int balance = 0;
  final log = <BalanceEntry>[];
  final subscriptions = <Subscription>[];
  final invoices = <Invoice>[];
  Customer(this.name, this.region);
}

class Coupon {
  final String name;
  final String kind;
  final int value;
  final int? applications;
  final int? maximum;
  int redemptions = 0;
  Coupon(this.name, this.kind, this.value, this.applications, this.maximum);
}

class Pending {
  final Plan plan;
  final int seats;
  Pending(this.plan, this.seats);
}

class Subscription {
  final int number;
  final Customer customer;
  Plan plan;
  int seats;
  String state = 'NONE';
  int? start;
  int? end;
  int? trialEnd;
  int? pauseStart;
  Pending? pending;
  bool cancelEnd = false;
  int? cancelOn;
  int? canceledOn;
  Coupon? coupon;
  int? remaining;
  int usage = 0;
  final invoices = <Invoice>[];
  Subscription(this.number, this.customer, this.plan, this.seats, this.coupon)
      : remaining = coupon?.applications;
  int fee() => plan.fee(seats);
  String period() => '$start-$end';
}

class LineItem {
  final String label;
  final int amount;
  LineItem(this.label, this.amount);
}

class Totals {
  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  final int credit;
  final int due;
  Totals(this.subtotal, this.discount, this.tax, this.total, this.credit, this.due);
}

class Invoice {
  final int number;
  final Subscription subscription;
  late final Customer customer = subscription.customer;
  final int day;
  final String kind;
  final List<LineItem> items;
  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  final int credit;
  final int due;
  int paid = 0;
  int refunded = 0;
  late int outstanding = due;
  int attempts = 0;
  final retries = <int>[];

  Invoice(this.number, this.subscription, this.day, this.kind,
          this.items, Totals totals)
      : subtotal = totals.subtotal,
        discount = totals.discount,
        tax = totals.tax,
        total = totals.total,
        credit = totals.credit,
        due = totals.due;
  String get state => outstanding == 0 ? 'PAID' : 'OPEN';
}

class StateEvent {
  final int day;
  final int number;
  final String previous;
  final String next;
  StateEvent(this.day, this.number, this.previous, this.next);
}

class BillingService {
  int day = 1;
  final plans = <String, Plan>{};
  final taxRates = <String, int>{};
  final customers = <String, Customer>{};
  final coupons = <String, Coupon>{};
  final subscriptions = <Subscription>[];
  final invoices = <Invoice>[];
  final events = <StateEvent>[];
  final output = <String>[];

  void emit(List<Object> values, {int indent = 0}) {
    output.add('${List.filled(indent, ' ').join()}${values.join(' ')}');
  }

  void notice(List<Object> parts) => emit(['day', day, ...parts], indent: 2);

  Plan plan(String name) {
    final entry = plans[name];
    if (entry == null) throw CommandError('unknown plan $name');
    return entry;
  }

  Customer customer(String name) {
    final entry = customers[name];
    if (entry == null) throw CommandError('unknown customer $name');
    return entry;
  }

  Coupon redeemableCoupon(String name) {
    final entry = coupons[name];
    if (entry == null) throw CommandError('unknown coupon $name');
    if (entry.maximum != null && entry.redemptions == entry.maximum) {
      throw CommandError('coupon exhausted $name');
    }
    return entry;
  }

  Subscription subscription(String text, [Set<String>? allowed]) {
    final index = int.parse(text);
    if (index < 1 || index > subscriptions.length) {
      throw CommandError('unknown sub $text');
    }
    final sub = subscriptions[index - 1];
    if (allowed != null && !allowed.contains(sub.state)) {
      throw CommandError('invalid state $text ${sub.state}');
    }
    return sub;
  }

  Invoice invoice(String text) {
    final index = int.parse(text);
    if (index < 1 || index > invoices.length) {
      throw CommandError('unknown invoice $text');
    }
    return invoices[index - 1];
  }

  void balanceChange(Customer cust, int amount, String description) {
    if (amount == 0) return;
    cust.balance += amount;
    cust.log.add(BalanceEntry(day, description, amount, cust.balance));
  }

  void changeState(Subscription sub, String state) {
    final old = sub.state;
    if (old == 'PAST_DUE') {
      for (final bill in sub.invoices) {
        bill.retries.clear();
      }
    }
    sub.state = state;
    notice(['sub', sub.number, old, '->', state]);
    events.add(StateEvent(day, sub.number, old, state));
  }

  LineItem periodItem(Plan plan, int seats, int start) {
    return LineItem('charge ${plan.name} seats $seats $start-${start + plan.length}',
        plan.fee(seats));
  }

  List<LineItem> openingItems(Subscription sub, int start) {
    final items = [periodItem(sub.plan, sub.seats, start)];
    if (sub.plan.setup != 0) {
      items.add(LineItem('setup ${sub.plan.name}', sub.plan.setup));
    }
    return items;
  }

  List<LineItem> usageItems(Subscription sub, {bool close = false}) {
    if (sub.plan.mode == null || sub.usage == 0) return [];
    final units = sub.usage;
    final item = LineItem('usage ${sub.plan.name} $units units',
        sub.plan.usageCharge(units));
    if (close) sub.usage = 0;
    return [item];
  }

  bool couponUsable(Subscription sub, int subtotal) =>
      subtotal > 0 && sub.coupon != null &&
      (sub.remaining == null || sub.remaining! > 0);

  Totals invoiceTotals(Subscription sub, List<LineItem> items) {
    final subtotal = items.fold<int>(0, (sum, item) => sum + item.amount);
    var discount = 0;
    if (couponUsable(sub, subtotal)) {
      final coupon = sub.coupon!;
      discount = coupon.kind == 'PERCENT'
          ? subtotal * coupon.value ~/ 10000
          : (subtotal < coupon.value ? subtotal : coupon.value);
    }
    final tax = (subtotal - discount) *
        (taxRates[sub.customer.region] ?? 0) ~/ 10000;
    final total = subtotal - discount + tax;
    final credit = sub.customer.balance < total
        ? sub.customer.balance : total;
    return Totals(subtotal, discount, tax, total, credit, total - credit);
  }

  void issue(Subscription sub, String kind, List<LineItem> items) {
    final totals = invoiceTotals(sub, items);
    final bill = Invoice(invoices.length + 1, sub, day, kind, items, totals);
    if (couponUsable(sub, bill.subtotal) && sub.remaining != null) {
      sub.remaining = sub.remaining! - 1;
    }
    invoices.add(bill);
    sub.invoices.add(bill);
    sub.customer.invoices.add(bill);
    balanceChange(sub.customer, -bill.credit, 'applied invoice ${bill.number}');

    String result;
    if (bill.due == 0) {
      result = 'PAID';
    } else if (sub.state == 'UNPAID') {
      result = 'OPEN';
    } else {
      bill.attempts = 1;
      if (sub.customer.method == 'OK') {
        bill.paid = bill.due;
        bill.outstanding = 0;
        result = 'PAID';
      } else {
        result = 'FAILED';
      }
    }
    notice(['invoice', bill.number, 'sub', sub.number, kind,
      'total', money(bill.total), 'credit', money(bill.credit),
      'due', money(bill.due), result]);
    if (result == 'FAILED') {
      if (sub.state == 'ACTIVE') changeState(sub, 'PAST_DUE');
      if (sub.state == 'PAST_DUE') {
        bill.retries.addAll([day + 3, day + 5, day + 7]);
      }
    }
  }

  void paymentComplete(Invoice bill) {
    bill.retries.clear();
    final sub = bill.subscription;
    if ((sub.state == 'PAST_DUE' || sub.state == 'UNPAID') &&
        sub.invoices.every((item) => item.outstanding == 0)) {
      sub.cancelOn = null;
      changeState(sub, 'ACTIVE');
    }
  }

  void cancelSubscription(Subscription sub) {
    changeState(sub, 'CANCELED');
    sub.canceledOn = day;
    sub.pending = null;
    sub.cancelEnd = false;
    sub.cancelOn = null;
    final items = usageItems(sub, close: true);
    if (items.isNotEmpty) issue(sub, 'final', items);
  }

  void retry(Invoice bill) {
    bill.retries.removeAt(0);
    bill.attempts++;
    final retryNumber = bill.attempts - 1;
    if (bill.customer.method == 'OK') {
      bill.paid += bill.outstanding;
      bill.outstanding = 0;
      notice(['retry', retryNumber, 'invoice', bill.number, 'PAID']);
      paymentComplete(bill);
    } else {
      notice(['retry', retryNumber, 'invoice', bill.number, 'FAILED']);
      if (bill.retries.isEmpty) {
        changeState(bill.subscription, 'UNPAID');
        bill.subscription.cancelOn = day + 14;
      }
    }
  }

  void advanceSubscription(Subscription sub) {
    if (sub.state == 'PAUSED' || sub.state == 'CANCELED') return;
    for (final bill in sub.invoices) {
      if (bill.retries.isNotEmpty && bill.retries.first == day) {
        retry(bill);
      }
    }
    if (sub.state == 'UNPAID' && sub.cancelOn == day) {
      cancelSubscription(sub);
    }
    if (sub.state == 'TRIALING' && sub.trialEnd == day) {
      if (sub.cancelEnd) {
        cancelSubscription(sub);
      } else {
        changeState(sub, 'ACTIVE');
        sub.start = day;
        sub.end = day + sub.plan.length;
        issue(sub, 'first', openingItems(sub, day));
      }
    }
    if ({'ACTIVE', 'PAST_DUE', 'UNPAID'}.contains(sub.state) && sub.end == day) {
      if (sub.cancelEnd) {
        cancelSubscription(sub);
      } else {
        final items = usageItems(sub, close: true);
        if (sub.pending != null) {
          final pending = sub.pending!;
          notice(['sub', sub.number, sub.plan.name, 'seats', sub.seats,
            '->', pending.plan.name, 'seats', pending.seats]);
          sub.plan = pending.plan;
          sub.seats = pending.seats;
          sub.pending = null;
        }
        sub.start = day;
        sub.end = day + sub.plan.length;
        items.add(periodItem(sub.plan, sub.seats, day));
        issue(sub, 'renewal', items);
      }
    }
  }

  void cmdPlan(List<String> a) {
    final name = a[0];
    if (plans.containsKey(name)) throw CommandError('duplicate plan $name');
    final entry = Plan(name, cents(a[1]), a[2]);
    var index = 3;
    while (index < a.length) {
      final option = a[index];
      if (option == 'TRIAL') {
        entry.trial = int.parse(a[index + 1]);
        index += 2;
      } else if (option == 'SETUP') {
        entry.setup = cents(a[index + 1]);
        index += 2;
      } else {
        if (option == 'PERSEAT') {
          entry.perSeat = true;
        } else {
          entry.mode = option;
        }
        index++;
      }
    }
    plans[name] = entry;
    final parts = <Object>['PLAN', name, entry.cycle, a[1]];
    if (entry.trial != 0) parts.addAll(['trial', entry.trial]);
    if (entry.setup != 0) parts.addAll(['setup', money(entry.setup)]);
    if (entry.perSeat) parts.add('perseat');
    if (entry.mode != null) parts.add(entry.mode!.toLowerCase());
    emit(parts);
  }

  void cmdTier(List<String> a) {
    final entry = plan(a[0]);
    if (entry.mode == null) throw CommandError('not metered ${a[0]}');
    final upper = a[1] == 'INF' ? null : int.parse(a[1]);
    if (entry.tiers.isNotEmpty) {
      final previous = entry.tiers.last.upper;
      if (previous == null || (upper != null && upper <= previous)) {
        throw CommandError('tier order ${a[0]}');
      }
    }
    entry.tiers.add(Tier(upper, cents(a[2]), cents(a[3])));
    emit(['TIER', a[0], entry.tiers.length, 'upto', a[1], 'unit', a[2], 'flat', a[3]]);
  }

  void cmdTax(List<String> a) {
    final basis = int.parse(a[1]);
    taxRates[a[0]] = basis;
    emit(['TAX', a[0], percentage(basis)]);
  }

  void cmdCustomer(List<String> a) {
    if (customers.containsKey(a[0])) {
      throw CommandError('duplicate customer ${a[0]}');
    }
    customers[a[0]] = Customer(a[0], a[1]);
    emit(['CUSTOMER', a[0], 'region', a[1]]);
  }

  void cmdCoupon(List<String> a) {
    final name = a[0];
    if (coupons.containsKey(name)) throw CommandError('duplicate coupon $name');
    final kind = a[1];
    final application = a[3];
    int? applications = application == 'ONCE' ? 1 : null;
    var index = 4;
    if (application == 'REPEATING') {
      applications = int.parse(a[index]);
      index++;
    }
    final maximum = index < a.length ? int.parse(a[index + 1]) : null;
    final value = kind == 'PERCENT' ? int.parse(a[2]) : cents(a[2]);
    coupons[name] = Coupon(name, kind, value, applications, maximum);
    final parts = <Object>['COUPON', name, kind.toLowerCase(),
      kind == 'PERCENT' ? percentage(value) : money(value), application.toLowerCase()];
    if (application == 'REPEATING') parts.add(applications!);
    if (maximum != null) parts.addAll(['max', maximum]);
    emit(parts);
  }

  void cmdPaymethod(List<String> a) {
    customer(a[0]).method = a[1];
    emit(['PAYMETHOD', a[0], a[1]]);
  }

  void cmdCredit(List<String> a) {
    final cust = customer(a[0]);
    final amount = cents(a[1]);
    if (amount == 0) throw CommandError('invalid amount');
    balanceChange(cust, amount, 'grant');
    emit(['CREDIT', a[0], 'amount', a[1], 'balance', money(cust.balance)]);
  }

  void cmdDay(List<String> a) {
    final target = int.parse(a[0]);
    if (target <= day) throw CommandError('invalid day ${a[0]}');
    emit(['DAY', target]);
    for (var next = day + 1; next <= target; next++) {
      day = next;
      for (final sub in subscriptions) {
        advanceSubscription(sub);
      }
    }
  }

  void cmdSubscribe(List<String> a) {
    final cust = customer(a[0]);
    final entry = plan(a[1]);
    var seats = 1;
    var hasSeats = false;
    String? couponName;
    for (var index = 2; index < a.length; index += 2) {
      if (a[index] == 'SEATS') {
        seats = int.parse(a[index + 1]);
        hasSeats = true;
      } else {
        couponName = a[index + 1];
      }
    }
    if (hasSeats && !entry.perSeat) {
      throw CommandError('not per-seat ${entry.name}');
    }
    if (seats == 0) throw CommandError('invalid seats');
    final coupon = couponName == null ? null : redeemableCoupon(couponName);
    final sub = Subscription(subscriptions.length + 1, cust, entry, seats, coupon);
    if (coupon != null) coupon.redemptions++;
    subscriptions.add(sub);
    cust.subscriptions.add(sub);
    final parts = <Object>['SUBSCRIBE', 'sub', sub.number, cust.name, entry.name,
      'seats', seats];
    if (coupon != null) parts.addAll(['coupon', coupon.name]);
    emit(parts);
    if (entry.trial != 0) {
      sub.trialEnd = day + entry.trial;
      changeState(sub, 'TRIALING');
    } else {
      changeState(sub, 'ACTIVE');
      sub.start = day;
      sub.end = day + entry.length;
      issue(sub, 'first', openingItems(sub, day));
    }
  }

  void cmdChange(List<String> a) {
    final sub = subscription(a[0], {'ACTIVE', 'TRIALING'});
    late Plan newPlan;
    late int seats;
    if (a[1] == 'PLAN') {
      newPlan = plan(a[2]);
      seats = newPlan.perSeat ? sub.seats : 1;
    } else {
      newPlan = sub.plan;
      if (!newPlan.perSeat) {
        throw CommandError('not per-seat ${newPlan.name}');
      }
      seats = int.parse(a[2]);
      if (seats == 0) throw CommandError('invalid seats');
    }
    if (identical(newPlan, sub.plan) && seats == sub.seats) {
      throw CommandError('no change ${a[0]}');
    }
    final oldPlan = sub.plan;
    final oldSeats = sub.seats;
    final head = <Object>['CHANGE', 'sub', sub.number, oldPlan.name,
      'seats', oldSeats, '->', newPlan.name, 'seats', seats];
    sub.pending = null;
    final upgrade = newPlan.fee(seats) * oldPlan.length >
        oldPlan.fee(oldSeats) * newPlan.length;
    if (sub.state == 'TRIALING') {
      sub.plan = newPlan;
      sub.seats = seats;
      emit([...head, 'now']);
    } else if (upgrade) {
      emit([...head, 'now']);
      final days = sub.end! - day;
      final items = usageItems(sub, close: true);
      items.add(LineItem('unused ${oldPlan.name} seats $oldSeats $days days',
          -(oldPlan.fee(oldSeats) * days ~/ oldPlan.length)));
      items.add(LineItem('remaining ${newPlan.name} seats $seats $days days',
          newPlan.fee(seats) * days ~/ newPlan.length));
      sub.plan = newPlan;
      sub.seats = seats;
      issue(sub, 'upgrade', items);
    } else {
      sub.pending = Pending(newPlan, seats);
      emit([...head, 'at', sub.end!]);
    }
  }

  void cmdPause(List<String> a) {
    final sub = subscription(a[0], {'ACTIVE'});
    emit(['PAUSE', 'sub', sub.number]);
    sub.pauseStart = day;
    changeState(sub, 'PAUSED');
  }

  void cmdResume(List<String> a) {
    final sub = subscription(a[0], {'PAUSED'});
    final elapsed = day - sub.pauseStart!;
    sub.end = sub.end! + elapsed;
    sub.pauseStart = null;
    emit(['RESUME', 'sub', sub.number, 'shift', elapsed, 'period', sub.period()]);
    changeState(sub, 'ACTIVE');
  }

  void cmdCancel(List<String> a) {
    final sub = subscription(a[0]);
    if (a[1] == 'END') {
      if (!{'ACTIVE', 'TRIALING'}.contains(sub.state)) {
        throw CommandError('invalid state ${a[0]} ${sub.state}');
      }
      if (sub.cancelEnd) throw CommandError('already canceling ${a[0]}');
      sub.cancelEnd = true;
      final end = sub.state == 'TRIALING' ? sub.trialEnd! : sub.end!;
      emit(['CANCEL', 'sub', sub.number, 'end', end]);
    } else {
      if (sub.state == 'CANCELED') {
        throw CommandError('invalid state ${a[0]} ${sub.state}');
      }
      var refund = 0;
      if (sub.state == 'ACTIVE' || sub.state == 'PAUSED') {
        final start = sub.state == 'ACTIVE' ? day : sub.pauseStart!;
        refund = sub.fee() * (sub.end! - start) ~/ sub.plan.length;
      }
      balanceChange(sub.customer, refund, 'cancel sub ${sub.number}');
      emit(['CANCEL', 'sub', sub.number, 'now', 'credit', money(refund)]);
      cancelSubscription(sub);
    }
  }

  void cmdUsage(List<String> a) {
    final sub = subscription(a[0], {'ACTIVE', 'PAST_DUE'});
    if (sub.plan.mode == null) {
      throw CommandError('not metered ${sub.plan.name}');
    }
    final units = int.parse(a[1]);
    if (units == 0) throw CommandError('invalid units');
    sub.usage += units;
    emit(['USAGE', 'sub', sub.number, 'units', units, 'total', sub.usage]);
  }

  void cmdApply(List<String> a) {
    final sub = subscription(a[0]);
    if (sub.state == 'CANCELED') {
      throw CommandError('invalid state ${a[0]} ${sub.state}');
    }
    final coupon = redeemableCoupon(a[1]);
    coupon.redemptions++;
    sub.coupon = coupon;
    sub.remaining = coupon.applications;
    emit(['APPLY', 'sub', sub.number, 'coupon', coupon.name]);
  }

  void cmdPay(List<String> a) {
    final bill = invoice(a[0]);
    if (bill.outstanding == 0) throw CommandError('already paid ${a[0]}');
    emit(['PAY', 'invoice', bill.number, 'amount', money(bill.outstanding)]);
    bill.paid += bill.outstanding;
    bill.outstanding = 0;
    paymentComplete(bill);
  }

  void cmdRefund(List<String> a) {
    final bill = invoice(a[0]);
    final amount = cents(a[1]);
    if (amount == 0) throw CommandError('invalid amount');
    final maximum = bill.total - bill.refunded;
    if (amount > maximum) {
      throw CommandError('refund exceeds ${a[0]} ${money(maximum)}');
    }
    final applied = amount < bill.outstanding ? amount : bill.outstanding;
    bill.refunded += amount;
    bill.outstanding -= applied;
    balanceChange(bill.customer, amount - applied, 'refund invoice ${bill.number}');
    emit(['REFUND', 'invoice', bill.number, 'amount', a[1],
      'applied', money(applied), 'balance', money(bill.customer.balance)]);
    if (applied != 0 && bill.outstanding == 0) paymentComplete(bill);
  }

  void emitItems(List<LineItem> items) {
    for (final item in items) {
      emit([item.label, money(item.amount)], indent: 2);
    }
  }

  void emitTotals(Totals totals) {
    emit(['subtotal', money(totals.subtotal), 'discount', money(totals.discount),
      'tax', money(totals.tax), 'total', money(totals.total)], indent: 2);
  }

  void cmdInvoice(List<String> a) {
    final bill = invoice(a[0]);
    emit(['INVOICE', bill.number, 'sub', bill.subscription.number,
      bill.customer.name, 'day', bill.day, bill.kind, bill.state]);
    emitItems(bill.items);
    emit(['subtotal', money(bill.subtotal), 'discount', money(bill.discount),
      'tax', money(bill.tax), 'total', money(bill.total)], indent: 2);
    emit(['credit', money(bill.credit), 'due', money(bill.due), 'paid', money(bill.paid),
      'refunded', money(bill.refunded), 'outstanding', money(bill.outstanding)], indent: 2);
  }

  void cmdSub(List<String> a) {
    final sub = subscription(a[0]);
    emit(['SUB', sub.number, sub.customer.name, sub.plan.name,
      'seats', sub.seats, sub.state]);
    if (sub.state == 'TRIALING') emit(['trial until', sub.trialEnd!], indent: 2);
    if ({'ACTIVE', 'PAST_DUE', 'UNPAID', 'PAUSED'}.contains(sub.state)) {
      emit(['period', sub.period()], indent: 2);
    }
    if (sub.state == 'PAUSED') emit(['paused since', sub.pauseStart!], indent: 2);
    if (sub.pending != null) {
      emit(['pending', sub.pending!.plan.name, 'seats', sub.pending!.seats], indent: 2);
    }
    if (sub.cancelEnd) emit(['cancel at end'], indent: 2);
    if (sub.cancelOn != null) emit(['cancel on', sub.cancelOn!], indent: 2);
    if (sub.state == 'CANCELED') emit(['canceled on', sub.canceledOn!], indent: 2);
    if (sub.coupon != null) {
      if (sub.remaining == null) {
        emit(['coupon', sub.coupon!.name, 'forever'], indent: 2);
      } else if (sub.remaining! > 0) {
        emit(['coupon', sub.coupon!.name, 'left', sub.remaining!], indent: 2);
      }
    }
    if (sub.plan.mode != null && sub.state != 'CANCELED') {
      emit(['usage', sub.usage], indent: 2);
    }
    final open = sub.invoices.where((bill) => bill.outstanding != 0)
        .map((bill) => bill.number).toList();
    if (open.isNotEmpty) emit(['open', ...open], indent: 2);
  }

  void cmdPreview(List<String> a) {
    final sub = subscription(a[0], {'TRIALING', 'ACTIVE', 'PAST_DUE', 'UNPAID'});
    final previewDay = sub.state == 'TRIALING' ? sub.trialEnd! : sub.end!;
    late String kind;
    late List<LineItem> items;
    if (sub.cancelEnd) {
      kind = 'final';
      items = sub.state == 'TRIALING' ? [] : usageItems(sub);
    } else if (sub.state == 'TRIALING') {
      kind = 'first';
      items = openingItems(sub, previewDay);
    } else {
      kind = 'renewal';
      final entry = sub.pending?.plan ?? sub.plan;
      final seats = sub.pending?.seats ?? sub.seats;
      items = usageItems(sub);
      items.add(periodItem(entry, seats, previewDay));
    }
    emit(['PREVIEW', 'sub', sub.number, 'day', previewDay, kind]);
    if (items.isEmpty) {
      emit(['(none)'], indent: 2);
      return;
    }
    emitItems(items);
    final totals = invoiceTotals(sub, items);
    emitTotals(totals);
    emit(['credit', money(totals.credit), 'due', money(totals.due)], indent: 2);
  }

  void cmdStatement(List<String> a) {
    final cust = customer(a[0]);
    emit(['STATEMENT', cust.name, 'region', cust.region,
      'tax', percentage(taxRates[cust.region] ?? 0),
      'method', cust.method, 'balance', money(cust.balance)]);
    for (final sub in cust.subscriptions) {
      emit(['sub', sub.number, sub.plan.name, sub.state], indent: 2);
    }
    for (final bill in cust.invoices) {
      emit(['invoice', bill.number, 'day', bill.day, 'sub', bill.subscription.number,
        bill.kind, 'total', money(bill.total),
        'outstanding', money(bill.outstanding)], indent: 2);
    }
    final total = cust.invoices.fold<int>(0, (sum, bill) => sum + bill.outstanding);
    emit(['outstanding', money(total)], indent: 2);
  }

  void cmdLedger(List<String> a) {
    final cust = customer(a[0]);
    emit(['LEDGER', cust.name, 'balance', money(cust.balance)]);
    for (final entry in cust.log) {
      emit(['day', entry.day, entry.description, signedMoney(entry.change),
        'balance', money(entry.balance)], indent: 2);
    }
    if (cust.log.isEmpty) emit(['(none)'], indent: 2);
  }

  void cmdMrr() {
    final byPlan = <String, List<int>>{};
    for (final sub in subscriptions) {
      if (!{'ACTIVE', 'PAST_DUE'}.contains(sub.state)) continue;
      final fee = sub.fee();
      final monthly = sub.plan.cycle == 'MONTHLY' ? fee
          : sub.plan.cycle == 'YEARLY' ? fee ~/ 12 : fee * 30 ~/ 7;
      final row = byPlan.putIfAbsent(sub.plan.name, () => [0, 0]);
      row[0]++;
      row[1] += monthly;
    }
    emit(['MRR']);
    final names = byPlan.keys.toList()..sort();
    for (final name in names) {
      final row = byPlan[name]!;
      emit([name, 'subs', row[0], 'mrr', money(row[1])], indent: 2);
    }
    final count = byPlan.values.fold<int>(0, (sum, row) => sum + row[0]);
    final total = byPlan.values.fold<int>(0, (sum, row) => sum + row[1]);
    emit(['total subs', count, 'mrr', money(total)], indent: 2);
  }

  List<Object> agingParts(List<int> values) => [
    '0-30', money(values[0]), '31-60', money(values[1]),
    '61+', money(values[2]), 'sum', money(values[0] + values[1] + values[2])
  ];

  void cmdAging() {
    final byCustomer = <String, List<int>>{};
    final totals = [0, 0, 0];
    for (final bill in invoices) {
      if (bill.outstanding == 0) continue;
      final age = day - bill.day;
      final bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2;
      final values = byCustomer.putIfAbsent(bill.customer.name, () => [0, 0, 0]);
      values[bucket] += bill.outstanding;
      totals[bucket] += bill.outstanding;
    }
    emit(['AGING', 'day', day]);
    final names = byCustomer.keys.toList()..sort();
    for (final name in names) {
      emit([name, ...agingParts(byCustomer[name]!)], indent: 2);
    }
    emit(['total', ...agingParts(totals)], indent: 2);
  }

  void cmdDunning() {
    emit(['DUNNING']);
    final pending = invoices.where((bill) => bill.retries.isNotEmpty).toList();
    for (final bill in pending) {
      emit(['invoice', bill.number, 'sub', bill.subscription.number,
        bill.customer.name, 'outstanding', money(bill.outstanding),
        'attempts', bill.attempts, 'next', bill.retries.first], indent: 2);
    }
    if (pending.isEmpty) emit(['(none)'], indent: 2);
  }

  void cmdRevenue() {
    emit(['REVENUE']);
    int addInvoices(int Function(Invoice) field) =>
        invoices.fold<int>(0, (sum, bill) => sum + field(bill));
    emit(['invoices', invoices.length,
      'subtotal', money(addInvoices((bill) => bill.subtotal)),
      'discount', money(addInvoices((bill) => bill.discount)),
      'tax', money(addInvoices((bill) => bill.tax)),
      'total', money(addInvoices((bill) => bill.total))], indent: 2);
    emit(['credit', money(addInvoices((bill) => bill.credit)),
      'paid', money(addInvoices((bill) => bill.paid)),
      'refunded', money(addInvoices((bill) => bill.refunded)),
      'outstanding', money(addInvoices((bill) => bill.outstanding)),
      'balances', money(customers.values.fold<int>(0,
          (sum, cust) => sum + cust.balance))], indent: 2);
  }

  void cmdEvents(List<String> a) {
    final selected = a.isEmpty ? null : subscription(a[0]).number;
    emit(selected == null ? ['EVENTS'] : ['EVENTS', 'sub', selected]);
    final matching = events.where((event) =>
        selected == null || event.number == selected).toList();
    for (final event in matching) {
      emit(['day', event.day, 'sub', event.number,
        event.previous, '->', event.next], indent: 2);
    }
    if (matching.isEmpty) emit(['(none)'], indent: 2);
  }

  void execute(String line) {
    final tokens = line.trim().split(' ');
    final command = tokens.first;
    final a = tokens.sublist(1);
    try {
      switch (command) {
        case 'PLAN': cmdPlan(a); break;
        case 'TIER': cmdTier(a); break;
        case 'TAX': cmdTax(a); break;
        case 'CUSTOMER': cmdCustomer(a); break;
        case 'COUPON': cmdCoupon(a); break;
        case 'PAYMETHOD': cmdPaymethod(a); break;
        case 'CREDIT': cmdCredit(a); break;
        case 'DAY': cmdDay(a); break;
        case 'SUBSCRIBE': cmdSubscribe(a); break;
        case 'CHANGE': cmdChange(a); break;
        case 'PAUSE': cmdPause(a); break;
        case 'RESUME': cmdResume(a); break;
        case 'CANCEL': cmdCancel(a); break;
        case 'USAGE': cmdUsage(a); break;
        case 'APPLY': cmdApply(a); break;
        case 'PAY': cmdPay(a); break;
        case 'REFUND': cmdRefund(a); break;
        case 'INVOICE': cmdInvoice(a); break;
        case 'SUB': cmdSub(a); break;
        case 'PREVIEW': cmdPreview(a); break;
        case 'STATEMENT': cmdStatement(a); break;
        case 'LEDGER': cmdLedger(a); break;
        case 'MRR': cmdMrr(); break;
        case 'AGING': cmdAging(); break;
        case 'DUNNING': cmdDunning(); break;
        case 'REVENUE': cmdRevenue(); break;
        case 'EVENTS': cmdEvents(a); break;
      }
    } on CommandError catch (error) {
      emit(['ERROR', error.reason]);
    }
  }

  String get result => output.isEmpty ? '' : '${output.join('\n')}\n';
}

void main() {
  final lines = stdin.readAsLinesSync();
  final count = int.parse(lines.first);
  final billing = BillingService();
  for (var i = 0; i < count; ++i) {
    billing.execute(lines[i + 1]);
  }
  stdout.write(billing.result);
}
