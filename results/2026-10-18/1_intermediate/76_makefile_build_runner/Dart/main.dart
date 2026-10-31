import 'dart:io';
import 'dart:math' as math;

class MakeError implements Exception {
  final String message;
  MakeError(String location, String reason) : message = '$location: *** $reason.  Stop.';
}
class BuildAbort implements Exception {}
class Variable {
  final String kind;
  String value;
  Variable(this.kind, this.value);
}
class RecipeLine {
  final int line;
  final String text;
  RecipeLine(this.line, this.text);
}
class Rule {
  final String name;
  List<String> prerequisites;
  List<RecipeLine>? recipe;
  String stem;
  Rule(this.name, this.prerequisites, [this.recipe, this.stem = '']);
}
class CurrentRule {
  final List<Rule> entries = [];
  bool explicit = true;
  List<RecipeLine>? recipe;
}
class Condition {
  final bool outer;
  final int line;
  bool value, alternate = false;
  Condition(this.outer, this.value, this.line);
}
sealed class Scope {}
class ForeachScope extends Scope {
  final String name, word;
  ForeachScope(this.name, this.word);
}
class CallScope extends Scope {
  final List<String> values;
  CallScope(this.values);
}
class PatternCandidate {
  final Rule rule;
  final int index;
  final String stem;
  PatternCandidate(this.rule, this.index, this.stem);
}
class Determined extends Rule {
  final String kind;
  Determined(String name, List<String> prerequisites, List<RecipeLine>? recipe, String stem, this.kind)
      : super(name, prerequisites, recipe, stem);
}
class BuildResult {
  final String status;
  final Determined rule;
  BuildResult(this.status, this.rule);
}
final limits = <String, (int, int?)>{
  'subst': (3, 3), 'patsubst': (3, 3), 'strip': (1, 1), 'findstring': (2, 2),
  'filter': (2, 2), 'filter-out': (2, 2), 'sort': (1, 1), 'word': (2, 2),
  'wordlist': (3, 3), 'words': (1, 1), 'firstword': (1, 1), 'lastword': (1, 1),
  'dir': (1, 1), 'notdir': (1, 1), 'suffix': (1, 1), 'basename': (1, 1),
  'addsuffix': (2, 2), 'addprefix': (2, 2), 'wildcard': (1, 1), 'foreach': (3, 3),
  'if': (2, 3), 'call': (1, null), 'value': (1, 1), 'info': (1, 1),
  'warning': (1, 1), 'error': (1, 1)
};
final output = <String>[];
String leftTrim(String text) {
  var i = 0;
  while (i < text.length && text[i] == ' ') { i++; }
  return text.substring(i);
}
String rightTrim(String text) {
  var i = text.length;
  while (i > 0 && text[i - 1] == ' ') { i--; }
  return text.substring(0, i);
}
String trim(String text) => rightTrim(leftTrim(text));
List<String> words(String text) => text.split(' ').where((word) => word.isNotEmpty).toList();
List<String> unique(List<String> items) => items.toSet().toList();
bool numeric(String text) => text.isNotEmpty && !RegExp(r'[^0-9]').hasMatch(text);
String substitute(String text, String stem) {
  final i = text.indexOf('%');
  return i < 0 ? text : text.substring(0, i) + stem + text.substring(i + 1);
}
String? patternStem(String pattern, String word) {
  final i = pattern.indexOf('%');
  if (i < 0) return pattern == word ? '' : null;
  final before = pattern.substring(0, i), after = pattern.substring(i + 1);
  return word.length >= before.length + after.length && word.startsWith(before) && word.endsWith(after)
      ? word.substring(before.length, word.length - after.length) : null;
}
String replaceWord(String word, String pattern, String replacement) {
  final stem = patternStem(pattern, word);
  return stem == null ? word : pattern.contains('%') ? substitute(replacement, stem) : replacement;
}
bool wildcardMatch(String pattern, String name) {
  var previous = List<bool>.filled(name.length + 1, false);
  previous[0] = true;
  for (final c in pattern.split('')) {
    final next = List<bool>.filled(name.length + 1, false);
    for (var j = 0; j <= name.length; j++) {
      next[j] = c == '*' ? previous[j] || j > 0 && name[j - 1] != '/' && next[j - 1]
          : j > 0 && previous[j - 1] && (c == '?' ? name[j - 1] != '/' : c == name[j - 1]);
    }
    previous = next;
  }
  return previous[name.length];
}
class Simulator {
  Map<String, int> files = {};
  int clock = 0;
  bool loaded = false;
  final variables = <String, Variable>{};
  final explicit = <String, Rule>{};
  final patterns = <Rule>[];
  final phony = <String>{};
  String? goal;
  String location = 'make';
  final scopes = <Scope>[];
  final expanding = <String>{};
  Map<String, String>? automatic;
  Never fail(String reason) => throw MakeError(location, reason);
  void resetMakefile() {
    loaded = false;
    variables.clear();
    explicit.clear();
    patterns.clear();
    phony.clear();
    goal = null;
  }
  void touch(String name) { files[name] = ++clock; }
  List<String> wildcard(String pattern) => (files.keys.toList()..sort())
      .where((name) => wildcardMatch(pattern, name)).toList();
  int closing(String text, int dollar) {
    final open = text[dollar + 1], close = open == '(' ? ')' : '}';
    var depth = 0;
    for (var i = dollar + 1; i < text.length; i++) {
      if (text[i] == open) depth++;
      if (text[i] == close && --depth == 0) return i;
    }
    fail('unterminated variable reference');
  }
  String expand(String text) {
    final result = StringBuffer();
    for (var i = 0; i < text.length;) {
      if (text[i] != r'$') { result.write(text[i++]); continue; }
      if (i + 1 == text.length) break;
      final next = text[i + 1];
      if (next == r'$') { result.write(r'$'); i += 2; }
      else if (next == '(' || next == '{') {
        final end = closing(text, i);
        result.write(reference(text.substring(i + 2, end), next));
        i = end + 1;
      } else { result.write(value(next)); i += 2; }
    }
    return result.toString();
  }
  String reference(String content, String open) {
    final space = content.indexOf(' ');
    final name = space < 0 ? '' : content.substring(0, space);
    if (space >= 0 && limits.containsKey(name)) return callFunction(name, leftTrim(content.substring(space + 1)), open);
    final expanded = expand(content);
    final colon = expanded.indexOf(':');
    final equal = expanded.indexOf('=', colon + 1);
    if (colon >= 0 && equal >= 0) {
      var pattern = expanded.substring(colon + 1, equal), replacement = expanded.substring(equal + 1);
      if (!pattern.contains('%')) { pattern = '%$pattern'; replacement = '%$replacement'; }
      return words(value(expanded.substring(0, colon))).map((word) => replaceWord(word, pattern, replacement)).join(' ');
    }
    return value(expanded);
  }
  String value(String name) {
    for (final scope in scopes.reversed) {
      if (scope is ForeachScope && scope.name == name) return scope.word;
      if (scope is CallScope && numeric(name)) {
        final i = int.parse(name);
        return i < scope.values.length ? scope.values[i] : '';
      }
    }
    if (automatic != null && automatic!.containsKey(name)) return automatic![name]!;
    final variable = variables[name];
    if (variable == null) return '';
    if (variable.kind == ':=') return variable.value;
    if (expanding.contains(name)) fail("Recursive variable '$name' references itself (eventually)");
    expanding.add(name);
    try { return expand(variable.value); } finally { expanding.remove(name); }
  }
  String callFunction(String name, String text, String open) {
    final (minimum, maximum) = limits[name]!;
    final args = <String>[];
    final close = open == '(' ? ')' : '}';
    var depth = 0, start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == open) { depth++; }
      else if (text[i] == close) { depth--; }
      else if (text[i] == ',' && depth == 0 && (maximum == null || args.length < maximum - 1)) {
        args.add(text.substring(start, i));
        start = i + 1;
      }
    }
    args.add(text.substring(start));
    if (args.length < minimum) fail("insufficient number of arguments (${args.length}) to function '$name'");
    if (name == 'foreach') {
      final variable = trim(expand(args[0])), list = words(expand(args[1])), result = <String>[];
      for (final word in list) {
        scopes.add(ForeachScope(variable, word));
        try { result.add(expand(args[2])); } finally { scopes.removeLast(); }
      }
      return result.join(' ');
    }
    if (name == 'if') {
      final index = trim(expand(args[0])).isNotEmpty ? 1 : 2;
      return expand(index < args.length ? args[index] : '');
    }
    final expanded = args.map(expand).toList();
    if (name == 'subst') return expanded[0].isEmpty ? expanded[2] : expanded[2].replaceAll(expanded[0], expanded[1]);
    if (name == 'call') {
      final variableName = trim(expanded[0]), variable = variables[trim(expanded[0])];
      if (variable == null) return '';
      if (variable.kind == ':=') return variable.value;
      scopes.add(CallScope([variableName, ...expanded.skip(1)]));
      try { return expand(variable.value); } finally { scopes.removeLast(); }
    }
    final values = expanded.map(trim).toList(), a = trim(expanded[0]);
    final b = values.length > 1 ? values[1] : '', c = values.length > 2 ? values[2] : '';
    switch (name) {
      case 'patsubst': return words(c).map((word) => replaceWord(word, a, b)).join(' ');
      case 'strip': return words(a).join(' ');
      case 'findstring': return b.contains(a) ? a : '';
      case 'filter':
      case 'filter-out': return words(b).where((word) => words(a).any((pattern) => patternStem(pattern, word) != null) == (name == 'filter')).join(' ');
      case 'sort': return (unique(words(a))..sort()).join(' ');
      case 'word':
        if (!numeric(a)) fail("non-numeric first argument to 'word' function: '$a'");
        final index = int.parse(a), list = words(b);
        if (index == 0) fail("first argument to 'word' function must be greater than 0");
        return index <= list.length ? list[index - 1] : '';
      case 'wordlist':
        if (!numeric(a)) fail("non-numeric first argument to 'wordlist' function: '$a'");
        if (!numeric(b)) fail("non-numeric second argument to 'wordlist' function: '$b'");
        if (int.parse(a) == 0) fail("invalid first argument to 'wordlist' function: '$a'");
        final start = int.parse(a) - 1, end = int.parse(b), list = words(c);
        return start >= list.length || end <= start ? '' : list.sublist(start, math.min(end, list.length)).join(' ');
      case 'words': return '${words(a).length}';
      case 'firstword': return words(a).isEmpty ? '' : words(a).first;
      case 'lastword': return words(a).isEmpty ? '' : words(a).last;
      case 'dir': return words(a).map((word) => word.contains('/') ? word.substring(0, word.lastIndexOf('/') + 1) : './').join(' ');
      case 'notdir': return words(a).map((word) => word.substring(word.lastIndexOf('/') + 1)).join(' ');
      case 'suffix': return words(a).where((word) => word.lastIndexOf('.') > word.lastIndexOf('/')).map((word) => word.substring(word.lastIndexOf('.'))).join(' ');
      case 'basename': return words(a).map((word) => word.lastIndexOf('.') > word.lastIndexOf('/') ? word.substring(0, word.lastIndexOf('.')) : word).join(' ');
      case 'addsuffix': return words(b).map((word) => word + a).join(' ');
      case 'addprefix': return words(b).map((word) => a + word).join(' ');
      case 'wildcard': return words(a).expand(wildcard).join(' ');
      case 'value': return variables[a]?.value ?? '';
      case 'info': output.add(a); return '';
      case 'warning': output.add('$location: $a'); return '';
      case 'error': fail(a);
    }
    return '';
  }
  Map<String, int> punctuation(String text) {
    final result = <String, int>{};
    for (var i = 0; i < text.length; i++) {
      if (text[i] == r'$') {
        if (i + 1 < text.length && (text[i + 1] == '(' || text[i + 1] == '{')) { i = closing(text, i); }
        else if (i + 1 < text.length) { i++; }
      } else if ('=:;'.contains(text[i])) { result.putIfAbsent(text[i], () => i); }
    }
    return result;
  }
  Rule register(String name, List<String> prerequisites) {
    final rule = explicit.putIfAbsent(name, () => Rule(name, []));
    rule.prerequisites = unique([...rule.prerequisites, ...prerequisites]);
    if (goal == null && !name.startsWith('.')) goal = name;
    return rule;
  }
  void addRecipe(CurrentRule current, int line, String text) {
    if (current.entries.isEmpty) return;
    if (current.recipe == null) {
      current.recipe = [];
      for (final entry in current.entries) {
        if (current.explicit && entry.recipe != null) {
          output.add("Makefile:$line: warning: overriding recipe for target '${entry.name}'");
          output.add("Makefile:${entry.recipe!.first.line}: warning: ignoring old recipe for target '${entry.name}'");
        }
        entry.recipe = current.recipe;
      }
    }
    current.recipe!.add(RecipeLine(line, text));
  }
  void load(List<String> body) {
    resetMakefile();
    final conditions = <Condition>[];
    CurrentRule? current;
    bool active() => conditions.isEmpty || conditions.last.outer && conditions.last.value;
    try {
      for (var i = 0; i < body.length; i++) {
        final line = i + 1;
        location = 'Makefile:$line';
        if (body[i].startsWith('>')) {
          if (!active()) continue;
          if (current == null) fail('recipe commences before first target');
          addRecipe(current, line, leftTrim(body[i].substring(1)));
          continue;
        }
        var logical = body[i];
        while (logical.endsWith(r'\') && i + 1 < body.length) {
          logical = '${rightTrim(logical.substring(0, logical.length - 1))} ${leftTrim(body[++i])}';
        }
        final text = trim(logical.split('#').first), space = trim(logical.split('#').first).indexOf(' ');
        final first = space < 0 ? text : text.substring(0, space), rest = space < 0 ? '' : trim(text.substring(space + 1));
        if (['ifeq', 'ifneq', 'ifdef', 'ifndef'].contains(first)) {
          final outer = active();
          var condition = false;
          if (outer) {
            if (first == 'ifdef' || first == 'ifndef') {
              final variable = variables[trim(expand(rest))];
              condition = variable != null && variable.value.isNotEmpty;
              if (first == 'ifndef') condition = !condition;
            } else {
              if (rest.length < 2 || !rest.startsWith('(') || !rest.endsWith(')')) fail('invalid syntax in conditional');
              final inside = rest.substring(1, rest.length - 1);
              var depth = 0, comma = -1;
              for (var j = 0; j < inside.length; j++) {
                if (inside[j] == '(') { depth++; }
                else if (inside[j] == ')') { depth--; }
                else if (inside[j] == ',' && depth == 0) { comma = j; break; }
              }
              if (comma < 0) fail('invalid syntax in conditional');
              final left = trim(expand(inside.substring(0, comma))), right = trim(expand(inside.substring(comma + 1)));
              condition = left == right;
              if (first == 'ifneq') condition = !condition;
            }
          }
          conditions.add(Condition(outer, condition, line));
          continue;
        }
        if (first == 'else') {
          if (conditions.isEmpty) fail("extraneous 'else'");
          final condition = conditions.last;
          if (condition.alternate) fail("only one 'else' per conditional");
          condition.value = !condition.value;
          condition.alternate = true;
          continue;
        }
        if (first == 'endif') {
          if (conditions.isEmpty) fail("extraneous 'endif'");
          conditions.removeLast();
          continue;
        }
        if (text.isEmpty || !active()) continue;
        final positions = punctuation(text);
        final equal = positions['='], colon = positions[':'];
        if (equal != null && (colon == null || colon >= equal - 1)) {
          final special = equal > 0 && ':+?'.contains(text[equal - 1]);
          final op = special ? '${text[equal - 1]}=' : '=';
          final name = trim(text.substring(0, equal - (special ? 1 : 0))), rhs = trim(text.substring(equal + 1));
          if (name.isEmpty) fail('empty variable name');
          final previous = variables[name];
          if (op == '=' || op == '?=' && previous == null || op == '+=' && previous == null) { variables[name] = Variable('=', rhs); }
          else if (op == ':=') { variables[name] = Variable(':=', expand(rhs)); }
          else if (op == '+=') {
            final addition = previous!.kind == ':=' ? expand(rhs) : rhs;
            previous.value = previous.value.isEmpty ? addition : '${previous.value} $addition';
          }
          current = null;
        } else if (colon != null) {
          final targets = unique(words(expand(text.substring(0, colon))));
          var rhs = text.substring(colon + 1);
          String? inline, targetPattern;
          final semicolon = punctuation(rhs)[';'];
          if (semicolon != null) { inline = leftTrim(rhs.substring(semicolon + 1)); rhs = rhs.substring(0, semicolon); }
          final secondColon = punctuation(rhs)[':'];
          if (secondColon != null) { targetPattern = trim(expand(rhs.substring(0, secondColon))); rhs = rhs.substring(secondColon + 1); }
          final prerequisites = words(expand(rhs));
          current = CurrentRule();
          if (targets.length == 1 && targets.first == '.PHONY') { phony.addAll(prerequisites); }
          else if (targetPattern != null) {
            if (!targetPattern.contains('%')) fail("target pattern contains no '%'");
            for (final name in targets) {
              final stem = patternStem(targetPattern, name);
              if (stem == null || stem.isEmpty) { output.add("Makefile:$line: target '$name' doesn't match the target pattern"); }
              else {
                final entry = register(name, prerequisites.map((value) => substitute(value, stem)).toList());
                entry.stem = stem;
                current.entries.add(entry);
              }
            }
          } else if (targets.any((name) => name.contains('%'))) {
            if (targets.any((name) => !name.contains('%'))) fail('mixed implicit and normal rules');
            current.explicit = false;
            for (final name in targets) {
              final entry = Rule(name, List.of(prerequisites));
              patterns.add(entry);
              current.entries.add(entry);
            }
          } else {
            for (final name in targets) { current.entries.add(register(name, prerequisites)); }
          }
          if (inline != null) addRecipe(current, line, inline);
        } else if (trim(expand(text)).isNotEmpty) { fail('missing separator'); }
      }
      if (conditions.isNotEmpty) { location = 'Makefile:${conditions.last.line}'; fail("missing 'endif'"); }
      loaded = true;
      output.add('Makefile loaded: lines=${body.length} variables=${variables.length} targets=${explicit.length} patterns=${patterns.where((rule) => rule.recipe != null).length} goal=${goal ?? '(none)'}');
    } on MakeError catch (error) {
      output.add(error.message);
      resetMakefile();
    } finally { location = 'make'; }
  }
  Determined determine(String name) {
    final entry = explicit[name];
    if (entry != null && entry.recipe != null) return Determined(name, List.of(entry.prerequisites), entry.recipe, entry.stem, 'rule');
    if (!phony.contains(name)) {
      final candidates = <PatternCandidate>[];
      for (var i = 0; i < patterns.length; i++) {
        final rule = patterns[i], stem = patternStem(patterns[i].name, name);
        if (rule.recipe != null && stem != null && stem.isNotEmpty) candidates.add(PatternCandidate(rule, i, stem));
      }
      candidates.sort((a, b) {
        final order = a.stem.length.compareTo(b.stem.length);
        return order == 0 ? a.index.compareTo(b.index) : order;
      });
      for (final candidate in candidates) {
        final prerequisites = candidate.rule.prerequisites.map((value) => substitute(value, candidate.stem)).toList();
        if (prerequisites.every((value) => files.containsKey(value) || explicit.containsKey(value))) {
          return Determined(name, unique([...prerequisites, ...?entry?.prerequisites]), candidate.rule.recipe, candidate.stem, 'rule');
        }
      }
    }
    if (entry != null || phony.contains(name)) return Determined(name, List.of(entry?.prerequisites ?? []), null, entry?.stem ?? '', 'rule');
    return Determined(name, [], null, '', files.containsKey(name) ? 'source' : 'missing');
  }
  int executeRecipeCommand(String command) {
    final list = words(command), args = words(command).skip(1).toList();
    if (list.first == 'echo') { output.add(args.join(' ')); }
    else if (list.first == 'touch') { for (final name in args) { touch(name); } }
    else if (list.first == 'rm') {
      final forced = args.isNotEmpty && args.first == '-f';
      var status = 0;
      for (final pattern in forced ? args.skip(1) : args) {
        final matches = wildcard(pattern);
        for (final name in matches.isEmpty ? [pattern] : matches) {
          if (files.remove(name) == null && !forced) { output.add("rm: cannot remove '$name': No such file or directory"); status = 1; }
        }
      }
      return status;
    } else if (list.first == 'false') { return 1; }
    else if (list.first == 'exit') { return args.isEmpty ? 0 : int.parse(args.first); }
    return 0;
  }
  void make(List<String> args) {
    final flags = <String>{}, goals = <String>[];
    for (final argument in args) {
      if (argument.startsWith('-')) {
        for (final c in argument.substring(1).split('')) {
          if (!'nBkis'.contains(c)) { output.add("make: invalid option -- '$c'"); return; }
          flags.add(c);
        }
      } else { goals.add(argument); }
    }
    if (goals.isEmpty) {
      if (!loaded) { output.add('make: *** No targets specified and no makefile found.  Stop.'); return; }
      if (goal == null) { output.add('make: *** No targets.  Stop.'); return; }
      goals.add(goal!);
    }
    final savedFiles = Map<String, int>.of(files), savedClock = clock;
    final results = <String, BuildResult>{}, beingBuilt = <String>{};
    var runs = 0;
    int? targetTime(String name) => phony.contains(name) ? null : files[name];
    BuildResult build(String name, String? parent) {
      final cached = results[name];
      if (cached != null) return cached;
      final rule = determine(name);
      if (rule.kind == 'missing') {
        output.add("make: *** No rule to make target '$name'${parent == null ? '' : ", needed by '$parent'"}.${flags.contains('k') ? '' : '  Stop.'}");
        if (!flags.contains('k')) throw BuildAbort();
        return results[name] = BuildResult('failure', rule);
      }
      if (rule.kind == 'source') return results[name] = BuildResult('success', rule);
      beingBuilt.add(name);
      var failed = false;
      final kept = <String>[];
      for (final prerequisite in rule.prerequisites) {
        if (beingBuilt.contains(prerequisite)) { output.add('make: Circular $name <- $prerequisite dependency dropped.'); continue; }
        kept.add(prerequisite);
        if (build(prerequisite, name).status != 'success') failed = true;
      }
      rule.prerequisites = kept;
      beingBuilt.remove(name);
      var status = 'dependency failure';
      if (!failed) {
        status = 'success';
        final time = targetTime(name);
        final newer = kept.where((value) => flags.contains('B') || time == null || targetTime(value) == null || targetTime(value)! > time).toList();
        if (rule.recipe != null && (flags.contains('B') || time == null || newer.isNotEmpty)) {
          runs++;
          automatic = {'@': name, '<': kept.isEmpty ? '' : kept.first, '^': kept.join(' '), '?': newer.join(' '), '*': rule.stem};
          final commands = <RecipeLine>[];
          try {
            for (final line in rule.recipe!) { location = 'Makefile:${line.line}'; commands.add(RecipeLine(line.line, expand(line.text))); }
          } finally { automatic = null; location = 'make'; }
          for (final line in commands) {
            var i = 0;
            while (i < line.text.length && ' @-'.contains(line.text[i])) { i++; }
            final prefix = line.text.substring(0, i), command = rightTrim(line.text.substring(i));
            if (command.isEmpty) continue;
            if (flags.contains('n') || !prefix.contains('@') && !flags.contains('s')) output.add(command);
            if (flags.contains('n')) continue;
            final code = executeRecipeCommand(command);
            if (code != 0) {
              if (prefix.contains('-') || flags.contains('i')) { output.add('make: [Makefile:${line.line}: $name] Error $code (ignored)'); }
              else {
                output.add('make: *** [Makefile:${line.line}: $name] Error $code');
                if (!flags.contains('k')) throw BuildAbort();
                status = 'failure';
                break;
              }
            }
          }
          if (status == 'success' && !phony.contains(name)) touch(name);
        }
      }
      return results[name] = BuildResult(status, rule);
    }
    try {
      for (final goal in goals) {
        final previous = runs, result = build(goal, null);
        if (result.status == 'dependency failure') { output.add("make: Target '$goal' not remade because of errors."); }
        else if (result.status == 'success' && previous == runs) {
          output.add(phony.contains(goal) || result.rule.recipe == null ? "make: Nothing to be done for '$goal'." : "make: '$goal' is up to date.");
        }
      }
    } on MakeError catch (error) { output.add(error.message); }
    on BuildAbort {}
    finally { if (flags.contains('n')) { files = savedFiles; clock = savedClock; } }
  }
  void other(String commandLine) {
    location = 'make';
    final list = commandLine.split(' '), command = commandLine.split(' ').first;
    final args = list.skip(1).toList();
    if (command == 'MAKE') { make(args); }
    else if (command == 'TOUCH') { for (final name in args) { touch(name); } }
    else if (command == 'RM') { for (final name in args) { if (files.remove(name) == null) output.add("rm: cannot remove '$name': No such file or directory"); } }
    else if (command == 'FILES') {
      output.add('clock $clock');
      for (final name in files.keys.toList()..sort()) { output.add('$name ${files[name]}'); }
    } else if (command == 'EXPAND') { output.add('[${expand(commandLine.substring(7))}]'); }
    else if (command == 'VARS' && loaded) {
      for (final name in variables.keys.toList()..sort()) {
        final expanded = trim(value(name));
        output.add('$name ${variables[name]!.kind}${expanded.isEmpty ? '' : ' $expanded'}');
      }
    } else if (command == 'RULES' && loaded) {
      final rules = [...(explicit.keys.toList()..sort()).map((name) => explicit[name]!), ...patterns.where((rule) => rule.recipe != null)];
      for (final rule in rules) {
        output.add('${rule.name}:${rule.prerequisites.map((value) => ' $value').join()}');
        for (final line in rule.recipe ?? <RecipeLine>[]) { output.add('>${line.text}'); }
      }
      if (phony.isNotEmpty) output.add('.PHONY: ${(phony.toList()..sort()).join(' ')}');
    }
  }
}
void main() {
  final simulator = Simulator();
  stdin.readLineSync();
  String line;
  while ((line = stdin.readLineSync()!) != 'END FILES') {
    final parts = line.split(' '), time = int.parse(line.split(' ')[1]);
    simulator.files[parts[0]] = time;
    simulator.clock = math.max(simulator.clock, time);
  }
  while ((line = stdin.readLineSync()!) != 'QUIT') {
    output.add('\$ $line');
    if (line == 'MAKEFILE') {
      final body = <String>[];
      while ((line = stdin.readLineSync()!) != 'END MAKEFILE') { body.add(line); }
      simulator.load(body);
    } else {
      try { simulator.other(line); }
      on MakeError catch (error) { output.add(error.message); }
    }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
