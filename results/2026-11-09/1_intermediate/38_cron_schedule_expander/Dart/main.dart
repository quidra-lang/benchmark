import 'dart:collection';
import 'dart:io';

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
String two(int value) => value.toString().padLeft(2, '0');
bool leap(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
int daysInMonth(int year, int month) => month == 2 && leap(year) ? 29 : monthDays[month - 1];
bool digits(String text, int minimum, int maximum) => text.length >= minimum && text.length <= maximum && text.codeUnits.every((c) => c >= 48 && c <= 57);

final class CivilDate {
  final int year, month, day;
  const CivilDate(this.year, this.month, this.day);
  int get number {
    var result = day - 1;
    for (var y = 2000; y < year; y++) result += leap(y) ? 366 : 365;
    for (var m = 1; m < month; m++) result += daysInMonth(year, m);
    return result;
  }
  int get weekday => (number + 6) % 7;
  String get dateText => '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}';
  @override
  String toString() => '$dateText ${weekdays[weekday].substring(0, 3)}';
  static CivilDate fromNumber(int number) {
    var year = 2000, month = 1;
    while (number >= (leap(year) ? 366 : 365)) { number -= leap(year) ? 366 : 365; year++; }
    while (number >= daysInMonth(year, month)) { number -= daysInMonth(year, month); month++; }
    return CivilDate(year, month, number + 1);
  }
}

CivilDate? tryDate(String text) {
  if (text.length != 10 || text[4] != '-' || text[7] != '-' || !digits(text.substring(0, 4), 4, 4) || !digits(text.substring(5, 7), 2, 2) || !digits(text.substring(8), 2, 2)) return null;
  final year = int.parse(text.substring(0, 4)), month = int.parse(text.substring(5, 7)), day = int.parse(text.substring(8));
  if (year < 2001 || year > 2098 || month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return CivilDate(year, month, day);
}
CivilDate readDate(String text) => tryDate(text) ?? (throw const CommandError('invalid date'));
int readMinute(String dateText, String time) {
  final date = tryDate(dateText);
  if (date == null || time.length != 5 || time[2] != ':' || !digits(time.substring(0, 2), 2, 2) || !digits(time.substring(3), 2, 2)) throw const CommandError('invalid datetime');
  final hour = int.parse(time.substring(0, 2)), minute = int.parse(time.substring(3));
  if (hour > 23 || minute > 59) throw const CommandError('invalid datetime');
  return date.number * 1440 + hour * 60 + minute;
}
(int, int) readMonth(String text) {
  if (text.length != 7 || text[4] != '-' || !digits(text.substring(0, 4), 4, 4) || !digits(text.substring(5), 2, 2)) throw const CommandError('invalid month');
  final year = int.parse(text.substring(0, 4)), month = int.parse(text.substring(5));
  if (year < 2001 || year > 2098 || month < 1 || month > 12) throw const CommandError('invalid month');
  return (year, month);
}
String minuteText(int minute) {
  final date = CivilDate.fromNumber(minute ~/ 1440);
  return '${date.dateText} ${two(minute % 1440 ~/ 60)}:${two(minute % 60)} ${weekdays[date.weekday].substring(0, 3)}';
}
String span(int minutes) => '${minutes ~/ 1440}d${two(minutes % 1440 ~/ 60)}h${two(minutes % 60)}m';
void checkWindow(int low, int high) {
  if (low > high) throw const CommandError('invalid window');
  if (high - low > 44640) throw const CommandError('window too long');
}

enum SpecialKind { last, lastWeekday, beforeLast, nearestWeekday, nthWeekday, lastOccurrence }
final class Special {
  final SpecialKind kind;
  final int value, occurrence;
  const Special(this.kind, [this.value = 0, this.occurrence = 0]);
  @override
  bool operator ==(Object other) => other is Special && kind == other.kind && value == other.value && occurrence == other.occurrence;
  @override
  int get hashCode => Object.hash(kind, value, occurrence);
  @override
  String toString() => switch (kind) {
    SpecialKind.last => 'L', SpecialKind.lastWeekday => 'LW', SpecialKind.beforeLast => 'L-$value',
    SpecialKind.nearestWeekday => '${value}W', SpecialKind.nthWeekday => '$value#$occurrence', SpecialKind.lastOccurrence => '${value}L',
  };
}
final class CronField {
  final int index;
  final List<int> values;
  final List<Special> specials;
  final bool restricted;
  CronField(this.index, Iterable<int> values, Iterable<Special> specials, this.restricted)
      : values = List.unmodifiable(values), specials = List.unmodifiable(specials);
  bool contains(int value) => values.contains(value);
}

final class Cron {
  static const fieldNames = ['minute', 'hour', 'day-of-month', 'month', 'day-of-week'];
  static const minimum = [0, 0, 1, 1, 0], maximum = [59, 23, 31, 12, 7];
  static const monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  static const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const macros = {
    '@yearly': '0 0 1 1 *', '@annually': '0 0 1 1 *', '@monthly': '0 0 1 * *', '@weekly': '0 0 * * 0',
    '@daily': '0 0 * * *', '@midnight': '0 0 * * *', '@hourly': '0 * * * *',
  };
  final List<CronField> fields;
  final String expanded;
  final List<int> daily;
  Cron._(List<String> words, List<CronField> fields)
      : fields = List.unmodifiable(fields), expanded = words.join(' '),
        daily = [for (final hour in fields[1].values) for (final minute in fields[0].values) hour * 60 + minute];
  bool get orRule => fields[2].restricted && fields[4].restricted;
  String get rule => orRule ? 'OR' : 'AND';
  static CommandError fieldError(int index, String reason) => CommandError('${fieldNames[index]} $reason');
  static int readValue(String text, int index) {
    final named = index == 3 ? monthNames.indexOf(text) : index == 4 ? dayNames.indexOf(text) : -1;
    if (named >= 0) return named + (index == 3 ? 1 : 0);
    if (!digits(text, 1, 2)) throw fieldError(index, 'invalid value');
    final value = int.parse(text);
    if (value < minimum[index] || value > maximum[index]) throw fieldError(index, 'out of range');
    return value;
  }
  static int specialNumber(String text, int index, int maximum, [int size = 2]) {
    if (!digits(text, 1, size)) throw fieldError(index, 'invalid value');
    final value = int.parse(text);
    if (value < 1 || value > maximum) throw fieldError(index, 'out of range');
    return value;
  }
  static CronField readField(String text, int index) {
    final values = SplayTreeSet<int>(), specials = <Special>[];
    for (final item in text.split(',')) {
      if (item.isEmpty) throw fieldError(index, 'empty item');
      Special? special;
      final hash = item.indexOf('#');
      if (index == 2 && (item.startsWith('L') || item.endsWith('W'))) {
        if (item == 'L') special = const Special(SpecialKind.last);
        else if (item == 'LW') special = const Special(SpecialKind.lastWeekday);
        else if (item.startsWith('L-')) special = Special(SpecialKind.beforeLast, specialNumber(item.substring(2), index, 30));
        else if (item.endsWith('W')) special = Special(SpecialKind.nearestWeekday, specialNumber(item.substring(0, item.length - 1), index, 31));
        else throw fieldError(index, 'invalid value');
      } else if (index == 4 && hash >= 0) {
        final weekday = readValue(item.substring(0, hash), index);
        final occurrence = specialNumber(item.substring(hash + 1), index, 5, 1);
        special = Special(SpecialKind.nthWeekday, weekday % 7, occurrence);
      } else if (index == 4 && item.length >= 2 && item.endsWith('L')) {
        special = Special(SpecialKind.lastOccurrence, readValue(item.substring(0, item.length - 1), index) % 7);
      }
      if (special != null) {
        if (!specials.contains(special)) specials.add(special);
        continue;
      }
      final slash = item.indexOf('/'), basis = item.split('/').first;
      int low, high;
      if (basis == '*') { low = minimum[index]; high = maximum[index]; }
      else {
        final dash = basis.indexOf('-');
        if (dash >= 0) {
          low = readValue(basis.substring(0, dash), index);
          high = readValue(basis.substring(dash + 1), index);
          if (low > high) throw fieldError(index, 'invalid range');
        } else { low = readValue(basis, index); high = slash < 0 ? low : maximum[index]; }
      }
      var step = 1;
      if (slash >= 0) {
        final part = item.substring(slash + 1);
        if (!digits(part, 1, 2) || int.parse(part) == 0) throw fieldError(index, 'invalid step');
        step = int.parse(part);
      }
      for (var value = low; value <= high; value += step) values.add(index == 4 ? value % 7 : value);
    }
    return CronField(index, values, specials, !text.startsWith('*'));
  }
  factory Cron.parse(List<String> words) {
    if (words.length == 1 && words.first.startsWith('@')) {
      final replacement = macros[words.first];
      if (replacement == null) throw const CommandError('unknown macro');
      words = replacement.split(' ');
    }
    if (words.length != 5) throw const CommandError('field count');
    final fields = <CronField>[];
    for (var index = 0; index < 5; index++) fields.add(readField(words[index], index));
    return Cron._(words, fields);
  }
  static int nearest(CivilDate date, int day) {
    final weekday = (date.number - date.day + day + 6) % 7;
    if (weekday == 6) return day == 1 ? 3 : day - 1;
    if (weekday == 0) return day == daysInMonth(date.year, date.month) ? day - 2 : day + 1;
    return day;
  }
  ({bool monthDay, bool weekDay, bool condition}) matchDay(CivilDate date) {
    final last = daysInMonth(date.year, date.month), day = date.day, weekday = date.weekday;
    var monthDay = fields[2].contains(day), weekDay = fields[4].contains(weekday);
    for (final special in fields[2].specials) {
      final matches = switch (special.kind) {
        SpecialKind.last => day == last, SpecialKind.lastWeekday => day == nearest(date, last),
        SpecialKind.beforeLast => day == last - special.value,
        _ => special.value <= last && day == nearest(date, special.value),
      };
      monthDay = monthDay || matches;
    }
    for (final special in fields[4].specials) {
      final matches = weekday == special.value && (special.kind == SpecialKind.nthWeekday ? (day - 1) ~/ 7 + 1 == special.occurrence : day + 7 > last);
      weekDay = weekDay || matches;
    }
    return (monthDay: monthDay, weekDay: weekDay, condition: orRule ? monthDay || weekDay : monthDay && weekDay);
  }
  bool scheduled(CivilDate date) => fields[3].contains(date.month) && matchDay(date).condition;
  Iterable<int> fireTimes(int low, int high, Set<int> holidays, {bool reverse = false}) sync* {
    final first = low ~/ 1440, last = high ~/ 1440;
    for (var day = reverse ? last : first; reverse ? day >= first : day <= last; day += reverse ? -1 : 1) {
      if (holidays.contains(day) || !scheduled(CivilDate.fromNumber(day))) continue;
      for (var i = reverse ? daily.length - 1 : 0; reverse ? i >= 0 : i < daily.length; i += reverse ? -1 : 1) {
        final time = day * 1440 + daily[i];
        if (low <= time && time <= high) yield time;
      }
    }
  }
  List<String> reasons(int minute, Set<int> holidays) {
    final date = CivilDate.fromNumber(minute ~/ 1440), result = <String>[];
    final matches = matchDay(date);
    if (!fields[0].contains(minute % 60)) result.add('minute');
    if (!fields[1].contains(minute % 1440 ~/ 60)) result.add('hour');
    if (!matches.condition && !matches.monthDay) result.add('day-of-month');
    if (!fields[3].contains(date.month)) result.add('month');
    if (!matches.condition && !matches.weekDay) result.add('day-of-week');
    if (holidays.contains(date.number)) result.add('excluded');
    return result;
  }
  static String listJoin(Iterable<String> values, {bool either = false}) {
    final parts = values.toList();
    if (parts.length <= 1) return parts.isEmpty ? '' : parts.first;
    return '${parts.take(parts.length - 1).join(', ')}${either ? ' or ' : ' and '}${parts.last}';
  }
  static String valueName(int index, int value) => index == 3 ? months[value - 1] : index == 4 ? weekdays[value] : '$value';
  static String valueList(CronField field, {bool either = false}) {
    final parts = <String>[];
    for (var start = 0; start < field.values.length;) {
      var end = start;
      while (end + 1 < field.values.length && field.values[end + 1] == field.values[end] + 1) end++;
      if (end - start >= 2) parts.add('${valueName(field.index, field.values[start])} through ${valueName(field.index, field.values[end])}');
      else for (var i = start; i <= end; i++) parts.add(valueName(field.index, field.values[i]));
      start = end + 1;
    }
    return listJoin(parts, either: either);
  }
  static int step(CronField field) {
    final values = field.values;
    if (values.length < 2 || values[0] != 0 || values[1] < 2) return 0;
    final step = values[1];
    if (values.length != maximum[field.index] ~/ step + 1) return 0;
    for (var i = 0; i < values.length; i++) if (values[i] != i * step) return 0;
    return step;
  }
  String dayClause(bool weekday, {bool either = false}) {
    final field = fields[weekday ? 4 : 2], parts = <String>[];
    if (field.values.isNotEmpty) parts.add(weekday ? valueList(field, either: either) : field.values.length == 1 ? 'day ${field.values[0]}' : 'days ${valueList(field)}');
    const ordinals = ['1st', '2nd', '3rd', '4th', '5th'];
    for (final special in field.specials) {
      parts.add(switch (special.kind) {
        SpecialKind.last => 'the last day', SpecialKind.lastWeekday => 'the last weekday',
        SpecialKind.beforeLast => special.value == 1 ? '1 day before the last day' : '${special.value} days before the last day',
        SpecialKind.nearestWeekday => 'the weekday nearest day ${special.value}',
        SpecialKind.nthWeekday => 'the ${ordinals[special.occurrence - 1]} ${weekdays[special.value]}',
        SpecialKind.lastOccurrence => 'the last ${weekdays[special.value]}',
      });
    }
    return listJoin(parts, either: either) + (!weekday || field.specials.isNotEmpty ? ' of the month' : '');
  }
  String describe() {
    final minute = fields[0], hour = fields[1];
    String text;
    if (daily.length <= 4) text = 'At ${listJoin(daily.map((t) => '${two(t ~/ 60)}:${two(t % 60)}'))}';
    else {
      final minuteStep = step(minute), hourStep = step(hour);
      text = minute.values.length == 60 ? 'Every minute' : minuteStep != 0 ? 'Every $minuteStep minutes'
          : minute.values.length == 1 ? 'At minute ${minute.values[0]}' : 'At minutes ${valueList(minute)}';
      if (hour.values.length == 24) {
        if (text.startsWith('At minute')) text += ' of every hour';
      } else if (hourStep != 0) text += ', every $hourStep hours';
      else if (hour.values.last - hour.values.first + 1 == hour.values.length) text += ', between ${two(hour.values.first)}:00 and ${two(hour.values.last)}:59';
      else text += ', during hours ${valueList(hour)}';
    }
    final monthFull = fields[2].values.length == 31, weekFull = fields[4].values.length == 7;
    if (orRule) {
      if (!monthFull && !weekFull) text += ', on ${dayClause(false)} or on ${dayClause(true)}';
    } else if (!monthFull && !weekFull) text += ', on ${dayClause(false)} if it is ${dayClause(true, either: true)}';
    else if (!monthFull) text += ', on ${dayClause(false)}';
    else if (!weekFull) text += ', on ${dayClause(true)}';
    if (fields[3].values.length != 12) text += ', in ${valueList(fields[3])}';
    return text;
  }
}

enum Policy { allow, forbid, replace;
  String get text => name.toUpperCase();
}
final class Job {
  String id;
  final Cron cron;
  final String text;
  bool enabled = true;
  int duration = 1;
  Policy policy = Policy.allow;
  Job(this.id, this.cron, this.text);
}
final class Execution {
  final int start;
  int end;
  Execution(this.start, this.end);
}

final class Scheduler {
  final jobs = <String, Job>{};
  final holidays = <int>{};
  static const arity = {
    'JOB': -2, 'VALIDATE': -1, 'REMOVE': 1, 'RENAME': 2, 'ENABLE': 1, 'DISABLE': 1, 'RUNTIME': 3, 'LIST': 0,
    'EXPAND': 2, 'DESCRIBE': 1, 'MATCH': 3, 'NEXT': 4, 'PREV': 4, 'COUNT': 5, 'GAP': 3, 'OVERLAP': 6,
    'TIMELINE': 4, 'CONFLICTS': 4, 'WEEK': 1, 'CALENDAR': 2, 'SIMULATE': 4, 'EXCLUDE': 1, 'INCLUDE': 1, 'HOLIDAYS': 0,
  };
  Job getJob(String id) => jobs[id] ?? (throw const CommandError('unknown job'));
  void newId(String id) {
    if (id.isEmpty || id.length > 16 || id.codeUnitAt(0) < 97 || id.codeUnitAt(0) > 122 || id.codeUnits.any((c) => !(c >= 97 && c <= 122 || c >= 48 && c <= 57 || c == 95))) throw const CommandError('invalid id');
    if (jobs.containsKey(id)) throw const CommandError('duplicate job');
  }
  static int positive(String text, int size, int maximum, String reason) {
    if (!digits(text, 1, size) || text[0] == '0' || int.parse(text) > maximum) throw CommandError(reason);
    return int.parse(text);
  }
  List<Job> ordered({bool enabledOnly = false}) => jobs.values.where((job) => !enabledOnly || job.enabled).toList()..sort((a, b) => a.id.compareTo(b.id));
  SplayTreeMap<int, List<String>> schedule(int low, int high) {
    final result = SplayTreeMap<int, List<String>>();
    for (final job in ordered(enabledOnly: true)) {
      for (final time in job.cron.fireTimes(low, high, holidays)) result.putIfAbsent(time, () => []).add(job.id);
    }
    return result;
  }
  List<String> timeline(int low, int high, bool conflicts) {
    final times = schedule(low, high), rows = <String>[];
    if (conflicts) {
      final entries = times.entries.where((entry) => entry.value.length >= 2).toList();
      var peak = 0;
      for (final entry in entries) if (entry.value.length > peak) peak = entry.value.length;
      rows.add('CONFLICTS ${entries.length} peak $peak');
      for (final entry in entries.take(100)) rows.add('${minuteText(entry.key)} ${entry.value.length} ${entry.value.join(' ')}');
      if (entries.length > 100) rows.add('... ${entries.length - 100} more');
    } else {
      final count = times.values.fold(0, (sum, ids) => sum + ids.length);
      var written = 0;
      rows.add('TIMELINE $count');
      for (final entry in times.entries) {
        for (final id in entry.value) {
          if (written == 100) break;
          rows.add('${minuteText(entry.key)} $id');
          written++;
        }
      }
      if (count > 100) rows.add('... ${count - 100} more');
    }
    return rows;
  }
  List<String> week(String input, CivilDate start) {
    final counts = List.generate(7, (_) => List.filled(24, 0));
    final low = start.number * 1440;
    var total = 0;
    for (final job in ordered(enabledOnly: true)) {
      for (final time in job.cron.fireTimes(low, low + 7 * 1440 - 1, holidays)) { counts[(time - low) ~/ 1440][time % 1440 ~/ 60]++; total++; }
    }
    final rows = ['WEEK $input $total'];
    for (var day = 0; day < 7; day++) {
      final marks = counts[day].map((count) => count == 0 ? '.' : count >= 10 ? '+' : '$count').join();
      rows.add('${CivilDate.fromNumber(start.number + day)} $marks ${counts[day].fold(0, (sum, count) => sum + count)}');
    }
    return rows;
  }
  List<String> month(Job job, String input, int year, int month) {
    final first = CivilDate(year, month, 1);
    final cells = List.filled(first.weekday, '...', growable: true);
    var count = 0;
    for (var day = 1; day <= daysInMonth(year, month); day++) {
      final date = CivilDate(year, month, day);
      final mark = job.cron.scheduled(date) ? holidays.contains(date.number) ? 'x' : '*' : '-';
      if (mark == '*') count++;
      cells.add('${two(day)}$mark');
    }
    while (cells.length % 7 != 0) cells.add('...');
    final rows = ['CALENDAR ${job.id} $input days $count runs ${count * job.cron.daily.length}', 'Sun Mon Tue Wed Thu Fri Sat'];
    for (var i = 0; i < cells.length; i += 7) rows.add(cells.skip(i).take(7).join(' '));
    return rows;
  }
  List<String> simulate(int low, int high) {
    final enabled = ordered(enabledOnly: true), events = SplayTreeMap<int, int>(), details = <String>[];
    for (final job in enabled) {
      final executions = <Execution>[];
      var skipped = 0, replaced = 0;
      for (final time in job.cron.fireTimes(low, high, holidays)) {
        final previous = executions.isEmpty ? null : executions.last;
        if (previous != null && previous.end > time) {
          if (job.policy == Policy.forbid) { skipped++; continue; }
          if (job.policy == Policy.replace) { previous.end = time; replaced++; }
        }
        executions.add(Execution(time, time + job.duration));
      }
      var busy = 0;
      for (final execution in executions) {
        busy += execution.end - execution.start;
        events[execution.start] = (events[execution.start] ?? 0) + 1;
        events[execution.end] = (events[execution.end] ?? 0) - 1;
      }
      details.add('${job.id} ${job.policy.text} started ${executions.length} skipped $skipped replaced $replaced busy $busy');
    }
    var running = 0, peak = 0, at = 0;
    for (final entry in events.entries) {
      running += entry.value;
      if (running > peak) { peak = running; at = entry.key; }
    }
    return ['SIMULATE ${enabled.length} peak $peak${peak == 0 ? '' : ' at ${minuteText(at)}'}', ...details];
  }
  List<String> execute(List<String> words) {
    final command = words[0], expected = arity[words[0]];
    if (expected == null) throw const CommandError('unknown command');
    final count = words.length - 1;
    if (expected < 0 ? count < -expected : count != expected) throw const CommandError('wrong arguments');
    switch (command) {
      case 'JOB':
        final id = words[1]; newId(id);
        final expression = words.sublist(2);
        final cron = Cron.parse(expression);
        jobs[id] = Job(id, cron, expression.join(' '));
        return ['JOB $id added'];
      case 'VALIDATE':
        final cron = Cron.parse(words.sublist(1));
        return ['VALID ${cron.expanded} ${cron.rule} ${cron.daily.length}'];
      case 'REMOVE':
        final job = getJob(words[1]); jobs.remove(job.id);
        return ['REMOVE ${job.id}'];
      case 'RENAME':
        final job = getJob(words[1]); newId(words[2]);
        jobs.remove(job.id); job.id = words[2]; jobs[job.id] = job;
        return ['RENAME ${words[1]} ${job.id}'];
      case 'ENABLE': case 'DISABLE':
        final job = getJob(words[1]), enable = command == 'ENABLE';
        if (job.enabled == enable) throw CommandError(enable ? 'already enabled' : 'already disabled');
        job.enabled = enable;
        return ['$command ${job.id}'];
      case 'RUNTIME':
        final job = getJob(words[1]);
        final duration = positive(words[2], 4, 1440, 'invalid duration');
        final policy = switch (words[3]) { 'ALLOW' => Policy.allow, 'FORBID' => Policy.forbid, 'REPLACE' => Policy.replace, _ => throw const CommandError('invalid policy') };
        job.duration = duration; job.policy = policy;
        return ['RUNTIME ${job.id} $duration ${policy.text}'];
      case 'LIST':
        return ['LIST ${jobs.length}', for (final job in ordered()) '${job.id} ${job.enabled ? 'on' : 'off'} ${job.duration} ${job.policy.text} ${job.text}'];
      case 'EXPAND':
        final job = getJob(words[1]), index = Cron.fieldNames.indexOf(words[2]);
        if (index < 0) throw const CommandError('invalid field');
        final field = job.cron.fields[index];
        final items = [...field.values.map((v) => '$v'), ...field.specials.map((item) => '$item')];
        return ['EXPAND ${job.id} ${words[2]} ${field.values.length}${items.isEmpty ? '' : ' ${items.join(' ')}'}'];
      case 'DESCRIBE':
        final job = getJob(words[1]); return ['DESCRIBE ${job.id} ${job.cron.describe()}'];
      case 'MATCH':
        final job = getJob(words[1]);
        final time = readMinute(words[2], words[3]);
        final reasons = job.cron.reasons(time, holidays);
        return ['MATCH ${job.id} ${minuteText(time)} ${reasons.isEmpty ? 'yes' : 'no ${reasons.join(' ')}'}'];
      case 'NEXT': case 'PREV':
        final job = getJob(words[1]);
        final start = readMinute(words[2], words[3]);
        final limit = positive(words[4], 2, 50, 'invalid count'), reverse = command == 'PREV';
        final times = job.cron.fireTimes(reverse ? start - 527040 : start + 1, reverse ? start - 1 : start + 527040, holidays, reverse: reverse).take(limit).toList();
        return ['$command ${job.id} ${times.length}', for (final time in times) '${minuteText(time)} ${reverse ? '-' : '+'}${span((time - start).abs())}', if (times.length < limit) 'NONE'];
      case 'COUNT':
        final job = getJob(words[1]);
        final low = readMinute(words[2], words[3]);
        final high = readMinute(words[4], words[5]); checkWindow(low, high);
        final times = job.cron.fireTimes(low, high, holidays).toList();
        return ['COUNT ${job.id} runs ${times.length} days ${times.map((time) => time ~/ 1440).toSet().length}'];
      case 'GAP':
        final job = getJob(words[1]);
        final start = readMinute(words[2], words[3]);
        final times = job.cron.fireTimes(start, start + 44640, holidays).toList();
        if (times.length < 2) return ['GAP ${job.id} runs ${times.length} none'];
        final frequencies = SplayTreeMap<int, int>();
        var shortest = 44641, longest = 0, from = 0;
        for (var i = 1; i < times.length; i++) {
          final gap = times[i] - times[i - 1];
          if (gap < shortest) shortest = gap;
          if (gap > longest) { longest = gap; from = i - 1; }
          frequencies[gap] = (frequencies[gap] ?? 0) + 1;
        }
        return ['GAP ${job.id} runs ${times.length} shortest ${span(shortest)} longest ${span(longest)} from ${minuteText(times[from])} to ${minuteText(times[from + 1])}',
          for (final entry in frequencies.entries) '${span(entry.key)} ${entry.value}'];
      case 'OVERLAP':
        final a = getJob(words[1]); final b = getJob(words[2]);
        final low = readMinute(words[3], words[4]);
        final high = readMinute(words[5], words[6]); checkWindow(low, high);
        final other = b.cron.fireTimes(low, high, holidays).toSet();
        final times = a.cron.fireTimes(low, high, holidays).where(other.contains).toList();
        return ['OVERLAP ${a.id} ${b.id} ${times.length}${times.isEmpty ? '' : ' first ${minuteText(times.first)} last ${minuteText(times.last)}'}'];
      case 'TIMELINE': case 'CONFLICTS': case 'SIMULATE':
        final low = readMinute(words[1], words[2]);
        final high = readMinute(words[3], words[4]); checkWindow(low, high);
        return command == 'SIMULATE' ? simulate(low, high) : timeline(low, high, command == 'CONFLICTS');
      case 'WEEK':
        final date = readDate(words[1]); return week(words[1], date);
      case 'CALENDAR':
        final job = getJob(words[1]);
        final (year, monthValue) = readMonth(words[2]);
        return month(job, words[2], year, monthValue);
      case 'EXCLUDE': case 'INCLUDE':
        final date = readDate(words[1]);
        final day = date.number;
        if (command == 'EXCLUDE') {
          if (!holidays.add(day)) throw const CommandError('already excluded');
        } else if (!holidays.remove(day)) throw const CommandError('not excluded');
        return ['$command $date holidays ${holidays.length}'];
      case 'HOLIDAYS':
        return ['HOLIDAYS ${holidays.length}', for (final day in holidays.toList()..sort()) '${CivilDate.fromNumber(day)}'];
    }
    throw StateError('Unknown command');
  }
}

void main() {
  final first = stdin.readLineSync();
  if (first == null) return;
  final scheduler = Scheduler(), count = int.parse(first);
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ').where((word) => word.isNotEmpty).toList();
    try { for (final row in scheduler.execute(words)) stdout.writeln(row); }
    on CommandError catch (error) { stdout.writeln('ERROR ${error.message}'); }
  }
}
