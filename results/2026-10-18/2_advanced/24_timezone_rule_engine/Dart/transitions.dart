import 'day_rules.dart';
import 'tz_parser.dart';

class Rule {
  final int number;
  final List<String> fields;
  final String name;
  final int from;
  final int to;
  final int month;
  final DaySpec day;
  final int at;
  final String atType;
  final int save;
  final String letter;
  Rule(this.number, this.fields, this.name, this.from, this.to, this.month, this.day, this.at, this.atType, this.save, this.letter);
}
class RuleInstance {
  final Rule rule;
  final int nominal;
  RuleInstance(this.rule, this.nominal);
}
class AppliedInstance {
  final int time;
  final Rule rule;
  AppliedInstance(this.time, this.rule);
}
class LineRun {
  final List<Rule> preStart;
  final List<AppliedInstance> applied;
  final int end;
  LineRun(this.preStart, this.applied, this.end);
}
List<RuleInstance> instanceSequence(List<Rule> rules) {
  final instances = <RuleInstance>[];
  for (final rule in rules) {
    for (var year = rule.from; year <= rule.to; year++) {
      instances.add(RuleInstance(rule, rule.day.value(year, rule.month) * secondsPerDay + rule.at));
    }
  }
  instances.sort((a, b) {
    final compared = a.nominal.compareTo(b.nominal);
    return compared == 0 ? a.rule.number.compareTo(b.rule.number) : compared;
  });
  return instances;
}
int adjustment(String type, int offset, int save) => type == 'u' ? 0 : type == 's' ? offset : offset + save;
LineRun runInstances(List<RuleInstance> instances, int offset, int start, Until? until) {
  final preStart = <Rule>[];
  final applied = <AppliedInstance>[];
  var save = 0;
  for (final instance in instances) {
    final rule = instance.rule;
    final time = instance.nominal - adjustment(rule.atType, offset, save);
    if (until != null && time >= until.value - adjustment(until.type, offset, save)) break;
    if (time <= start) {
      preStart.add(rule);
    } else {
      applied.add(AppliedInstance(time, rule));
    }
    save = rule.save;
  }
  final end = until == null ? posInfinity : until.value - adjustment(until.type, offset, save);
  return LineRun(preStart, applied, end);
}
String abbreviation(String format, int save, String letter) {
  final position = format.indexOf('/');
  if (position >= 0) return save == 0 ? format.substring(0, position) : format.substring(position + 1);
  return format.replaceAll('%s', letter);
}
