import 'dart:io';
import 'baskets.dart';
import 'rules.dart';

const rulesHeader = 'rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement';

String fractionText(Fraction value) {
  final numerator = value.numerator.abs(), denominator = value.denominator, scaled = 10000 * numerator ~/ denominator;
  final decimal = '${scaled ~/ 10000}.${(scaled % 10000).toString().padLeft(4, '0')}';
  return '${value.numerator < 0 ? '-' : ''}$numerator/$denominator=${value.numerator < 0 && scaled > 0 ? '-' : ''}$decimal';
}
String percentText(int part, int whole) { final scaled = 10000 * part ~/ whole; return '${scaled ~/ 100}.${(scaled % 100).toString().padLeft(2, '0')}%'; }
String moneyText(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
String ruleArrow(Rule rule) => '${setKey(rule.antecedent)} -> ${setKey(rule.consequent)}';
List<String> rulesCsv(List<Rule> rules) => [rulesHeader, for (final rule in rules) '${rule.rank},${setKey(rule.antecedent)},${setKey(rule.consequent)},${rule.count},${fractionText(rule.support)},${fractionText(rule.confidence)},${fractionText(rule.lift)},${fractionText(rule.leverage)},${rule.conviction == null ? 'INF' : fractionText(rule.conviction!)},${fractionText(rule.improvement)}'];
void writeReport(String name, List<String> lines) {
  Directory('output').createSync(recursive: true); File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
