import 'dart:io';
part 'groups.dart';
part 'units.dart';
part 'metar.dart';
part 'taf.dart';
part 'verification.dart';
class Runway {
  final String name;
  final int heading;
  Runway(this.name, this.heading);
}

class Station {
  final String code, name;
  final int elevation;
  final List<Runway> runways;
  Station(this.code, this.elevation, this.runways, this.name);
  String get title => '$code ($name)';
}

class Report {
  final int number;
  final List<String> words;
  final errors = <(int, String)>[];
  Report(this.number, this.words);
}

class Header {
  final String kind;
  final Station station;
  final int time, start, end;
  final String modifier;
  final List<(int, String)> body;
  Header(this.kind, this.station, this.time, this.start, this.end, this.modifier, this.body);
}

class RunwayWind {
  final Runway runway;
  final (int, int) mean;
  final (int, int)? gust;
  final bool usable;
  RunwayWind(this.runway, this.mean, this.gust, this.usable);
}

class Observation {
  final int number, time;
  final String kind;
  final Station station;
  final Section main;
  List<Trend> trends = [];
  List<int> pressures = [];
  List<(int, int)> temperatures = [];
  int? ceilingValue, pressureAltitude, densityAltitude;
  String category = '';
  List<RunwayWind>? winds;
  List<String> reasons = [];
  Observation(this.number, Header h)
      : time = h.time,
        kind = h.kind,
        station = h.station,
        main = Section(h.station.runways.map((r) => r.name).toList());
}

List<String> readLines(String path) => File(path).readAsLinesSync();

List<(int, String)> joinGroups(List<String> words, int start) {
  final result = <(int, String)>[];
  var i = start;
  while (i<words.length) {
    if (digits(words[i], 1, 1) && i + 1<words.length && captures(r'([0-9])/([0-9]{1,2})SM', words[i + 1]) != null) {
      result.add((i + 1, '${words[i]} ${words[i+1]}'));
      i += 2;
    } else {
      result.add((i + 1, words[i]));
      i++;
    }
  }
  return result;
}

Header? parseHeader(Report r, Map<String, Station> stations, Calendar c) {
  final w = r.words, kind = w[0];
  void reject(int p, String message) => r.errors.add((p, 'rejected report, $message'));
  if (!['METAR', 'SPECI', 'TAF'].contains(kind)) {
    reject(1, 'invalid type "$kind"');
    return null;
  }
  var i = 1, modifier = '';
  if (kind == 'TAF' && i<w.length && ['AMD', 'COR'].contains(w[i])) modifier = w[i++];
  Station? station;
  var time = 0, start = 0, end = 0;
  for (final item in ['station', 'time', if (kind == 'TAF') 'validity']) {
    if (i == w.length) {
      reject(i + 1, 'missing $item');
      return null;
    }
    final text = w[i];
    var valid = false;
    if (item == 'station') {
      station = stations[text];
      valid = station != null;
    } else if (item == 'time') {
      final m = captures(r'([0-9]{2})([0-9]{2})([0-9]{2})Z', text);
      if (m != null) {
        final n = m.map(int.parse).toList();
        valid = n[0] >= 1 && n[0] <= c.days && n[1] <= 23 && n[2] <= 59;
        if (valid) time = dayMinutes(n[0], n[1], n[2]);
      }
    } else {
      final p = parsePeriod(text, time ~/ 1440 + 1, c);
      valid = p != null && p.$2 <= p.$1 + 1800;
      if (valid) {
        start = p!.$1;
        end = p.$2;
      }
    }
    if (!valid) {
      reject(i + 1, 'invalid $item "$text"');
      return null;
    }
    i++;
  }
  return Header(kind, station!, time, start, end, modifier, joinGroups(w, i));
}

void matchGroups(List<(int, String)> groups, List<String> slots, Section section, List<(int, String)> errors) {
  var current = 0;
  for (final (position, text) in groups) {
    var index = -1;
    Group? value;
    for (var j = current; j<slots.length; j++) {
      value = parseGroup(slots[j], text);
      if (value != null) {
        index = j;
        break;
      }
    }
    if (index<0) {
      final earlier = slots.take(current).any((s) => parseGroup(s, text) != null);
      errors.add((position, '${earlier?'out of order group':'unknown group'} "$text"'));
      continue;
    }
    final g = value!;
    if (!validGroup(g, section)) {
      errors.add((position, 'invalid group "$text"'));
      continue;
    }
    section.record(g);
    if (g.kind == 'visibility' && g.visibilityKind == 'CAVOK') {
      section.state.weather = [];
      section.state.cloud = [];
      current = slots.indexOf('cloud') + 1;
    } else {
      current = index + (repeatable(slots[index])?0:1);
    }
  }
}

State forecastState(List<(int, String)> groups, bool nsw, List<(int, String)> errors) {
  final section = Section([], nsw);
  matchGroups(groups, tafSlots, section, errors);
  return section.state;
}

Observation decodeObservation(Report r, Header h) {
  final o = Observation(r.number, h), parts = splitMetar(h.body);
  matchGroups(parts.$1, mainSlots, o.main, r.errors);
  for (final groups in parts.$2) {
    final t = readTrend(groups, r.errors);
    if (t != null) {
      matchGroups(t.groups, trendSlots, t.section, r.errors);
      o.trends.add(t);
    }
  }
  final remarks = readRemarks(parts.$3);
  o.pressures = remarks.$1;
  o.temperatures = remarks.$2;
  return o;
}

Forecast decodeForecast(Report r, Header h, Calendar c) {
  final f = Forecast(r.number, h.station, h.time, h.modifier, h.start, h.end);
  final parts = splitChanges(f, h.body, c, r.errors);
  f.base = forecastState(parts.$1, false, r.errors);
  f.changes = parts.$2;
  for (final change in f.changes) {
    change.state = forecastState(change.groups, true, r.errors);
  }
  return f;
}

int? ceiling(State s) {
  for (final g in s.cloud ?? <Group>[]) {
    if (['BKN', 'OVC', 'VV'].contains(g.amount)) return g.height;
  }
  return null;
}

String flightCategory(State s) {
  final c = ceiling(s), v = s.visibility == null?(1, 0):miles(s.visibility!);
  if (c != null && c<500 || v.$1<v.$2) return 'LIFR';
  if (c != null && c<1000 || v.$1<3*v.$2) return 'IFR';
  if (c != null && c <= 3000 || v.$1 <= 5*v.$2) return 'MVFR';
  return 'VFR';
}

int pressureInhg(Group g) => g.unit == 'A'?g.pressureValue:inhg(g.pressureValue);

(int, int) components(int d, int h, int w) => (floorDiv(w*cosine(d-h), 1000), floorDiv(w*sine(d-h), 1000));

List<String> windChanges(Group? a, Group? b, int alpha) {
  if (a == null || b == null) return [];
  final result = <String>[];
  if (a.directed && b.directed && (a.speed >= 10 || b.speed >= 10)) {
    final d = (int.parse(a.direction)-int.parse(b.direction)).abs()%360;
    if ((d<360-d?d:360-d) >= alpha) result.add('wind shift');
  }
  if ((a.speed-b.speed).abs() >= 10) result.add('wind speed');
  return result;
}

bool thunder(State s) => (s.weather ?? []).any((g) => g.descriptor == 'TS');

bool freezing(State s) => (s.weather ?? []).any((g) => g.descriptor == 'FZ' && g.weatherPhenomena.any((p) => ['DZ', 'RA'].contains(p)));

void derive(Observation o, Observation? previous, int crossLimit, int tailLimit) {
  final s = o.main.state, p = o.main.pressure, t = o.main.temperature;
  o.ceilingValue = ceiling(s);
  o.category = flightCategory(s);
  if (p != null) {
    final a = o.station.elevation + (2992-pressureInhg(p))*10;
    o.pressureAltitude = a;
    if (t != null) o.densityAltitude = a + floorDiv(120*(1000*t.air-15000 + 2*a), 1000);
  }
  final w = s.wind;
  if (w != null && w.directed) {
    o.winds = [];
    for (final r in o.station.runways) {
      final mean = components(int.parse(w.direction), r.heading, w.speed), gust = w.gust != null?components(int.parse(w.direction), r.heading, w.gust!):null, deciding = gust ?? mean;
      o.winds!.add(RunwayWind(r, mean, gust, deciding.$2.abs() <= crossLimit && -deciding.$1 <= tailLimit));
    }
  }
  if (o.kind != 'SPECI') return;
  if (previous == null) {
    o.reasons = ['no previous report'];
    return;
  }
  if (previous.category != o.category) o.reasons.add('category ${previous.category} to ${o.category}');
  final before = previous.main.state;
  o.reasons.addAll(windChanges(before.wind, s.wind, 45));
  if (thunder(before) != thunder(s)) o.reasons.add('thunderstorm ${thunder(s)?'began':'ended'}');
  if (freezing(before) != freezing(s)) o.reasons.add('freezing precipitation ${freezing(s)?'began':'ended'}');
  if (o.reasons.isEmpty) o.reasons.add('no criteria met');
}

String windPhrase(Group g) {
  var t = g.calm?'calm':g.direction == 'VRB'?'variable at ${g.speed} KT':'${g.direction} degrees at ${g.speed} KT';
  if (g.gust != null) t += ' gusting ${g.gust!} KT';
  return t;
}

String mileNumber(Group g) => g.denominator == 0?'${g.whole}':'${g.whole==0?'':'${g.whole} '}${g.numerator}/${g.denominator}';

String qualifier(String q) => q == 'M'?'less than ':q == 'P'?'more than ':'';

String visibilityPhrase(Group g) => g.visibilityKind == 'CAVOK'?'10 km or more (CAVOK)':g.visibilityKind == 'METERS'?(g.qualifier == 'P'?'10 km or more':'${g.meters} m'):'${qualifier(g.qualifier)}${mileNumber(g)} SM';

String weatherPhrase(Group g) {
  if (g.text == 'NSW') return 'no significant weather';
  return [if (g.intensity.isNotEmpty) intensities[g.intensity]!, if (g.descriptor.isNotEmpty) descriptors[g.descriptor]!, if (g.weatherPhenomena.isNotEmpty) g.weatherPhenomena.map((p) => phenomena[p]!).join(' and ')].join(' ');
}

String cloudPhrase(Group g) {
  if (clearSkies.containsKey(g.amount)) return clearSkies[g.amount]!;
  if (g.amount == 'VV') return 'vertical visibility ${g.height} ft';
  return '${amounts[g.amount]} at ${g.height} ft${g.cloudType.isEmpty?'':g.cloudType=='CB'?' cumulonimbus':' towering cumulus'}';
}

String summary(State s) {
  final p = [if (s.wind != null)'wind ${windPhrase(s.wind!)}', if (s.visibility != null)'visibility ${visibilityPhrase(s.visibility!)}', if (s.weather?.isNotEmpty ?? false)'weather ${s.weather!.map(weatherPhrase).join(', ')}', if (s.cloud?.isNotEmpty ?? false)'cloud ${s.cloud!.map(cloudPhrase).join(', ')}'];
  return p.isEmpty?'no conditions':p.join('; ');
}

String windCode(Group g) => g.calm?'00000KT':'${g.direction}${pad(g.speed,2)}${g.gust != null?'G${pad(g.gust!,2)}':''}KT';

String visibilityCode(Group g) => g.visibilityKind == 'CAVOK'?'CAVOK':g.visibilityKind == 'METERS'?(g.qualifier == 'P'?'9999':pad(g.meters, 4)):'${g.qualifier}${mileNumber(g)}SM';

String tokens(State s) => [if (s.wind != null) windCode(s.wind!), if (s.visibility != null) visibilityCode(s.visibility!), for (final g in s.weather ?? <Group>[]) if (g.text != 'NSW') g.text, for (final g in s.cloud ?? <Group>[]) g.text, flightCategory(s)].join(' ');

String tenths(int v) => '${v<0?'-':''}${v.abs()~/10}.${v.abs()%10}';

String inhgText(int v) => '${v~/100}.${pad(v%100,2)}';

String componentPhrase((int, int) c) => '${c.$1<0?'tailwind ${-c.$1}':'headwind ${c.$1}'} KT, crosswind ${c.$2.abs()} KT${c.$2==0?'':c.$2>0?' from right':' from left'}';

String rvrPhrase(Group g) {
  final readings = g.readings.map((r) => '${qualifier(r.qualifier)}${r.value}').toList();
  final value = readings.length == 1 ? readings.first : 'between ${readings.first} and ${readings.last}';
  final trend = g.trend.isEmpty ? '' : ', ${ {'U': 'rising', 'D': 'falling', 'N': 'no change'}[g.trend]}';
  return 'runway ${g.runway} $value${g.feet ? ' ft' : ' m'}$trend';
}

String altitude(int? v) => v == null?'not available':'$v ft';

List<String> observationLines(Observation o, Calendar c) {
  final m = o.main, s = m.state, w = s.wind, v = s.visibility, t = m.temperature, p = m.pressure;
  final lines = ['REPORT ${o.number}: ${o.kind} ${o.station.title}', '  time: ${c.stamp(o.time)}'];
  if (m.modifier != null) lines.add('  modifier: ${m.modifier!.text=='AUTO'?'automated':'corrected'}');
  var wind = w == null?'not reported':windPhrase(w);
  if (m.variation != null) wind += ', varying between ${pad(m.variation!.firstDirection,3)} and ${pad(m.variation!.secondDirection,3)} degrees';
  lines.addAll(['  wind: $wind', '  visibility: ${v==null?'not reported':visibilityPhrase(v)}']);
  for (final g in m.rvrs) {
    lines.add('  runway visual range: ${rvrPhrase(g)}');
  }
  for (final g in s.weather ?? <Group>[]) {
    lines.add('  weather: ${weatherPhrase(g)}');
  }
  final clouds = v?.visibilityKind == 'CAVOK'?['no significant cloud']:s.cloud == null?['not reported']:s.cloud!.map(cloudPhrase).toList();
  for (final text in clouds) {
    lines.add('  cloud: $text');
  }
  lines.add('  temperature: ${t==null?'not reported':'${t.air} C, dew point ${t.dewPoint} C, spread ${t.air-t.dewPoint} C'}');
  lines.add('  altimeter: ${p==null?'not reported':p.unit=='A'?'${inhgText(p.pressureValue)} inHg (${hpa(p.pressureValue)} hPa)':'${p.pressureValue} hPa (${inhgText(pressureInhg(p))} inHg)'}');
  if (m.noTrend != null) lines.add('  trend: no significant change');
  for (final trend in o.trends) {
    var text = trend.kind == 'BECMG'?'becoming':'temporarily';
    for (final t in trend.times) {
      text += ' ${ {'FM':'from','TL':'until','AT':'at'}[t.substring(0,2)]} ${t.substring(2,4)}:${t.substring(4)}Z';
    }
    lines.add('  trend: $text: ${summary(trend.section.state)}');
  }
  for (final p in o.pressures) {
    lines.add('  sea level pressure: ${tenths(p)} hPa');
  }
  for (final t in o.temperatures) {
    lines.add('  precise temperature: ${tenths(t.$1)} C, dew point ${tenths(t.$2)} C');
  }
  lines.addAll(['  ceiling: ${o.ceilingValue==null?'none':'${o.ceilingValue} ft'}', '  flight category: ${o.category}', '  pressure altitude: ${altitude(o.pressureAltitude)}', '  density altitude: ${altitude(o.densityAltitude)}']);
  if (o.winds == null) {
    lines.add('  runway wind: not computed');
  } else {
    RunwayWind? preferred;
    final usable = <String>[];
    for (final r in o.winds!) {
      lines.add('  runway ${r.runway.name}: ${componentPhrase(r.mean)}${r.gust==null?'':'; gusts ${componentPhrase(r.gust!)}'}');
      if (r.usable) {
        usable.add(r.runway.name);
        if (preferred == null || r.mean.$1>preferred.mean.$1) preferred = r;
      }
    }
    lines.add('  usable runways: ${usable.isEmpty?'none':usable.join(' ')}');
    lines.add('  preferred runway: ${preferred?.runway.name??'none'}');
  }
  if (o.kind == 'SPECI') lines.add('  speci check: ${o.reasons.join(', ')}');
  return lines;
}

List<String> forecastLines(Forecast f, Calendar c) => ['REPORT ${f.number}: TAF ${f.station.title}', '  issued: ${c.stamp(f.issue)}', if (f.modifier.isNotEmpty)'  modifier: ${f.modifier=='AMD'?'amended':'corrected'}', '  valid: ${c.stamp(f.start)} to ${c.stamp(f.end)}', '  base: ${summary(f.base)}', for (final g in f.changes)'  ${g.kind} ${c.stamp(g.start)}${g.kind=='FM'?'':' to ${c.stamp(g.end)}'}: ${summary(g.state)}'];

String categoryCounts(List<String> cs) => categories.map((name) => '$name ${cs.where((c)=>c==name).length}').join(', ');

List<String> timelineLines(Forecast f, Calendar c) {
  final lines = ['TAF ${f.station.code} issued ${c.stamp(f.issue)} valid ${c.stamp(f.start)} to ${c.stamp(f.end)}'], cs = <String>[];
  for (var h = f.start; h<f.end; h += 60) {
    final state = prevailing(f, h);
    var line = '${c.stamp(h)} ${tokens(state)}';
    for (final t in temporary(f, h)) {
      line += ' | ${t.$1} ${tokens(t.$2)}';
    }
    lines.add(line);
    cs.add(flightCategory(state));
  }
  lines.add('summary: ${categoryCounts(cs)}');
  return lines;
}

List<String> extremeLines(List<Observation> os, Calendar c) {
  Observation? cold, warm, wind, cloud, vis;
  for (final o in os) {
    final t = o.main.temperature, w = o.main.state.wind, v = o.main.state.visibility;
    if (t != null) {
      if (cold == null || t.air<cold.main.temperature!.air) cold = o;
      if (warm == null || t.air>warm.main.temperature!.air) warm = o;
    }
    if (w != null && (wind == null || w.strength>wind.main.state.wind!.strength)) wind = o;
    if (o.ceilingValue != null && (cloud == null || o.ceilingValue!<cloud.ceilingValue!)) cloud = o;
    if (v != null && (vis == null || lessFraction(miles(v), miles(vis.main.state.visibility!)))) vis = o;
  }
  String line(String label, Observation? o, String Function(Observation) describe) => '$label: ${o==null?'not available':'${describe(o)} at ${c.stamp(o.time)}'}';
  return [line('lowest temperature', cold, (o) => '${o.main.temperature!.air} C'), line('highest temperature', warm, (o) => '${o.main.temperature!.air} C'), line('strongest wind', wind, (o) => windPhrase(o.main.state.wind!)), line('lowest ceiling', cloud, (o) => '${o.ceilingValue} ft'), line('lowest visibility', vis, (o) => visibilityPhrase(o.main.state.visibility!))];
}

String tableRow(String label, List<Object> cells) => label.padRight(8) + cells.map((v) => v.toString().padLeft(6)).join();

List<String> verificationLines(Station station, List<Observation> observations, List<Forecast> forecasts, Calendar c) {
  final os = observations.where((o) => o.station == station).toList();
  final fs = forecasts.where((f) => f.station == station).toList();
  final cont = Contingency();
  final amendments = <String>[];
  var noForecast = 0;
  final pairs = List.filled(5, 0), hits = List.filled(5, 0);
  final lines = ['station ${station.title}', 'reports: METAR ${os.where((o)=>o.kind=='METAR').length}, SPECI ${os.where((o)=>o.kind=='SPECI').length}', 'observed categories: ${categoryCounts(os.map((o)=>o.category).toList())}', ...extremeLines(os, c)];
  for (final o in os) {
    final f = chosenForecast(fs, o.time);
    if (f == null) {
      noForecast++;
      continue;
    }
    final h = o.time - o.time % 60;
    final p = prevailing(f, h);
    final expected = flightCategory(p);
    final alternatives = [expected, ...temporary(f, h).map((t) => flightCategory(t.$2))];
    final hit = alternatives.contains(o.category);
    cont.add(expected, o.category, hit);
    final reasons = <String>[];
    if (!hit) reasons.add('category ${o.category}, forecast $expected');
    if (windChanges(p.wind, o.main.state.wind, 60).isNotEmpty) reasons.add('wind ${windCode(o.main.state.wind!)}, forecast ${windCode(p.wind!)}');
    if (reasons.isNotEmpty) amendments.add('amendment ${c.stamp(o.time)}: ${reasons.join('; ')}');
  }
  for (final f in fs) {
    for (final o in os) {
      if (covers(f, o.time)) {
        final h = o.time-o.time%60, b = (h-f.start) ~/ 360;
        pairs[b]++;
        if (flightCategory(prevailing(f, h)) == o.category) hits[b]++;
      }
    }
  }
  lines.addAll(['verified: ${cont.total}', 'no forecast: $noForecast', tableRow('forecast', [...categories, 'total'])]);
  for (var i = 0; i<4; i++) {
    lines.add(tableRow(categories[i], [...cont.table[i], cont.row(i)]));
  }
  lines.add(tableRow('total', [for (var i = 0; i<4; i++) cont.column(i), cont.total]));
  lines.addAll(['hit rate: ${fraction(cont.hits,cont.total)}', 'hit rate with temporary groups: ${fraction(cont.temporaryHits,cont.total)}', 'heidke skill score: ${fraction(cont.skill.$1,cont.skill.$2)}']);
  for (var i = 0; i<4; i++) {
    final pod = cont.detection(i), far = cont.falseAlarm(i);
    lines.add('${categories[i]}: pod ${fraction(pod.$1,pod.$2)}, far ${fraction(far.$1,far.$2)}');
  }
  for (var b = 0; b<5; b++) {
    lines.add('hours ${b*6}-${b*6+5}: ${fraction(hits[b],pairs[b])}');
  }
  return [...lines, ...amendments];
}

List<String> blocks(List<List<String>> values) => [for (var i = 0; i<values.length; i++)...[if (i>0)'', ...values[i]]];

void writeLines(String path, List<String> lines) => File(path).writeAsStringSync(lines.isEmpty?'':'${lines.join('\n')}\n');

void main() {
  final stations = <String, Station>{};
  for (final line in readLines('input/stations.txt')) {
    final p = line.split(' ');
    stations[p[0]] = Station(p[0], int.parse(p[1]), p[2].split(',').map((r) {
      final a = r.split('/');
      return Runway(a[0], int.parse(a[1]));
    }).toList(), p.skip(3).join(' '));
  }
  final settings = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final p = line.split(' ');
    settings[p[0]] = p.skip(1).toList();
  }
  final c = Calendar(int.parse(settings['YEAR']![0]), int.parse(settings['MONTH']![0])), cross = int.parse(settings['CROSSWIND_LIMIT']![0]), tail = int.parse(settings['TAILWIND_LIMIT']![0]);
  final reports = <Report>[];
  for (final line in readLines('input/reports.txt')) {
    final words = line.trimLeft().split(' ');
    if (line.startsWith(' ')) {
      reports.last.words.addAll(words);
    } else {
      reports.add(Report(reports.length + 1, words));
    }
  }
  final observations = <Observation>[], forecasts = <Forecast>[], decoded = <List<String>>[], latest = <String, Observation>{};
  for (final r in reports) {
    final h = parseHeader(r, stations, c);
    if (h == null) continue;
    if (h.kind == 'TAF') {
      final f = decodeForecast(r, h, c);
      forecasts.add(f);
      decoded.add(forecastLines(f, c));
    } else {
      final o = decodeObservation(r, h);
      derive(o, latest[h.station.code], cross, tail);
      latest[h.station.code] = o;
      observations.add(o);
      decoded.add(observationLines(o, c));
    }
  }
  Directory('output').createSync(recursive: true);
  writeLines('output/decoded.txt', blocks(decoded));
  writeLines('output/categories.csv', ['station,time,ceiling,visibility,category', for (final o in observations)'${o.station.code},${c.stamp(o.time)},${o.ceilingValue??'NONE'},${o.main.state.visibility==null?'NONE':'${o.main.state.visibility!.qualifier}${meterValue(o.main.state.visibility!)}'},${o.category}']);
  writeLines('output/taf_timeline.txt', blocks(forecasts.map((f) => timelineLines(f, c)).toList()));
  writeLines('output/verification.txt', blocks(settings['VERIFY']!.map((code) => verificationLines(stations[code]!, observations, forecasts, c)).toList()));
  final errors = <String>[];
  for (final r in reports) {
    r.errors.sort((a, b) => a.$1.compareTo(b.$1));
    for (final e in r.errors) {
      errors.add('report ${r.number} word ${e.$1}: ${e.$2}');
    }
  }
  writeLines('output/errors.txt', errors);
}
