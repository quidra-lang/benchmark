import 'lexer.dart';
import 'ini_parser.dart' show isSectionName;
import 'schema.dart' show sectionOf;

class Expander {
  final Map<String, String> values;
  final Map<String, Origin> origins;
  final results = <String, String?>{};
  final inProgress = <String>[];
  final cycleKeys = <String>{};
  final diagnostics = <Diagnostic>[];
  Expander(this.values, this.origins);

  void report(Origin origin, String code, String message) =>
      diagnostics.add(Diagnostic(origin, code, message));

  String? expand(String key) {
    if (results.containsKey(key)) return results[key];
    inProgress.add(key);
    final result = evaluate(key);
    inProgress.removeLast();
    results[key] = result;
    return result;
  }

  String? evaluate(String key) {
    final value = values[key]!;
    final origin = origins[key]!;
    final result = StringBuffer();
    var position = 0;
    while (position < value.length) {
      if (!value.startsWith(r'${', position)) {
        final char = value[position++];
        result.write(char == literalDollar ? r'$' : char);
        continue;
      }
      final close = value.indexOf('}', position + 2);
      if (close < 0 || !isSectionName(value.substring(position + 2, close))) {
        report(origin, 'E_BAD_REF', '$key: invalid reference');
        return null;
      }
      final reference = value.substring(position + 2, close);
      final target = reference.contains('.') ? reference : '${sectionOf(key)}.$reference';
      if (!values.containsKey(target)) {
        report(origin, 'E_UNDEFINED', '$key: undefined reference $target');
        return null;
      }
      String? expanded;
      final cycleStart = inProgress.indexOf(target);
      if (cycleStart >= 0) {
        final path = [...inProgress.skip(cycleStart), target];
        report(origins[target]!, 'E_CYCLE', 'interpolation cycle ${path.join(' -> ')}');
        cycleKeys.addAll(path);
        expanded = null;
      } else {
        expanded = expand(target);
      }
      if (expanded == null) {
        if (!cycleKeys.contains(key)) {
          report(origin, 'E_DEPENDENCY', '$key: depends on failed key $target');
        }
        return null;
      }
      result.write(expanded);
      position = close + 1;
    }
    return result.toString();
  }
}
