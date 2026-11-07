part of 'main.dart';
const tafSlots = ['wind', 'visibility', 'weather', 'cloud'];

const temporaryKinds = ['TEMPO', 'PROB30', 'PROB40', 'PROB30 TEMPO', 'PROB40 TEMPO'];

class Change {
  final String kind;
  final int start, end;
  final List<(int, String)> groups;
  State state = State();
  Change(this.kind, this.start, this.end, this.groups);
}

class Forecast {
  final int number, issue, start, end;
  final Station station;
  final String modifier;
  State base = State();
  List<Change> changes = [];
  Forecast(this.number, this.station, this.issue, this.modifier, this.start, this.end);
}

bool fmIndicator(String t) => captures(r'FM([0-9]{6})', t) != null;

bool changeIndicator(String t) => ['BECMG', 'TEMPO', 'PROB30', 'PROB40'].contains(t) || fmIndicator(t);

(int, int)? parsePeriod(String t, int issueDay, Calendar c) {
  final m = captures(r'([0-9]{2})([0-9]{2})/([0-9]{2})([0-9]{2})', t);
  if (m == null) return null;
  final n = m.map(int.parse).toList();
  if (n[1]>23 || n[3]<1 || n[3]>24) return null;
  final s = c.forecastTime(n[0], n[1], 0, issueDay), e = c.forecastTime(n[2], n[3], 0, issueDay);
  return s == null || e == null || s >= e?null:(s, e);
}

(List<(int, String)>, List<Change>) splitChanges(Forecast f, List<(int, String)> groups, Calendar c, List<(int, String)> errors) {
  var i = 0;
  while (i<groups.length && !changeIndicator(groups[i].$2)) {
    i++;
  }
  final base = groups.take(i).toList(), changes = <Change>[];
  while (i<groups.length) {
    final indicator = groups[i++];
    var kind = indicator.$2;
    int? start, end;
    if (['PROB30', 'PROB40'].contains(kind) && i<groups.length && groups[i].$2 == 'TEMPO') {
      kind += ' TEMPO';
      i++;
    }
    if (fmIndicator(kind)) {
      final d = int.parse(kind.substring(2, 4)), h = int.parse(kind.substring(4, 6)), m = int.parse(kind.substring(6));
      start = h <= 23 && m <= 59?c.forecastTime(d, h, m, f.issue ~/ 1440 + 1):null;
      if (start == null || start<f.start || start >= f.end) {
        errors.add((indicator.$1, 'invalid period "$kind"'));
        start = null;
      } else {
        kind = 'FM';
        end = start;
      }
    } else if (i == groups.length || captures(r'([0-9]{4})/([0-9]{4})', groups[i].$2) == null) {
      errors.add((indicator.$1, 'missing period "$kind"'));
    } else {
      final p = groups[i++], period = parsePeriod(p.$2, f.issue ~/ 1440 + 1, c);
      if (period == null || period.$1<f.start || period.$2>f.end) {
        errors.add((p.$1, 'invalid period "${p.$2}"'));
      } else {
        start = period.$1;
        end = period.$2;
      }
    }
    final first = i;
    while (i<groups.length && !changeIndicator(groups[i].$2)) {
      i++;
    }
    if (start != null) changes.add(Change(kind, start, end!, groups.sublist(first, i)));
  }
  return (base, changes);
}

State overlay(State s, State c) => State(c.wind ?? s.wind, c.visibility ?? s.visibility, c.weather ?? s.weather, c.cloud ?? s.cloud);

State prevailing(Forecast f, int h) {
  var state = f.base;
  for (final c in f.changes) {
    if (c.kind == 'FM' && c.start <= h) state = c.state;
    else if (c.kind == 'BECMG' && c.end <= h) state = overlay(state, c.state);
  }
  return state;
}

List<(String, State)> temporary(Forecast f, int h) {
  final p = prevailing(f, h);
  return [for (final c in f.changes) if (temporaryKinds.contains(c.kind) && c.start <= h && h<c.end) (c.kind, overlay(p, c.state))];
}
