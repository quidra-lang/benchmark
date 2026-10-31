import 'dart:io';
import 'dart:math';

part 'grammar_parser.dart';
part 'transform.dart';
part 'first_follow.dart';
part 'table.dart';
part 'driver.dart';

bool listEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

Set<String> reachable(Grammar g) {
  final seen = <String>{g.start}, queue = <String>[g.start];
  for (var i = 0; i < queue.length; i++) {
    for (final rhs in g.rules[queue[i]] ?? <List<String>>[]) {
      for (final s in rhs) {
        if (isNonterminal(s) && seen.add(s)) {
          queue.add(s);
        }
      }
    }
  }
  return seen;
}

void pruneOrder(Grammar g, Set<String> keep) {
  for (final lhs in g.order) {
    if (!keep.contains(lhs)) {
      g.rules.remove(lhs);
    }
  }
  g.order = g.order.where(keep.contains).toList();
}

List<String> checkDeclarations(Grammar source) => !source.hasDeclaration
    ? []
    : [
        for (final word in terminalOrder(source.words.keys))
          if (!source.declared.contains(word))
            'undeclared terminal $word at line ${source.words[word]}',
      ];
(Grammar, List<String>) cleanGrammar(Grammar source) {
  final g = cloneGrammar(source),
      log = <String>[],
      defined = source.order.toSet(),
      undefined = <String>{};
  for (final lhs in g.order) {
    for (final rhs in g.rules[lhs]!) {
      for (final s in rhs) {
        if (isNonterminal(s) && !defined.contains(s)) {
          undefined.add(s);
        }
      }
    }
  }
  final names = undefined.toList()
    ..sort(
      (a, b) =>
          a.substring(1, a.length - 1).compareTo(b.substring(1, b.length - 1)),
    );
  for (final name in names) {
    log.add('undefined nonterminal $name');
  }
  void removeAlternatives(Set<String> discarded, String kind) {
    for (final lhs in g.order) {
      final kept = <List<String>>[];
      for (final rhs in g.rules[lhs]!) {
        String? bad;
        for (final s in rhs) {
          if (discarded.contains(s)) {
            bad = s;
            break;
          }
        }
        if (bad != null) {
          log.add('removed ${productionNotation(lhs, rhs)} ($kind $bad)');
        } else {
          kept.add(rhs);
        }
      }
      g.rules[lhs] = kept;
    }
  }

  removeAlternatives(undefined, 'undefined');
  final productive = <String>{};
  while (true) {
    var changed = false;
    for (final lhs in g.order) {
      if (productive.contains(lhs)) {
        continue;
      }
      for (final rhs in g.rules[lhs]!) {
        if (rhs.every((s) => !isNonterminal(s) || productive.contains(s))) {
          productive.add(lhs);
          changed = true;
          break;
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  final discarded = <String>{};
  for (final lhs in g.order) {
    if (!productive.contains(lhs)) {
      log.add('unproductive nonterminal $lhs');
      discarded.add(lhs);
    }
  }
  pruneOrder(g, productive);
  removeAlternatives(discarded, 'unproductive');
  final reached = reachable(g);
  for (final lhs in g.order) {
    if (!reached.contains(lhs)) {
      log.add('unreachable nonterminal $lhs');
    }
  }
  pruneOrder(g, reached);
  return (g, log);
}

List<String> recursionDiagnostics(Grammar g) {
  final log = <String>[];
  for (final start in g.order) {
    final queue = <String>[start], parent = <String, String>{start: ''};
    var found = false;
    for (var cursor = 0; cursor < queue.length && !found; cursor++) {
      final lhs = queue[cursor];
      for (final rhs in g.rules[lhs]!) {
        if (rhs.isEmpty || !isNonterminal(rhs.first)) {
          continue;
        }
        final next = rhs.first;
        if (next == start) {
          final backwards = <String>[lhs];
          while (parent[backwards.last]!.isNotEmpty) {
            backwards.add(parent[backwards.last]!);
          }
          log.add(
            'left recursion: ${[...backwards.reversed, start].join(' -> ')}',
          );
          found = true;
          break;
        }
        if (!parent.containsKey(next)) {
          parent[next] = lhs;
          queue.add(next);
        }
      }
    }
  }
  return log;
}

(Grammar, List<String>, List<String>) finalPruning(Grammar grammar) {
  final g = cloneGrammar(grammar),
      reached = reachable(g),
      log = <String>[],
      diagnostics = <String>[];
  for (final lhs in g.order) {
    if (!reached.contains(lhs)) {
      log.add('remove unreachable $lhs');
      diagnostics.add('unreachable after transformation $lhs');
    }
  }
  pruneOrder(g, reached);
  return (g, log, diagnostics);
}

List<String> unusedDeclarations(Grammar source, Grammar g) =>
    !source.hasDeclaration
    ? []
    : [
        for (final token in terminalOrder(
          source.declared.difference(terminalsOf(g)),
        ))
          'unused token $token',
      ];
String grammarSummary(Grammar g) {
  var count = 0, empty = 0, unit = 0;
  for (final lhs in g.order) {
    for (final rhs in g.rules[lhs]!) {
      count++;
      if (rhs.isEmpty) {
        empty++;
      }
      if (rhs.length == 1 && isNonterminal(rhs.first)) {
        unit++;
      }
    }
  }
  return 'start=${g.start} nonterminals=${g.order.length} terminals=${terminalsOf(g).length} productions=$count empty=$empty unit=$unit';
}

List<String> grammarListing(Grammar g, bool numbered) {
  final lines = <String>[], width = '${numberProductions(g).length}'.length;
  var number = 0;
  for (final lhs in g.order) {
    final alternatives = g.rules[lhs]!;
    for (var i = 0; i < alternatives.length; i++) {
      number++;
      var line = i == 0
          ? productionNotation(lhs, alternatives[i])
          : '${' ' * lhs.length} | ${notation(alternatives[i])}';
      if (numbered) {
        line = '${'$number'.padLeft(width)}  $line';
      }
      lines.add(line);
    }
  }
  return lines;
}

List<String> intStrings(List<int> values) => values.map((v) => '$v').toList();
String listLine(String heading, List<String> values) =>
    values.isEmpty ? heading : '$heading ${values.join(' ')}';
List<String> grammarFile(
  Grammar cleaned,
  Grammar recursion,
  Grammar factored,
  Grammar finalGrammar,
  List<String> firstLog,
  List<String> secondLog,
  List<String> lastLog,
) {
  final lines = <String>[
    '== cleaned grammar ==',
    grammarSummary(cleaned),
    ...grammarListing(cleaned, false),
  ];
  for (final (title, g, log, numbered) in [
    ('left recursion elimination', recursion, firstLog, false),
    ('left factoring', factored, secondLog, false),
    ('final grammar', finalGrammar, lastLog, true),
  ]) {
    lines.addAll([
      '',
      '== $title ==',
      ...log.isEmpty ? ['none'] : log,
      grammarSummary(g),
      ...grammarListing(g, numbered),
    ]);
  }
  lines.addAll(['', '== cross reference ==']);
  final productions = numberProductions(finalGrammar);
  for (final symbol in [
    ...finalGrammar.order,
    ...terminalOrder(terminalsOf(finalGrammar)),
  ]) {
    final numbers = [
          for (final p in productions)
            if (p.rhs.contains(symbol)) p.number,
        ],
        name = isNonterminal(symbol) ? symbol : '"$symbol"';
    lines.add(
      numbers.isEmpty
          ? '$name not used'
          : listLine('$name used in', intStrings(numbers)),
    );
  }
  return lines;
}

typedef Measure = (int, int);
bool measureLess(Measure a, Measure b) =>
    a.$1 < b.$1 || a.$1 == b.$1 && a.$2 < b.$2;
Measure? sequenceMeasure(List<String> rhs, Map<String, Measure> scores) {
  var length = 0, height = 1;
  for (final s in rhs) {
    if (isNonterminal(s)) {
      final value = scores[s];
      if (value == null) {
        return null;
      }
      length += value.$1;
      height = max(height, value.$2 + 1);
    } else {
      length++;
    }
  }
  return (length, height);
}

List<String> expandSequence(
  List<String> rhs,
  Map<String, List<String>> sentences,
) => [
  for (final s in rhs) ...isNonterminal(s) ? sentences[s]! : [s],
];
(Map<String, Measure>, Map<String, List<String>>) shortestSentences(Grammar g) {
  final scores = <String, Measure>{};
  while (true) {
    var changed = false;
    for (final lhs in g.order) {
      for (final rhs in g.rules[lhs]!) {
        final candidate = sequenceMeasure(rhs, scores), old = scores[lhs];
        if (candidate != null && (old == null || measureLess(candidate, old))) {
          scores[lhs] = candidate;
          changed = true;
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  final selected = <String, List<String>>{},
      sentences = <String, List<String>>{};
  for (final lhs in g.order) {
    for (final rhs in g.rules[lhs]!) {
      if (sequenceMeasure(rhs, scores) == scores[lhs]) {
        selected[lhs] = rhs;
        break;
      }
    }
  }
  late List<String> Function(String) expand;
  expand = (symbol) {
    if (!isNonterminal(symbol)) {
      return [symbol];
    }
    final known = sentences[symbol];
    if (known != null) {
      return known;
    }
    final result = <String>[];
    for (final s in selected[symbol]!) {
      result.addAll(expand(s));
    }
    sentences[symbol] = result;
    return result;
  };
  for (final lhs in g.order) {
    expand(lhs);
  }
  return (scores, sentences);
}

class Context {
  final List<String> prefix, suffix;
  Context(this.prefix, this.suffix);
}

class ContextParent {
  final int number, index;
  final String lhs;
  final List<String> before, after;
  ContextParent(this.number, this.index, this.lhs, this.before, this.after);
}

Map<String, Context> shortestContexts(
  Grammar g,
  Map<String, Measure> scores,
  Map<String, List<String>> sentences,
) {
  final productions = numberProductions(g),
      costs = <String, Measure>{g.start: (0, 0)},
      parents = <String, ContextParent>{};
  while (true) {
    var changed = false;
    for (final p in productions) {
      final outer = costs[p.lhs];
      if (outer == null) {
        continue;
      }
      for (var i = 0; i < p.rhs.length; i++) {
        final s = p.rhs[i];
        if (!isNonterminal(s) || s == g.start) {
          continue;
        }
        final before = p.rhs.sublist(0, i), after = p.rhs.sublist(i + 1);
        var length = 0;
        for (final other in [...before, ...after]) {
          length += isNonterminal(other) ? scores[other]!.$1 : 1;
        }
        final candidate = (outer.$1 + length, outer.$2 + 1),
            old = costs[s],
            parent = parents[s];
        final tieBetter =
            candidate == old &&
            parent != null &&
            (p.number < parent.number ||
                p.number == parent.number && i < parent.index);
        if (old == null || measureLess(candidate, old) || tieBetter) {
          costs[s] = candidate;
          parents[s] = ContextParent(p.number, i, p.lhs, before, after);
          changed = true;
        }
      }
    }
    if (!changed) {
      break;
    }
  }
  final memo = <String, Context>{g.start: Context([], [])};
  late Context Function(String) context;
  context = (symbol) {
    final known = memo[symbol];
    if (known != null) {
      return known;
    }
    final p = parents[symbol]!,
        outer = context(p.lhs),
        value = Context(
          [...outer.prefix, ...expandSequence(p.before, sentences)],
          [...expandSequence(p.after, sentences), ...outer.suffix],
        );
    memo[symbol] = value;
    return value;
  };
  for (final s in g.order) {
    context(s);
  }
  return memo;
}

List<String> setsFile(
  Grammar g,
  Sets sets,
  Map<String, List<String>> sentences,
) => [
  'passes: nullable=${sets.nullablePasses} first=${sets.firstPasses} follow=${sets.followPasses}',
  '',
  for (final lhs in g.order) ...[
    lhs,
    '  nullable: ${sets.nullable[lhs]! ? 'yes' : 'no'}',
    listLine('  first:', terminalOrder(sets.first[lhs]!)),
    listLine('  follow:', terminalOrder(sets.follow[lhs]!)),
    listLine('  shortest:', sentences[lhs]!),
  ],
];
List<int> firstPath(int start, String token, ParseTable table, Sets sets) {
  final byLhs = <String, List<int>>{};
  for (final p in table.productions) {
    byLhs.putIfAbsent(p.lhs, () => []).add(p.number);
  }
  final queue = <int>[start], parent = <int, int>{start: 0};
  for (var cursor = 0; cursor < queue.length; cursor++) {
    var current = queue[cursor];
    for (final symbol in table.productions[current - 1].rhs) {
      if (symbol == token) {
        final path = <int>[];
        while (current != start) {
          path.add(current);
          current = parent[current]!;
        }
        return path.reversed.toList();
      }
      if (isNonterminal(symbol)) {
        for (final number in byLhs[symbol]!) {
          if (!parent.containsKey(number)) {
            parent[number] = current;
            queue.add(number);
          }
        }
        if (!sets.nullable[symbol]!) {
          break;
        }
      } else {
        break;
      }
    }
  }
  return [];
}

List<int> followPath(
  String lhs,
  String token,
  Grammar g,
  ParseTable table,
  Sets sets,
) {
  final queue = <String>[lhs], paths = <String, List<int>>{lhs: []};
  for (var cursor = 0; cursor < queue.length; cursor++) {
    final symbol = queue[cursor], path = paths[symbol]!;
    if (symbol == g.start && token == endToken) {
      return path;
    }
    for (final p in table.productions) {
      for (var i = 0; i < p.rhs.length; i++) {
        if (p.rhs[i] != symbol) {
          continue;
        }
        final (more, empty) = firstSequence(
          p.rhs.sublist(i + 1),
          sets.nullable,
          sets.first,
        );
        final next = [...path, p.number];
        if (more.contains(token)) {
          return next;
        }
        if (empty && !paths.containsKey(p.lhs)) {
          paths[p.lhs] = next;
          queue.add(p.lhs);
        }
      }
    }
  }
  return [];
}

List<String> tableFile(Grammar g, Sets sets, ParseTable table, int before) {
  final lines = <String>['== predict sets =='];
  for (final p in table.productions) {
    lines.addAll([
      '${p.number}: ${p.notation}',
      listLine('  predict:', terminalOrder(p.predict.keys)),
    ]);
  }
  lines.addAll(['', '== parse table ==']);
  final tokens = [...sets.terminals, endToken],
      matrix = <List<String>>[
        ['', ...tokens],
      ];
  for (final lhs in g.order) {
    final row = <String>[lhs];
    for (final token in tokens) {
      final entries = table.cells[(lhs, token)] ?? [];
      row.add(entries.isEmpty ? '.' : entries.map((e) => e.number).join('/'));
    }
    matrix.add(row);
  }
  final widths = List.filled(tokens.length + 1, 0);
  for (final row in matrix) {
    for (var i = 0; i < row.length; i++) {
      widths[i] = max(widths[i], row[i].length);
    }
  }
  for (final row in matrix) {
    var line = row[0].padRight(widths[0]);
    for (var i = 1; i < row.length; i++) {
      line += '  ${row[i].padLeft(widths[i])}';
    }
    lines.add(line);
  }
  lines.addAll(['', '== conflicts ==']);
  if (table.conflicts.isEmpty) {
    lines.add('none');
  }
  for (final conflict in table.conflicts) {
    lines.add(
      'conflict ${conflict.lhs} on ${conflict.token}: ${conflict.kind}, chosen ${conflict.chosen}',
    );
    for (final entry in conflict.entries) {
      final p = table.productions[entry.number - 1],
          path = entry.reason == 'FIRST'
              ? firstPath(entry.number, conflict.token, table, sets)
              : followPath(conflict.lhs, conflict.token, g, table, sets);
      final reason = path.isEmpty
          ? entry.reason
          : listLine('${entry.reason} via', intStrings(path));
      lines.add('  ${entry.number}: ${p.notation} ($reason)');
    }
  }
  lines.addAll([
    'LL(1): ${table.conflicts.isEmpty ? 'yes' : 'no'}',
    'conflicts before transformation: $before',
  ]);
  return lines;
}

TreeNode compactTree(TreeNode node) {
  final children = <TreeNode>[];
  for (final original in node.children) {
    if (original.symbol == '%empty') {
      continue;
    }
    final child = compactTree(original);
    if (isNonterminal(child.symbol) &&
        child.mark.isEmpty &&
        child.children.isEmpty) {
      continue;
    }
    if (isNonterminal(child.symbol) &&
        child.symbol.contains("'") &&
        child.mark.isEmpty) {
      children.addAll(child.children);
    } else {
      children.add(child);
    }
  }
  return children.length == 1 && node.mark.isEmpty
      ? children.first
      : TreeNode(node.symbol, mark: node.mark, children: children);
}

List<String> treeLines(TreeNode root) {
  final lines = <String>[treeLabel(root)];
  void visit(TreeNode node, String prefix, bool last) {
    lines.add('$prefix${last ? '`-- ' : '|-- '}${treeLabel(node)}');
    final next = '$prefix${last ? '    ' : '|   '}';
    for (var i = 0; i < node.children.length; i++) {
      visit(node.children[i], next, i == node.children.length - 1);
    }
  }

  for (var i = 0; i < root.children.length; i++) {
    visit(root.children[i], '', i == root.children.length - 1);
  }
  return lines;
}

List<String> traceLines(List<List<String>> trace) {
  final rows = <List<String>>[
        ['step', 'stack', 'input', 'action'],
        ...trace,
      ],
      widths = List.filled(3, 0);
  for (final row in rows) {
    for (var i = 0; i < 3; i++) {
      widths[i] = max(widths[i], row[i].length);
    }
  }
  return [
    for (final row in rows)
      '${row[0].padRight(widths[0])}  ${row[1].padRight(widths[1])}  ${row[2].padRight(widths[2])}  ${row[3]}',
  ];
}

List<String> leftmostDerivation(
  String start,
  List<int> numbers,
  List<Production> productions,
) {
  var symbols = <String>[start];
  final lines = <String>['  $start'];
  for (final number in numbers) {
    final position = symbols.indexWhere(isNonterminal);
    symbols = [
      ...symbols.take(position),
      ...productions[number - 1].rhs,
      ...symbols.skip(position + 1),
    ];
    lines.add('  => ${notation(symbols)}');
  }
  return lines;
}

typedef EarleyState = (int, int, int);
bool recognizeLanguage(Grammar g, List<String> tokens) {
  final productions = <Production>[
        Production(0, '<__root>', [g.start]),
        ...numberProductions(g),
      ],
      byLhs = <String, List<int>>{};
  for (var i = 1; i < productions.length; i++) {
    byLhs.putIfAbsent(productions[i].lhs, () => []).add(i);
  }
  final chart = List.generate(tokens.length + 1, (_) => <EarleyState>{}),
      pending = List.generate(tokens.length + 1, (_) => <EarleyState>[]);
  void add(int position, EarleyState state) {
    if (chart[position].add(state)) {
      pending[position].add(state);
    }
  }

  add(0, (0, 0, 0));
  for (var position = 0; position <= tokens.length; position++) {
    for (var cursor = 0; cursor < pending[position].length; cursor++) {
      final state = pending[position][cursor], p = productions[state.$1];
      if (state.$2 == p.rhs.length) {
        for (final waiting in List<EarleyState>.of(pending[state.$3])) {
          final body = productions[waiting.$1].rhs;
          if (waiting.$2 < body.length && body[waiting.$2] == p.lhs) {
            add(position, (waiting.$1, waiting.$2 + 1, waiting.$3));
          }
        }
      } else {
        final symbol = p.rhs[state.$2];
        if (isNonterminal(symbol)) {
          for (final number in byLhs[symbol]!) {
            add(position, (number, 0, position));
          }
          for (final done in List<EarleyState>.of(pending[position])) {
            final completed = productions[done.$1];
            if (completed.lhs == symbol &&
                done.$2 == completed.rhs.length &&
                done.$3 == position) {
              add(position, (state.$1, state.$2 + 1, state.$3));
            }
          }
        } else if (position < tokens.length && symbol == tokens[position]) {
          add(position + 1, (state.$1, state.$2 + 1, state.$3));
        }
      }
    }
  }
  return chart[tokens.length].contains((0, 1, 0));
}

ParseResult parseInput(
  List<String> tokens,
  Grammar g,
  Sets sets,
  ParseTable table,
) {
  final known = sets.terminals.toSet(),
      kept = <InputToken>[],
      unknown = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (known.contains(token)) {
      kept.add((token, i + 1));
    } else {
      unknown.add('unknown "$token" at token ${i + 1}; removed');
    }
  }
  final result = parseTokens(kept, g, sets, table);
  result.original.addAll(tokens);
  result.unknownErrors.addAll(unknown);
  result.accepted = unknown.isEmpty && result.errors.isEmpty;
  return result;
}

List<String> oneParseReport(
  int index,
  ParseResult p,
  Grammar g,
  ParseTable table,
) {
  final errors = [...p.unknownErrors, ...p.errors],
      lines = <String>[
        '== input $index ==',
        listLine('tokens:', p.original),
        ...traceLines(p.trace),
        listLine('left parse:', intStrings(p.leftParse)),
        'stats: steps=${p.trace.length} predicts=${p.predicts} matches=${p.matches} max_stack=${p.maxStack}',
      ];
  if (errors.isNotEmpty) {
    lines.addAll(['errors:', for (final error in errors) '  $error']);
  }
  lines.addAll([
    p.accepted
        ? 'result: accepted'
        : 'result: rejected (errors: ${errors.length})',
    'language: ${p.language ? 'yes' : 'no'}',
  ]);
  if (p.accepted) {
    lines.addAll([
      'derivation:',
      ...leftmostDerivation(g.start, p.leftParse, table.productions),
    ]);
  }
  lines.addAll([
    'tree:',
    ...treeLines(p.root),
    'compact tree:',
    ...treeLines(compactTree(p.root)),
  ]);
  return lines;
}

List<String> parseReport(
  List<ParseResult> inputs,
  Grammar g,
  Sets sets,
  ParseTable table,
  Map<String, List<String>> sentences,
  Map<String, Context> contexts,
) {
  final lines = <String>[], mismatches = <int>[], used = <int>{};
  var accepted = 0, inLanguage = 0, unknown = 0, skip = 0, pop = 0, missing = 0;
  for (var i = 0; i < inputs.length; i++) {
    final p = inputs[i];
    lines.addAll([...oneParseReport(i + 1, p, g, table), '']);
    if (p.accepted) {
      accepted++;
    }
    if (p.language) {
      inLanguage++;
    }
    if (p.accepted != p.language) {
      mismatches.add(i + 1);
    }
    unknown += p.unknownErrors.length;
    skip += p.skip;
    pop += p.pop;
    missing += p.missing;
    used.addAll(p.leftParse);
  }
  final unused = [
    for (final p in table.productions)
      if (!used.contains(p.number)) p.number,
  ];
  lines.addAll([
    '== summary ==',
    'inputs=${inputs.length} accepted=$accepted rejected=${inputs.length - accepted} in_language=$inLanguage',
    listLine('mismatches:', intStrings(mismatches)),
    'recovery: unknown=$unknown skip=$skip pop=$pop missing=$missing',
    'coverage: ${used.length} of ${table.productions.length} productions used',
    listLine('unused:', intStrings(unused)),
  ]);
  for (final number in unused) {
    final p = table.productions[number - 1],
        context = contexts[p.lhs]!,
        sentence = [
          ...context.prefix,
          ...expandSequence(p.rhs, sentences),
          ...context.suffix,
        ];
    final parsed = parseTokens(
          [for (var i = 0; i < sentence.length; i++) (sentence[i], i + 1)],
          g,
          sets,
          table,
        ),
        errors = parsed.skip + parsed.pop + parsed.missing;
    lines.addAll([
      '  $number: ${p.notation}',
      listLine('    example:', sentence),
      errors == 0
          ? '    result: accepted'
          : '    result: rejected (errors: $errors)',
      '    used: ${parsed.leftParse.contains(number) ? 'yes' : 'no'}',
    ]);
  }
  return lines;
}

void save(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

void main() {
  final source = parseGrammar(), declarations = checkDeclarations(source);
  final (cleaned, cleanDiags) = cleanGrammar(source);
  final recursionDiags = recursionDiagnostics(cleaned);
  final (recursion, recursionLog) = eliminateLeftRecursion(cleaned);
  final (factored, factoringLog) = leftFactor(recursion);
  final (finalGrammar, finalLog, finalDiags) = finalPruning(factored);
  final unusedDiags = unusedDeclarations(source, finalGrammar),
      beforeSets = analyzeSets(cleaned),
      beforeTable = buildTable(cleaned, beforeSets),
      sets = analyzeSets(finalGrammar),
      table = buildTable(finalGrammar, sets);
  final (scores, sentences) = shortestSentences(finalGrammar);
  final contexts = shortestContexts(finalGrammar, scores, sentences),
      inputs = <ParseResult>[];
  for (final line in readLines('input/inputs.txt')) {
    final tokens = line.isEmpty ? <String>[] : line.split(' '),
        parsed = parseInput(tokens, finalGrammar, sets, table);
    parsed.language = recognizeLanguage(cleaned, tokens);
    inputs.add(parsed);
  }
  final diagnostics = [
    ...source.diagnostics,
    ...declarations,
    ...cleanDiags,
    ...recursionDiags,
    ...finalDiags,
    ...unusedDiags,
    table.conflicts.isEmpty
        ? 'result: LL(1)'
        : 'result: not LL(1) (conflicts: ${table.conflicts.length})',
  ];
  save(
    'grammar.txt',
    grammarFile(
      cleaned,
      recursion,
      factored,
      finalGrammar,
      recursionLog,
      factoringLog,
      finalLog,
    ),
  );
  save('sets.txt', setsFile(finalGrammar, sets, sentences));
  save(
    'table.txt',
    tableFile(finalGrammar, sets, table, beforeTable.conflicts.length),
  );
  save(
    'parses.txt',
    parseReport(inputs, finalGrammar, sets, table, sentences, contexts),
  );
  save('diagnostics.txt', diagnostics);
}
