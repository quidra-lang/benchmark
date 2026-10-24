part of 'main.dart';
const mainSlots = ['modifier', 'wind', 'variation', 'visibility', 'rvr', 'weather', 'cloud', 'temperature', 'pressure', 'no trend'];

const trendSlots = ['wind', 'visibility', 'weather', 'cloud'];

bool repeatable(String kind) => ['rvr', 'weather', 'cloud'].contains(kind);

class Trend {
  final String kind;
  final List<String> times;
  final List<(int, String)> groups;
  Section section = Section([], true);
  Trend(this.kind, this.times, this.groups);
}

(List<(int, String)>, List<List<(int, String)>>, List<(int, String)>) splitMetar(List<(int, String)> groups) {
  var r = groups.indexWhere((g) => g.$2 == 'RMK');
  if (r<0) r = groups.length;
  final remarks = groups.skip(r + 1).toList(), before = groups.take(r).toList();
  var t = before.indexWhere((g) => ['BECMG', 'TEMPO'].contains(g.$2));
  if (t<0) t = before.length;
  final trends = <List<(int, String)>>[];
  for (final g in before.skip(t)) {
    if (['BECMG', 'TEMPO'].contains(g.$2)) trends.add([]);
    trends.last.add(g);
  }
  return (before.take(t).toList(), trends, remarks);
}

Trend? readTrend(List<(int, String)> groups, List<(int, String)> errors) {
  bool time(int i, List<String> prefixes) => i<groups.length && captures(r'(FM|TL|AT)([0-9]{4})', groups[i].$2) != null && prefixes.contains(groups[i].$2.substring(0, 2));
  final count = time(1, ['FM'])?(time(2, ['TL'])?2:1):(time(1, ['TL', 'AT'])?1:0);
  final times = <String>[];
  for (final g in groups.skip(1).take(count)) {
    if (int.parse(g.$2.substring(2, 4))>23 || int.parse(g.$2.substring(4))>59) {
      errors.add((g.$1, 'invalid period "${g.$2}"'));
      return null;
    }
    times.add(g.$2);
  }
  return Trend(groups[0].$2, times, groups.skip(1 + count).toList());
}

(List<int>, List<(int, int)>) readRemarks(List<(int, String)> groups) {
  final pressures = <int>[], temperatures = <(int, int)>[];
  for (final g in groups) {
    var m = captures(r'SLP([0-9]{3})', g.$2);
    if (m != null) {
      final p = int.parse(m[0]);
      pressures.add((p >= 500?9000:10000) + p);
    }
    m = captures(r'T([01])([0-9]{3})([01])([0-9]{3})', g.$2);
    if (m != null) temperatures.add((int.parse(m[1])*(m[0] == '1'?-1:1), int.parse(m[3])*(m[2] == '1'?-1:1)));
  }
  return (pressures, temperatures);
}
