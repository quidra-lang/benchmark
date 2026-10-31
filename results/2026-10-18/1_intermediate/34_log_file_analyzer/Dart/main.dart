import 'dart:io';
import 'dart:math' as math;

const methods = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'];
const reasons = ['fields', 'date', 'time', 'ip', 'method', 'path', 'status', 'bytes', 'latency'];
const classes = ['1xx', '2xx', '3xx', '4xx', '5xx'];
const keys = ['METHOD', 'STATUS', 'IP', 'PATH'];
const daysByMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const forms = <String, List<String>>{
  'SUMMARY': [], 'MALFORMED': [], 'STATUS': [], 'METHODS': [],
  'TOP': ['kind', 'limit'], 'HOURLY': [], 'TIMELINE': ['minutes'],
  'BANDWIDTH': [], 'VISITORS': [], 'LATENCY': ['path'],
  'HISTOGRAM': ['width'], 'APDEX': ['threshold'], 'ERRORS': [],
  'SLOWEST': ['limit'], 'SESSIONS': ['ip', 'minutes'],
  'BURST': ['length', 'times'], 'PEAK': ['length'], 'GAPS': ['length'],
  'IP': ['ip'], 'RANGE': ['date', 'time', 'date', 'time'],
  'FILTER': ['key', 'value'], 'UNFILTER': ['subject'], 'RESET': [], 'STATE': []
};
const needRecords = {
  'STATUS', 'METHODS', 'TOP', 'HOURLY', 'TIMELINE', 'BANDWIDTH',
  'VISITORS', 'HISTOGRAM', 'APDEX', 'ERRORS', 'SLOWEST', 'BURST', 'PEAK', 'GAPS'
};
const ranges = <String, List<int>>{
  'limit': [1, 100], 'minutes': [1, 1440], 'width': [1, 100000],
  'threshold': [1, 100000], 'length': [1, 86400], 'times': [1, 1000]
};
const errors = <String, String>{
  'limit': 'invalid number', 'minutes': 'invalid number',
  'width': 'invalid number', 'threshold': 'invalid number',
  'length': 'invalid number', 'times': 'invalid number',
  'kind': 'invalid kind', 'path': 'invalid path', 'ip': 'invalid ip',
  'date': 'invalid timestamp', 'time': 'invalid timestamp',
  'key': 'invalid key', 'subject': 'invalid key', 'value': 'invalid value'
};

class QueryError implements Exception {
  final String message;
  QueryError(this.message);
}

void ensure(bool yes, String reason) {
  if (!yes) throw QueryError(reason);
}

List<String> tokens(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? <String>[] : trimmed.split(RegExp(r'\s+'));
}

bool digits(String s) => RegExp(r'^[0-9]+$').hasMatch(s);

bool canonical(String s, int maxLength) =>
    s.isNotEmpty && s.length <= maxLength && digits(s) &&
    (s.length == 1 || s[0] != '0');

bool leap(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int yearDays(int year) => leap(year) ? 366 : 365;

int monthDays(int year, int month) =>
    month == 2 && leap(year) ? 29 : daysByMonth[month - 1];

bool validDate(String s) {
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(s)) return false;
  final y = int.parse(s.substring(0, 4));
  final m = int.parse(s.substring(5, 7));
  final d = int.parse(s.substring(8, 10));
  return y >= 2000 && y <= 2059 && m >= 1 && m <= 12 &&
      d >= 1 && d <= monthDays(y, m);
}

bool validTime(String s) {
  if (!RegExp(r'^[0-9]{2}:[0-9]{2}:[0-9]{2}$').hasMatch(s)) return false;
  return int.parse(s.substring(0, 2)) <= 23 &&
      int.parse(s.substring(3, 5)) <= 59 &&
      int.parse(s.substring(6, 8)) <= 59;
}

bool validIp(String s) {
  final parts = s.split('.');
  return parts.length == 4 &&
      parts.every((p) => canonical(p, 3) && int.parse(p) <= 255);
}

bool validStatus(String s) =>
    RegExp(r'^[0-9]{3}$').hasMatch(s) &&
    int.parse(s) >= 100 && int.parse(s) <= 599;

bool validFilterValue(String key, String s) {
  if (key == 'METHOD') return methods.contains(s);
  if (key == 'STATUS') return classes.contains(s) || validStatus(s);
  if (key == 'IP') return validIp(s);
  return s.startsWith('/');
}

bool validArgument(String kind, String value, List<String> args) {
  final range = ranges[kind];
  if (range != null) {
    return canonical(value, 6) &&
        int.parse(value) >= range[0] && int.parse(value) <= range[1];
  }
  switch (kind) {
    case 'kind': return value == 'PATHS' || value == 'IPS';
    case 'path': return value.startsWith('/');
    case 'ip': return validIp(value);
    case 'date': return validDate(value);
    case 'time': return validTime(value);
    case 'key': return keys.contains(value);
    case 'subject': return value == 'RANGE' || keys.contains(value);
    default: return validFilterValue(args[0], value);
  }
}

String? malformedReason(List<String> fields) {
  if (fields.length != 8) return 'fields';
  if (!validDate(fields[0])) return 'date';
  if (!validTime(fields[1])) return 'time';
  if (!validIp(fields[2])) return 'ip';
  if (!methods.contains(fields[3])) return 'method';
  if (!fields[4].startsWith('/')) return 'path';
  if (!validStatus(fields[5])) return 'status';
  if (!canonical(fields[6], 8)) return 'bytes';
  if (!canonical(fields[7], 6)) return 'latency';
  return null;
}

int secondsOf(String date, String time) {
  final year = int.parse(date.substring(0, 4));
  final month = int.parse(date.substring(5, 7));
  final day = int.parse(date.substring(8, 10));
  var days = day - 1;
  for (var y = 2000; y < year; y++) days += yearDays(y);
  for (var m = 1; m < month; m++) days += monthDays(year, m);
  return days * 86400 + int.parse(time.substring(0, 2)) * 3600 +
      int.parse(time.substring(3, 5)) * 60 +
      int.parse(time.substring(6, 8));
}

String pad2(int n) => n.toString().padLeft(2, '0');

String intervalLabel(int seconds) {
  var days = seconds ~/ 86400;
  final minutes = (seconds % 86400) ~/ 60;
  var year = 2000, month = 1;
  while (days >= yearDays(year)) {
    days -= yearDays(year);
    year++;
  }
  while (days >= monthDays(year, month)) {
    days -= monthDays(year, month);
    month++;
  }
  return '$year-' + pad2(month) + '-' + pad2(days + 1) +
      ' ' + pad2(minutes ~/ 60) + ':' + pad2(minutes % 60);
}

String normalizePath(String raw) {
  final parts = <String>[];
  for (final part in raw.split('?').first.split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  final normalized = parts.map((s) {
    if (digits(s)) return '{id}';
    if (s.length >= 8 && RegExp(r'^[0-9a-f]+$').hasMatch(s) &&
        RegExp(r'[0-9]').hasMatch(s)) return '{hex}';
    return s;
  });
  return '/' + normalized.join('/');
}

int compareIp(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 4; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

bool statusMatches(String match, int status) =>
    classes.contains(match) ? status ~/ 100 == int.parse(match[0]) :
    status == int.parse(match);

String decimal(int numerator, int denominator, int places) {
  final scale = places == 1 ? 10 : places == 2 ? 100 : 1000;
  final n = numerator * scale ~/ denominator;
  return (n ~/ scale).toString() + '.' +
      (n % scale).toString().padLeft(places, '0');
}

String percent(int count, int total) =>
    decimal(count * 100, total, 2) + '%';

String bar(int count, int maximum) =>
    '#' * ((count * 30 + maximum - 1) ~/ maximum);

String bytesText(int count) {
  if (count >= 1073741824) return decimal(count, 1073741824, 1) + 'GB';
  if (count >= 1048576) return decimal(count, 1048576, 1) + 'MB';
  if (count >= 1024) return decimal(count, 1024, 1) + 'KB';
  return count.toString() + 'B';
}

int total<T>(Iterable<T> items, int Function(T) value) =>
    items.fold<int>(0, (sum, item) => sum + value(item));

Map<String, int> counts(Iterable<String> values) {
  final result = <String, int>{};
  for (final s in values) result[s] = (result[s] ?? 0) + 1;
  return result;
}

List<String> byCount(Map<String, int> numbers, [int Function(String, String)? compare]) {
  compare ??= (a, b) => a.compareTo(b);
  final sorted = numbers.keys.toList();
  sorted.sort((a, b) {
    final n = numbers[b]!.compareTo(numbers[a]!);
    return n != 0 ? n : compare!(a, b);
  });
  return sorted;
}

class LogRecord {
  final int line, hour, seconds, status, bytes, latency;
  final String date, timestamp, ip, method, path;
  LogRecord(this.line, List<String> fields)
      : date = fields[0],
        timestamp = fields[0] + ' ' + fields[1],
        hour = int.parse(fields[1].substring(0, 2)),
        seconds = secondsOf(fields[0], fields[1]),
        ip = fields[2],
        method = fields[3],
        path = normalizePath(fields[4]),
        status = int.parse(fields[5]),
        bytes = int.parse(fields[6]),
        latency = int.parse(fields[7]);
}

Map<String, List<LogRecord>> groups(
    Iterable<LogRecord> records, String Function(LogRecord) key) {
  final result = <String, List<LogRecord>>{};
  for (final row in records) {
    result.putIfAbsent(key(row), () => <LogRecord>[]).add(row);
  }
  return result;
}

List<int> classCounts(Iterable<LogRecord> records) {
  final numbers = List<int>.filled(5, 0);
  for (final row in records) numbers[row.status ~/ 100 - 1]++;
  return numbers;
}

class Buckets {
  final int first;
  final List<int> counts;

  Buckets._(this.first, this.counts);

  factory Buckets(List<int> values) {
    final first = values.reduce(math.min);
    final width = values.reduce(math.max) - first + 1;
    ensure(width <= 60, 'too many buckets');
    final counts = List<int>.filled(width, 0);
    for (final n in values) counts[n - first]++;
    return Buckets._(first, counts);
  }
}

int percentile(List<int> sorted, int rank) =>
    sorted[(rank * sorted.length + 99) ~/ 100 - 1];

class WindowPeak {
  final int count;
  final LogRecord start, end;
  WindowPeak(this.count, this.start, this.end);
}

WindowPeak peak(List<LogRecord> records, int length) {
  var first = 0, count = 0, begin = 0, end = 0;
  for (var i = 0; i < records.length; i++) {
    while (records[i].seconds - records[first].seconds >= length) first++;
    if (i - first + 1 > count) {
      count = i - first + 1;
      begin = first;
      end = i;
    }
  }
  return WindowPeak(count, records[begin], records[end]);
}

class Apdex {
  final int count, satisfied, tolerating, frustrated, points, all;
  final String notation, rating;
  Apdex(List<LogRecord> records, int threshold)
      : count = records.length,
        satisfied = records.where((r) =>
            r.status < 500 && r.latency <= threshold).length,
        tolerating = records.where((r) =>
            r.status < 500 && r.latency > threshold &&
            r.latency <= 4 * threshold).length,
        frustrated = records.where((r) =>
            r.status >= 500 || r.latency > 4 * threshold).length,
        points = _points(records, threshold),
        all = 2 * records.length,
        notation = decimal(_points(records, threshold), 2 * records.length, 3),
        rating = _rating(records, threshold);

  static int _points(List<LogRecord> records, int threshold) =>
      2 * records.where((r) =>
          r.status < 500 && r.latency <= threshold).length +
      records.where((r) => r.status < 500 &&
          r.latency > threshold && r.latency <= 4 * threshold).length;

  static String _rating(List<LogRecord> records, int threshold) {
    final numerator = 100 * _points(records, threshold);
    final denominator = 2 * records.length;
    if (numerator >= 94 * denominator) return 'excellent';
    if (numerator >= 85 * denominator) return 'good';
    if (numerator >= 70 * denominator) return 'fair';
    if (numerator >= 50 * denominator) return 'poor';
    return 'unacceptable';
  }
}

class Analyzer {
  final records = <LogRecord>[];
  final malformed = <(int, String)>[];
  final output = <String>[];
  final conditions = <String, String?>{
    'METHOD': null, 'STATUS': null, 'IP': null, 'PATH': null
  };
  final int lines;
  int? rangeStart, rangeEnd;
  String? fromLabel, toLabel;

  Analyzer(List<String> logLines) : lines = logLines.length {
    for (var i = 0; i < logLines.length; i++) {
      final fields = tokens(logLines[i]);
      final reason = malformedReason(fields);
      if (reason == null) {
        records.add(LogRecord(i + 1, fields));
      } else {
        malformed.add((i + 1, reason));
      }
    }
    records.sort((a, b) {
      final byTime = a.seconds.compareTo(b.seconds);
      return byTime == 0 ? a.line.compareTo(b.line) : byTime;
    });
  }

  void emit(List<Object> values) {
    output.add(values.join(' '));
  }

  List<LogRecord> selected() => records.where((r) {
    if (rangeStart != null &&
        (r.seconds < rangeStart! || r.seconds > rangeEnd!)) return false;
    if (conditions['METHOD'] != null && conditions['METHOD'] != r.method) return false;
    if (conditions['STATUS'] != null &&
        !statusMatches(conditions['STATUS']!, r.status)) return false;
    if (conditions['IP'] != null && conditions['IP'] != r.ip) return false;
    return conditions['PATH'] == null || conditions['PATH'] == r.path;
  }).toList();

  void barLine(String label, int count, int maximum) {
    emit([label, count, if (count > 0) bar(count, maximum)]);
  }

  void execute(String line) {
    final parts = tokens(line);
    final name = parts.isEmpty ? '' : parts.first;
    final args = parts.skip(1).toList();
    try {
      ensure(forms.containsKey(name), 'unknown query');
      final form = forms[name]!;
      final optional = (name == 'LATENCY' || name == 'SESSIONS') &&
          args.length == form.length - 1;
      ensure(args.length == form.length || optional, 'wrong arguments');
      for (var i = 0; i < args.length; i++) {
        ensure(validArgument(form[i], args[i], args), errors[form[i]]!);
      }
      final rows = selected();
      if (needRecords.contains(name) && rows.isEmpty) {
        emit([name, 'no records']);
      } else {
        run(name, args, rows);
      }
    } on QueryError catch (error) {
      emit(['ERROR', error.message]);
    }
  }

  void run(String name, List<String> a, List<LogRecord> rows) {
    switch (name) {
      case 'SUMMARY': {
        emit(['SUMMARY', 'lines', lines, 'valid', records.length,
          'malformed', malformed.length]);
        emit(['requests', rows.length, 'bytes', total(rows, (r) => r.bytes),
          'ips', rows.map((r) => r.ip).toSet().length,
          'paths', rows.map((r) => r.path).toSet().length]);
        if (rows.isEmpty) {
          emit(['span', 'none']);
        } else {
          emit(['span', rows.first.timestamp, rows.last.timestamp,
            rows.last.seconds - rows.first.seconds]);
        }
        break;

      }
      case 'MALFORMED': {
        emit(['MALFORMED', malformed.length]);
        for (final reason in reasons) {
          final found = malformed.where((m) => m.$2 == reason)
              .map((m) => m.$1).toList();
          if (found.isNotEmpty) emit([reason, found.length, ...found]);
        }
        break;

      }
      case 'STATUS': {
        emit(['STATUS', rows.length]);
        final cs = classCounts(rows);
        for (var i = 0; i < 5; i++) emit([classes[i], cs[i], percent(cs[i], rows.length)]);
        final statuses = <int, int>{};
        for (final row in rows) {
          statuses[row.status] = (statuses[row.status] ?? 0) + 1;
        }
        final sorted = statuses.keys.toList()..sort();
        for (final status in sorted) {
          emit([status, statuses[status]!, percent(statuses[status]!, rows.length)]);
        }
        break;

      }
      case 'METHODS': {
        final values = counts(rows.map((r) => r.method));
        emit(['METHODS', rows.length]);
        for (final method in byCount(values)) {
          emit([method, values[method]!, percent(values[method]!, rows.length)]);
        }
        break;

      }
      case 'TOP': {
        final kind = a[0];
        final values = counts(rows.map((r) => kind == 'PATHS' ? r.path : r.ip));
        final sorted = byCount(values, kind == 'IPS' ? compareIp : null);
        final limit = math.min(int.parse(a[1]), sorted.length);
        emit(['TOP', kind, limit, 'of', sorted.length]);
        var rank = 0;
        for (var i = 0; i < limit; i++) {
          if (i == 0 || values[sorted[i]] != values[sorted[i - 1]]) rank = i + 1;
          emit([rank, sorted[i], values[sorted[i]]!,
            percent(values[sorted[i]]!, rows.length)]);
        }
        break;

      }
      case 'HOURLY': {
        final values = List<int>.filled(24, 0);
        for (final row in rows) values[row.hour]++;
        final highest = values.reduce(math.max);
        emit(['HOURLY', rows.length, 'peak', pad2(values.indexOf(highest)), highest]);
        for (var i = 0; i < 24; i++) barLine(pad2(i), values[i], highest);
        break;

      }
      case 'TIMELINE': {
        final minutes = int.parse(a[0]), step = int.parse(a[0]) * 60;
        final buckets = Buckets(rows.map((r) => r.seconds ~/ step).toList());
        emit(['TIMELINE', minutes, buckets.counts.length]);
        final highest = buckets.counts.reduce(math.max);
        for (var i = 0; i < buckets.counts.length; i++) {
          barLine(intervalLabel((buckets.first + i) * step), buckets.counts[i], highest);
        }
        break;

      }
      case 'BANDWIDTH': {
        final byDay = groups(rows, (r) => r.date);
        final size = total(rows, (r) => r.bytes);
        emit(['BANDWIDTH', byDay.length, size, bytesText(size)]);
        final dates = byDay.keys.toList()..sort();
        for (final date in dates) {
          final items = byDay[date]!;
          final bytes = total(items, (r) => r.bytes);
          emit([date, items.length, bytes, bytesText(bytes)]);
        }
        break;

      }
      case 'VISITORS': {
        final firstDate = <String, String>{};
        for (final row in rows) {
          if (!firstDate.containsKey(row.ip) ||
              row.date.compareTo(firstDate[row.ip]!) < 0) firstDate[row.ip] = row.date;
        }
        final byDay = groups(rows, (r) => r.date);
        emit(['VISITORS', byDay.length, firstDate.length]);
        final dates = byDay.keys.toList()..sort();
        for (final date in dates) {
          final ips = byDay[date]!.map((r) => r.ip).toSet();
          final fresh = ips.where((ip) => firstDate[ip] == date).length;
          emit([date, 'unique', ips.length, 'new', fresh, 'returning', ips.length - fresh]);
        }
        break;

      }
      case 'LATENCY': {
        final label = a.isEmpty ? 'all' : normalizePath(a[0]);
        final selectedRows = a.isEmpty ? rows :
            rows.where((r) => r.path == label).toList();
        if (selectedRows.isEmpty) {
          emit(['LATENCY', 'no records']);
          break;
        }
        final values = selectedRows.map((r) => r.latency).toList()..sort();
        final n = values.length, trim = values.length ~/ 10;
        final trimmed = values.sublist(trim, n - trim);
        emit(['LATENCY', label, 'count', n, 'min', values.first,
          'p50', percentile(values, 50), 'p90', percentile(values, 90),
          'p99', percentile(values, 99), 'max', values.last,
          'mean', decimal(total(values, (x) => x), n, 2),
          'trimmed', decimal(total(trimmed, (x) => x), trimmed.length, 2)]);
        break;

      }
      case 'HISTOGRAM': {
        final width = int.parse(a[0]);
        final buckets = Buckets(rows.map((r) => r.latency ~/ width).toList());
        emit(['HISTOGRAM', width, buckets.counts.length]);
        final highest = buckets.counts.reduce(math.max);
        for (var i = 0; i < buckets.counts.length; i++) {
          final lo = (buckets.first + i) * width;
          barLine(lo.toString() + '-' + (lo + width - 1).toString(),
              buckets.counts[i], highest);
        }
        break;

      }
      case 'APDEX': {
        final threshold = int.parse(a[0]);
        final all = Apdex(rows, threshold);
        emit(['APDEX', threshold, all.notation, all.rating, 'satisfied',
          all.satisfied, 'tolerating', all.tolerating, 'frustrated', all.frustrated]);
        final byPath = groups(rows, (r) => r.path).entries.map((e) =>
            (path: e.key, score: Apdex(e.value, threshold))).toList();
        byPath.sort((x, y) {
          final n = (x.score.points * y.score.all)
              .compareTo(y.score.points * x.score.all);
          if (n != 0) return n;
          final size = y.score.count.compareTo(x.score.count);
          return size != 0 ? size : x.path.compareTo(y.path);
        });
        for (final item in byPath) {
          emit([item.path, item.score.notation, item.score.rating, item.score.count]);
        }
        break;

      }
      case 'ERRORS': {
        final failed = rows.where((r) => r.status >= 400).length;
        emit(['ERRORS', failed, 'of', rows.length, percent(failed, rows.length)]);
        final byPath = groups(rows, (r) => r.path).entries.map((e) =>
            (path: e.key, count: e.value.length,
              client: e.value.where((r) => r.status ~/ 100 == 4).length,
              server: e.value.where((r) => r.status ~/ 100 == 5).length))
            .where((e) => e.client + e.server > 0).toList();
        byPath.sort((x, y) {
          final xf = x.client + x.server, yf = y.client + y.server;
          final n = yf * x.count - xf * y.count;
          if (n != 0) return n;
          final ties = yf.compareTo(xf);
          return ties != 0 ? ties : x.path.compareTo(y.path);
        });
        for (final p in byPath) {
          emit([p.path, p.count, p.client, p.server,
            percent(p.client + p.server, p.count)]);
        }
        break;

      }
      case 'SLOWEST': {
        final entries = groups(rows, (r) => r.method + '\u0001' + r.path);
        final endpoints = entries.entries.map((e) {
          final pair = e.key.split('\u0001');
          return (method: pair[0], path: pair[1], count: e.value.length,
            sum: total(e.value, (r) => r.latency),
            maxLatency: e.value.map((r) => r.latency).reduce(math.max));
        }).toList();
        endpoints.sort((x, y) {
          final n = y.sum * x.count - x.sum * y.count;
          if (n != 0) return n;
          final m = y.maxLatency.compareTo(x.maxLatency);
          if (m != 0) return m;
          final path = x.path.compareTo(y.path);
          return path != 0 ? path : x.method.compareTo(y.method);
        });
        final limit = math.min(int.parse(a[0]), endpoints.length);
        emit(['SLOWEST', limit, 'of', endpoints.length]);
        for (var i = 0; i < limit; i++) {
          final p = endpoints[i];
          emit([i + 1, p.method, p.path, 'count', p.count,
            'avg', decimal(p.sum, p.count, 2), 'max', p.maxLatency]);
        }
        break;

      }
      case 'SESSIONS': {
        final ip = a[0], timeout = a.length == 1 ? 30 : int.parse(a[1]);
        final found = rows.where((r) => r.ip == ip).toList();
        if (found.isEmpty) {
          emit(['SESSIONS', 'no records']);
          break;
        }
        final sessions = <List<LogRecord>>[[found.first]];
        for (var i = 1; i < found.length; i++) {
          if (found[i].seconds - found[i - 1].seconds <= timeout * 60) {
            sessions.last.add(found[i]);
          } else {
            sessions.add([found[i]]);
          }
        }
        final duration = total(sessions, (s) => s.last.seconds - s.first.seconds);
        emit(['SESSIONS', ip, 'timeout', timeout, 'count', sessions.length,
          'requests', found.length, 'avg_duration', decimal(duration, sessions.length, 1),
          'avg_requests', decimal(found.length, sessions.length, 1)]);
        for (var i = 0; i < sessions.length; i++) {
          final s = sessions[i];
          emit([i + 1, s.first.timestamp, s.last.timestamp,
            s.last.seconds - s.first.seconds, s.length,
            s.map((r) => r.path).toSet().length]);
        }
        break;

      }
      case 'BURST': {
        final length = int.parse(a[0]), count = int.parse(a[1]);
        final ips = groups(rows.where((r) => r.status >= 400), (r) => r.ip);
        final bursts = ips.entries.map((e) =>
            (ip: e.key, window: peak(e.value, length)))
            .where((e) => e.window.count >= count).toList();
        bursts.sort((x, y) {
          final n = y.window.count.compareTo(x.window.count);
          return n != 0 ? n : compareIp(x.ip, y.ip);
        });
        emit(['BURST', length, count, bursts.length]);
        for (final entry in bursts) {
          emit([entry.ip, entry.window.count,
            entry.window.start.timestamp, entry.window.end.timestamp]);
        }
        break;

      }
      case 'PEAK': {
        final length = int.parse(a[0]), result = peak(rows, int.parse(a[0]));
        emit(['PEAK', length, result.count, result.start.timestamp, result.end.timestamp]);
        break;

      }
      case 'GAPS': {
        final length = int.parse(a[0]);
        final gaps = <(LogRecord, LogRecord)>[];
        for (var i = 1; i < rows.length; i++) {
          if (rows[i].seconds - rows[i - 1].seconds >= length) {
            gaps.add((rows[i - 1], rows[i]));
          }
        }
        emit(['GAPS', length, gaps.length]);
        for (final g in gaps) {
          emit([g.$1.timestamp, g.$2.timestamp,
            g.$2.seconds - g.$1.seconds]);
        }
        break;

      }
      case 'IP': {
        final ip = a[0], found = rows.where((r) => r.ip == a[0]).toList();
        if (found.isEmpty) {
          emit(['IP', 'no records']);
          break;
        }
        final byPath = counts(found.map((r) => r.path));
        emit(['IP', ip, 'requests', found.length,
          'bytes', total(found, (r) => r.bytes),
          'errors', found.where((r) => r.status >= 400).length,
          'paths', byPath.length]);
        emit(['first', found.first.timestamp, 'last', found.last.timestamp]);
        final byMethod = counts(found.map((r) => r.method));
        emit(['methods', for (final m in byCount(byMethod)) ...[m, byMethod[m]!] ]);
        final cs = classCounts(found);
        emit(['classes', for (var i = 0; i < 5; i++) ...[classes[i], cs[i]]]);
        for (final p in byCount(byPath).take(3)) {
          emit(['path', p, byPath[p]!]);
        }
        break;

      }
      case 'RANGE': {
        final start = secondsOf(a[0], a[1]), end = secondsOf(a[2], a[3]);
        ensure(start <= end, 'invalid range');
        rangeStart = start;
        rangeEnd = end;
        fromLabel = a[0] + ' ' + a[1];
        toLabel = a[2] + ' ' + a[3];
        emit(['RANGE', fromLabel!, toLabel!, 'active', selected().length]);
        break;

      }
      case 'FILTER': {
        final key = a[0], raw = a[1];
        conditions[key] = key == 'PATH' ? normalizePath(raw) : raw;
        emit(['FILTER', key, conditions[key]!, 'active', selected().length]);
        break;

      }
      case 'UNFILTER': {
        final key = a[0];
        if (key == 'RANGE') {
          ensure(rangeStart != null, 'not filtered');
          rangeStart = rangeEnd = null;
          fromLabel = toLabel = null;
        } else {
          ensure(conditions[key] != null, 'not filtered');
          conditions[key] = null;
        }
        emit(['UNFILTER', key, 'active', selected().length]);
        break;

      }
      case 'RESET': {
        rangeStart = rangeEnd = null;
        fromLabel = toLabel = null;
        for (final key in keys) conditions[key] = null;
        emit(['RESET', 'active', selected().length]);
        break;

      }
      case 'STATE': {
        emit(['STATE', 'active', rows.length, 'range',
          rangeStart == null ? '-' : fromLabel! + ' ' + toLabel!,
          for (final key in keys) ...[key.toLowerCase(), conditions[key] ?? '-']]);
        break;
      }
    }
  }
}

void main() {
  final input = stdin.readAsLinesSync();
  final separator = input.indexOf('---');
  final end = input.indexOf('END', separator + 1);
  final analyzer = Analyzer(input.sublist(0, separator));
  for (var i = separator + 1; i < end; i++) analyzer.execute(input[i]);
  if (analyzer.output.isNotEmpty) {
    stdout.writeln(analyzer.output.join('\n'));
  }
}
