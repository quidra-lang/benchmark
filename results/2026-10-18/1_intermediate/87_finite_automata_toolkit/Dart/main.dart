import 'dart:io';

typedef Triple = (int, String, int);
typedef Pair = (int, int);

class CommandError implements Exception {
  final String reason;
  CommandError(this.reason);
}
Never fail(String reason) => throw CommandError(reason);
List<String> sequence(String prefix, int count) => List.generate(count, (i) => '$prefix$i');
List<int> ordered(Iterable<int> values) => values.toList()..sort();
String subsetKey(Iterable<int> values) => ordered(values).join(',');
String stripRight(String text) {
  int end = text.length;
  while (end > 0 && text[end - 1] == ' ') end--;
  return text.substring(0, end);
}

class Automaton {
  final String kind;
  final List<String> names, alphabet;
  final int start;
  final Set<int> accepting;
  final List<Map<String, Set<int>>> rows;
  List<Set<int>>? closures;
  Determinization? determinized;
  Automaton(this.kind, List<String> names, Iterable<String> alphabet, this.start, [Iterable<int> accepting = const []])
      : names = List.of(names), alphabet = alphabet.toList()..sort(), accepting = accepting.toSet(),
        rows = List.generate(names.length, (_) => <String, Set<int>>{});
  void add(int from, String symbol, int to) => rows[from].putIfAbsent(symbol, () => <int>{}).add(to);
  Set<int> targets(int from, String symbol) => rows[from][symbol] ?? <int>{};
  int delta(int from, String symbol) => targets(from, symbol).first;
  List<Triple> triples() {
    final result = <Triple>[];
    for (int p = 0; p < names.length; p++) {
      for (final symbol in [...alphabet, 'e']) {
        for (final q in ordered(targets(p, symbol))) { result.add((p, symbol, q)); }
      }
    }
    return result;
  }
  String summary(String name) {
    int transitions = 0;
    for (final row in rows) { for (final values in row.values) { transitions += values.length; } }
    return '$kind $name: alphabet=${alphabet.join()} states=${names.length} accepting=${accepting.length} transitions=$transitions';
  }
  String notation(Iterable<int> states) => '{${ordered(states).map((i) => names[i]).join(',')}}';
  String list(Iterable<int> states) {
    final text = ordered(states).map((i) => names[i]).join(',');
    return text.isEmpty ? 'none' : text;
  }
  Set<int> closure(Iterable<int> states) {
    closures ??= List.generate(names.length, (start) {
      final seen = <int>{start}, queue = <int>[start];
      for (int i = 0; i < queue.length; i++) {
        for (final q in targets(queue[i], 'e')) { if (seen.add(q)) queue.add(q); }
      }
      return seen;
    });
    final result = <int>{};
    for (final p in states) { result.addAll(closures![p]); }
    return result;
  }
  Set<int> destination(Iterable<int> states, String symbol) {
    final moved = <int>{};
    for (final p in states) { moved.addAll(targets(p, symbol)); }
    return closure(moved);
  }
  bool accepts(Iterable<int> states) => states.any(accepting.contains);
}

class Determinization {
  final Automaton automaton;
  final List<Set<int>> sets;
  Determinization(this.automaton, this.sets);
}
class Minimization {
  final Automaton automaton;
  final List<List<List<int>>> rounds;
  final List<List<int>> blocks;
  final List<int> unreachable;
  Minimization(this.automaton, this.rounds, this.blocks, this.unreachable);
}
class Product {
  final Automaton automaton;
  final List<Pair> pairs;
  Product(this.automaton, this.pairs);
}

Determinization determinize(Automaton source) {
  final cached = source.determinized;
  if (cached != null) return cached;
  final sets = <Set<int>>[source.closure([source.start])], transitions = <Triple>[];
  final indices = <String, int>{subsetKey(sets[0]): 0};
  for (int i = 0; i < sets.length; i++) {
    for (final symbol in source.alphabet) {
      final next = source.destination(sets[i], symbol), key = subsetKey(next);
      if (!indices.containsKey(key)) { indices[key] = sets.length; sets.add(next); }
      transitions.add((i, symbol, indices[key]!));
    }
  }
  final accepting = <int>[];
  for (int i = 0; i < sets.length; i++) { if (source.accepts(sets[i])) accepting.add(i); }
  final result = Automaton('DFA', sequence('D', sets.length), source.alphabet, 0, accepting);
  for (final (p, symbol, q) in transitions) { result.add(p, symbol, q); }
  return source.determinized = Determinization(result, sets);
}

Set<int> graphReach(Automaton source, [bool reverse = false]) {
  final edges = List.generate(source.names.length, (_) => <int>{});
  for (final (p, _, q) in source.triples()) { edges[reverse ? q : p].add(reverse ? p : q); }
  final seen = reverse ? Set<int>.of(source.accepting) : <int>{source.start}, queue = <int>[];
  queue.addAll(seen);
  for (int i = 0; i < queue.length; i++) { for (final q in edges[queue[i]]) { if (seen.add(q)) queue.add(q); } }
  return seen;
}

Minimization minimize(Automaton source) {
  final reachable = graphReach(source), states = ordered(reachable);
  var blocks = <List<int>>[states.where(source.accepting.contains).toList(), states.where((p) => !source.accepting.contains(p)).toList()]
      .where((block) => block.isNotEmpty).toList()..sort((a, b) => a.first.compareTo(b.first));
  final rounds = <List<List<int>>>[blocks];
  while (true) {
    final membership = <int, int>{};
    for (int i = 0; i < blocks.length; i++) { for (final p in blocks[i]) { membership[p] = i; } }
    final groups = <String, List<int>>{};
    for (final p in states) {
      final key = [membership[p]!, ...source.alphabet.map((symbol) => membership[source.delta(p, symbol)]!)].join(',');
      groups.putIfAbsent(key, () => <int>[]).add(p);
    }
    final next = groups.values.toList();
    if (next.length == blocks.length) break;
    blocks = next;
    rounds.add(blocks);
  }
  final membership = <int, int>{};
  for (int i = 0; i < blocks.length; i++) { for (final p in blocks[i]) { membership[p] = i; } }
  final order = <int>[membership[source.start]!], transitions = <Triple>[];
  final indices = <int, int>{order[0]: 0};
  for (int i = 0; i < order.length; i++) {
    for (final symbol in source.alphabet) {
      final next = membership[source.delta(blocks[order[i]][0], symbol)]!;
      if (!indices.containsKey(next)) { indices[next] = order.length; order.add(next); }
      transitions.add((i, symbol, indices[next]!));
    }
  }
  final accepting = <int>[];
  for (int i = 0; i < order.length; i++) { if (source.accepting.contains(blocks[order[i]][0])) accepting.add(i); }
  final result = Automaton('DFA', sequence('M', order.length), source.alphabet, 0, accepting);
  for (final (p, symbol, q) in transitions) { result.add(p, symbol, q); }
  return Minimization(result, rounds, order.map((i) => blocks[i]).toList(),
      List.generate(source.names.length, (i) => i).where((i) => !reachable.contains(i)).toList());
}

({String kind, int count}) language(Automaton source, [bool countWords = false]) {
  final dfa = determinize(source).automaton, live = graphReach(dfa, true);
  if (!live.contains(dfa.start)) return (kind: 'empty', count: 0);
  final color = List.filled(dfa.names.length, 0), postorder = <int>[];
  bool infinite = false;
  void visit(int p) {
    if (!live.contains(p)) return;
    if (color[p] == 1) { infinite = true; return; }
    if (color[p] == 2) return;
    color[p] = 1;
    for (final symbol in dfa.alphabet) { visit(dfa.delta(p, symbol)); }
    color[p] = 2;
    postorder.add(p);
  }
  visit(dfa.start);
  if (infinite) return (kind: 'infinite', count: 0);
  if (!countWords) return (kind: 'finite', count: 0);
  final totals = List.filled(dfa.names.length, 0);
  for (final p in postorder) {
    totals[p] = dfa.accepting.contains(p) ? 1 : 0;
    for (final symbol in dfa.alphabet) { totals[p] += totals[dfa.delta(p, symbol)]; }
  }
  return (kind: 'finite', count: totals[dfa.start]);
}

String? smallest(Automaton source) {
  final dfa = determinize(source).automaton, queue = <(int, String)>[(dfa.start, '')], seen = <int>{dfa.start};
  for (int i = 0; i < queue.length; i++) {
    final (state, word) = queue[i];
    if (dfa.accepting.contains(state)) return word;
    for (final symbol in dfa.alphabet) {
      final next = dfa.delta(state, symbol);
      if (seen.add(next)) queue.add((next, word + symbol));
    }
  }
  return null;
}

sealed class RegexTree {}
class RegexSymbol extends RegexTree {
  final String symbol;
  RegexSymbol(this.symbol);
}
class RegexMany extends RegexTree {
  final String kind;
  final List<RegexTree> children;
  RegexMany(this.kind, this.children);
}
class RegexPostfix extends RegexTree {
  final String op;
  final RegexTree child;
  RegexPostfix(this.op, this.child);
}
class RegexParser {
  final String text;
  int position = 0;
  RegexParser(this.text);
  String get peek => position < text.length ? text[position] : '';
  bool atomStart() => peek.isNotEmpty && RegExp(r'[a-z0-9(]').hasMatch(peek);
  Never error() => fail('syntax error at ${position + 1}');
  RegexTree atom() {
    final symbol = peek;
    if (symbol.isNotEmpty && RegExp(r'[a-z0-9]').hasMatch(symbol)) { position++; return RegexSymbol(symbol); }
    if (symbol == '(') {
      position++;
      final result = alternation();
      if (peek != ')') error();
      position++;
      return result;
    }
    error();
  }
  RegexTree factor() {
    var result = atom();
    while (peek.isNotEmpty && '*+?'.contains(peek)) {
      final op = peek;
      position++;
      result = RegexPostfix(op, result);
    }
    return result;
  }
  RegexTree concatenation() {
    final children = <RegexTree>[factor()];
    while (atomStart()) { children.add(factor()); }
    return children.length == 1 ? children[0] : RegexMany('concat', children);
  }
  RegexTree alternation() {
    final children = <RegexTree>[concatenation()];
    while (peek == '|') { position++; children.add(concatenation()); }
    return children.length == 1 ? children[0] : RegexMany('alternate', children);
  }
  RegexTree parse() {
    final result = alternation();
    if (position != text.length) error();
    return result;
  }
}

Automaton fromRegex(Iterable<String> alphabet, RegexTree tree) {
  int count = 0;
  final transitions = <Triple>[];
  Pair build(RegexTree node) {
    if (node is RegexSymbol) {
      final start = count++, finish = count++;
      transitions.add((start, node.symbol, finish));
      return (start, finish);
    }
    if (node is RegexMany && node.kind == 'concat') {
      final parts = node.children.map(build).toList();
      for (int i = 1; i < parts.length; i++) { transitions.add((parts[i - 1].$2, 'e', parts[i].$1)); }
      return (parts.first.$1, parts.last.$2);
    }
    final start = count++;
    if (node is RegexMany) {
      final parts = node.children.map(build).toList(), finish = count++;
      for (final (s, f) in parts) { transitions.addAll([(start, 'e', s), (f, 'e', finish)]); }
      return (start, finish);
    }
    final postfix = node as RegexPostfix, part = build(postfix.child), finish = count++;
    transitions.addAll([(start, 'e', part.$1), (part.$2, 'e', finish)]);
    if (postfix.op != '?') transitions.add((part.$2, 'e', part.$1));
    if (postfix.op != '+') transitions.add((start, 'e', finish));
    return (start, finish);
  }
  final part = build(tree), result = Automaton('NFA', sequence('N', count), alphabet, part.$1, [part.$2]);
  for (final (p, symbol, q) in transitions) { result.add(p, symbol, q); }
  return result;
}

Product product(Automaton left, Automaton right, String operation) {
  final pairs = <Pair>[(left.start, right.start)], transitions = <Triple>[];
  final indices = <Pair, int>{pairs[0]: 0};
  for (int i = 0; i < pairs.length; i++) {
    for (final symbol in left.alphabet) {
      final next = (left.delta(pairs[i].$1, symbol), right.delta(pairs[i].$2, symbol));
      if (!indices.containsKey(next)) { indices[next] = pairs.length; pairs.add(next); }
      transitions.add((i, symbol, indices[next]!));
    }
  }
  final accepting = <int>[];
  for (int i = 0; i < pairs.length; i++) {
    final a = left.accepting.contains(pairs[i].$1), b = right.accepting.contains(pairs[i].$2);
    if (operation == 'UNION' ? a || b : operation == 'INTERSECT' ? a && b : a && !b) accepting.add(i);
  }
  final result = Automaton('DFA', sequence('P', pairs.length), left.alphabet, 0, accepting);
  for (final (p, symbol, q) in transitions) { result.add(p, symbol, q); }
  return Product(result, pairs);
}

({String word, bool left})? distinguishing(Automaton left, Automaton right) {
  final a = determinize(left).automaton, b = determinize(right).automaton;
  final queue = <(int, int, String)>[(a.start, b.start, '')], seen = <Pair>{(a.start, b.start)};
  for (int i = 0; i < queue.length; i++) {
    final (p, q, word) = queue[i];
    if (a.accepting.contains(p) != b.accepting.contains(q)) return (word: word, left: a.accepting.contains(p));
    for (final symbol in a.alphabet) {
      final next = (a.delta(p, symbol), b.delta(q, symbol));
      if (seen.add(next)) queue.add((next.$1, next.$2, word + symbol));
    }
  }
  return null;
}

Automaton combine(Automaton source, Automaton? other, String operation) {
  final count = source.names.length, extra = operation == 'CONCAT' ? other!.names.length : 1;
  final offset = operation == 'CONCAT' ? 0 : 1, start = operation == 'CONCAT' ? source.start : 0;
  final accepting = operation == 'REVERSE' ? [source.start + 1] : operation == 'STAR'
      ? [0, ...source.accepting.map((p) => p + 1)] : other!.accepting.map((p) => p + count);
  final result = Automaton('NFA', sequence('N', count + extra), source.alphabet, start, accepting);
  for (final (p, symbol, q) in source.triples()) {
    if (operation == 'REVERSE') { result.add(q + 1, symbol, p + 1); }
    else { result.add(p + offset, symbol, q + offset); }
  }
  if (operation == 'REVERSE') {
    for (final p in source.accepting) { result.add(0, 'e', p + 1); }
  } else if (operation == 'STAR') {
    result.add(0, 'e', source.start + 1);
    for (final p in source.accepting) { result.add(p + 1, 'e', source.start + 1); }
  } else {
    final right = other!;
    for (final (p, symbol, q) in right.triples()) { result.add(p + count, symbol, q + count); }
    for (final p in source.accepting) { result.add(p, 'e', right.start + count); }
  }
  return result;
}

const roles = <String, String>{
  'ACCEPT': 'RO', 'CLOSURE': 'RO', 'ENUM': 'RO', 'COUNT': 'RO', 'TODFA': 'RN', 'EPSFREE': 'RN',
  'REVERSE': 'RN', 'STAR': 'RN', 'MINIMIZE': 'DN', 'COMPLEMENT': 'DN', 'EQUIV': 'RR',
  'UNION': 'DDN', 'INTERSECT': 'DDN', 'DIFF': 'DDN', 'CONCAT': 'RRN', 'EMPTY': 'R', 'FINITE': 'R',
  'INFO': 'R', 'TABLE': 'R', 'SHOW': 'R', 'DELETE': 'R', 'SYNC': 'D', 'LIST': '',
};

class Toolkit {
  final table = <String, Automaton>{};
  List<String> register(String name, Automaton source, [List<String> details = const []]) {
    table[name] = source;
    return [source.summary(name), ...details];
  }
  List<String> define(String kind, List<String> args) {
    if (args.length < 5) fail('wrong number of arguments');
    final name = args[0], names = args[1].split(','), alphabet = args[2], startName = args[3], acceptingText = args[4];
    if (table.containsKey(name)) fail('$name already exists');
    final index = <String, int>{};
    for (int i = 0; i < names.length; i++) {
      if (index.containsKey(names[i])) fail('duplicate state ${names[i]}');
      index[names[i]] = i;
    }
    if (!index.containsKey(startName)) fail('unknown state $startName');
    final accepting = <int>{};
    if (acceptingText != '-') {
      for (final state in acceptingText.split(',')) {
        if (!index.containsKey(state)) fail('unknown state $state');
        if (!accepting.add(index[state]!)) fail('duplicate state $state');
      }
    }
    final result = Automaton(kind, names, alphabet.split(''), index[startName]!, accepting), seen = <String>{};
    for (final word in args.skip(5)) {
      final parts = word.split(':'), p = parts[0], symbol = parts[1], q = parts[2];
      if (!index.containsKey(p)) fail('unknown state $p');
      if (symbol == 'e' && kind == 'DFA') fail('epsilon transition in DFA');
      if (symbol != 'e' && !result.alphabet.contains(symbol)) fail('unknown symbol $symbol');
      if (!index.containsKey(q)) fail('unknown state $q');
      if (seen.contains(word)) fail('duplicate transition $word');
      if (kind == 'DFA' && result.targets(index[p]!, symbol).isNotEmpty) fail('conflicting transition $word');
      seen.add(word);
      result.add(index[p]!, symbol, index[q]!);
    }
    if (kind == 'DFA') {
      for (int p = 0; p < names.length; p++) {
        for (final symbol in result.alphabet) { if (result.targets(p, symbol).isEmpty) fail('missing transition ${names[p]}:$symbol'); }
      }
    }
    return register(name, result);
  }
  List<String> command(String line) {
    final words = line.split(' '), command = words[0], args = words.sublist(1);
    if (command == 'DFA' || command == 'NFA') return define(command, args);
    if (command == 'REGEX') {
      if (args.length != 3) fail('wrong number of arguments');
      final name = args[0], alphabet = args[1], text = args[2];
      if (table.containsKey(name)) fail('$name already exists');
      for (final symbol in text.split('')) {
        if (RegExp(r'[a-z0-9]').hasMatch(symbol) && symbol != 'e' && !alphabet.contains(symbol)) fail('unknown symbol $symbol');
      }
      return register(name, fromRegex(alphabet.split(''), RegexParser(text).parse()));
    }
    if (!roles.containsKey(command)) fail('unknown command $command');
    final kinds = roles[command]!;
    if (args.length != kinds.length) fail('wrong number of arguments');
    for (int i = 0; i < kinds.length; i++) {
      if ('RD'.contains(kinds[i]) && !table.containsKey(args[i])) fail('unknown automaton ${args[i]}');
    }
    final newIndex = kinds.indexOf('N');
    if (newIndex >= 0 && table.containsKey(args[newIndex])) fail('${args[newIndex]} already exists');
    for (int i = 0; i < kinds.length; i++) {
      if (kinds[i] == 'D' && table[args[i]]!.kind != 'DFA') fail('${args[i]} is not a DFA');
    }
    if (command == 'LIST') return table.isEmpty ? ['(none)'] : table.entries.map((item) => item.value.summary(item.key)).toList();
    final source = table[args[0]]!;
    final other = kinds.length > 1 && 'RD'.contains(kinds[1]) ? table[args[1]]! : null;
    if (other != null && source.alphabet.join() != other.alphabet.join()) fail('alphabets differ');
    switch (command) {
      case 'DELETE': table.remove(args[0]); return ['deleted ${args[0]}'];
      case 'ACCEPT':
        final word = args[1] == 'e' ? '' : args[1];
        for (final symbol in word.split('')) { if (!source.alphabet.contains(symbol)) fail('unknown symbol $symbol'); }
        var states = source.closure([source.start]);
        String notation(Set<int> set) => source.kind == 'DFA' ? source.names[set.first] : source.notation(set);
        var path = notation(states);
        for (final symbol in word.split('')) { states = source.destination(states, symbol); path += ' -$symbol-> ${notation(states)}'; }
        return ['${source.accepts(states) ? 'ACCEPT' : 'REJECT'} $path'];
      case 'CLOSURE':
        final states = <int>[];
        for (final name in args[1].split(',')) {
          final i = source.names.indexOf(name);
          if (i < 0) fail('unknown state $name');
          states.add(i);
        }
        return [source.notation(source.closure(states))];
      case 'TODFA':
        final result = determinize(source), details = <String>[];
        for (int i = 0; i < result.sets.length; i++) { details.add('  D$i = ${source.notation(result.sets[i])}'); }
        return register(args[1], result.automaton, details);
      case 'EPSFREE':
        final result = Automaton('NFA', source.names, source.alphabet, source.start);
        for (int p = 0; p < source.names.length; p++) {
          final set = source.closure([p]);
          if (source.accepts(set)) result.accepting.add(p);
          for (final symbol in source.alphabet) { for (final q in source.destination(set, symbol)) { result.add(p, symbol, q); } }
        }
        return register(args[1], result);
      case 'MINIMIZE':
        final result = minimize(source), details = ['  unreachable: ${source.list(result.unreachable)}'];
        for (int i = 0; i < result.rounds.length; i++) { details.add('  round $i: ${result.rounds[i].map(source.notation).join(' ')}'); }
        for (int i = 0; i < result.blocks.length; i++) { details.add('  M$i = ${source.notation(result.blocks[i])}'); }
        return register(args[1], result.automaton, details);
      case 'EQUIV':
        final result = distinguishing(source, other!);
        return [result == null ? 'EQUIVALENT' : 'NOT EQUIVALENT: ${result.word.isEmpty ? 'e' : result.word} is accepted only by ${args[result.left ? 0 : 1]}'];
      case 'UNION': case 'INTERSECT': case 'DIFF':
        final right = other!, result = product(source, right, command), details = <String>[];
        for (int i = 0; i < result.pairs.length; i++) {
          final (p, q) = result.pairs[i];
          details.add('  P$i = (${source.names[p]},${right.names[q]})');
        }
        return register(args[2], result.automaton, details);
      case 'COMPLEMENT':
        final result = Automaton('DFA', source.names, source.alphabet, source.start,
            List.generate(source.names.length, (i) => i).where((i) => !source.accepting.contains(i)));
        for (final (p, symbol, q) in source.triples()) { result.add(p, symbol, q); }
        return register(args[1], result);
      case 'REVERSE': case 'STAR': case 'CONCAT': return register(args[newIndex], combine(source, other, command));
      case 'COUNT':
        final dfa = determinize(source).automaton, length = int.parse(args[1]);
        var counts = List.filled(dfa.names.length, 0);
        counts[dfa.start] = 1;
        for (int i = 0; i < length; i++) {
          final next = List.filled(dfa.names.length, 0);
          for (int p = 0; p < counts.length; p++) { for (final symbol in dfa.alphabet) { next[dfa.delta(p, symbol)] += counts[p]; } }
          counts = next;
        }
        return ['${dfa.accepting.fold<int>(0, (sum, p) => sum + counts[p])}'];
      case 'ENUM':
        final dfa = determinize(source).automaton, accepted = <String>[], maximum = int.parse(args[1]);
        var level = <(int, String)>[(dfa.start, '')];
        int total = 0;
        for (int length = 0; length <= maximum; length++) {
          for (final (state, word) in level) {
            if (dfa.accepting.contains(state)) { total++; if (accepted.length < 50) accepted.add(word.isEmpty ? 'e' : word); }
          }
          if (length < maximum) {
            level = [for (final (state, word) in level) for (final symbol in dfa.alphabet) (dfa.delta(state, symbol), word + symbol)];
          }
        }
        return ['$total${accepted.isEmpty ? '' : ' ${accepted.join(' ')}'}${total > 50 ? ' ...' : ''}'];
      case 'EMPTY':
        final word = smallest(source);
        return [word == null ? 'EMPTY' : 'NOT EMPTY ${word.isEmpty ? 'e' : word}'];
      case 'FINITE':
        final result = language(source, true);
        return [result.kind == 'infinite' ? 'INFINITE' : 'FINITE ${result.count}'];
      case 'SYNC':
        final initial = (1 << source.names.length) - 1, seen = <int>{initial}, queue = <(int, String)>[(initial, '')];
        for (int i = 0; i < queue.length; i++) {
          final (set, word) = queue[i];
          if ((set & (set - 1)) == 0) return ['SYNCHRONIZING ${word.isEmpty ? 'e' : word} -> ${source.names[set.bitLength - 1]}'];
          for (final symbol in source.alphabet) {
            int next = 0;
            for (int p = 0; p < source.names.length; p++) { if ((set & (1 << p)) != 0) next |= 1 << source.delta(p, symbol); }
            if (seen.add(next)) queue.add((next, word + symbol));
          }
        }
        return ['NOT SYNCHRONIZING'];
      case 'INFO':
        int epsilon = 0;
        for (int p = 0; p < source.names.length; p++) { epsilon += source.targets(p, 'e').length; }
        bool deterministic = epsilon == 0, complete = true;
        for (int p = 0; p < source.names.length; p++) {
          for (final symbol in source.alphabet) {
            final size = source.targets(p, symbol).length;
            if (size > 1) deterministic = false;
            if (size == 0) complete = false;
          }
        }
        return [source.summary(args[0]), '  epsilon transitions: $epsilon', '  reachable: ${source.list(graphReach(source))}',
          '  live: ${source.list(graphReach(source, true))}', '  deterministic: ${deterministic ? 'yes' : 'no'}',
          '  complete: ${complete ? 'yes' : 'no'}', '  language: ${language(source).kind}',
          '  minimal DFA states: ${minimize(determinize(source).automaton).automaton.names.length}'];
      case 'TABLE':
        final columns = List<String>.of(source.alphabet);
        if (source.kind == 'NFA' && source.rows.asMap().keys.any((p) => source.targets(p, 'e').isNotEmpty)) columns.add('e');
        final rows = <List<String>>[['', ...columns]];
        for (int p = 0; p < source.names.length; p++) {
          rows.add(['${p == source.start ? '->' : '  '}${source.accepting.contains(p) ? '*' : ' '}${source.names[p]}',
            ...columns.map((symbol) => source.kind == 'DFA' ? source.names[source.delta(p, symbol)]
                : source.targets(p, symbol).isEmpty ? '-' : source.notation(source.targets(p, symbol)))]);
        }
        final widths = List.filled(rows[0].length, 0);
        for (final row in rows) { for (int i = 0; i < row.length; i++) { if (row[i].length > widths[i]) widths[i] = row[i].length; } }
        return rows.map((row) => stripRight([for (int i = 0; i < row.length; i++) row[i].padRight(widths[i])].join('  '))).toList();
      case 'SHOW':
        final accepting = ordered(source.accepting).map((p) => source.names[p]).join(',');
        return [[source.kind, args[0], source.names.join(','), source.alphabet.join(), source.names[source.start], accepting.isEmpty ? '-' : accepting,
          ...source.triples().map((t) => '${source.names[t.$1]}:${t.$2}:${source.names[t.$3]}')].join(' ')];
    }
    throw StateError('unhandled command');
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!), toolkit = Toolkit(), output = <String>[];
  for (int i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    if (line.startsWith('#')) continue;
    try { output.addAll(toolkit.command(line)); }
    on CommandError catch (error) { output.add('error: ${error.reason}'); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
