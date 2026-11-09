part of 'main.dart';

const endToken = r'$';
List<String> terminalOrder(Iterable<String> terms) {
  final set = terms.toSet(),
      result = terms.where((s) => s != endToken).toSet().toList()..sort();
  if (set.contains(endToken)) {
    result.add(endToken);
  }
  return result;
}

Set<String> terminalsOf(Grammar g) => {
  for (final lhs in g.order)
    for (final rhs in g.rules[lhs]!)
      for (final s in rhs)
        if (!isNonterminal(s)) s,
};
bool mergeSet(Set<String> target, Set<String> source) {
  final before = target.length;
  target.addAll(source);
  return target.length != before;
}

(Set<String>, bool) firstSequence(
  List<String> rhs,
  Map<String, bool> nullable,
  Map<String, Set<String>> first,
) {
  final result = <String>{};
  for (final s in rhs) {
    if (!isNonterminal(s)) {
      result.add(s);
      return (result, false);
    }
    result.addAll(first[s]!);
    if (!(nullable[s] ?? false)) {
      return (result, false);
    }
  }
  return (result, true);
}

class Sets {
  final nullable = <String, bool>{},
      first = <String, Set<String>>{},
      follow = <String, Set<String>>{};
  int nullablePasses = 0, firstPasses = 0, followPasses = 0;
  final List<String> terminals;
  Sets(this.terminals);
}

Sets analyzeSets(Grammar g) {
  final result = Sets(terminalOrder(terminalsOf(g)));
  for (final lhs in g.order) {
    result.nullable[lhs] = false;
    result.first[lhs] = {};
    result.follow[lhs] = {};
  }
  result.follow[g.start]!.add(endToken);
  while (true) {
    result.nullablePasses++;
    var changed = false;
    for (final lhs in g.order) {
      if (result.nullable[lhs]!) {
        continue;
      }
      for (final rhs in g.rules[lhs]!) {
        if (rhs.every((s) => isNonterminal(s) && result.nullable[s]!)) {
          result.nullable[lhs] = true;
          changed = true;
          break;
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  while (true) {
    result.firstPasses++;
    var changed = false;
    for (final lhs in g.order) {
      for (final rhs in g.rules[lhs]!) {
        final (more, _) = firstSequence(rhs, result.nullable, result.first);
        if (mergeSet(result.first[lhs]!, more)) {
          changed = true;
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  while (true) {
    result.followPasses++;
    var changed = false;
    for (final lhs in g.order) {
      for (final rhs in g.rules[lhs]!) {
        for (var i = 0; i < rhs.length; i++) {
          final s = rhs[i];
          if (!isNonterminal(s)) {
            continue;
          }
          final (more, empty) = firstSequence(
            rhs.sublist(i + 1),
            result.nullable,
            result.first,
          );
          if (empty) {
            more.addAll(result.follow[lhs]!);
          }
          if (mergeSet(result.follow[s]!, more)) {
            changed = true;
          }
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  return result;
}
