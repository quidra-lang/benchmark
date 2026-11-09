part of 'main.dart';

class Event {
  final String caseId, activity, timestamp, resource;
  final int time, line;
  Event(
    this.caseId,
    this.activity,
    this.timestamp,
    this.resource,
    this.time,
    this.line,
  );
}

class Case {
  final String id;
  final List<Event> events = [];
  List<String> trace = [];
  int duration = 0, variant = 0;
  Case(this.id);
}

(List<String>, Map<String, String>) inputRows() {
  final rows = File('input/eventlog.csv').readAsLinesSync().skip(1).toList(),
      params = <String, String>{};
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    params[a[0]] = a[1];
  }
  return (rows, params);
}

int? timestamp(String s) {
  final month = int.parse(s.substring(5, 7)),
      day = int.parse(s.substring(8, 10)),
      hour = int.parse(s.substring(11, 13)),
      minute = int.parse(s.substring(14, 16));
  final days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > days[month - 1] ||
      hour > 23 ||
      minute > 59)
    return null;
  var d = day - 1;
  for (var m = 0; m < month - 1; m++) {
    d += days[m];
  }
  return (d * 24 + hour) * 60 + minute;
}

List<Case> groupCases(List<Event> events) {
  final m = <String, Case>{};
  for (final e in events) {
    (m[e.caseId] ??= Case(e.caseId)).events.add(e);
  }
  final cases = m.values.toList();
  for (final c in cases) {
    c.events.sort((a, b) {
      final d = a.time.compareTo(b.time);
      return d != 0 ? d : a.line.compareTo(b.line);
    });
    c.trace = c.events.map((e) => e.activity).toList();
    c.duration = c.events.last.time - c.events.first.time;
  }
  cases.sort((a, b) => a.id.compareTo(b.id));
  return cases;
}

Ratio median(List<int> a) {
  a = List.of(a)..sort();
  final n = a.length;
  return n.isOdd ? Ratio(a[n ~/ 2], 1) : Ratio(a[n ~/ 2 - 1] + a[n ~/ 2], 2);
}
