part of 'main.dart';

Grammar cloneGrammar(Grammar g) {
  final result = Grammar()
    ..order = List<String>.of(g.order)
    ..start = g.start;
  for (final lhs in g.order) {
    result.rules[lhs] = [for (final rhs in g.rules[lhs]!) List<String>.of(rhs)];
  }
  return result;
}

String freshName(String lhs, Map<String, List<List<String>>> rules) {
  var proposed = "${lhs.substring(0, lhs.length - 1)}'>";
  while (rules.containsKey(proposed)) {
    proposed = "${proposed.substring(0, proposed.length - 1)}'>";
  }
  return proposed;
}

bool leadingReaches(
  Map<String, List<List<String>>> rules,
  String source,
  String target,
) {
  final queue = <String>[source], seen = <String>{source};
  for (var i = 0; i < queue.length; i++) {
    for (final rhs in rules[queue[i]] ?? <List<String>>[]) {
      if (rhs.isEmpty || !isNonterminal(rhs.first)) {
        continue;
      }
      final next = rhs.first;
      if (next == target) {
        return true;
      }
      if (seen.add(next)) {
        queue.add(next);
      }
    }
  }
  return false;
}

List<List<String>> deduplicate(List<List<String>> alternatives) {
  final result = <List<String>>[];
  for (final rhs in alternatives) {
    if (!result.any((old) => listEqual(old, rhs))) {
      result.add(rhs);
    }
  }
  return result;
}

(Grammar, List<String>) eliminateLeftRecursion(Grammar grammar) {
  final g = cloneGrammar(grammar),
      initial = List<String>.of(grammar.order),
      log = <String>[];
  for (var i = 0; i < initial.length; i++) {
    final lhs = initial[i];
    for (final earlier in initial.take(i)) {
      if (!g.rules[lhs]!.any((rhs) => rhs.isNotEmpty && rhs.first == earlier) ||
          !leadingReaches(g.rules, earlier, lhs)) {
        continue;
      }
      final replacements = <List<String>>[];
      for (final rhs in g.rules[lhs]!) {
        if (rhs.isNotEmpty && rhs.first == earlier) {
          for (final source in g.rules[earlier]!) {
            replacements.add([...source, ...rhs.skip(1)]);
          }
        } else {
          replacements.add(rhs);
        }
      }
      g.rules[lhs] = deduplicate(replacements);
      log.add('substitute $earlier into $lhs');
    }
    final recursive = <List<String>>[], nonrecursive = <List<String>>[];
    for (final rhs in g.rules[lhs]!) {
      if (rhs.length == 1 && rhs.first == lhs) {
        log.add('remove cycle ${productionNotation(lhs, rhs)}');
        continue;
      }
      if (rhs.isNotEmpty && rhs.first == lhs) {
        recursive.add(rhs.sublist(1));
      } else {
        nonrecursive.add(rhs);
      }
    }
    g.rules[lhs] = nonrecursive;
    if (recursive.isEmpty) {
      continue;
    }
    final created = freshName(lhs, g.rules);
    g.rules[lhs] = [
      for (final rhs in nonrecursive) [...rhs, created],
    ];
    g.rules[created] = [
      for (final rhs in recursive) [...rhs, created],
      [],
    ];
    g.order.insert(g.order.indexOf(lhs) + 1, created);
    log.add('eliminate left recursion in $lhs with $created');
  }
  return (g, log);
}

(Grammar, List<String>) leftFactor(Grammar grammar) {
  final g = cloneGrammar(grammar), log = <String>[];
  for (var position = 0; position < g.order.length; position++) {
    final lhs = g.order[position],
        current = g.rules[lhs]!,
        kept = <List<String>>[],
        createdNames = <String>[],
        handled = <String>{};
    for (final rhs in current) {
      if (rhs.isEmpty) {
        kept.add(rhs);
        continue;
      }
      final first = rhs.first;
      if (!handled.add(first)) {
        continue;
      }
      final group = current
          .where((other) => other.isNotEmpty && other.first == first)
          .toList();
      if (group.length == 1) {
        kept.add(rhs);
        continue;
      }
      var length = group.first.length;
      for (final other in group.skip(1)) {
        length = min(length, other.length);
        for (var k = 0; k < length; k++) {
          if (other[k] != group.first[k]) {
            length = k;
            break;
          }
        }
      }
      final prefix = group.first.sublist(0, length),
          created = freshName(lhs, g.rules);
      g.rules[created] = [for (final other in group) other.sublist(length)];
      kept.add([...prefix, created]);
      createdNames.add(created);
      log.add('left factor $lhs on ${notation(prefix)} with $created');
    }
    g.rules[lhs] = kept;
    g.order.insertAll(position + 1, createdNames);
  }
  return (g, log);
}
