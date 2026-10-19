import 'dart:collection';
import 'dart:io';
import 'dart:math';

class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

enum AccountType {
  asset('ASSET'),
  liability('LIABILITY'),
  equity('EQUITY'),
  revenue('REVENUE'),
  expense('EXPENSE'),
  contraAsset('CONTRA_ASSET');

  final String label;
  const AccountType(this.label);
  int get sign => this == asset || this == expense ? 1 : -1;
  AccountType get group => this == contraAsset ? asset : this;
}

enum EntryKind { journal, recurring, reversal, closing, reopen, depreciation, interest, writeoff }

int sum(Iterable<int> values) => values.fold(0, (total, value) => total + value);
String pad(int value, int width) => value.toString().padLeft(width, '0');
String money(int cents) => '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${pad(cents.abs() % 100, 2)}';
int parseMoney(String text) => int.parse(text.substring(0, text.length - 3)) * 100 + int.parse(text.substring(text.length - 2));

class BookDate {
  static const lastNumber = 36524;
  static const monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final int year, month, day;
  const BookDate(this.year, this.month, this.day);

  static int daysInMonth(int year, int month) => monthLengths[month - 1] +
      (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 1 : 0);

  factory BookDate.parse(String text) {
    final year = int.parse(text.substring(0, 4));
    final month = int.parse(text.substring(5, 7));
    final day = int.parse(text.substring(8));
    if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
      throw CommandError('invalid date $text');
    }
    return BookDate(year, month, day);
  }

  int get number {
    final previous = year - 1;
    var days = 365 * (year - 2000) + previous ~/ 4 - 1999 ~/ 4 - previous ~/ 100 + 1999 ~/ 100 + previous ~/ 400 - 1999 ~/ 400;
    for (var m = 1; m < month; m++) {
      days += daysInMonth(year, m);
    }
    return days + day - 1;
  }

  BookDate addMonths(int count) {
    final offset = month - 1 + count;
    final nextYear = year + offset ~/ 12;
    final nextMonth = offset % 12 + 1;
    return BookDate(nextYear, nextMonth, min(day, daysInMonth(nextYear, nextMonth)));
  }

  @override
  String toString() => '${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}';
}

class Account {
  final String code, name;
  final AccountType type;
  bool active = true;
  Account(this.code, this.type, this.name);
  int get sign => type.sign;
}

class Line {
  final bool debit;
  final String code;
  final int amount;
  final String? partner;
  const Line(this.debit, this.code, this.amount, [this.partner]);
  int get difference => debit ? amount : -amount;
  String get side => debit ? 'DR' : 'CR';
  Line get reversed => Line(!debit, code, amount, partner);
}

class Entry {
  final String id, memo;
  final BookDate date;
  final EntryKind kind;
  final List<Line> lines;
  final int sequence;
  String? reversedBy, reverses;
  Entry(this.id, this.date, this.kind, this.memo, Iterable<Line> lines, this.sequence)
      : lines = List.unmodifiable(lines);
  int get amount => sum(lines.where((line) => line.debit).map((line) => line.amount));
}

class Template {
  final String memo;
  final List<Line> lines;
  int uses = 0;
  Template(this.memo, Iterable<Line> lines) : lines = List.unmodifiable(lines);
}

class Draft {
  final bool journal;
  final String key, memo;
  final String? date;
  final lines = <Line>[];
  Draft(this.journal, this.key, this.date, this.memo);
  String get kind => journal ? 'journal' : 'template';
}

class Totals {
  int debit = 0, credit = 0;
  int get difference => debit - credit;
  void add(Line line) {
    if (line.debit) {
      debit += line.amount;
    } else {
      credit += line.amount;
    }
  }
}

class OpenItem {
  final Entry entry;
  final int original;
  int remaining;
  OpenItem(this.entry, this.original, this.remaining);
}

class Settlement {
  final items = Queue<OpenItem>();
  int unapplied = 0;
}

class CloseRecord {
  final BookDate date;
  final Entry? entry;
  const CloseRecord(this.date, this.entry);
}

class Books {
  final accounts = SplayTreeMap<String, Account>();
  final entries = <Entry>[];
  final entryIds = <String, Entry>{};
  final templates = SplayTreeMap<String, Template>();
  final closes = <CloseRecord>[];
  final output = StringBuffer();
  Draft? draft;
  int closeCount = 0, depreciationCount = 0, interestCount = 0, writeoffCount = 0;

  void emit(String line) => output.writeln(line);
  String get closed => closes.isEmpty ? 'none' : closes.last.date.toString();
  Account account(String code) => accounts[code] ?? (throw CommandError('unknown account $code'));
  Entry entry(String id) => entryIds[id] ?? (throw CommandError('unknown entry $id'));

  Account requireType(String code, AccountType type) {
    final result = account(code);
    if (result.type != type) throw CommandError('wrong type $code ${type.label}');
    return result;
  }

  void active(Iterable<Account> sequence) {
    for (final account in sequence) {
      if (!account.active) throw CommandError('inactive account ${account.code}');
    }
  }

  void checkClosed(BookDate date) {
    if (closes.isNotEmpty && date.number <= closes.last.date.number) throw CommandError('period closed $date');
  }

  (BookDate, BookDate) range(String start, String end) {
    final a = BookDate.parse(start);
    final b = BookDate.parse(end);
    if (a.number > b.number) throw CommandError('invalid range $start $end');
    return (a, b);
  }

  List<Entry> ordered({int start = 0, int end = BookDate.lastNumber}) => entries
      .where((entry) => entry.date.number >= start && entry.date.number <= end).toList()
    ..sort((a, b) {
      final date = a.date.number.compareTo(b.date.number);
      return date == 0 ? a.sequence.compareTo(b.sequence) : date;
    });

  Map<String, Totals> aggregate({int start = 0, int end = BookDate.lastNumber, bool operating = false}) {
    final result = <String, Totals>{};
    for (final entry in entries) {
      if (entry.date.number < start || entry.date.number > end ||
          operating && (entry.kind == EntryKind.closing || entry.kind == EntryKind.reopen)) continue;
      for (final line in entry.lines) {
        result.putIfAbsent(line.code, Totals.new).add(line);
      }
    }
    return result;
  }

  int balance(Account account, [int end = BookDate.lastNumber]) => sum(entries
      .where((entry) => entry.date.number <= end)
      .map((entry) => sum(entry.lines.where((line) => line.code == account.code).map((line) => line.difference)))) * account.sign;

  int dailySum(Account account, int start, int end) {
    var total = 0;
    for (final entry in entries) {
      if (entry.date.number > end) continue;
      final change = sum(entry.lines.where((line) => line.code == account.code).map((line) => line.difference)) * account.sign;
      total += change * (end - max(start, entry.date.number) + 1);
    }
    return total;
  }

  String parent(String code) {
    var result = '';
    for (final other in accounts.keys) {
      if (other != code && code.startsWith(other) && other.length > result.length) result = other;
    }
    return result.isEmpty ? 'none' : result;
  }

  String top(String code) => accounts.keys.firstWhere((other) => code.startsWith(other));

  Entry post(String id, BookDate date, EntryKind kind, String memo, Iterable<Line> lines) {
    final posted = Entry(id, date, kind, memo, lines, entries.length + 1);
    entries.add(posted);
    entryIds[id] = posted;
    return posted;
  }

  Entry reverse(Entry original, BookDate date, EntryKind kind, String memo) {
    final posted = post('${original.id}-R', date, kind, memo, original.lines.map((line) => line.reversed));
    original.reversedBy = posted.id;
    posted.reverses = original.id;
    return posted;
  }

  Totals lineTotals(Iterable<Line> lines) {
    final totals = Totals();
    for (final line in lines) {
      totals.add(line);
    }
    return totals;
  }

  SplayTreeMap<String, Settlement> settlements(Account account, int date) {
    final result = SplayTreeMap<String, Settlement>();
    for (final entry in ordered(end: date)) {
      for (final line in entry.lines) {
        final partner = line.partner;
        if (line.code != account.code || partner == null) continue;
        final settlement = result.putIfAbsent(partner, Settlement.new);
        final signed = line.difference * account.sign;
        if (signed > 0) {
          final applied = min(signed, settlement.unapplied);
          settlement.unapplied -= applied;
          if (signed > applied) settlement.items.add(OpenItem(entry, signed, signed - applied));
        } else {
          var remaining = -signed;
          while (remaining > 0 && settlement.items.isNotEmpty) {
            final item = settlement.items.first;
            final applied = min(remaining, item.remaining);
            item.remaining -= applied;
            remaining -= applied;
            if (item.remaining == 0) settlement.items.removeFirst();
          }
          settlement.unapplied += remaining;
        }
      }
    }
    return result;
  }

  int section(String heading, Set<AccountType> types, int sign, Map<String, Totals> totals, {int? earnings}) {
    final groups = SplayTreeMap<String, List<Account>>();
    int display(Account account) => (totals[account.code]?.difference ?? 0) * sign;
    var total = earnings ?? 0;
    for (final account in accounts.values.where((account) => types.contains(account.type))) {
      groups.putIfAbsent(top(account.code), () => []).add(account);
      total += display(account);
    }
    emit('  $heading ${money(total)}');
    for (final group in groups.entries) {
      if (!group.value.any((account) => display(account) != 0)) continue;
      emit('    ${group.key} ${accounts[group.key]!.name} ${money(sum(group.value.map(display)))}');
      for (final account in group.value) {
        if (display(account) != 0) emit('      ${account.code} ${account.name} ${money(display(account))}');
      }
    }
    if (earnings != null) emit('    current earnings ${money(earnings)}');
    return total;
  }

  void postDraft() {
    final block = draft ?? (throw const CommandError('no open entry'));
    draft = null;
    BookDate? date;
    if (block.journal) {
      if (entryIds.containsKey(block.key)) throw CommandError('duplicate entry ${block.key}');
      date = BookDate.parse(block.date!);
      checkClosed(date);
    } else if (templates.containsKey(block.key)) {
      throw CommandError('duplicate template ${block.key}');
    }
    if (block.lines.length < 2) throw CommandError('too few lines ${block.key}');
    for (final line in block.lines) {
      final found = account(line.code);
      if (block.journal && !found.active) throw CommandError('inactive account ${line.code}');
      if (line.amount == 0) throw CommandError('zero amount ${line.code}');
    }
    final total = lineTotals(block.lines);
    if (total.debit != total.credit) {
      throw CommandError('unbalanced ${block.key} debit ${money(total.debit)} credit ${money(total.credit)}');
    }
    if (block.journal) {
      final entry = post(block.key, date!, EntryKind.journal, block.memo, block.lines);
      emit('POST ${entry.id} $date lines ${entry.lines.length} amount ${money(entry.amount)}');
    } else {
      templates[block.key] = Template(block.memo, block.lines);
      emit('TEMPLATE ${block.key} lines ${block.lines.length} amount ${money(total.debit)}');
    }
  }

  void close(BookDate date, String code) {
    checkClosed(date);
    final equity = requireType(code, AccountType.equity);
    active([equity]);
    final totals = aggregate(end: date.number);
    final targets = accounts.values.where((account) =>
        (account.type == AccountType.revenue || account.type == AccountType.expense) &&
        (totals[account.code]?.difference ?? 0) != 0).toList();
    active(targets);
    final lines = <Line>[];
    var income = 0;
    for (final account in targets) {
      final difference = totals[account.code]!.difference;
      lines.add(Line(difference < 0, account.code, difference.abs()));
      income -= difference;
    }
    if (income != 0) lines.add(Line(income < 0, code, income.abs()));
    closeCount++;
    final entry = lines.isEmpty ? null : post('CLOSE-$closeCount', date, EntryKind.closing, 'closing', lines);
    closes.add(CloseRecord(date, entry));
    emit(entry == null ? 'CLOSE $date no entry' : 'CLOSE $date entry ${entry.id} lines ${lines.length} net income ${money(income)}');
  }

  void ledger(Account account, BookDate start, BookDate end) {
    var running = balance(account, start.number - 1), debit = 0, credit = 0;
    emit('LEDGER ${account.code} ${account.name} $start $end');
    emit('  opening ${money(running)}');
    for (final entry in ordered(start: start.number, end: end.number)) {
      for (final line in entry.lines) {
        if (line.code != account.code) continue;
        running += line.difference * account.sign;
        if (line.debit) {
          debit += line.amount;
        } else {
          credit += line.amount;
        }
        emit('  ${entry.date} ${entry.id} ${line.side} ${money(line.amount)} balance ${money(running)} ${entry.memo}');
      }
    }
    final days = end.number - start.number + 1;
    emit('  ending ${money(running)} debits ${money(debit)} credits ${money(credit)} days $days average ${money(dailySum(account, start.number, end.number) ~/ days)}');
  }

  String ageColumns(List<int> values) => '0-30 ${money(values[0])} 31-60 ${money(values[1])} 61-90 ${money(values[2])} '
      '91+ ${money(values[3])} unapplied ${money(values[4])} balance ${money(sum(values.take(4)) - values[4])}';

  void execute(String text) {
    final words = text.split(' ');
    switch (words[0]) {
      case 'ACCOUNT':
        final code = words[1];
        if (accounts.containsKey(code)) throw CommandError('duplicate account $code');
        final type = AccountType.values.firstWhere((type) => type.label == words[2]);
        for (final other in accounts.values) {
          if ((code.startsWith(other.code) || other.code.startsWith(code)) && type.group != other.type.group) {
            throw CommandError('class mismatch $code ${other.code}');
          }
        }
        accounts[code] = Account(code, type, words[3]);
        emit('ACCOUNT $code ${type.label} ${words[3]} parent ${parent(code)}');
        return;
      case 'DEACTIVATE':
        final found = account(words[1]);
        if (!found.active) throw CommandError('already inactive ${found.code}');
        final current = balance(found);
        if (current != 0) throw CommandError('nonzero balance ${found.code} ${money(current)}');
        found.active = false;
        emit('DEACTIVATE ${found.code} ${found.name}');
        return;
      case 'JOURNAL':
      case 'TEMPLATE':
        final previous = draft;
        if (previous != null) emit('DISCARD ${previous.key} lines ${previous.lines.length}');
        draft = words[0] == 'JOURNAL' ? Draft(true, words[1], words[2], words[3]) : Draft(false, words[1], null, words[2]);
        return;
      case 'DR':
      case 'CR':
        final block = draft ?? (throw const CommandError('no open entry'));
        block.lines.add(Line(words[0] == 'DR', words[1], parseMoney(words[2]), words.length == 4 ? words[3] : null));
        return;
      case 'POST':
        postDraft();
        return;
      case 'DRAFT':
        final block = draft ?? (throw const CommandError('no open entry'));
        final total = lineTotals(block.lines);
        emit('DRAFT ${block.kind} ${block.key} lines ${block.lines.length} debit ${money(total.debit)} credit ${money(total.credit)} difference ${money(total.difference)}');
        return;
      case 'REVERSE':
        final original = entry(words[1]);
        if ({EntryKind.reversal, EntryKind.closing, EntryKind.reopen}.contains(original.kind)) throw CommandError('cannot reverse ${original.id}');
        if (original.reversedBy != null) throw CommandError('already reversed ${original.id}');
        final date = BookDate.parse(words[2]);
        if (date.number < original.date.number) throw CommandError('reverse before entry ${original.id} ${original.date}');
        checkClosed(date);
        active(original.lines.map((line) => accounts[line.code]!));
        final posted = reverse(original, date, EntryKind.reversal, original.memo);
        emit('REVERSE ${original.id} entry ${posted.id} $date amount ${money(posted.amount)}');
        return;
      case 'RECUR':
        final template = templates[words[1]] ?? (throw CommandError('unknown template ${words[1]}'));
        final date = BookDate.parse(words[2]);
        final count = int.parse(words[3]);
        if (count == 0) throw const CommandError('invalid count');
        checkClosed(date);
        active(template.lines.map((line) => accounts[line.code]!));
        emit('RECUR ${words[1]} count $count');
        for (var month = 0; month < count; month++) {
          final posted = post('${words[1]}-${++template.uses}', date.addMonths(month), EntryKind.recurring, template.memo, template.lines);
          emit('  POST ${posted.id} ${posted.date} lines ${posted.lines.length} amount ${money(posted.amount)}');
        }
        return;
      case 'DEPRECIATE':
        final date = BookDate.parse(words[1]);
        checkClosed(date);
        final asset = requireType(words[2], AccountType.asset);
        final contra = requireType(words[3], AccountType.contraAsset);
        final expense = requireType(words[4], AccountType.expense);
        active([contra, expense]);
        final cost = balance(asset, date.number), accumulated = balance(contra, date.number);
        final amount = cost > 0 ? min(cost ~/ int.parse(words[5]), cost - accumulated) : 0;
        if (amount <= 0) throw CommandError('nothing to depreciate ${asset.code}');
        final posted = post('DEP-${++depreciationCount}', date, EntryKind.depreciation, 'depreciation',
            [Line(true, expense.code, amount), Line(false, contra.code, amount)]);
        emit('DEPRECIATE ${asset.code} entry ${posted.id} $date amount ${money(amount)} accumulated ${money(accumulated + amount)} book ${money(cost - accumulated - amount)}');
        return;
      case 'INTEREST':
        final found = account(words[1]);
        if (found.type != AccountType.asset && found.type != AccountType.liability) throw CommandError('not interest bearing ${found.code}');
        final offset = requireType(words[2], found.type == AccountType.asset ? AccountType.revenue : AccountType.expense);
        final (start, end) = range(words[3], words[4]);
        checkClosed(end);
        active([found, offset]);
        final daily = dailySum(found, start.number, end.number);
        final amount = daily * int.parse(words[5]) ~/ 3650000;
        if (amount <= 0) throw CommandError('no interest ${found.code}');
        final debit = found.type == AccountType.asset ? found.code : offset.code;
        final credit = found.type == AccountType.asset ? offset.code : found.code;
        final posted = post('INT-${++interestCount}', end, EntryKind.interest, 'interest', [Line(true, debit, amount), Line(false, credit, amount)]);
        final days = end.number - start.number + 1;
        emit('INTEREST ${found.code} entry ${posted.id} $end days $days average ${money(daily ~/ days)} amount ${money(amount)}');
        return;
      case 'WRITEOFF':
        final date = BookDate.parse(words[1]);
        checkClosed(date);
        final found = requireType(words[2], AccountType.asset);
        final expense = requireType(words[3], AccountType.expense);
        active([found, expense]);
        final age = int.parse(words[4]);
        final targets = <(String, int)>[];
        for (final pair in settlements(found, date.number).entries) {
          final amount = sum(pair.value.items.where((item) => date.number - item.entry.date.number > age).map((item) => item.remaining));
          if (amount > 0) targets.add((pair.key, amount));
        }
        final total = sum(targets.map((target) => target.$2));
        if (total == 0) throw CommandError('nothing to write off ${found.code}');
        final lines = [Line(true, expense.code, total), for (final (partner, amount) in targets) Line(false, found.code, amount, partner)];
        final posted = post('WO-${++writeoffCount}', date, EntryKind.writeoff, 'writeoff', lines);
        emit('WRITEOFF ${found.code} entry ${posted.id} $date partners ${targets.length} amount ${money(total)}');
        for (final (partner, amount) in targets) {
          emit('  $partner ${money(amount)}');
        }
        return;
      case 'CLOSE':
        close(BookDate.parse(words[1]), words[2]);
        return;
      case 'REOPEN':
        if (closes.isEmpty) throw const CommandError('nothing to reopen');
        final record = closes.last;
        final original = record.entry;
        var result = 'no entry';
        if (original != null) {
          active(original.lines.map((line) => accounts[line.code]!));
          result = 'entry ${reverse(original, record.date, EntryKind.reopen, 'reopen').id}';
        }
        closes.removeLast();
        emit('REOPEN ${record.date} $result closed $closed');
        return;
      case 'LEDGER':
        final found = account(words[1]);
        final (start, end) = range(words[2], words[3]);
        ledger(found, start, end);
        return;
      case 'ACTIVITY':
        final found = account(words[1]);
        final year = int.parse(words[2]);
        var debit = 0, credit = 0;
        emit('ACTIVITY ${found.code} ${found.name} $year');
        for (var month = 1; month <= 12; month++) {
          final start = BookDate(year, month, 1).number;
          final end = BookDate(year, month, BookDate.daysInMonth(year, month)).number;
          final total = aggregate(start: start, end: end)[found.code] ?? Totals();
          debit += total.debit;
          credit += total.credit;
          emit('  ${pad(year, 4)}-${pad(month, 2)} debit ${money(total.debit)} credit ${money(total.credit)} balance ${money(balance(found, end))}');
        }
        emit('  total debit ${money(debit)} credit ${money(credit)}');
        return;
      case 'TRIAL':
        final date = BookDate.parse(words[1]);
        final totals = aggregate(end: date.number);
        var debit = 0, credit = 0;
        emit('TRIAL $date');
        for (final account in accounts.values) {
          final difference = totals[account.code]?.difference ?? 0;
          if (difference == 0) continue;
          if (difference > 0) { debit += difference; } else { credit -= difference; }
          emit('  ${account.code} ${account.name} ${difference > 0 ? 'debit' : 'credit'} ${money(difference.abs())}');
        }
        emit('  total debit ${money(debit)} credit ${money(credit)}');
        return;
      case 'INCOME':
        final (start, end) = range(words[1], words[2]);
        final totals = aggregate(start: start.number, end: end.number, operating: true);
        emit('INCOME $start $end');
        final revenue = section('REVENUE', {AccountType.revenue}, -1, totals);
        final expense = section('EXPENSE', {AccountType.expense}, 1, totals);
        emit('  NET INCOME ${money(revenue - expense)}');
        return;
      case 'BALANCE':
        final date = BookDate.parse(words[1]);
        final totals = aggregate(end: date.number);
        final earnings = -sum(accounts.values.where((account) => account.type == AccountType.revenue || account.type == AccountType.expense)
            .map((account) => totals[account.code]?.difference ?? 0));
        emit('BALANCE $date');
        final assets = section('ASSETS', {AccountType.asset, AccountType.contraAsset}, 1, totals);
        final liabilities = section('LIABILITIES', {AccountType.liability}, -1, totals);
        final equity = section('EQUITY', {AccountType.equity}, -1, totals, earnings: earnings);
        emit(assets == liabilities + equity ? '  check ok' : '  check mismatch ${money(assets - liabilities - equity)}');
        return;
      case 'ROLLUP':
        final date = BookDate.parse(words[2]);
        final targets = accounts.values.where((account) => account.code.startsWith(words[1])).toList();
        emit('ROLLUP ${words[1]} $date');
        if (targets.isEmpty) { emit('  (none)'); return; }
        final totals = aggregate(end: date.number);
        for (final account in targets) {
          final depth = targets.where((other) => other.code != account.code && account.code.startsWith(other.code)).length;
          final subtotal = sum(targets.where((other) => other.code.startsWith(account.code))
              .map((other) => totals[other.code]?.difference ?? 0)) * account.sign;
          emit('${' ' * (2 * (1 + depth))}${account.code} ${account.name} own ${money((totals[account.code]?.difference ?? 0) * account.sign)} total ${money(subtotal)}');
        }
        emit('  postings debit ${money(sum(targets.map((account) => totals[account.code]?.debit ?? 0)))} credit ${money(sum(targets.map((account) => totals[account.code]?.credit ?? 0)))}');
        return;
      case 'AGING':
        final found = account(words[1]);
        final date = BookDate.parse(words[2]);
        final total = List.filled(5, 0);
        emit('AGING ${found.code} ${found.name} $date');
        for (final pair in settlements(found, date.number).entries) {
          final settlement = pair.value;
          if (settlement.items.isEmpty && settlement.unapplied == 0) continue;
          final values = List.filled(5, 0);
          for (final item in settlement.items) {
            final age = date.number - item.entry.date.number;
            values[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += item.remaining;
          }
          values[4] = settlement.unapplied;
          for (var i = 0; i < 5; i++) { total[i] += values[i]; }
          emit('  ${pair.key} ${ageColumns(values)}');
        }
        emit('  total ${ageColumns(total)}');
        return;
      case 'ITEMS':
        final found = account(words[1]);
        final date = BookDate.parse(words[3]);
        final settlement = settlements(found, date.number)[words[2]] ?? Settlement();
        emit('ITEMS ${found.code} ${found.name} ${words[2]} $date');
        for (final item in settlement.items) {
          emit('  ${item.entry.date} ${item.entry.id} amount ${money(item.original)} open ${money(item.remaining)} age ${date.number - item.entry.date.number}');
        }
        emit('  unapplied ${money(settlement.unapplied)} balance ${money(sum(settlement.items.map((item) => item.remaining)) - settlement.unapplied)}');
        return;
      case 'ENTRY':
        final found = entry(words[1]);
        emit('ENTRY ${found.id} ${found.date} ${found.kind.name} ${found.memo}');
        for (final line in found.lines) {
          emit('  ${line.side} ${line.code} ${accounts[line.code]!.name} ${money(line.amount)}${line.partner == null ? '' : ' ${line.partner}'}');
        }
        emit('  total ${money(found.amount)}');
        if (found.reverses != null) emit('  reverses ${found.reverses}');
        if (found.reversedBy != null) emit('  reversed by ${found.reversedBy}');
        return;
      case 'DAYBOOK':
        final (start, end) = range(words[1], words[2]);
        final selected = ordered(start: start.number, end: end.number);
        emit('DAYBOOK $start $end');
        for (final entry in selected) { emit('  ${entry.date} ${entry.id} ${entry.kind.name} ${money(entry.amount)} ${entry.memo}'); }
        emit('  total entries ${selected.length} amount ${money(sum(selected.map((entry) => entry.amount)))}');
        return;
      case 'ACCOUNTS':
        final totals = aggregate();
        emit('ACCOUNTS');
        for (final account in accounts.values) {
          emit('  ${account.code} ${account.type.label} ${account.name} parent ${parent(account.code)} balance ${money((totals[account.code]?.difference ?? 0) * account.sign)} ${account.active ? 'active' : 'inactive'}');
        }
        if (accounts.isEmpty) emit('  (none)');
        return;
      case 'TEMPLATES':
        emit('TEMPLATES');
        for (final pair in templates.entries) {
          final template = pair.value;
          emit('  ${pair.key} ${template.memo} lines ${template.lines.length} amount ${money(lineTotals(template.lines).debit)} used ${template.uses}');
        }
        if (templates.isEmpty) emit('  (none)');
        return;
      case 'STATUS':
        emit('STATUS accounts ${accounts.length} inactive ${accounts.values.where((account) => !account.active).length} entries ${entries.length} templates ${templates.length} closed $closed open ${draft?.key ?? 'none'}');
        return;
    }
  }

  void process(String text) {
    try {
      execute(text);
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final books = Books();
  for (var i = 0; i < count; i++) {
    books.process(stdin.readLineSync()!);
  }
  stdout.write(books.output);
}
