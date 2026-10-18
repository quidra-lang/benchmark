import 'dart:io';

class LibraryError implements Exception {
  final String message;
  LibraryError(this.message);
}
Never fail(String message) => throw LibraryError(message);
int amount(String text) {
  final p = text.split('.');
  return int.parse(p[0]) * 100 + int.parse(p[1]);
}

String money(int n) => '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
String normalizeISBN(String text) {
  final s = text.replaceAll('-', '');
  bool digit(int c) => c >= 48 && c <= 57;
  if (s.length == 10 && s.substring(0, 9).codeUnits.every(digit) && (digit(s.codeUnitAt(9)) || s[9] == 'X')) {
    var total = 0;
    for (var i = 0; i < 10; i++)
      total += (10 - i) * (s[i] == 'X' ? 10 : s.codeUnitAt(i) - 48);
    if (total % 11 != 0)
      fail('invalid isbn');
    final prefix = '978${s.substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < 12; i++)
      sum += (i % 2 == 0 ? 1 : 3) * (prefix.codeUnitAt(i) - 48);
    return '$prefix${(10 - sum % 10) % 10}';
  }
  if (s.length == 13 && s.codeUnits.every(digit) && (s.startsWith('978') || s.startsWith('979'))) {
    var sum = 0;
    for (var i = 0; i < 13; i++)
      sum += (i % 2 == 0 ? 1 : 3) * (s.codeUnitAt(i) - 48);
    if (sum % 10 == 0)
      return s;
  }
  fail('invalid isbn');
}

class Charge {
  final int day, amount;
  final String kind, isbn;
  int unpaid;
  Charge(this.day, this.kind, this.isbn, this.amount): unpaid = amount;
}

class Member {
  final String id, type, name;
  final items = <Charge>[], history = <String>[];
  Member(this.id, this.type, this.name);
  bool get student => type == 'STUDENT';
  int get loanLimit => student ? 3 : 10;
  int get period => student ? 14 : 28;
  int get rate => student ? 25 : 10;
  int get cap => student ? 1000 : 2000;
  int get reservationLimit => student ? 2 : 5;
  int get fee => student ? 50 : 100;
  int get balance => items.fold(0, (s, i) => s + i.unpaid);
  bool get blocked => balance > 500;
}

class Title {
  final String isbn, name;
  int price, borrowed = 0;
  final copies = <Copy>[], queue = <Member>[];
  Title(this.isbn, this.name, this.price);
  int get holdings => copies.where((c) => ['AVAILABLE', 'LOANED', 'HOLD'].contains(c.state)).length;
  int count(String state) => copies.where((c) => c.state == state).length;
}

class Copy {
  final Title title;
  final int number;
  String state = 'AVAILABLE';
  Member? member;
  int loanDay = 0, due = 0, renewals = 0, expiry = 0;
  Copy(this.title, this.number);
}

class Library {
  int day = 1, borrowed = 0, returned = 0, renewed = 0, lost = 0, paid = 0, waived = 0;
  final charged = <String, int>{ 'FINE': 0, 'FEE': 0, 'PRICE': 0 };
  final titles = <String, Title>{}, members = <String, Member>{}, closed = <int>{};
  List<Title> books() => titles.values.toList()..sort((a, b) => a.isbn.compareTo(b.isbn));
  List<Member> people() => members.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  List<Copy> copies() => titles.values.expand((t) => t.copies).toList();
  List<Copy> loans([Member? m]) => titles.values.expand((t) => t.copies).where((c) => c.state == 'LOANED'
    && (m == null || c.member == m)).toList();
  List<Copy> holds([Member? m]) => titles.values.expand((t) => t.copies).where((c) => c.state == 'HOLD'
    && (m == null || c.member == m)).toList();
  int reservations(Member m) => holds(m).length + titles.values.where((t) => t.queue.contains(m)).length;
  Member member(String id) {
    final m = members[id];
    if (m == null)
      fail('unknown member');
    return m;
  }
  Title book(String token) {
    final isbn = normalizeISBN(token), t = titles[isbn];
    if (t == null)
      fail('unknown book');
    return t;
  }
  Copy? loan(Member m, Title t) {
    for (final c in t.copies)
      if (c.state == 'LOANED' && c.member == m) return c;
    return null;
  }
  Copy? hold(Member m, Title t) {
    for (final c in t.copies)
      if (c.state == 'HOLD' && c.member == m) return c;
    return null;
  }

  int openDay(int t) {
    while (closed.contains(t))
      t++;
    return t;
  }

  int daysLate(Copy c) => day > c.due ? day - c.due : 0;
  int fine(Copy c) {
    final value = daysLate(c) * c.member!.rate;
    return value < c.member!.cap ? value : c.member!.cap;
  }

  void charge(Member m, Title t, String kind, int value) {
    if (value == 0)
      return;
    m.items.add(Charge(day, kind, t.isbn, value));
    charged[kind] = charged[kind]! + value;
  }

  void release(Copy c, StringBuffer out) {
    if (c.title.queue.isEmpty) {
      c.state = 'AVAILABLE';
      c.member = null;
      return;
    }
    final m = c.title.queue.removeAt(0);
    c.state = 'HOLD';
    c.member = m;
    c.expiry = openDay(day + 3);
    out.writeln('HOLD ${c.title.isbn} copy ${c.number} ${m.id} until ${c.expiry}');
  }(int, int) endLoan(Copy c, String result) {
    final m = c.member!, late = daysLate(c), value = fine(c);
    charge(m, c.title, 'FINE', value);
    m.history.add('$result ${c.title.isbn} copy ${c.number} from ${c.loanDay} to $day late $late fine ${money(value)}');
    c.state = 'AVAILABLE';
    c.member = null;
    return (late, value);
  }

  void processLoss(Copy c, String heading, StringBuffer out) {
    final m = c.member!, t = c.title, result = endLoan(c, 'LOST');
    m.history[m.history.length - 1] += ' price ${money(t.price)}';
    charge(m, t, 'PRICE', t.price);
    c.state = 'LOST';
    lost++;
    out.writeln('$heading ${m.id} ${t.isbn} copy ${c.number} late ${result.$1} fine ${money(result.$2)} price ${money(t.price)} balance ${money(m.balance)}');
    if (t.holdings == 0) {
      for (final member in t.queue)
        out.writeln('DROPPED ${t.isbn} ${member.id}');
      t.queue.clear();
    }
  }
  String? renewalProblem(Copy c) => c.due < day ? 'loan overdue' : c.renewals == 2 ? 'renewal limit' : c.title.queue.isNotEmpty ? 'title reserved' : null;
  void renew(Copy c, StringBuffer out) {
    c.due = openDay(day + c.member!.period);
    c.renewals++;
    renewed++;
    out.writeln('RENEW ${c.member!.id} ${c.title.isbn} copy ${c.number} due ${c.due} renewals ${c.renewals}');
  }
  List<Copy> dueOrder(List<Copy> cs, [bool expiry = false]) => cs..sort((a, b) {
    final x = expiry ? a.expiry : a.due, y = expiry ? b.expiry : b.due;
    return x != y ? x.compareTo(y) : a.title.isbn.compareTo(b.title.isbn);
  });
  String execute(String line) {
    final a = line.split(' '), op = a[0], out = StringBuffer();
    if (op == 'DAY') {
      final target = int.parse(a[1]);
      if (target <= day)
        fail('invalid day');
      out.writeln('DAY $target');
      while (day < target) {
        day++;
        final automatic = loans().where((c) => c.due + 365 <= day).toList()..sort((a, b) => a.member!.id != b.member!.id ? a.member!.id.compareTo(b.member!.id) : a.title.isbn.compareTo(b.title.isbn));
        for (final c in automatic)
          processLoss(c, 'AUTOLOST', out);
        final expired = holds().where((c) => c.expiry < day).toList()..sort((a, b) => a.title.isbn != b.title.isbn ? a.title.isbn.compareTo(b.title.isbn) : a.number.compareTo(b.number));
        for (final c in expired) {
          final m = c.member!;
          charge(m, c.title, 'FEE', m.fee);
          out.writeln('EXPIRED ${c.title.isbn} copy ${c.number} ${m.id} fee ${money(m.fee)}');
          release(c, out);
        }
      }
    } else if (op == 'CLOSED') {
      final target = int.parse(a[1]);
      if (target <= day)
        fail('invalid day');
      if (closed.contains(target))
        fail('already closed');
      closed.add(target);
      out.writeln('CLOSED $target');
      for (final t in books()) {
        for (final c in t.copies) {
          if (c.state == 'LOANED' && c.due == target) {
            c.due = openDay(target);
            out.writeln('MOVED ${t.isbn} copy ${c.number} ${c.member!.id} due ${c.due}');
          } else if (c.state == 'HOLD' && c.expiry == target) {
            c.expiry = openDay(target);
            out.writeln('MOVED ${t.isbn} copy ${c.number} ${c.member!.id} until ${c.expiry}');
          }
        }
      }
    } else if (op == 'ADDBOOK') {
      final isbn = normalizeISBN(a[1]), name = a.skip(4).join(' '), old = titles[isbn];
      if (old != null && old.name != name)
        fail('title mismatch');
      final t = old ?? Title(isbn, name, amount(a[3])), count = int.parse(a[2]);
      t.price = amount(a[3]);
      titles[isbn] = t;
      final added = [for (var i = 0; i < count; i++) Copy(t, t.copies.length + i + 1)];
      t.copies.addAll(added);
      out.writeln('ADDBOOK $isbn added $count total ${t.holdings}');
      for (final c in added)
        release(c, out);
    } else if (op == 'ADDMEMBER') {
      if (members.containsKey(a[1]))
        fail('duplicate member');
      if (!['STUDENT', 'STAFF'].contains(a[2]))
        fail('unknown type');
      final m = Member(a[1], a[2], a.skip(3).join(' '));
      members[m.id] = m;
      out.writeln('ADDMEMBER ${m.id} ${m.type} loans ${m.loanLimit} days ${m.period}');
    } else if (op == 'WITHDRAW') {
      final t = book(a[1]), n = int.parse(a[2]);
      if (n < 1 || n > t.copies.length)
        fail('unknown copy');
      final c = t.copies[n - 1];
      if (c.state != 'AVAILABLE')
        fail('copy not available');
      c.state = 'WITHDRAWN';
      out.writeln('WITHDRAW ${t.isbn} copy $n total ${t.holdings}');
    } else if (['BORROW', 'RETURN', 'RENEW', 'RESERVE', 'CANCEL', 'LOST'].contains(op)) {
      final m = member(a[1]), t = book(a[2]), current = loan(m, t), held = hold(m, t);
      if (op == 'BORROW') {
        if (closed.contains(day))
          fail('library closed');
        if (current != null)
          fail('already borrowed');
        if (m.blocked)
          fail('member blocked');
        if (loans(m).any((c) => c.due < day))
          fail('overdue loans');
        if (loans(m).length >= m.loanLimit)
          fail('loan limit');
        final available = t.copies.where((c) => c.state == 'AVAILABLE').toList(), c = held ?? (available.isEmpty ? null : available.first);
        if (c == null)
          fail(t.count('HOLD') > 0 ? 'all copies on hold' : 'no copy available');
        c.state = 'LOANED';
        c.member = m;
        c.loanDay = day;
        c.due = openDay(day + m.period);
        c.renewals = 0;
        t.borrowed++;
        borrowed++;
        out.writeln('BORROW ${m.id} ${t.isbn} copy ${c.number} due ${c.due}');
      } else if (op == 'RETURN' || op == 'LOST') {
        if (current == null)
          fail('not borrowed');
        if (op == 'LOST')
          processLoss(current, 'LOST', out);
        else {
          final result = endLoan(current, 'RETURNED');
          returned++;
          out.writeln('RETURN ${m.id} ${t.isbn} copy ${current.number} late ${result.$1} fine ${money(result.$2)} balance ${money(m.balance)}');
          release(current, out);
        }
      } else if (op == 'RENEW') {
        if (current == null)
          fail('not borrowed');
        if (m.blocked)
          fail('member blocked');
        final reason = renewalProblem(current);
        if (reason != null)
          fail(reason);
        renew(current, out);
      } else if (op == 'RESERVE') {
        if (current != null)
          fail('already borrowed');
        if (t.queue.contains(m) || held != null)
          fail('already reserved');
        if (m.blocked)
          fail('member blocked');
        if (reservations(m) >= m.reservationLimit)
          fail('reservation limit');
        if (t.holdings == 0)
          fail('no copies');
        if (t.count('AVAILABLE') > 0)
          fail('copy available');
        t.queue.add(m);
        final p = t.queue.length, due = t.copies.where((c) => c.state == 'LOANED').map((c) => c.due).toList()..sort();
        out.writeln('RESERVE ${m.id} ${t.isbn} position $p estimate ${p <= due.length ? due[p - 1] : 'none'}');
      } else {
        if (!t.queue.contains(m) && held == null)
          fail('not reserved');
        if (t.queue.remove(m))
          out.writeln('CANCEL ${m.id} ${t.isbn} queue');
        else {
          out.writeln('CANCEL ${m.id} ${t.isbn} hold copy ${held!.number}');
          release(held!, out);
        }
      }
    } else if (op == 'RENEWALL') {
      final m = member(a[1]), cs = loans(m)..sort((a, b) => a.title.isbn.compareTo(b.title.isbn));
      if (cs.isEmpty)
        fail('no loans');
      if (m.blocked)
        fail('member blocked');
      var success = 0, skipped = 0;
      for (final c in cs) {
        final reason = renewalProblem(c);
        if (reason == null) {
          renew(c, out);
          success++;
        } else {
          out.writeln('SKIP ${c.title.isbn} $reason');
          skipped++;
        }
      }
      out.writeln('RENEWALL ${m.id} renewed $success skipped $skipped');
    } else if (op == 'PAYFINE') {
      final m = member(a[1]);
      if (m.balance == 0)
        fail('no fines');
      var remaining = amount(a[2]);
      final applied = <(int, int)>[];
      for (var i = 0; i < m.items.length && remaining > 0; i++) {
        final item = m.items[i], value = item.unpaid < remaining ? item.unpaid : remaining;
        if (value == 0)
          continue;
        item.unpaid -= value;
        remaining -= value;
        applied.add((i, value));
      }
      final value = amount(a[2]) - remaining;
      paid += value;
      out.writeln('PAYFINE ${m.id} paid ${money(value)} change ${money(remaining)} balance ${money(m.balance)}');
      for (final entry in applied)
        out.writeln('ITEM ${entry.$1 + 1} ${m.items[entry.$1].kind} paid ${money(entry.$2)} remaining ${money(m.items[entry.$1].unpaid)}');
    } else if (op == 'WAIVE') {
      final m = member(a[1]), n = int.parse(a[2]);
      if (n < 1 || n > m.items.length)
        fail('unknown item');
      final item = m.items[n - 1];
      if (item.unpaid == 0)
        fail('item settled');
      final value = item.unpaid;
      item.unpaid = 0;
      waived += value;
      out.writeln('WAIVE ${m.id} item $n ${item.kind} amount ${money(value)} balance ${money(m.balance)}');
    } else if (op == 'FINES') {
      final m = member(a[1]);
      out.writeln('FINES ${m.id} items ${m.items.where((i) => i.unpaid != 0).length} balance ${money(m.balance)}');
      for (var i = 0; i < m.items.length; i++) {
        final item = m.items[i];
        if (item.unpaid > 0)
          out.writeln('${i + 1} day ${item.day} ${item.kind} ${item.isbn} amount ${money(item.amount)} remaining ${money(item.unpaid)}');
      }
    } else if (op == 'SEARCH') {
      final keyword = a.skip(1).join(' ').toLowerCase(), selected = titles.values.where((t) => t.name.toLowerCase().contains(keyword)).toList();
      selected.sort((a, b) => a.name.toLowerCase() != b.name.toLowerCase() ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : a.isbn.compareTo(b.isbn));
      out.writeln('SEARCH ${selected.length}');
      for (final t in selected)
        out.writeln('${t.isbn} ${t.count('AVAILABLE')}/${t.holdings} ${t.name}');
    } else if (op == 'OVERDUE') {
      final cs = loans().where((c) => c.due < day).toList()..sort((a, b) => a.due != b.due ? a.due.compareTo(b.due) : a.member!.id != b.member!.id ? a.member!.id.compareTo(b.member!.id) : a.title.isbn.compareTo(b.title.isbn));
      out.writeln('OVERDUE ${cs.length}');
      for (final c in cs)
        out.writeln('${c.member!.id} ${c.title.isbn} copy ${c.number} due ${c.due} late ${daysLate(c)} fine ${money(fine(c))}');
    } else if (op == 'NOTICES') {
      final lines = <String>[];
      for (final m in people()) {
        final cs = dueOrder(loans(m));
        for (final c in cs.where((c) => c.due < day))
          lines.add('OVERDUE ${m.id} ${c.title.isbn} due ${c.due}');
        for (final c in cs.where((c) => c.due >= day && c.due <= day + 2))
          lines.add('DUESOON ${m.id} ${c.title.isbn} due ${c.due}');
        for (final c in dueOrder(holds(m), true))
          lines.add('PICKUP ${m.id} ${c.title.isbn} until ${c.expiry}');
      }
      out.writeln('NOTICES ${lines.length}');
      for (final text in lines)
        out.writeln(text);
    } else if (op == 'MEMBER' || op == 'MEMBERS') {
      final ms = op == 'MEMBER' ? [member(a[1])] : people();
      if (op == 'MEMBERS')
        out.writeln('MEMBERS ${ms.length}');
      for (final m in ms) {
        final cs = dueOrder(loans(m));
        if (op == 'MEMBERS') {
          out.writeln('${m.id} ${m.type} loans ${cs.length} reservations ${reservations(m)} balance ${money(m.balance)} ${m.blocked ? 'BLOCKED' : 'OK'}');
          continue;
        }
        out.writeln('MEMBER ${m.id} ${m.type} ${m.name}');
        out.writeln('STATUS loans ${cs.length}/${m.loanLimit} reservations ${reservations(m)}/${m.reservationLimit} balance ${money(m.balance)} ${m.blocked ? 'BLOCKED' : 'OK'}');
        for (final c in cs)
          out.writeln('LOAN ${c.title.isbn} copy ${c.number} due ${c.due} renewals ${c.renewals}${c.due < day ? ' late ${daysLate(c)} fine ${money(fine(c))}' : ''}');
        for (final c in dueOrder(holds(m), true))
          out.writeln('HOLD ${c.title.isbn} copy ${c.number} until ${c.expiry}');
        for (final t in books())
          if (t.queue.contains(m)) out.writeln('QUEUE ${t.isbn} position ${t.queue.indexOf(m) + 1}');
      }
    } else if (op == 'BOOK') {
      final t = book(a[1]);
      out.writeln('BOOK ${t.isbn} ${t.name}');
      out.writeln('PRICE ${money(t.price)} copies ${t.holdings} borrowed ${t.borrowed}');
      for (final c in t.copies)
        out.writeln('COPY ${c.number} ${c.state}${c.state == 'LOANED' ? ' ${c.member!.id} due ${c.due}' : c.state == 'HOLD' ? ' ${c.member!.id} until ${c.expiry}' : ''}');
      out.writeln('QUEUE ${t.queue.length}${t.queue.isEmpty ? '' : ' ${t.queue.map((m) => m.id).join(' ')}'}');
    } else if (op == 'INVENTORY') {
      final cs = copies();
      int count(String state) => cs.where((c) => c.state == state).length;
      out.writeln('INVENTORY titles ${titles.length} copies ${books().fold(0, (s, t) => s + t.holdings)} available ${count('AVAILABLE')} loaned ${count('LOANED')} hold ${count('HOLD')} lost ${count('LOST')} withdrawn ${count('WITHDRAWN')}');
      for (final t in books())
        out.writeln('${t.isbn} copies ${t.holdings} available ${t.count('AVAILABLE')} loaned ${t.count('LOANED')} hold ${t.count('HOLD')} queue ${t.queue.length}');
    } else if (op == 'HISTORY') {
      final m = member(a[1]);
      out.writeln('HISTORY ${m.id} ${m.history.length}');
      for (final text in m.history)
        out.writeln(text);
    } else if (op == 'STATS') {
      out.writeln('STATS day $day titles ${titles.length} members ${members.length} closed ${closed.length}');
      out.writeln('LOANS borrowed $borrowed returned $returned renewed $renewed lost $lost active ${loans().length}');
      out.writeln('MONEY fines ${money(charged['FINE']!)} fees ${money(charged['FEE']!)} charges ${money(charged['PRICE']!)} paid ${money(paid)} waived ${money(waived)} outstanding ${money(members.values.fold(0, (s, m) => s + m.balance))}');
      final top = books().where((t) => t.borrowed > 0).toList()..sort((a, b) => a.borrowed != b.borrowed ? b.borrowed.compareTo(a.borrowed) : a.isbn.compareTo(b.isbn));
      for (var i = 0; i < top.length && i < 3; i++)
        out.writeln('TOP ${i + 1} ${top[i].isbn} ${top[i].borrowed} ${top[i].name}');
    }
    return out.toString();
  }
}

void main() {
  final library = Library(), output = StringBuffer(), count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      output.write(library.execute(line));
    } on LibraryError catch (error) {
      output.writeln('ERROR ${error.message}');
    }
  }
  stdout.write(output);
}
