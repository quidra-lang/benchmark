import 'dart:io';

class LedgerError implements Exception {
  final String message;
  LedgerError(this.message);
}
Never fail(String message) => throw LedgerError(message);
int amount(String text) {
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 + int.parse(parts[1]);
}
String money(int value) => '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
String signedMoney(int value) => value == 0 ? '0.00' : '${value > 0 ? '+' : '-'}${money(value.abs())}';
String percentage(int part, int whole) => '${money(part * 10000 ~/ whole)}%';
String rateText(int value) => '${value ~/ 10000}.${(value % 10000).toString().padLeft(4, '0')}';
List<int> distribute(int total, List<int> weights) {
  final sum = weights.fold(0, (a, b) => a + b);
  final result = weights.map((w) => total * w ~/ sum).toList();
  final order = [for (var i = 0; i < weights.length; i++) i];
  order.sort((a, b) {
    final cmp = (total * weights[b] % sum).compareTo(total * weights[a] % sum);
    return cmp != 0 ? cmp : a.compareTo(b);
  });
  final left = total - result.fold(0, (a, b) => a + b);
  for (var i = 0; i < left; i++) result[order[i]]++;
  return result;
}
List<int> equalParts(int total, int count) =>
    [for (var i = 0; i < count; i++) total ~/ count + (i < total % count ? 1 : 0)];

class Member {
  bool active = true;
  int statusDay;
  Member(this.statusDay);
}
class Entry {
  final String name;
  final int value;
  Entry(this.name, this.value);
}
class Expense {
  final String id;
  final int day, serial;
  String currency, category, mode;
  int original, total;
  List<Entry> payers, participants;
  List<int> contributions, shares;
  int interval = 0, nextDay = 0, copies = 0;
  Expense(this.id, this.day, this.serial, this.original, this.currency, this.category,
      this.mode, this.payers, this.participants, this.total, this.contributions, this.shares);
  bool includes(String name) => payers.any((e) => e.name == name) || participants.any((e) => e.name == name);
  int net(String name) {
    var result = 0;
    for (var i = 0; i < payers.length; i++) if (payers[i].name == name) result += contributions[i];
    for (var i = 0; i < participants.length; i++) if (participants[i].name == name) result -= shares[i];
    return result;
  }
  String get note => currency.isEmpty ? '' : ' [${money(original)} $currency]';
}
class Settlement {
  final String from, to, currency;
  final int original, total, day, serial;
  Settlement(this.from, this.to, this.original, this.currency, this.total, this.day, this.serial);
  String get note => currency.isEmpty ? '' : ' [${money(original)} $currency]';
}

class Ledger {
  int day = 1, serial = 0;
  final members = <String, Member>{}, rates = <String, int>{}, budgets = <String, int>{};
  final used = <String>{}, expenses = <Expense>[], settlements = <Settlement>[];
  List<String> names([bool activeOnly = false]) =>
      (members.keys.where((n) => !activeOnly || members[n]!.active).toList()..sort());
  void registered(String name) { if (!members.containsKey(name)) fail('unknown member $name'); }
  void active(String name) {
    registered(name);
    if (!members[name]!.active) fail('inactive member $name');
  }
  Expense expense(String id) => expenses.firstWhere((e) => e.id == id,
      orElse: () => fail('unknown expense $id'));
  void unfrozen(Expense e) {
    for (final entry in [...e.payers, ...e.participants]) {
      if (!members[entry.name]!.active) fail('inactive member ${entry.name}');
    }
  }
  (int, String) spec(String text) {
    final parts = text.split('@'), currency = parts.length == 1 ? '' : parts[1];
    if (currency.isNotEmpty && !rates.containsKey(currency)) fail('unknown currency $currency');
    return (amount(parts[0]), currency);
  }
  int convert(int value, String currency) => currency.isEmpty ? value : (value * rates[currency]! + 5000) ~/ 10000;
  List<int> portions(Expense e) {
    final values = e.participants.map((p) => p.value).toList();
    if (e.mode == 'EQUAL') return equalParts(e.original, values.length);
    if (e.mode == 'EXACT') return values;
    if (e.mode == 'ADJUST') {
      final base = equalParts(e.original - values.fold(0, (a, b) => a + b), values.length);
      return [for (var i = 0; i < values.length; i++) base[i] + values[i]];
    }
    return distribute(e.original, values);
  }
  void compute(Expense e) {
    e.total = convert(e.original, e.currency);
    e.shares = distribute(e.total, portions(e));
    e.contributions = distribute(e.total, e.payers.map((p) => p.value).toList());
  }
  Expense build(List<String> args, Expense? old) {
    final id = args[1], payer = args[2];
    active(payer);
    final parsed = spec(args[3]), total = convert(parsed.$1, parsed.$2);
    if (parsed.$1 == 0 || total == 0) fail('invalid amount');
    final mode = args[5], participants = <Entry>[], seen = <String>{};
    final raw = mode == 'EQUAL' && args[6] == 'ALL' ? names(true) : args.sublist(6);
    for (final token in raw) {
      final pair = token.split(':'), name = pair[0];
      active(name);
      if (!seen.add(name)) fail('duplicate member $name');
      final value = pair.length == 1 ? 0 : mode == 'PERCENT' || mode == 'SHARES' ? int.parse(pair[1]) : amount(pair[1]);
      participants.add(Entry(name, value));
    }
    final sum = participants.fold(0, (s, p) => s + p.value);
    if (mode == 'EXACT' && sum != parsed.$1 || mode == 'PERCENT' && sum != 10000 ||
        mode == 'SHARES' && sum < 1 || mode == 'ADJUST' && sum > parsed.$1) fail('splits do not add up');
    final e = Expense(id, old?.day ?? day, old?.serial ?? serial + 1, parsed.$1, parsed.$2,
        args[4], mode, [Entry(payer, parsed.$1)], participants, total, [], []);
    if (old != null) { e.interval = old.interval; e.nextDay = old.nextDay; e.copies = old.copies; }
    compute(e);
    return e;
  }
  Map<String, int> balances() {
    final result = {for (final n in names()) n: 0};
    for (final e in expenses) {
      for (final name in result.keys) result[name] = result[name]! + e.net(name);
    }
    for (final s in settlements) {
      result[s.from] = result[s.from]! + s.total;
      result[s.to] = result[s.to]! - s.total;
    }
    return result;
  }
  List<List<int>> debts(List<String> ns) {
    final result = [for (final _ in ns) List.filled(ns.length, 0)];
    for (final e in expenses) {
      final net = ns.map(e.net).toList();
      final borrowers = [for (var i = 0; i < ns.length; i++) if (net[i] < 0) i];
      final lenders = [for (var i = 0; i < ns.length; i++) if (net[i] > 0) i];
      var b = 0, l = 0;
      while (b < borrowers.length && l < lenders.length) {
        final x = borrowers[b], y = lenders[l], transfer = -net[x] < net[y] ? -net[x] : net[y];
        result[x][y] += transfer; net[x] += transfer; net[y] -= transfer;
        if (net[x] == 0) b++;
        if (net[y] == 0) l++;
      }
    }
    for (final s in settlements) result[ns.indexOf(s.from)][ns.indexOf(s.to)] -= s.total;
    return [for (var i = 0; i < ns.length; i++) [for (var j = 0; j < ns.length; j++) result[i][j] - result[j][i]]];
  }
  int spent(String category) => expenses.where((e) => e.category == category).fold(0, (s, e) => s + e.total);
  void warning(StringBuffer out, String category) {
    final budget = budgets[category];
    if (budget != null && spent(category) > budget) out.writeln('  WARNING $category over budget by ${money(spent(category) - budget)}');
  }
  List<Expense> chronological(Iterable<Expense> values) => values.toList()..sort((a, b) {
    final cmp = a.day.compareTo(b.day);
    return cmp != 0 ? cmp : a.serial.compareTo(b.serial);
  });
  List<(String, String, int)> greedy(List<String> ns, Map<String, int> original) {
    final balance = {for (final n in ns) n: original[n]!}, result = <(String, String, int)>[];
    while (balance.values.any((v) => v != 0)) {
      var sender = ns.first, receiver = ns.first;
      for (final n in ns) {
        if (balance[n]! < balance[sender]!) sender = n;
        if (balance[n]! > balance[receiver]!) receiver = n;
      }
      final value = -balance[sender]! < balance[receiver]! ? -balance[sender]! : balance[receiver]!;
      result.add((sender, receiver, value));
      balance[sender] = balance[sender]! + value; balance[receiver] = balance[receiver]! - value;
    }
    return result;
  }
  String execute(String line) {
    final a = line.split(' '), op = a[0], out = StringBuffer();
    switch (op) {
      case 'DAY':
        final target = int.parse(a[1]);
        if (target <= day) fail('invalid day ${a[1]}');
        out.writeln('DAY $target');
        while (true) {
          final templates = expenses.where((e) => e.interval > 0 && e.nextDay <= target).toList();
          if (templates.isEmpty) break;
          templates.sort((x, y) {
            final cmp = x.nextDay.compareTo(y.nextDay);
            return cmp != 0 ? cmp : x.serial.compareTo(y.serial);
          });
          final e = templates.first;
          if ([...e.payers, ...e.participants].any((p) => !members[p.name]!.active) || convert(e.original, e.currency) == 0) {
            e.interval = 0; out.writeln('  CANCEL ${e.id}'); continue;
          }
          e.copies++;
          final copy = Expense('${e.id}#${e.copies + 1}', e.nextDay, ++serial, e.original,
              e.currency, e.category, e.mode, List.of(e.payers), List.of(e.participants), 0, [], []);
          compute(copy); expenses.add(copy); used.add(copy.id); e.nextDay += e.interval;
          out.writeln('  RECUR ${copy.id} ${money(copy.total)}'); warning(out, copy.category);
        }
        day = target;
      case 'MEMBER':
        final member = members[a[1]];
        if (member != null && member.active) fail('duplicate member ${a[1]}');
        out.writeln('MEMBER ${a[1]} ${member == null ? 'joined' : 'rejoined'}');
        members[a[1]] = Member(day);
      case 'LEAVE':
        active(a[1]);
        if (balances()[a[1]] != 0) fail('member has a balance ${a[1]}');
        members[a[1]]!.active = false; members[a[1]]!.statusDay = day;
        out.writeln('LEAVE ${a[1]}');
      case 'CURRENCY':
        final value = int.parse(a[2]), old = rates[a[1]];
        rates[a[1]] = value;
        out.writeln('CURRENCY ${a[1]} ${rateText(value)}${old == null ? '' : ' was ${rateText(old)}'}');
      case 'EXPENSE' || 'EDIT':
        Expense? old;
        if (op == 'EXPENSE') { if (used.contains(a[1])) fail('duplicate id ${a[1]}'); }
        else { old = expense(a[1]); unfrozen(old); }
        final e = build(a, old);
        if (old == null) { serial++; expenses.add(e); used.add(e.id); }
        else expenses[expenses.indexOf(old)] = e;
        out.writeln('$op ${e.id} ${money(e.total)}${e.note} = ${[for (var i = 0; i < e.participants.length; i++) '${e.participants[i].name} ${money(e.shares[i])}'].join(' + ')}');
        warning(out, e.category);
      case 'PAYERS':
        final e = expense(a[1]); unfrozen(e);
        final payers = <Entry>[], seen = <String>{};
        for (final token in a.skip(2)) {
          final pair = token.split(':'), name = pair[0];
          active(name);
          if (!seen.add(name)) fail('duplicate member $name');
          payers.add(Entry(name, amount(pair[1])));
        }
        if (payers.fold(0, (sum, p) => sum + p.value) != e.original) fail('payers do not add up');
        e.payers = payers; e.contributions = distribute(e.total, payers.map((p) => p.value).toList());
        out.writeln('PAYERS ${e.id} ${money(e.total)}${e.note} = ${[for (var i = 0; i < payers.length; i++) '${payers[i].name} ${money(e.contributions[i])}'].join(' + ')}');
      case 'DELETE':
        final e = expense(a[1]); unfrozen(e); expenses.remove(e);
        out.writeln('DELETE ${e.id}');
      case 'RECURRING':
        final e = expense(a[1]); e.interval = int.parse(a[2]);
        if (e.interval == 0) out.writeln('RECURRING ${e.id} stopped');
        else { e.nextDay = day + e.interval; out.writeln('RECURRING ${e.id} interval ${e.interval} next ${e.nextDay}'); }
      case 'SETTLE':
        active(a[1]); active(a[2]);
        if (a[1] == a[2]) fail('same member ${a[1]}');
        final parsed = spec(a[3]), total = convert(parsed.$1, parsed.$2);
        if (parsed.$1 == 0 || total == 0) fail('invalid amount');
        final s = Settlement(a[1], a[2], parsed.$1, parsed.$2, total, day, ++serial);
        settlements.add(s);
        out.writeln('SETTLE ${s.from} -> ${s.to} ${money(s.total)}${s.note}');
      case 'BUDGET':
        final value = amount(a[2]);
        if (value == 0) budgets.remove(a[1]); else budgets[a[1]] = value;
        out.writeln('BUDGET ${a[1]} ${value == 0 ? 'removed' : money(value)}');
      case 'BALANCES':
        out.writeln('BALANCES');
        final ns = names(true), balance = balances();
        if (ns.isEmpty) out.writeln('  (none)');
        for (final name in ns) out.writeln('  $name ${signedMoney(balance[name]!)}');
      case 'OWES':
        registered(a[1]); out.writeln('OWES ${a[1]}');
        final ns = names(), matrix = debts(ns), i = ns.indexOf(a[1]);
        var count = 0;
        for (var j = 0; j < ns.length; j++) {
          final debt = matrix[i][j];
          if (debt > 0) out.writeln('  ${a[1]} owes ${ns[j]} ${money(debt)}');
          if (debt < 0) out.writeln('  ${ns[j]} owes ${a[1]} ${money(-debt)}');
          if (debt != 0) count++;
        }
        if (count == 0) out.writeln('  (none)');
      case 'HISTORY':
        registered(a[1]); out.writeln('HISTORY ${a[1]}');
        final records = <(int, int, String, int)>[];
        for (final e in expenses.where((e) => e.includes(a[1]))) records.add((e.day, e.serial, e.id, e.net(a[1])));
        for (final s in settlements.where((s) => s.from == a[1] || s.to == a[1])) records.add((s.day, s.serial, '${s.from}->${s.to}', s.from == a[1] ? s.total : -s.total));
        records.sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));
        var running = 0;
        for (final r in records) { running += r.$4; out.writeln('  day ${r.$1} ${r.$3} ${signedMoney(r.$4)} balance ${signedMoney(running)}'); }
        if (records.isEmpty) out.writeln('  (none)');
      case 'MATRIX':
        out.writeln('MATRIX');
        final ns = names(true), all = names(), matrix = debts(all);
        if (ns.isEmpty) { out.writeln('  (none)'); break; }
        final cells = [for (final x in ns) [for (final y in ns) x == y ? '-' : money(matrix[all.indexOf(x)][all.indexOf(y)] > 0 ? matrix[all.indexOf(x)][all.indexOf(y)] : 0)]];
        final l = ns.map((s) => s.length).reduce((a, b) => a > b ? a : b);
        final w = [...ns, ...cells.expand((r) => r)].map((s) => s.length).reduce((a, b) => a > b ? a : b);
        out.writeln('${' ' * l}${ns.map((s) => '  ${s.padLeft(w)}').join()}');
        for (var i = 0; i < ns.length; i++) out.writeln('${ns[i].padRight(l)}${cells[i].map((s) => '  ${s.padLeft(w)}').join()}');
      case 'CATEGORY':
        out.writeln('CATEGORY');
        final categoryTotals = <String, int>{};
        for (final e in expenses) {
          categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.total;
        }
        final categories = categoryTotals.keys.toList();
        categories.sort((a, b) => categoryTotals[a] != categoryTotals[b]
            ? categoryTotals[b]!.compareTo(categoryTotals[a]!) : a.compareTo(b));
        final total = categoryTotals.values.fold(0, (sum, value) => sum + value);
        for (final c in categories) {
          final categoryTotal = categoryTotals[c]!, shares = {for (final n in names()) n: 0};
          for (final e in expenses.where((e) => e.category == c)) {
            for (var i = 0; i < e.participants.length; i++) shares[e.participants[i].name] = shares[e.participants[i].name]! + e.shares[i];
          }
          final ns = shares.keys.where((n) => shares[n] != 0).toList()..sort((a, b) => shares[a] != shares[b] ? shares[b]!.compareTo(shares[a]!) : a.compareTo(b));
          out.writeln('  $c ${money(categoryTotal)} ${percentage(categoryTotal, total)}');
          for (final n in ns) out.writeln('    $n ${money(shares[n]!)} ${percentage(shares[n]!, categoryTotal)}');
        }
        if (categories.isEmpty) out.writeln('  (none)');
      case 'BUDGETS':
        out.writeln('BUDGETS');
        final categories = budgets.keys.toList()..sort();
        for (final c in categories) {
          final s = spent(c), b = budgets[c]!;
          out.writeln('  $c spent ${money(s)} budget ${money(b)} used ${percentage(s, b)} ${s <= b ? 'left ${money(b - s)}' : 'over ${money(s - b)}'}');
        }
        if (categories.isEmpty) out.writeln('  (none)');
      case 'TOTALS':
        out.writeln('TOTALS');
        for (final n in names()) {
          var paid = 0, share = 0, sent = 0, received = 0;
          for (final e in expenses) {
            for (var i = 0; i < e.payers.length; i++) if (e.payers[i].name == n) paid += e.contributions[i];
            for (var i = 0; i < e.participants.length; i++) if (e.participants[i].name == n) share += e.shares[i];
          }
          for (final s in settlements) { if (s.from == n) sent += s.total; if (s.to == n) received += s.total; }
          out.writeln('  $n paid ${money(paid)} share ${money(share)} sent ${money(sent)} received ${money(received)}');
        }
        final currencies = expenses.map((e) => e.currency).where((c) => c.isNotEmpty).toSet().toList()..sort();
        for (final c in currencies) {
          final es = expenses.where((e) => e.currency == c).toList();
          out.writeln('  currency $c expenses ${es.length} amount ${money(es.fold(0, (s, e) => s + e.original))} base ${money(es.fold(0, (s, e) => s + e.total))}');
        }
        out.writeln('  expenses ${expenses.length} total ${money(expenses.fold(0, (s, e) => s + e.total))} settlements ${settlements.length} total ${money(settlements.fold(0, (s, e) => s + e.total))}');
      case 'MEMBERS':
        out.writeln('MEMBERS');
        for (final n in names()) out.writeln('  $n ${members[n]!.active ? 'active' : 'left'} day ${members[n]!.statusDay} expenses ${expenses.where((e) => e.includes(n)).length}');
        if (members.isEmpty) out.writeln('  (none)');
      case 'EXPENSES':
        if (a[1] == 'MEMBER') registered(a[2]);
        out.writeln(line);
        final selected = chronological(expenses.where((e) => switch (a[1]) {
          'ALL' => true, 'CATEGORY' => e.category == a[2], 'MEMBER' => e.includes(a[2]),
          _ => e.day >= int.parse(a[2]) && e.day <= int.parse(a[3]),
        }));
        for (final e in selected) out.writeln('  day ${e.day} ${e.id} ${e.category} ${money(e.total)} by ${e.payers.map((p) => p.name).join(',')}');
        out.writeln('  count ${selected.length} total ${money(selected.fold(0, (s, e) => s + e.total))}');
      case 'PERIODS':
        final k = int.parse(a[1]), groups = <int, List<Expense>>{};
        out.writeln('PERIODS $k');
        for (final e in expenses) (groups[(e.day - 1) ~/ k] ??= []).add(e);
        for (final i in groups.keys.toList()..sort()) out.writeln('  days ${i * k + 1}-${i * k + k} expenses ${groups[i]!.length} total ${money(groups[i]!.fold(0, (s, e) => s + e.total))}');
        if (groups.isEmpty) out.writeln('  (none)');
      case 'SHOW':
        final e = expense(a[1]);
        out.writeln('SHOW ${e.id}');
        out.writeln('  day ${e.day} category ${e.category} mode ${e.mode} total ${money(e.total)}${e.note}');
        for (var i = 0; i < e.payers.length; i++) out.writeln('  paid ${e.payers[i].name} ${money(e.contributions[i])}');
        final units = e.participants.fold(0, (s, p) => s + p.value);
        for (var i = 0; i < e.participants.length; i++) {
          final p = e.participants[i];
          final suffix = switch (e.mode) {
            'EXACT' => ' ${money(p.value)}', 'PERCENT' => ' ${money(p.value)}%',
            'SHARES' => ' ${p.value}/$units', 'ADJUST' => ' +${money(p.value)}', _ => '',
          };
          out.writeln('  share ${p.name} ${money(e.shares[i])}$suffix');
        }
        if (e.interval > 0) out.writeln('  recurring interval ${e.interval} next ${e.nextDay}');
      case 'SIMPLIFY':
        final balance = balances(), ns = names().where((n) => balance[n] != 0).toList();
        if (a[1] == 'GREEDY') {
          final transfers = ns.isEmpty ? <(String, String, int)>[] : greedy(ns, balance);
          out.writeln('SIMPLIFY GREEDY transfers ${transfers.length}');
          for (final t in transfers) out.writeln('  ${t.$1} -> ${t.$2} ${money(t.$3)}');
        } else {
          if (ns.length > 12) fail('too many members');
          final size = 1 << ns.length, sums = List.filled(1 << ns.length, 0), memo = <int, int>{0: 0};
          for (var mask = 1; mask < size; mask++) {
            final bit = mask & -mask, index = bit.bitLength - 1;
            sums[mask] = sums[mask ^ bit] + balance[ns[index]]!;
          }
          int solve(int mask) {
            if (memo.containsKey(mask)) return memo[mask]!;
            final first = mask & -mask;
            var best = -100;
            for (var sub = mask; sub > 0; sub = (sub - 1) & mask) {
              if ((sub & first) != 0 && sums[sub] == 0) {
                final value = 1 + solve(mask ^ sub);
                if (value > best) best = value;
              }
            }
            return memo[mask] = best;
          }
          List<int> indices(int mask) => [for (var i = 0; i < ns.length; i++) if ((mask & (1 << i)) != 0) i];
          bool lexLess(int x, int y) {
            final left = indices(x), right = indices(y);
            for (var i = 0; i < left.length && i < right.length; i++) {
              if (left[i] != right[i]) return left[i] < right[i];
            }
            return left.length < right.length;
          }
          var mask = size - 1;
          final groups = solve(mask);
          out.writeln('SIMPLIFY OPTIMAL transfers ${ns.length - groups} groups $groups');
          while (mask != 0) {
            final first = mask & -mask;
            var chosen = 0;
            for (var sub = mask; sub > 0; sub = (sub - 1) & mask) {
              if ((sub & first) != 0 && sums[sub] == 0 && 1 + solve(mask ^ sub) == solve(mask) &&
                  (chosen == 0 || lexLess(sub, chosen))) chosen = sub;
            }
            final group = indices(chosen).map((i) => ns[i]).toList();
            out.writeln('  group ${group.join(' ')}');
            for (final t in greedy(group, balance)) out.writeln('    ${t.$1} -> ${t.$2} ${money(t.$3)}');
            mask ^= chosen;
          }
        }
    }
    return out.toString();
  }
}

void main() {
  final ledger = Ledger(), output = StringBuffer();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try { output.write(ledger.execute(line)); }
    on LedgerError catch (error) { output.writeln('ERROR ${error.message}'); }
  }
  stdout.write(output);
}
