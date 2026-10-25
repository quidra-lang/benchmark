import 'dart:io';

const textDirectives = {'INITIAL', 'FINAL', 'DEFAULT', 'QUESTION', 'REPEAT'};
const globalDirectives = {'INITIAL', 'FINAL', 'QUIT', 'STOP', 'DEFAULT', 'QUESTION', 'REPEAT', 'MEMSIZE', 'PERSIST', 'PRE', 'POST', 'SYNON'};
const ruleDirectives = {'DECOMP', 'MEMORY'};
const itemDirectives = {'REASM', 'GOTO', 'NEWKEY', 'RESTATE'};

List<String> readLines(String path) => File(path).readAsStringSync().split('\n')..removeLast();
bool isWord(String word) => RegExp(r"^[a-z0-9](?:[a-z0-9']*[a-z0-9])?$").hasMatch(word);
bool isNumber(String word) => RegExp(r'^[0-9]{1,2}$').hasMatch(word);
int? reference(String word) => RegExp(r'^\([0-9]\)$').hasMatch(word) ? int.parse(word[1]) : null;
bool isElement(String word) => word == '*' || word == '#' || (word.startsWith('@') ? isWord(word.substring(1)) : isWord(word));

class Diagnostic {
  final int line;
  final String code, message;
  Diagnostic(this.line, this.code, this.message);
}
class Substitution {
  final String source;
  final List<String> replacement;
  final int line;
  Substitution(this.source, this.replacement, this.line);
}
class Group {
  final String name;
  final Set<String> members;
  final int line;
  Group(this.name, this.members, this.line);
}
class Item {
  final String kind, text;
  final List<String> arguments;
  final int line;
  Item(this.kind, this.text, this.arguments, this.line);
}
class Rule {
  final String kind;
  final List<String> pattern;
  final int line;
  final List<int> items = [];
  Rule(this.kind, this.pattern, this.line);
}
class Keyword {
  final String word;
  final int rank, line;
  final List<int> memories = [], decomps = [];
  Keyword(this.word, this.rank, this.line);
}
class Script {
  final List<String> lines;
  final Map<String, List<String>> texts = {for (final name in textDirectives) name: []};
  final Set<String> quit = {}, stop = {}, persist = {};
  int capacity = 3;
  final Map<String, Substitution> pre = {}, post = {};
  final Map<String, Group> groups = {};
  final List<Keyword> keywords = [];
  final Map<String, int> keywordMap = {};
  final List<Rule> rules = [];
  final List<Item> items = [];
  final List<Diagnostic> diagnostics = [];
  Script(this.lines);
}

bool wellFormed(String name, List<String> arguments) {
  final count = arguments.length;
  if (textDirectives.contains(name) || name == 'REASM') return count > 0;
  if (name == 'QUIT' || name == 'STOP') return count > 0 && arguments.every(isWord);
  if (name == 'MEMSIZE') return count == 1 && isNumber(arguments[0]) && int.parse(arguments[0]) >= 1 && int.parse(arguments[0]) <= 20;
  if (name == 'PERSIST') return count == 1 && {'cycles', 'memory'}.contains(arguments[0]);
  if (name == 'PRE' || name == 'SYNON') return count >= 2 && arguments.every(isWord);
  if (name == 'POST') return count >= 2 && isWord(arguments[0]);
  if (name == 'KEY') return count == 2 && isWord(arguments[0]) && isNumber(arguments[1]);
  if (ruleDirectives.contains(name)) return count > 0 && arguments.every(isElement);
  if (name == 'GOTO') return count == 1 && isWord(arguments[0]);
  if (name == 'NEWKEY') return count == 0;
  return name == 'RESTATE' && count >= 2 && isWord(arguments[0]) && arguments.skip(1).every((word) => isWord(word) || reference(word) != null);
}

Script loadScript(String path) {
  final script = Script(readLines(path));
  int? keyword, rule;
  var ignoring = false;
  final first = <String, int>{};
  for (var index = 0; index < script.lines.length; index++) {
    final line = script.lines[index];
    if (line.isEmpty || line.startsWith('#')) continue;
    final space = line.indexOf(' ');
    final name = space < 0 ? line : line.substring(0, space);
    final text = space < 0 ? '' : line.substring(space + 1);
    final arguments = text.isEmpty ? <String>[] : text.split(' ');
    final isRule = ruleDirectives.contains(name), isItem = itemDirectives.contains(name);
    if (globalDirectives.contains(name) || name == 'KEY') {
      keyword = rule = null;
      ignoring = false;
    } else if (isRule || isItem) {
      if (ignoring) continue;
      if (isRule) rule = null;
    }
    final definition = name == 'MEMSIZE' ? name : ({'KEY', 'SYNON', 'PRE', 'POST', 'PERSIST'}.contains(name) && arguments.isNotEmpty ? '$name ${arguments[0]}' : null);
    String? code, message;
    if (!globalDirectives.contains(name) && name != 'KEY' && !isRule && !isItem) { code = 'SYNTAX'; message = 'unknown directive $name'; }
    else if (!wellFormed(name, arguments)) { code = 'SYNTAX'; message = 'bad arguments for $name'; }
    else if (isRule && keyword == null) { code = 'ORPHAN'; message = '$name without KEY'; }
    else if (name == 'REASM' && rule == null) { code = 'ORPHAN'; message = 'REASM without DECOMP or MEMORY'; }
    else if ({'GOTO', 'NEWKEY', 'RESTATE'}.contains(name) && (rule == null || script.rules[rule].kind == 'MEMORY')) { code = 'ORPHAN'; message = '$name without DECOMP'; }
    else if (definition != null && first.containsKey(definition)) { code = 'DUPLICATE'; message = '$definition first defined at line ${first[definition]}'; }
    final number = index + 1;
    if (code != null) {
      script.diagnostics.add(Diagnostic(number, code, message!));
      if (name == 'KEY' && code == 'DUPLICATE') ignoring = true;
      continue;
    }
    if (definition != null) first[definition] = number;
    if (textDirectives.contains(name)) script.texts[name]!.add(text);
    else if (name == 'QUIT') script.quit.addAll(arguments);
    else if (name == 'STOP') script.stop.addAll(arguments);
    else if (name == 'MEMSIZE') script.capacity = int.parse(arguments[0]);
    else if (name == 'PERSIST') script.persist.add(arguments[0]);
    else if (name == 'PRE' || name == 'POST') {
      (name == 'PRE' ? script.pre : script.post)[arguments[0]] = Substitution(arguments[0], arguments.sublist(1), number);
    } else if (name == 'SYNON') script.groups[arguments[0]] = Group(arguments[0], arguments.toSet(), number);
    else if (name == 'KEY') {
      keyword = script.keywords.length;
      script.keywordMap[arguments[0]] = keyword;
      script.keywords.add(Keyword(arguments[0], int.parse(arguments[1]), number));
    } else if (isRule) {
      rule = script.rules.length;
      script.rules.add(Rule(name, arguments, number));
      (name == 'MEMORY' ? script.keywords[keyword!].memories : script.keywords[keyword!].decomps).add(rule);
    } else {
      script.rules[rule!].items.add(script.items.length);
      script.items.add(Item(name, text, arguments, number));
    }
  }
  return script;
}
