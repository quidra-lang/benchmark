import 'dart:io';
import 'dart:math' as math;

int amount(String s) {
  final p = s.split('.');
  return int.parse(p[0]) * 100 + int.parse(p[1]);
}
String money(int n) => '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
String rateText(int n) => '${money(n)}%';
String duration(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
String clock(int m) => duration(m).padLeft(5, '0');
int period(int day) => (day - 1) ~/ 14 + 1;
String weekday(int day) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][(day - 1) % 7];
const settingNames = ['STATE', 'SUPP', 'SSRATE', 'MEDRATE', 'ADDMED', 'UIRATE', 'MATCH', 'MATCHMAX', 'GARNCAP', 'SSBASE', 'ADDBASE', 'UIBASE', 'RETIRECAP', 'ALLOWANCE', 'NIGHT'];
const initialSettings = [500, 2200, 620, 145, 90, 270, 5000, 600, 2500, 16860000, 20000000, 700000, 2300000, 15000, 100];
class PayrollError implements Exception {
  final String reason;
  PayrollError(this.reason);
}
Never fail(String s) => throw PayrollError(s);
enum V { r, o, d, n, p, accrued, salary, leave, leaveDeduction, sales, commission, earnings, bonus, gross, retirement, health, federal, supplemental, state, ss, medicare, garnishment, net, employerSS, employerMedicare, unemployment, match, employerTotal, w, y, f, j }
class Stub {
  final values = List.filled(V.values.length, 0);
  int postPto = 0, postGarnishment = 0;
  List<int> balances = [];
  int operator [](V key) => values[key.index];
  void operator []=(V key, int value) {
    values[key.index] = value;
  }
  void add(Stub other) {
    for (final key in V.values) this[key] += other[key];
  }
}
class Shift {
  final int start, end;
  Shift(this.start, this.end);
}
class Garnishment {
  final int rate;
  int balance;
  Garnishment(this.rate, this.balance);
}
class Record {
  final Stub stub;
  final String department;
  Record(this.stub, this.department);
}
class Employee {
  final int id;
  final String type;
  String department;
  int base, retirement = 0, health = 0, allowances = 0, extra = 0, bonus = 0, pto = 0, stubCount = 0;
  bool active = true;
  final garnishments = <Garnishment>[];
  final shifts = <int, List<Shift>>{};
  final ptos = <int, int>{};
  final leave = <int>{};
  final sales = List.filled(27, 0);
  final records = <int, Record>{};
  final ytd = Stub();
  Employee(this.id, this.department, this.type, this.base);
  int get garnishmentBalance => garnishments.fold(0, (n, g) => n + g.balance);
}
int progressive(Map<int, int> table, int x) {
  final bounds = table.keys.toList()..sort();
  var total = 0;
  for (var i = 0; i < bounds.length; i++)
    if (bounds[i] < x) total += table[bounds[i]]! * ((i + 1 == bounds.length ? x : math.min(x, bounds[i + 1])) - bounds[i]);
  return total ~/ 10000;
}
class Payroll {
  int closed = 0;
  final settings = Map<String, int>.fromIterables(settingNames, initialSettings);
  final taxTable = <int, int>{};
  final commissionTable = <int, int>{};
  final holidays = <int>{};
  final employees = <int, Employee>{};
  List<Employee> people() => employees.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  Employee employee(String id, {bool active = false}) {
    final e = employees[int.parse(id)] ?? fail('unknown employee $id');
    if (active && !e.active) fail('terminated employee $id');
    return e;
  }
  void typeCheck(Employee e, String type) {
    if (e.type != type) fail('not ${type == 'HOURLY' ? 'hourly' : type == 'SALARIED' ? 'salaried' : 'commission'} ${e.id}');
  }
  int dayCheck(String s) {
    final d = int.parse(s);
    if (d < 1 || d > 364) fail('invalid day $s');
    if (period(d) <= closed) fail('period closed ${period(d)}');
    return d;
  }
  void periodCheck(int p, String token) {
    if (p < 1 || p > 26) fail('invalid period $token');
  }
  void rateCheck(String s) {
    if (amount(s) > 10000) fail('invalid rate $s');
  }
  void amountCheck(int n) {
    if (n == 0) fail('invalid amount');
  }
  int timeCheck(String s) {
    final h = int.parse(s.substring(0, 2)), m = int.parse(s.substring(3));
    if (h > 23 || m > 59) fail('invalid time $s');
    return h * 60 + m;
  }
  List<int> daily(Employee e, int d) {
    var worked = 0, night = 0;
    for (final s in e.shifts[d] ?? <Shift>[]) {
      worked += s.end - s.start;
      night += math.max(0, math.min(s.end, 360) - s.start) + math.max(0, s.end - math.max(s.start, 1320));
    }
    final special = d % 7 == 0 || holidays.contains(d);
    return [worked, special ? 0 : math.min(worked, 480), special ? 0 : math.min(math.max(worked - 480, 0), 240), special ? worked : math.max(0, worked - 720), night, e.ptos[d] ?? 0];
  }
  List<int> weekly(Employee e, int week) {
    final result = List.filled(6, 0);
    for (var d = week * 7 - 6; d <= week * 7; d++) {
      final b = daily(e, d);
      for (var i = 0; i < 5; i++) result[i] += b[i + 1];
    }
    result[5] = math.max(0, result[0] - 2400);
    result[0] -= result[5];
    result[1] += result[5];
    return result;
  }
  List<int> breakdown(Employee e, int p) {
    final a = weekly(e, 2 * p - 1), b = weekly(e, 2 * p);
    return List.generate(5, (i) => a[i] + b[i]);
  }
  Stub? calculate(Employee e, int p) {
    final s = Stub();
    if (e.type == 'HOURLY') {
      final b = breakdown(e, p);
      for (var i = 0; i < 5; i++) s[V.values[i]] = b[i];
      s[V.earnings] = ((2 * (b[0] + b[4]) + 3 * b[1] + 4 * b[2]) * e.base + 2 * b[3] * settings['NIGHT']!) ~/ 120;
    } else if (e.type == 'SALARIED') {
      if (e.active) {
        s[V.salary] = e.base ~/ 26;
        s[V.leave] = e.leave.where((d) => period(d) == p && !holidays.contains(d)).length;
        s[V.leaveDeduction] = s[V.leave] * (e.base ~/ 260);
        s[V.earnings] = s[V.salary] - s[V.leaveDeduction];
      }
    } else {
      s[V.sales] = e.sales[p];
      s[V.commission] = progressive(commissionTable, s[V.sales]);
      s[V.earnings] = s[V.commission] + (e.active ? e.base : 0);
    }
    s[V.bonus] = e.bonus;
    s[V.gross] = s[V.earnings] + s[V.bonus];
    if (s[V.gross] == 0) return null;
    var left = s[V.gross];
    void deduct(V key, int value) {
      s[key] = math.min(left, value);
      left -= s[key];
    }
    deduct(V.retirement, math.min(s[V.gross] * e.retirement ~/ 10000, math.max(0, settings['RETIRECAP']! - e.ytd[V.retirement])));
    deduct(V.health, e.health);
    s[V.w] = left;
    final q = math.max(0, s[V.earnings] - s[V.retirement] - s[V.health]), taxable = math.max(0, q - e.allowances * settings['ALLOWANCE']!);
    deduct(V.federal, progressive(taxTable, taxable) + e.extra);
    deduct(V.supplemental, (s[V.w] - q) * settings['SUPP']! ~/ 10000);
    deduct(V.state, s[V.w] * settings['STATE']! ~/ 10000);
    s[V.f] = s[V.gross] - s[V.health];
    s[V.y] = math.min(s[V.f], math.max(0, settings['SSBASE']! - e.ytd[V.y]));
    final additional = math.max(0, math.min(s[V.f], e.ytd[V.f] + s[V.f] - settings['ADDBASE']!));
    deduct(V.ss, s[V.y] * settings['SSRATE']! ~/ 10000);
    deduct(V.medicare, s[V.f] * settings['MEDRATE']! ~/ 10000 + additional * settings['ADDMED']! ~/ 10000);
    final disposable = left, cap = left * settings['GARNCAP']! ~/ 10000;
    for (final g in e.garnishments) {
      final taken = math.min(math.min(disposable * g.rate ~/ 10000, g.balance), cap - s[V.garnishment]);
      s[V.garnishment] += taken;
      s.balances.add(g.balance - taken);
      s.postGarnishment += g.balance - taken;
    }
    s[V.net] = left - s[V.garnishment];
    s[V.employerSS] = s[V.y] * settings['SSRATE']! ~/ 10000;
    s[V.employerMedicare] = s[V.f] * settings['MEDRATE']! ~/ 10000;
    s[V.j] = math.min(s[V.f], math.max(0, settings['UIBASE']! - e.ytd[V.j]));
    s[V.unemployment] = s[V.j] * settings['UIRATE']! ~/ 10000;
    s[V.match] = math.min(s[V.retirement], s[V.gross] * settings['MATCHMAX']! ~/ 10000) * settings['MATCH']! ~/ 10000;
    s[V.employerTotal] = s[V.employerSS] + s[V.employerMedicare] + s[V.unemployment] + s[V.match];
    s[V.accrued] = e.type == 'HOURLY' ? math.min(960 - e.pto, (s[V.r] + s[V.o] + s[V.d]) ~/ 20) : 0;
    s.postPto = e.pto + s[V.accrued];
    return s;
  }
  void block(Employee e, Stub s, String indent, StringBuffer out, {bool ytd = false}) {
    if (e.type == 'HOURLY') {
      out.writeln('${indent}hours reg ${duration(s[V.r])} ot ${duration(s[V.o])} dbl ${duration(s[V.d])} night ${duration(s[V.n])} pto ${duration(s[V.p])}');
      out.writeln('${indent}pto accrued ${duration(s[V.accrued])} balance ${duration(ytd ? e.pto : s.postPto)}');
    } else if (e.type == 'SALARIED') {
      out.writeln('${indent}salary ${money(s[V.salary])} leave ${s[V.leave]} deduction ${money(s[V.leaveDeduction])}');
    } else {
      out.writeln('${indent}sales ${money(s[V.sales])} commission ${money(s[V.commission])}');
    }
    const labels = [('earnings', V.earnings), ('bonus', V.bonus), ('gross', V.gross), ('retirement', V.retirement), ('health', V.health), ('federal', V.federal), ('supplemental', V.supplemental), ('state', V.state), ('social-security', V.ss), ('medicare', V.medicare)];
    for (final (label, key) in labels) out.writeln('$indent$label ${money(s[key])}');
    out.writeln('${indent}garnishment ${money(s[V.garnishment])} balance ${money(ytd ? e.garnishmentBalance : s.postGarnishment)}');
    out.writeln('${indent}net ${money(s[V.net])}');
    out.writeln('${indent}employer social-security ${money(s[V.employerSS])} medicare ${money(s[V.employerMedicare])} unemployment ${money(s[V.unemployment])} match ${money(s[V.match])}');
  }
  void stub(Employee e, Stub s, int p, String department, StringBuffer out) {
    out.writeln('  STUB ${e.id} $department ${e.type} period $p');
    block(e, s, '    ', out);
  }
  void hours(Employee e, int p, StringBuffer out) {
    out.writeln('HOURS ${e.id} period $p');
    var count = 0;
    for (var d = 14 * p - 13; d <= 14 * p; d++) {
      final shifts = e.shifts[d] ?? <Shift>[];
      if (shifts.isEmpty && !e.ptos.containsKey(d)) continue;
      count++;
      final b = daily(e, d);
      out.writeln('  day $d ${weekday(d)}${holidays.contains(d) ? ' holiday' : ''}${shifts.isEmpty ? '' : ' ${shifts.map((s) => '${clock(s.start)}-${clock(s.end)}').join(' ')}'} total ${duration(b[0])} reg ${duration(b[1])} ot ${duration(b[2])} dbl ${duration(b[3])} night ${duration(b[4])} pto ${duration(b[5])}');
    }
    if (count == 0) out.writeln('  (none)');
    for (final w in [2 * p - 1, 2 * p]) {
      final b = weekly(e, w);
      out.writeln('  week $w reg ${duration(b[0])} ot ${duration(b[1])} dbl ${duration(b[2])} night ${duration(b[3])} pto ${duration(b[4])} weekly-ot ${duration(b[5])}');
    }
    final b = breakdown(e, p);
    out.writeln('  total reg ${duration(b[0])} ot ${duration(b[1])} dbl ${duration(b[2])} night ${duration(b[3])} pto ${duration(b[4])}');
  }
  void execute(List<String> a, StringBuffer out) {
    final op = a[0], id = a.length > 1 ? a[1] : '';
    if (op == 'SET') {
      final index = settingNames.indexOf(id);
      if (index < 0) fail('unknown setting $id');
      if (index < 9) rateCheck(a[2]);
      final old = settings[id]!, value = amount(a[2]);
      settings[id] = value;
      out.writeln('SET $id ${index < 9 ? rateText(old) : money(old)} -> ${index < 9 ? rateText(value) : money(value)}');
    } else if (op == 'BRACKET' || op == 'TIER') {
      rateCheck(a[2]);
      final table = op == 'BRACKET' ? taxTable : commissionTable, bound = amount(id), rate = amount(a[2]);
      final existed = table.containsKey(bound);
      table[bound] = rate;
      out.writeln('$op ${money(bound)} ${rateText(rate)} ${existed ? 'replaced' : 'added'}');
    } else if (op == 'EMP') {
      final i = int.parse(id);
      if (employees.containsKey(i)) fail('duplicate employee $id');
      final base = amount(a[4]);
      amountCheck(base);
      employees[i] = Employee(i, a[2], a[3], base);
      out.writeln('EMP $id ${a[2]} ${a[3]} ${money(base)}');
    } else if (op == 'HOLIDAY') {
      final d = dayCheck(id);
      if (holidays.contains(d)) fail('duplicate holiday $id');
      holidays.add(d);
      out.writeln('HOLIDAY $d ${weekday(d)}');
    } else if (op == 'RUN') {
      final p = int.parse(id);
      if (p != closed + 1 || p > 26) fail('invalid period $id');
      closed = p;
      out.writeln('RUN $p days ${14 * p - 13}-${14 * p}');
      var paid = 0, skipped = 0;
      final total = Stub();
      for (final e in people()) {
        final s = calculate(e, p);
        if (s == null) {
          if (e.active) skipped++;
          continue;
        }
        stub(e, s, p, e.department, out);
        paid++;
        total.add(s);
        e.bonus = 0;
        e.pto = s.postPto;
        for (var i = 0; i < e.garnishments.length; i++) e.garnishments[i].balance = s.balances[i];
        e.ytd.add(s);
        e.stubCount++;
        e.records[p] = Record(s, e.department);
      }
      out.writeln('  TOTAL paid $paid skipped $skipped gross ${money(total[V.gross])} deductions ${money(total[V.gross] - total[V.net])} net ${money(total[V.net])} employer ${money(total[V.employerTotal])}');
    } else if (op == 'JOURNAL') {
      final p = int.parse(id);
      if (p < 1 || p > closed) fail('no run $id');
      final total = Stub();
      var count = 0;
      for (final e in employees.values) {
        final r = e.records[p];
        if (r != null) {
          count++;
          total.add(r.stub);
        }
      }
      out.writeln('JOURNAL $p stubs $count');
      final amounts = [total[V.gross], total[V.employerSS] + total[V.employerMedicare] + total[V.unemployment], total[V.match], total[V.retirement] + total[V.match], total[V.health], total[V.federal] + total[V.supplemental], total[V.state], total[V.ss] + total[V.medicare] + total[V.employerSS] + total[V.employerMedicare], total[V.unemployment], total[V.garnishment], total[V.net]];
      const labels = ['debit wages', 'debit employer-tax', 'debit retirement-match', 'credit retirement', 'credit health', 'credit federal', 'credit state', 'credit fica', 'credit unemployment', 'credit garnishment', 'credit net-pay'];
      for (var i = 0; i < 11; i++) out.writeln('  ${labels[i]} ${money(amounts[i])}');
      out.writeln('  total debit ${money(amounts.take(3).fold(0, (a, b) => a + b))} credit ${money(amounts.skip(3).fold(0, (a, b) => a + b))}');
    } else if (op == 'REPORT') {
      final totals = <String, Stub>{}, counts = <String, int>{}, all = Stub();
      var count = 0;
      for (final e in employees.values) {
        for (final r in e.records.values) {
          totals.putIfAbsent(r.department, () => Stub()).add(r.stub);
          counts.update(r.department, (n) => n + 1, ifAbsent: () => 1);
          all.add(r.stub);
          count++;
        }
      }
      out.writeln('REPORT period $closed');
      void line(String name, Stub s, int n) => out.writeln('  $name stubs $n gross ${money(s[V.gross])} pretax ${money(s[V.retirement] + s[V.health])} taxes ${money(s[V.federal] + s[V.supplemental] + s[V.state] + s[V.ss] + s[V.medicare])} garnishment ${money(s[V.garnishment])} net ${money(s[V.net])} employer ${money(s[V.employerTotal])}');
      final departments = totals.keys.toList()..sort();
      for (final department in departments) line(department, totals[department]!, counts[department]!);
      line('total', all, count);
    } else if (op == 'TOP') {
      final k = int.parse(id), es = employees.values.where((e) => e.stubCount > 0).toList()..sort((a, b) {
        final c = b.ytd[V.gross].compareTo(a.ytd[V.gross]);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      out.writeln('TOP $k');
      for (var i = 0; i < math.min(k, es.length); i++) {
        final e = es[i];
        out.writeln('  ${i + 1} ${e.id} ${e.department} gross ${money(e.ytd[V.gross])} net ${money(e.ytd[V.net])}');
      }
      if (es.isEmpty) out.writeln('  (none)');
    } else if (op == 'EMPLOYEES') {
      out.writeln('EMPLOYEES');
      for (final e in people()) {
        out.writeln('  ${e.id} ${e.department} ${e.type} ${money(e.base)} ${e.active ? 'active' : 'terminated'} retirement ${rateText(e.retirement)} health ${money(e.health)} allowances ${e.allowances} extra ${money(e.extra)} bonus ${money(e.bonus)}');
        for (var i = 0; i < e.garnishments.length; i++) {
          final g = e.garnishments[i];
          out.writeln('    garnish ${i + 1} ${rateText(g.rate)} balance ${money(g.balance)}');
        }
      }
      if (employees.isEmpty) out.writeln('  (none)');
    } else if (op == 'CONFIG') {
      out.writeln('CONFIG');
      for (var i = 0; i < settingNames.length; i++) {
        final s = settingNames[i];
        out.writeln('  $s ${i < 9 ? rateText(settings[s]!) : money(settings[s]!)}');
      }
      for (final pair in [('bracket', taxTable), ('tier', commissionTable)]) {
        final bounds = pair.$2.keys.toList()..sort();
        for (final b in bounds) out.writeln('  ${pair.$1} ${money(b)} ${rateText(pair.$2[b]!)}');
      }
    } else {
      final readOnly = ['HOURS', 'PREVIEW', 'REPRINT', 'YTD'].contains(op);
      final e = employee(id, active: !readOnly);
      if (op == 'RATE') {
        final m = amount(a[2]);
        amountCheck(m);
        final old = e.base;
        e.base = m;
        out.writeln('RATE $id ${money(old)} -> ${money(m)}');
      } else if (op == 'DEPT') {
        if (e.department == a[2]) fail('same department ${a[2]}');
        final old = e.department;
        e.department = a[2];
        out.writeln('DEPT $id $old -> ${a[2]}');
      } else if (op == 'BENEFIT') {
        rateCheck(a[2]);
        e.retirement = amount(a[2]);
        e.health = amount(a[3]);
        out.writeln('BENEFIT $id retirement ${rateText(e.retirement)} health ${money(e.health)}');
      } else if (op == 'W4') {
        e.allowances = int.parse(a[2]);
        e.extra = amount(a[3]);
        out.writeln('W4 $id allowances ${e.allowances} extra ${money(e.extra)}');
      } else if (op == 'GARNISH') {
        rateCheck(a[2]);
        final m = amount(a[3]);
        amountCheck(m);
        e.garnishments.add(Garnishment(amount(a[2]), m));
        out.writeln('GARNISH $id order ${e.garnishments.length} ${rateText(amount(a[2]))} balance ${money(m)}');
      } else if (op == 'TERM') {
        e.active = false;
        out.writeln('TERM $id');
      } else if (['TIME', 'UNTIME', 'PTO', 'LEAVE', 'SALES'].contains(op)) {
        typeCheck(e, op == 'LEAVE' ? 'SALARIED' : op == 'SALES' ? 'COMMISSION' : 'HOURLY');
        final d = dayCheck(a[2]);
        if (op == 'TIME' || op == 'UNTIME') {
          final start = timeCheck(a[3]), shifts = e.shifts[d] ?? <Shift>[];
          if (op == 'TIME') {
            final end = timeCheck(a[4]);
            if (start >= end) fail('invalid shift ${a[3]}-${a[4]}');
            for (final shift in shifts)
              if (start < shift.end && shift.start < end) fail('overlapping shift ${clock(shift.start)}-${clock(shift.end)}');
            if (shifts.fold(0, (n, s) => n + s.end - s.start) + end - start > 960) fail('daily limit $id ${a[2]}');
            e.shifts.putIfAbsent(d, () => []).add(Shift(start, end));
            e.shifts[d]!.sort((a, b) => a.start.compareTo(b.start));
            out.writeln('TIME $id day $d ${clock(start)}-${clock(end)} ${duration(end - start)}');
          } else {
            final index = shifts.indexWhere((s) => s.start == start);
            if (index < 0) fail('no shift $id ${a[2]} ${a[3]}');
            final s = shifts.removeAt(index);
            out.writeln('UNTIME $id day $d ${clock(s.start)}-${clock(s.end)}');
          }
        } else if (op == 'PTO') {
          final mm = int.parse(a[3].substring(3));
          final len = int.parse(a[3].substring(0, 2)) * 60 + mm;
          if (mm > 59 || len < 1 || len > 480) fail('invalid duration ${a[3]}');
          if (e.ptos.containsKey(d)) fail('duplicate pto $id ${a[2]}');
          if (len > e.pto) fail('insufficient pto $id ${duration(e.pto)}');
          e.ptos[d] = len;
          e.pto -= len;
          out.writeln('PTO $id day $d ${duration(len)} balance ${duration(e.pto)}');
        } else if (op == 'LEAVE') {
          if (d % 7 == 0 || d % 7 == 6 || holidays.contains(d)) fail('not workday ${a[2]}');
          if (e.leave.contains(d)) fail('duplicate leave $id ${a[2]}');
          e.leave.add(d);
          out.writeln('LEAVE $id day $d ${weekday(d)}');
        } else {
          final m = amount(a[3]);
          amountCheck(m);
          e.sales[period(d)] += m;
          out.writeln('SALES $id day $d ${money(m)} period ${period(d)} total ${money(e.sales[period(d)])}');
        }
      } else if (op == 'BONUS') {
        final m = amount(a[2]);
        amountCheck(m);
        e.bonus += m;
        out.writeln('BONUS $id ${money(m)} pending ${money(e.bonus)}');
      } else if (op == 'HOURS') {
        typeCheck(e, 'HOURLY');
        final p = int.parse(a[2]);
        periodCheck(p, a[2]);
        hours(e, p, out);
      } else if (op == 'PREVIEW') {
        final p = closed + 1;
        final s = calculate(e, p);
        out.writeln('PREVIEW $id period $p');
        if (s == null) {
          out.writeln('  no pay');
        } else {
          stub(e, s, p, e.department, out);
        }
      } else if (op == 'REPRINT') {
        final p = int.parse(a[2]);
        periodCheck(p, a[2]);
        final r = e.records[p] ?? fail('no stub $id ${a[2]}');
        out.writeln('REPRINT $id $p');
        stub(e, r.stub, p, r.department, out);
      } else if (op == 'YTD') {
        out.writeln('YTD $id ${e.department} ${e.type} ${e.active ? 'active' : 'terminated'} periods ${e.stubCount}');
        block(e, e.ytd, '  ', out, ytd: true);
        out.writeln('  wages federal ${money(e.ytd[V.w])} social-security ${money(e.ytd[V.y])} medicare ${money(e.ytd[V.f])} unemployment ${money(e.ytd[V.j])}');
        out.writeln('  retirement-room ${money(math.max(0, settings['RETIRECAP']! - e.ytd[V.retirement]))} pending-bonus ${money(e.bonus)}');
      }
    }
  }
}
void main() {
  final payroll = Payroll(), n = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final a = stdin.readLineSync()!.split(' '), draft = StringBuffer();
    try {
      payroll.execute(a, draft);
      stdout.write(draft);
    } on PayrollError catch (e) {
      print('ERROR ${e.reason}');
    }
  }
}
