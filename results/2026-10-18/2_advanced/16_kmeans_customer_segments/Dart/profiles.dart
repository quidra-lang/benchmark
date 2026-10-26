import 'features.dart';
import 'transactions.dart';

class Condition {
  final int feature;
  final String comparison;
  final double threshold;
  Condition(String name, this.comparison, String value)
      : feature = featureNames.indexOf(name), threshold = double.parse(value);
  bool holds(List<double> center) => comparison == '>' ? center[feature] > threshold : center[feature] < threshold;
}

class Rule {
  final String name;
  final List<Condition> conditions;
  Rule(List<String> words) : name = words.first,
      conditions = [for (var index = 1; index < words.length; index += 3) Condition(words[index], words[index + 1], words[index + 2])];
  bool holds(List<double> center) => conditions.every((condition) => condition.holds(center));
}

List<Rule> readRules() => [for (final line in readLines('input/segment_rules.txt')) Rule(line.split(' '))];
int ruleNumber(List<Rule> rules, List<double> center) => rules.indexWhere((rule) => rule.holds(center)) + 1;
List<double> originalScale(List<double> center, List<double> means, List<double> sds) {
  final values = <double>[];
  for (var feature = 0; feature < center.length; feature++) {
    final value = means[feature] + sds[feature] * center[feature];
    values.add(sqrtFeatures[feature] ? value * value : value);
  }
  return values;
}
