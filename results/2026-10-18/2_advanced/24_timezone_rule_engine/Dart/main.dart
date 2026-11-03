import 'dart:io';
import 'dart:math' as math;
import 'day_rules.dart';
import 'tz_parser.dart';
import 'transitions.dart';
import 'resolver.dart';
import 'report.dart';

List<String> readLines(String name) => File('input/$name').readAsLinesSync();
int yearStart(int year) => dayNumber(year, 1, 1) * secondsPerDay;
int clockSeconds(String text) => int.parse(text.substring(0, 2)) * 3600 + int.parse(text.substring(3, 5)) * 60;
String namesOrNone(List<String> names, String separator) => names.isEmpty ? 'none' : names.join(separator);
List<String> indented(List<String> lines) => [lines[0], ...lines.skip(1).map((line) => '  $line')];
typedef Interval = (int, int);
List<Interval> mergeIntervals(List<Interval> intervals) {
  intervals.sort((a, b) {
    final compared = a.$1.compareTo(b.$1);
    return compared == 0 ? a.$2.compareTo(b.$2) : compared;
  });
  final merged = <Interval>[];
  for (final (low, high) in intervals) {
    if (merged.isNotEmpty && low <= merged.last.$2) {
      merged[merged.length - 1] = (merged.last.$1, math.max(merged.last.$2, high));
    } else {
      merged.add((low, high));
    }
  }
  return merged;
}
List<Interval> intersectIntervals(List<Interval> first, List<Interval> second) {
  final pieces = <Interval>[];
  for (final a in first) {
    for (final b in second) {
      final low = math.max(a.$1, b.$1);
      final high = math.min(a.$2, b.$2);
      if (low < high) pieces.add((low, high));
    }
  }
  return mergeIntervals(pieces);
}

class SourceLine {
  final int number;
  final List<String> fields;
  late final String kind;
  Block? block;
  int position = 0;
  ZoneLine? zoneLine;
  bool fieldError = false;
  String? error;
  SourceLine(this.number, String content) : fields = splitFields(content) {
    kind = isContinuation(content) ? 'continuation' : ['Rule', 'Zone', 'Link'].contains(fields[0]) ? fields[0] : 'unknown';
  }
  bool get acceptsContinuation => kind == 'Zone' && fields.length >= 6 || kind == 'continuation' && fields.length >= 4;
}
class Block {
  final String name;
  final int number;
  final List<SourceLine> lines = [];
  bool defined = false;
  Block(SourceLine first) : name = first.fields[1], number = first.number { add(first); }
  void add(SourceLine line) {
    line.block = this;
    line.position = lines.length;
    lines.add(line);
  }
}
class ZoneLine {
  late final int stdOffset;
  late final String rulesText;
  String? ruleSet;
  int save = 0;
  late final String format;
  Until? until;
  int start = negInfinity;
  int end = posInfinity;
  ZoneLine(List<String> fields) {
    stdOffset = parseOffset(fields[0]);
    rulesText = fields[1];
    if (RegExp(r'^[0-9]').hasMatch(rulesText)) {
      save = parseSave(rulesText);
    } else if (rulesText != '-') {
      ruleSet = rulesText;
    }
    format = fields[2];
    checkFormat(format, ruleSet != null);
    if (fields.length > 3) until = parseUntil(fields.sublist(3));
  }
  String get rulesNotation => ruleSet ?? (rulesText == '-' ? '-' : clockText(save));
  String get untilNotation {
    final value = until!;
    return '${value.yearText} ${value.monthText} ${value.dayText} ${clockText(value.time)}${value.type}';
  }
}
class Zone {
  final String name;
  final List<ZoneLine> lines;
  final List<String> aliases = [];
  final Map<int, int> applied = {};
  late Timeline timeline;
  Zone(this.name, this.lines);
  List<String> get ruleSets {
    final names = <String>[];
    for (final line in lines) {
      final name = line.ruleSet;
      if (name != null && !names.contains(name)) names.add(name);
    }
    return names;
  }
  int lineNumberAt(int time) => lines.indexWhere((line) => line.start <= time && time < line.end) + 1;
}
Rule parseRule(SourceLine line) {
  final fields = line.fields;
  final from = parseYear(fields[2]);
  final to = parseTo(fields[3], from);
  if (fields[4] != '-') throw FieldError('syntax error');
  final month = parseMonth(fields[5]);
  final day = parseDaySpec(fields[6], month);
  final (at, type) = parseTime(fields[7]);
  final save = parseSave(fields[8]);
  final letter = parseLetter(fields[9]);
  return Rule(line.number, fields, fields[1], from, to, month, day, at, type, save, letter);
}
String standardLetter(List<RuleInstance> instances) {
  for (final instance in instances) {
    if (instance.rule.save == 0) return instance.rule.letter;
  }
  return '';
}
class Database {
  final List<SourceLine> lines = [];
  final List<Block> blocks = [];
  final Map<String, List<Rule>> rules = {};
  final Map<String, List<RuleInstance>> sequences = {};
  final Map<String, Zone> zones = {};
  final Map<String, Zone> aliases = {};
  Database(List<String> rawLines) {
    for (var i = 0; i < rawLines.length; i++) {
      final content = lineContent(rawLines[i]);
      if (content.isNotEmpty) lines.add(SourceLine(i + 1, content));
    }
    SourceLine? previous;
    for (final line in lines) {
      if (line.kind == 'Zone') {
        blocks.add(Block(line));
      } else if (line.kind == 'continuation' && previous != null && previous.block != null && previous.acceptsContinuation) {
        previous.block!.add(line);
      }
      previous = line;
    }
    for (final line in lines) {
      try {
        parseFields(line);
      } on FieldError catch (problem) {
        line.fieldError = true;
        line.error = problem.message;
      }
    }
    final zoneNames = <String>{};
    for (final line in lines) {
      if (line.zoneLine != null) line.error = structuralError(line, zoneNames);
    }
    for (final entry in rules.entries) {
      sequences[entry.key] = instanceSequence(entry.value);
    }
    for (final block in blocks) {
      block.defined = block.lines.every((line) => line.error == null);
      if (block.defined) defineZone(block);
    }
    for (final line in lines) {
      if (line.kind == 'Link' && line.error == null) registerLink(line);
    }
  }
  void parseFields(SourceLine line) {
    if (line.kind == 'unknown' || line.kind == 'continuation' && line.block == null) throw FieldError('syntax error');
    const counts = {'Rule': (10, 10), 'Zone': (5, 9), 'continuation': (3, 7), 'Link': (3, 3)};
    final (low, high) = counts[line.kind]!;
    if (line.fields.length < low || line.fields.length > high) throw FieldError('syntax error');
    if (line.kind == 'Rule') {
      final rule = parseRule(line);
      rules.putIfAbsent(rule.name, () => []).add(rule);
    } else if (line.kind == 'Zone') {
      line.zoneLine = ZoneLine(line.fields.sublist(2));
    } else if (line.kind == 'continuation') {
      line.zoneLine = ZoneLine(line.fields);
    }
  }
  String? structuralError(SourceLine line, Set<String> names) {
    final current = line.zoneLine!;
    if (line.kind == 'Zone') {
      final name = line.fields[1];
      if (names.contains(name)) return 'duplicate zone $name';
      names.add(name);
    }
    if (current.ruleSet != null && !rules.containsKey(current.ruleSet)) return 'unknown rule ${current.ruleSet}';
    if (current.until == null) return null;
    if (line.kind == 'continuation') {
      final previous = line.block!.lines[line.position - 1];
      if (!previous.fieldError && current.until!.value <= previous.zoneLine!.until!.value) return 'until not increasing';
    }
    if (line.position == line.block!.lines.length - 1) return 'missing continuation';
    return null;
  }
  void defineZone(Block block) {
    final zone = Zone(block.name, block.lines.map((line) => line.zoneLine!).toList());
    final periods = <Period>[];
    void add(int time, int save, String letter, ZoneLine line) {
      final period = Period(time, line.stdOffset + save, save != 0, abbreviation(line.format, save, letter));
      if (periods.isEmpty || !periods.last.sameState(period)) periods.add(period);
    }
    var start = negInfinity;
    for (final line in zone.lines) {
      line.start = start;
      if (line.ruleSet == null) {
        final until = line.until;
        if (until != null) line.end = until.value - adjustment(until.type, line.stdOffset, line.save);
        add(start, line.save, '', line);
      } else {
        final instances = sequences[line.ruleSet]!;
        final run = runInstances(instances, line.stdOffset, start, line.until);
        line.end = run.end;
        final save = run.preStart.isEmpty ? 0 : run.preStart.last.save;
        final letter = run.preStart.isEmpty ? standardLetter(instances) : run.preStart.last.letter;
        add(start, save, letter, line);
        for (final applied in run.applied) {
          add(applied.time, applied.rule.save, applied.rule.letter, line);
          zone.applied.update(applied.rule.number, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      start = line.end;
    }
    zone.timeline = Timeline(periods);
    zones[zone.name] = zone;
  }
  void registerLink(SourceLine line) {
    final target = line.fields[1];
    final alias = line.fields[2];
    final zone = zones[target];
    if (zone == null) {
      line.error = 'unknown link target $target';
    } else if (zones.containsKey(alias) || aliases.containsKey(alias)) {
      line.error = 'duplicate link $alias';
    } else {
      aliases[alias] = zone;
      zone.aliases.add(alias);
    }
  }
  Zone? findZone(String word) => zones[word] ?? aliases[word];
  List<String> get errorLines => [for (final line in lines) if (line.error != null) 'line ${line.number}: ${line.error}'];
}

int offsetShift(Timeline timeline, int index) => timeline.periods[index].offset - timeline.periods[index - 1].offset;
List<int> transitionsBetween(Timeline timeline, int low, int high) =>
    [for (var i = 1; i < timeline.periods.length; i++) if (low <= timeline.periods[i].start && timeline.periods[i].start < high) i];
String changeAt(Timeline timeline, int index) => changeText(timeline.periods[index].start, timeline.periods[index - 1], timeline.periods[index]);
String transitionLine(Timeline timeline, int index) {
  final time = timeline.periods[index].start;
  final shift = offsetShift(timeline, index);
  final kind = shift > 0 ? 'gap ${durationText(shift)}' : shift < 0 ? 'overlap ${durationText(-shift)}' : 'no shift';
  return '${changeAt(timeline, index)} (local ${localText(time + timeline.periods[index - 1].offset)} -> ${localText(time + timeline.periods[index].offset)}, $kind)';
}
String shiftsText(Timeline timeline, Iterable<int> indices) {
  var gaps = 0;
  var overlaps = 0;
  var unchanged = 0;
  for (final index in indices) {
    final shift = offsetShift(timeline, index);
    if (shift > 0) {
      gaps++;
    } else if (shift < 0) {
      overlaps++;
    } else {
      unchanged++;
    }
  }
  return 'gaps $gaps, overlaps $overlaps, no shift $unchanged';
}
String candidateText(Timeline timeline, int local, int index) {
  final period = timeline.periods[index];
  return '${utText(local - period.offset)} (${stateText(period)})';
}
int? chosenCandidate(List<int> candidates, String? option) {
  if (candidates.length == 1 || candidates.length == 2 && option == 'EARLIER') return candidates[0];
  if (candidates.length == 2 && option == 'LATER') return candidates[1];
  return null;
}
String unresolvedText(Timeline timeline, int local, List<int> candidates) {
  if (candidates.isNotEmpty) return 'AMBIGUOUS ${candidates.map((index) => candidateText(timeline, local, index)).join(' or ')}';
  final index = timeline.skippingTransition(local);
  final time = timeline.periods[index].start;
  return 'NONEXISTENT gap ${localText(time + timeline.periods[index - 1].offset)} to ${localText(time + timeline.periods[index].offset)} at ${utText(time)}';
}
List<Interval> workingHours(Timeline timeline, int start, int end) {
  final pieces = <Interval>[];
  for (final index in timeline.nearby(start, end)) {
    final offset = timeline.periods[index].offset;
    final low = math.max(start - offset, timeline.periods[index].start);
    final high = math.min(end - offset, timeline.endOf(index));
    if (low < high) pieces.add((low, high));
  }
  return mergeIntervals(pieces);
}
int? parseValue(String kind, String word) {
  final year = int.parse(word.substring(0, 4));
  if (year < 1800 || year > 2099) return null;
  if (kind == 'year') return year;
  final month = int.parse(word.substring(5, 7));
  final day = int.parse(word.substring(8, 10));
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  if (kind == 'date') return dayNumber(year, month, day);
  final hour = int.parse(word.substring(11, 13));
  final minute = int.parse(word.substring(14, 16));
  final second = int.parse(word.substring(17, 19));
  if (hour > 23 || minute > 59 || second > 59) return null;
  return timeValue(year, month, day, hour, minute, second);
}
class QueryArgument {
  final Zone? zone;
  final int? value;
  QueryArgument.zone(this.zone) : value = null;
  QueryArgument.value(this.value) : zone = null;
}
class QueryRunner {
  final Database database;
  final int workStart;
  final int workEnd;
  final List<String> answers = [];
  final List<List<String>> transitionBlocks = [];
  QueryRunner(this.database, this.workStart, this.workEnd);
  void run(String line) {
    final words = line.split(' ');
    final command = words[0];
    final arguments = words.sublist(1);
    String? option;
    if (['TOUTC', 'CONVERT'].contains(command) && ['EARLIER', 'LATER'].contains(arguments.last)) option = arguments.removeLast();
    const argumentKinds = {
      'TOUTC': ['zone', 'local'], 'TOLOCAL': ['zone', 'ut'], 'CONVERT': ['zone', 'zone', 'local'],
      'OFFSET': ['zone', 'ut'], 'TRANSITIONS': ['zone', 'year', 'year'], 'DURATION': ['zone', 'local', 'local']
    };
    final kinds = command == 'MEETING' ? ['date', ...List.filled(arguments.length - 1, 'zone')] : argumentKinds[command]!;
    final values = <QueryArgument>[];
    String? result;
    for (var i = 0; i < arguments.length; i++) {
      final word = arguments[i];
      if (kinds[i] == 'zone') {
        final zone = database.findZone(word);
        if (zone == null) {
          result = 'ERROR unknown zone $word';
          break;
        }
        values.add(QueryArgument.zone(zone));
      } else {
        final value = parseValue(kinds[i], word);
        if (value == null) {
          result = 'ERROR invalid value $word';
          break;
        }
        values.add(QueryArgument.value(value));
      }
    }
    result ??= answer(line, command, values, arguments, option);
    answers.add('$line => $result');
  }
  String answer(String line, String command, List<QueryArgument> values, List<String> arguments, String? option) {
    if (command == 'MEETING') return meeting(values[0].value!, values.skip(1).map((value) => value.zone!).toList(), arguments.sublist(1));
    final zone = values[0].zone!;
    final timeline = zone.timeline;
    if (command == 'CONVERT') {
      final local = values[2].value!;
      final candidates = timeline.candidates(local);
      final index = chosenCandidate(candidates, option);
      if (index == null) return unresolvedText(timeline, local, candidates);
      final time = local - timeline.periods[index].offset;
      final period = values[1].zone!.timeline.periodAt(time);
      final targetLocal = time + period.offset;
      final shift = floorDiv(targetLocal, secondsPerDay) - floorDiv(local, secondsPerDay);
      final shiftText = shift > 0 ? '+$shift' : '$shift';
      return '${localText(targetLocal)} (${stateText(period)}) at ${utText(time)}, day shift $shiftText';
    }
    final value = values[1].value!;
    switch (command) {
      case 'TOUTC':
        final candidates = timeline.candidates(value);
        final index = chosenCandidate(candidates, option);
        return index == null ? unresolvedText(timeline, value, candidates) : candidateText(timeline, value, index);
      case 'TOLOCAL':
        final period = timeline.periodAt(value);
        return '${localText(value + period.offset)} (${stateText(period)})';
      case 'OFFSET':
        final index = timeline.indexAt(value);
        var text = stateText(timeline.periods[index]);
        if (index >= 1) text += ' since ${utText(timeline.periods[index].start)}';
        if (index + 1 < timeline.periods.length) text += ' until ${utText(timeline.periods[index + 1].start)}';
        return text;
      case 'TRANSITIONS':
        final last = values[2].value!;
        if (value > last) return 'ERROR invalid range';
        final selected = transitionsBetween(timeline, yearStart(value), yearStart(last + 1));
        transitionBlocks.add([line, ...selected.map((index) => transitionLine(timeline, index)), shiftsText(timeline, selected)]);
        return 'transitions: ${selected.length}';
      case 'DURATION':
        final offsets = <int>[];
        for (var i = 1; i < 3; i++) {
          final candidates = timeline.candidates(values[i].value!);
          if (candidates.length == 2) return 'AMBIGUOUS ${arguments[i]}';
          if (candidates.isEmpty) return 'NONEXISTENT ${arguments[i]}';
          offsets.add(timeline.periods[candidates[0]].offset);
        }
        final second = values[2].value!;
        final elapsed = (second - offsets[1]) - (value - offsets[0]);
        return '$elapsed s (${durationText(elapsed)}), wall clock ${durationText(second - value)}, offset change ${offsetText(offsets[1] - offsets[0])}';
    }
    return '';
  }
  String meeting(int day, List<Zone> zones, List<String> words) {
    final start = day * secondsPerDay + workStart;
    final end = day * secondsPerDay + workEnd;
    var common = workingHours(zones[0].timeline, start, end);
    for (final zone in zones.skip(1)) {
      common = intersectIntervals(common, workingHours(zone.timeline, start, end));
    }
    if (common.isEmpty) return 'NONE';
    final parts = <String>[];
    for (final (low, high) in common) {
      final members = <String>[];
      for (var i = 0; i < zones.length; i++) {
        final period = zones[i].timeline.periodAt(low);
        members.add('${words[i]} ${localText(low + period.offset)} ${period.abbreviation}');
      }
      parts.add('${utText(low)} to ${utText(high)} (${durationText(high - low)}) [${members.join(', ')}]');
    }
    return parts.join('; ');
  }
}

String ruleText(Rule rule) {
  final fields = rule.fields;
  return 'rule ${rule.name} ${fields[2]} ${fields[3]} ${fields[5]} ${fields[6]} ${clockText(rule.at)}${rule.atType} ${clockText(rule.save)} ${fields[9]}';
}
List<String> databaseBlock(Database database) {
  final ruleLines = database.lines.where((line) => line.kind == 'Rule').toList();
  final linkLines = database.lines.where((line) => line.kind == 'Link').toList();
  final validRules = ruleLines.where((line) => line.error == null).length;
  final validLinks = linkLines.where((line) => line.error == null).length;
  final used = <String>{};
  var zoneLines = 0;
  for (final zone in database.zones.values) {
    zoneLines += zone.lines.length;
    used.addAll(zone.ruleSets);
  }
  final unused = database.rules.keys.where((name) => !used.contains(name)).toList();
  final invalid = [for (final block in database.blocks) if (!block.defined) '${block.name} (line ${block.number})'];
  final lines = <String>[
    'DATABASE', 'rule lines: $validRules valid, ${ruleLines.length - validRules} invalid',
    'zones: ${database.zones.length} defined, ${database.blocks.length - database.zones.length} invalid',
    'zone lines: $zoneLines in defined zones', 'links: $validLinks defined, ${linkLines.length - validLinks} invalid',
    'errors: ${database.errorLines.length}', 'unused rules: ${namesOrNone(unused, ' ')}',
    'invalid zones: ${namesOrNone(invalid, ', ')}'
  ];
  for (final entry in database.rules.entries) {
    final rules = entry.value;
    final first = rules.map((rule) => rule.from).reduce((a, b) => math.min(a, b));
    final last = rules.any((rule) => rule.fields[3] == 'max') ? 'max' : '${rules.map((rule) => rule.to).reduce((a, b) => math.max(a, b))}';
    final count = database.zones.values.where((zone) => zone.ruleSets.contains(entry.key)).length;
    lines.add('rule set ${entry.key}: lines ${rules.length}, years $first-$last, zones $count');
  }
  return lines;
}
List<String> dstLines(Timeline timeline, int reference) {
  final indices = [for (var i = 0; i < timeline.periods.length; i++) if (timeline.periods[i].dst) i];
  final lines = <String>[];
  if (indices.isEmpty) {
    lines.add('dst years: none');
  } else {
    final years = indices.map((index) => splitTime(timeline.periods[index].start).$1).toList();
    lines.add('dst years: ${years.reduce((a, b) => math.min(a, b))}-${years.reduce((a, b) => math.max(a, b))}');
  }
  final year = splitTime(reference).$1;
  final low = yearStart(year);
  final high = yearStart(year + 1);
  final pieces = <Interval>[];
  for (final index in indices) {
    final start = math.max(low, timeline.periods[index].start);
    final end = math.min(high, timeline.endOf(index));
    if (start < end) pieces.add((start, end));
  }
  var total = 0;
  for (final (start, end) in mergeIntervals(pieces)) {
    lines.add('dst period: ${utText(start)} to ${utText(end)} (${durationText(end - start)})');
    total += end - start;
  }
  lines.add('dst total $year: ${durationText(total)}');
  return lines;
}
List<String> zoneBlock(Database database, Zone zone, int reference) {
  final timeline = zone.timeline;
  final periods = timeline.periods;
  final lines = <String>['ZONE ${zone.name}', 'aliases: ${namesOrNone(zone.aliases, ' ')}'];
  for (var i = 0; i < zone.lines.length; i++) {
    final line = zone.lines[i];
    var text = 'line ${i + 1}: ${offsetText(line.stdOffset)} ${line.rulesNotation} ${line.format}';
    if (i > 0) text += ' from ${utText(line.start)}';
    if (line.until != null) text += ' until ${line.untilNotation} = ${utText(line.end)}';
    lines.add('$text, transitions ${transitionsBetween(timeline, line.start, line.end).length}');
  }
  for (final name in zone.ruleSets) {
    for (final rule in database.rules[name]!) {
      lines.add('${ruleText(rule)}, applied ${zone.applied[rule.number] ?? 0}');
    }
  }
  final offsets = periods.map((period) => period.offset).toList();
  lines.add('offset range: ${offsetText(offsets.reduce((a, b) => math.min(a, b)))} to ${offsetText(offsets.reduce((a, b) => math.max(a, b)))}');
  final counts = <String, int>{};
  for (final period in periods) {
    counts.update(stateText(period), (count) => count + 1, ifAbsent: () => 1);
  }
  for (final entry in counts.entries) {
    lines.add('state ${entry.key}, periods ${entry.value}');
  }
  final index = timeline.indexAt(reference);
  final period = periods[index];
  lines.add('reference: ${localText(reference + period.offset)} (${stateText(period)}), line ${zone.lineNumberAt(reference)}');
  lines.add('previous transition: ${index >= 1 ? changeAt(timeline, index) : 'none'}');
  lines.add('next transition: ${index + 1 < periods.length ? changeAt(timeline, index + 1) : 'none'}');
  final every = List.generate(periods.length - 1, (i) => i + 1);
  lines.add('transitions: ${every.length}, ${shiftsText(timeline, every)}');
  lines.addAll(dstLines(timeline, reference));
  return lines;
}
void main() {
  final database = Database(readLines('tzdata.txt'));
  final params = readLines('params.txt');
  final reference = parseValue('ut', params[0].split(' ')[1])!;
  final workday = params[1].split(' ');
  final runner = QueryRunner(database, clockSeconds(workday[1]), clockSeconds(workday[2]));
  for (final line in readLines('queries.txt')) {
    runner.run(line);
  }
  final blocks = <List<String>>[indented(databaseBlock(database))];
  final names = database.zones.keys.toList()..sort();
  for (final name in names) {
    blocks.add(indented(zoneBlock(database, database.zones[name]!, reference)));
  }
  Directory('output').createSync(recursive: true);
  writeLines('answers.txt', runner.answers);
  writeLines('errors.txt', database.errorLines);
  writeBlocks('transitions.txt', runner.transitionBlocks);
  writeBlocks('zone_summary.txt', blocks);
}
