import 'script_loader.dart';
import 'matcher.dart';

const diagnosticCodes = ['SYNTAX', 'ORPHAN', 'DUPLICATE', 'KEY_NO_DECOMP', 'KEY_UNREACHABLE', 'SYNON_UNUSED', 'PRE_CHAIN', 'SYNON_UNKNOWN', 'RULE_NO_REASM', 'RULE_SHADOWED', 'REF_UNBOUND', 'TARGET_UNDEFINED', 'TARGET_CYCLE'];
const errorCodes = {'SYNTAX', 'ORPHAN', 'DUPLICATE', 'SYNON_UNKNOWN', 'REF_UNBOUND', 'TARGET_UNDEFINED', 'TARGET_CYCLE'};

List<String> lint(Script script) {
  final found = List<Diagnostic>.of(script.diagnostics);
  void add(int line, String code, String message) => found.add(Diagnostic(line, code, message));
  final targets = <String>{};
  final graph = List.generate(script.keywords.length, (_) => <int>[]);
  for (var id = 0; id < script.keywords.length; id++) {
    for (final rule in script.keywords[id].decomps) {
      for (final itemId in script.rules[rule].items) {
        final item = script.items[itemId];
        if (!{'GOTO', 'RESTATE'}.contains(item.kind)) continue;
        final target = item.arguments[0];
        targets.add(target);
        if (script.keywordMap.containsKey(target)) graph[id].add(script.keywordMap[target]!);
      }
    }
  }
  List<String> unknown(List<String> pattern) => pattern.where((element) => element.startsWith('@') && !script.groups.containsKey(element.substring(1))).map((element) => element.substring(1)).toList();
  for (var id = 0; id < script.keywords.length; id++) {
    final keyword = script.keywords[id], word = keyword.word;
    if (keyword.decomps.isEmpty) add(keyword.line, 'KEY_NO_DECOMP', 'keyword $word has no DECOMP');
    if (script.pre.containsKey(word) && !script.pre.values.any((pre) => pre.replacement.contains(word)) && !targets.contains(word)) add(keyword.line, 'KEY_UNREACHABLE', 'keyword $word is replaced by PRE');
    for (final rules in [keyword.memories, keyword.decomps]) {
      for (var position = 0; position < rules.length; position++) {
        final rule = script.rules[rules[position]];
        final missing = unknown(rule.pattern);
        for (final group in missing) add(rule.line, 'SYNON_UNKNOWN', 'unknown group $group');
        if (rule.items.isEmpty) add(rule.line, 'RULE_NO_REASM', 'rule has no reassembly');
        if (missing.isEmpty) {
          for (final earlierId in rules.take(position)) {
            final earlier = script.rules[earlierId];
            if (unknown(earlier.pattern).isEmpty && patternCovers(earlier.pattern, rule.pattern, script.groups)) {
              add(rule.line, 'RULE_SHADOWED', 'pattern is shadowed by line ${earlier.line}');
              break;
            }
          }
        }
        final wildcards = rule.pattern.where(wildcard).length;
        for (final itemId in rule.items) {
          final item = script.items[itemId];
          final references = <int>[];
          if (item.kind == 'REASM') {
            for (var index = 0; index + 3 <= item.text.length; index++) {
              final number = reference(item.text.substring(index, index + 3));
              if (number != null) references.add(number);
            }
          } else if (item.kind == 'RESTATE') {
            for (final argument in item.arguments.skip(1)) { final number = reference(argument); if (number != null) references.add(number); }
          }
          for (final number in references) if (number == 0 || number > wildcards) add(item.line, 'REF_UNBOUND', 'reference ($number) is not bound');
          if (!{'GOTO', 'RESTATE'}.contains(item.kind)) continue;
          final target = item.arguments[0], start = script.keywordMap[target];
          if (start == null) add(item.line, 'TARGET_UNDEFINED', 'target $target is not a keyword');
          else {
            final pending = [start], seen = <int>{};
            while (pending.isNotEmpty) {
              final node = pending.removeLast();
              if (node == id) { add(item.line, 'TARGET_CYCLE', 'edge $word -> $target is on a cycle'); break; }
              if (seen.add(node)) pending.addAll(graph[node]);
            }
          }
        }
      }
    }
  }
  for (final group in script.groups.values) if (!script.rules.any((rule) => rule.pattern.contains('@${group.name}'))) add(group.line, 'SYNON_UNUSED', 'group ${group.name} is never used');
  for (final pre in script.pre.values) for (final word in pre.replacement) if (script.pre.containsKey(word)) add(pre.line, 'PRE_CHAIN', 'replacement $word is itself replaced by PRE');
  final ordered = found.asMap().entries.toList()..sort((a, b) {
    final byLine = a.value.line.compareTo(b.value.line);
    final byCode = diagnosticCodes.indexOf(a.value.code).compareTo(diagnosticCodes.indexOf(b.value.code));
    return byLine != 0 ? byLine : byCode != 0 ? byCode : a.key.compareTo(b.key);
  });
  if (ordered.isEmpty) return ['OK'];
  final errors = found.where((diagnostic) => errorCodes.contains(diagnostic.code)).length;
  return [...ordered.map((entry) => '${entry.value.line} ${entry.value.code} ${entry.value.message}'), 'TOTAL ${found.length} errors=$errors warnings=${found.length - errors}'];
}
