import 'dart:io';
import 'script_loader.dart';
import 'linter.dart';
import 'matcher.dart';
import 'responder.dart';
import 'memory.dart';

const sources = ['keyword', 'memory', 'question', 'default', 'repeat'];
const noArgument = {':keys', ':why', ':history', ':memory', ':forget', ':reset', ':unused', ':stats', ':undo'};
const textArgument = {':prepare', ':reflect', ':say', ':explain'};
const oneArgument = {':groups', ':find', ':script', ':cycles', ':coverage'};

List<List<String>> normalize(String text) => text.toLowerCase().split(RegExp(r'[,.?!;]')).map((part) {
  return RegExp(r"[a-z0-9']+").allMatches(part).map((match) => match[0]!.replaceAll(RegExp(r"^'+|'+$"), '')).where((word) => word.isNotEmpty).toList();
}).where((clause) => clause.isNotEmpty).toList();
bool sameClauses(List<List<String>>? first, List<List<String>> second) => first != null && first.length == second.length && List.generate(first.length, (index) => first[index].join(' ') == second[index].join(' ')).every((same) => same);
String countLine(int turns, List<int> counts) => 'turns=$turns ${List.generate(5, (index) => '${sources[index]}=${counts[index]}').join(' ')}';
String leaders(Map<String, int> counts) {
  final entries = counts.entries.where((entry) => entry.value > 0).toList()..sort((a, b) => a.value != b.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return entries.isEmpty ? 'none' : entries.take(5).map((entry) => '${entry.key} ${entry.value}').join(', ');
}
List<String> grouped(List<String> values, int size) => [for (var start = 0; start < values.length; start += size) values.sublist(start, start + size < values.length ? start + size : values.length).join(' ')];
List<(String, int, int)> ruleEntries(Keyword keyword) => [
  for (var index = 0; index < keyword.memories.length; index++) ('memory', index + 1, keyword.memories[index]),
  for (var index = 0; index < keyword.decomps.length; index++) ('decomp', index + 1, keyword.decomps[index]),
];

class Session {
  final String name;
  int turns = 0, stored = 0, recalled = 0;
  List<int> counts = List.filled(5, 0), unrecognized = [];
  List<List<String>>? previous;
  List<String> history = [];
  List<String>? lastTrace;
  bool traceOn = false;
  Map<String, int> topics = {}, words = {};
  State? undo;
  Session(this.name);
  Session copy() {
    final result = Session(name);
    result.turns = turns;
    result.stored = stored;
    result.recalled = recalled;
    result.counts = List.of(counts);
    result.unrecognized = List.of(unrecognized);
    result.previous = previous?.map((clause) => List<String>.of(clause)).toList();
    result.history = List.of(history);
    result.lastTrace = lastTrace == null ? null : List.of(lastTrace!);
    result.traceOn = traceOn;
    result.topics = Map.of(topics);
    result.words = Map.of(words);
    result.undo = undo?.copy();
    return result;
  }
}
class State {
  List<int> positions, hits, itemUses, keywordUses, keywordReplies, cycles;
  MemoryQueue memory;
  Session session;
  State(Script script) : positions = List.filled(script.rules.length, 0), hits = List.filled(script.rules.length, 0),
    itemUses = List.filled(script.items.length, 0), keywordUses = List.filled(script.keywords.length, 0),
    keywordReplies = List.filled(script.keywords.length, 0), cycles = List.filled(3, 0), memory = MemoryQueue(script.capacity), session = Session('');
  State._(this.positions, this.hits, this.itemUses, this.keywordUses, this.keywordReplies, this.cycles, this.memory, this.session);
  State copy() => State._(List.of(positions), List.of(hits), List.of(itemUses), List.of(keywordUses), List.of(keywordReplies), List.of(cycles), memory.copy(), session.copy());
}

class Chatbot {
  final Script script;
  late State state;
  final List<String> transcript = [];
  int sessions = 0, totalTurns = 0;
  final List<int> totalCounts = List.filled(5, 0);
  Chatbot(this.script) { state = State(script); }
  String get prefix => '${state.session.name} ${state.session.turns}';
  void resetCycles() { state.positions.fillRange(0, state.positions.length, 0); state.cycles.fillRange(0, 3, 0); }
  String takeText(String name) {
    final index = ['DEFAULT', 'QUESTION', 'REPEAT'].indexOf(name), position = state.cycles[['DEFAULT', 'QUESTION', 'REPEAT'].indexOf(name)];
    final texts = script.texts[name]!;
    state.cycles[index] = (position + 1) % texts.length;
    return texts[position];
  }
  (int, int) takeItem(int rule) {
    final position = state.positions[rule], item = script.rules[rule].items[position];
    state.itemUses[item]++;
    state.positions[rule] = (position + 1) % script.rules[rule].items.length;
    return (position + 1, item);
  }
  List<List<String>> prepared(List<List<String>> clauses) => clauses.map((clause) => clause.expand((word) => script.pre[word]?.replacement ?? [word]).toList()).toList();
  bool isQuit(List<List<String>> clauses) { final words = clauses.expand((clause) => clause).toList(); return words.length == 1 && script.quit.contains(words[0]); }
  (int, List<String>, List<int>)? selectClause(List<List<String>> clauses) {
    for (var index = 0; index < clauses.length; index++) {
      final found = <int, int>{};
      for (var position = 0; position < clauses[index].length; position++) {
        final id = script.keywordMap[clauses[index][position]];
        if (id != null) found.putIfAbsent(id, () => position);
      }
      if (found.isEmpty) continue;
      final keys = found.keys.toList()..sort((a, b) => script.keywords[a].rank != script.keywords[b].rank ? script.keywords[b].rank.compareTo(script.keywords[a].rank) : found[a]!.compareTo(found[b]!));
      return (index + 1, clauses[index], keys);
    }
    return null;
  }
  (int, int, List<List<String>>)? findRule(List<int> rules, List<String> words) {
    for (var index = 0; index < rules.length; index++) {
      final id = rules[index], bindings = matchPattern(script.rules[id].pattern, words, script.groups);
      if (bindings != null) return (index + 1, id, bindings);
    }
    return null;
  }
  void applyMemory(int keyword, List<String> words, List<String> trace) {
    final found = findRule(script.keywords[keyword].memories, words);
    if (found == null) return;
    final (number, rule, bindings) = found;
    final word = script.keywords[keyword].word;
    trace.add('MEMORY $word $number');
    state.hits[rule]++;
    if (script.rules[rule].items.isEmpty) return;
    final (_, item) = takeItem(rule);
    final text = buildReply(script.items[item].text, bindings, script.post);
    if (state.memory.store(prefix, word, text)) state.session.stored++;
  }
  String? keywordReply(List<List<String>> clauses, List<String> trace) {
    final selected = selectClause(clauses);
    if (selected == null) { trace.add('CLAUSE none'); return null; }
    final (number, words, keywords) = selected;
    trace.add('CLAUSE $number ${words.join(' ')}');
    trace.add('KEYS ${keywords.map((id) => script.keywords[id].word).join(' ')}');
    applyMemory(keywords[0], words, trace);
    final entered = <int>{};
    for (final initial in keywords) {
      if (entered.contains(initial)) continue;
      trace.add('ENTER ${script.keywords[initial].word}');
      var keyword = initial;
      var current = words;
      while (true) {
        entered.add(keyword);
        state.keywordUses[keyword]++;
        final word = script.keywords[keyword].word, found = findRule(script.keywords[keyword].decomps, current);
        if (found == null) { trace.add('NOMATCH $word'); break; }
        final (number, rule, bindings) = found;
        state.hits[rule]++;
        if (script.rules[rule].items.isEmpty) { trace.add('DECOMP $word $number 0'); break; }
        final (itemNumber, itemId) = takeItem(rule);
        final item = script.items[itemId];
        trace.add('DECOMP $word $number $itemNumber');
        if (item.kind == 'REASM') {
          state.keywordReplies[keyword]++;
          state.session.topics.update(word, (count) => count + 1, ifAbsent: () => 1);
          return buildReply(item.text, bindings, script.post);
        }
        if (item.kind == 'NEWKEY') break;
        final target = item.arguments[0], next = script.keywordMap[item.arguments[0]];
        if (next == null || entered.contains(next)) { trace.add('BLOCKED $target'); break; }
        if (item.kind == 'RESTATE') {
          current = restate(item.arguments.sublist(1), bindings);
          trace.add('RESTATE $target${current.isEmpty ? '' : ' ${current.join(' ')}'}');
        } else trace.add('GOTO $target');
        keyword = next;
      }
    }
    return null;
  }
  (String, List<String>) decide(String text) {
    final clauses = normalize(text), trace = <String>[];
    String reply;
    int source;
    if (script.texts['REPEAT']!.isNotEmpty && clauses.isNotEmpty && sameClauses(state.session.previous, clauses)) {
      trace.add('REPEAT'); reply = takeText('REPEAT'); source = 4;
    } else {
      final candidate = keywordReply(prepared(clauses), trace);
      if (candidate != null) { reply = candidate; source = 0; }
      else if (state.memory.texts.isNotEmpty) { reply = state.memory.recall(prefix); state.session.recalled++; source = 1; }
      else if (text.endsWith('?') && script.texts['QUESTION']!.isNotEmpty) { reply = takeText('QUESTION'); source = 2; }
      else { reply = takeText('DEFAULT'); source = 3; }
    }
    trace.add('REPLY ${sources[source]}');
    state.session.previous = clauses;
    state.session.counts[source]++;
    if (source == 2 || source == 3) state.session.unrecognized.add(state.session.turns);
    return (reply, trace);
  }
  void respond(String text) {
    final snapshot = state.copy()..session.undo = null;
    state.session.undo = snapshot;
    state.session.turns++;
    for (final word in normalize(text).expand((clause) => clause)) if (!script.stop.contains(word)) state.session.words.update(word, (count) => count + 1, ifAbsent: () => 1);
    state.session.history.add('${state.session.turns}: $text');
    final (reply, trace) = decide(text);
    transcript.addAll(wrapReply(reply));
    state.session.lastTrace = trace;
    if (state.session.traceOn) transcript.addAll(trace.map((line) => '  $line'));
  }
  List<String> prepare(String text) {
    final clauses = prepared(normalize(text));
    final lines = [for (var index = 0; index < clauses.length; index++) 'clause ${index + 1}: ${clauses[index].join(' ')}'];
    if (clauses.isEmpty) lines.add('no words');
    final selected = selectClause(clauses);
    if (selected == null) lines.add('selected none');
    else {
      lines.add('selected ${selected.$1}');
      lines.add('keys ${selected.$3.map((id) => '${script.keywords[id].word}/${script.keywords[id].rank}').join(' ')}');
    }
    return lines;
  }
  List<String> findWord(String word) {
    final lines = <String>[];
    final id = script.keywordMap[word];
    if (id != null) lines.add('keyword rank ${script.keywords[id].rank}');
    for (final (label, entries) in [('pre', script.pre), ('post', script.post)]) {
      for (final entry in entries.values) if (entry.source == word || entry.replacement.contains(word)) lines.add('$label ${entry.line}: ${entry.source} -> ${entry.replacement.join(' ')}');
    }
    for (final group in script.groups.values) if (group.members.contains(word)) lines.add('group ${group.name} line ${group.line}');
    for (final keyword in script.keywords) for (final (label, number, rule) in ruleEntries(keyword)) if (script.rules[rule].pattern.contains(word)) lines.add('pattern ${keyword.word} $label $number');
    if (script.stop.contains(word)) lines.add('stop word');
    if (script.quit.contains(word)) lines.add('quit word');
    return lines.isEmpty ? ['not found'] : lines;
  }
  List<String> command(String line) {
    final space = line.indexOf(' '), name = space < 0 ? line : line.substring(0, space), text = space < 0 ? '' : line.substring(space + 1);
    final arguments = text.isEmpty ? <String>[] : text.split(' ');
    if (!{...noArgument, ...textArgument, ...oneArgument, ':trace', ':test'}.contains(name)) return ['unknown command $name'];
    if (noArgument.contains(name) && arguments.isNotEmpty || textArgument.contains(name) && text.isEmpty
        || oneArgument.contains(name) && arguments.length != 1 || name == ':trace' && (arguments.length != 1 || !{'on', 'off'}.contains(arguments[0]))
        || name == ':test' && arguments.length < 2) return ['bad arguments'];
    final id = arguments.isEmpty ? null : script.keywordMap[arguments[0]];
    if ({':test', ':script', ':cycles', ':coverage'}.contains(name) && id == null) return ['unknown keyword ${arguments[0]}'];
    if (name == ':prepare') return prepare(text);
    if (name == ':reflect') { final clauses = prepared(normalize(text)); return clauses.isEmpty ? ['no words'] : clauses.map((clause) => reflect(clause, script.post).join(' ')).toList(); }
    if (name == ':test') {
      final words = prepared(normalize(text.substring(text.indexOf(' ') + 1))).expand((clause) => clause).toList();
      final lines = <String>[];
      for (final (label, number, rule) in ruleEntries(script.keywords[id!])) {
        final bindings = matchPattern(script.rules[rule].pattern, words, script.groups);
        final result = bindings == null ? 'no match' : bindings.isEmpty ? 'match' : bindings.map((binding) => '[${binding.join(' ')}]').join(' ');
        lines.add('$label $number: $result');
      }
      return lines.isEmpty ? ['no rules'] : lines;
    }
    if (name == ':keys') {
      final keys = List<Keyword>.of(script.keywords)..sort((a, b) => a.rank != b.rank ? b.rank.compareTo(a.rank) : a.word.compareTo(b.word));
      return grouped(keys.map((key) => '${key.word}/${key.rank}').toList(), 8);
    }
    if (name == ':groups') { final groups = script.groups.values.where((group) => group.members.contains(text)).map((group) => group.name).toList()..sort(); return [groups.isEmpty ? 'none' : groups.join(' ')]; }
    if (name == ':find') return findWord(text);
    if (name == ':script') {
      final keyword = script.keywords[id!], numbers = <int>[script.keywords[id!].line];
      for (final (_, _, rule) in ruleEntries(keyword)) { numbers.add(script.rules[rule].line); numbers.addAll(script.rules[rule].items.map((item) => script.items[item].line)); }
      numbers.sort();
      return numbers.map((number) => '$number ${script.lines[number - 1]}').toList();
    }
    if (name == ':why') return state.session.lastTrace ?? ['no reply yet'];
    if (name == ':trace') { state.session.traceOn = text == 'on'; return ['trace $text']; }
    if (name == ':history') { final history = state.session.history; return history.isEmpty ? ['no turns yet'] : history.skip(history.length > 5 ? history.length - 5 : 0).toList(); }
    if (name == ':memory') return ['memory ${state.memory.texts.length}/${script.capacity}', for (var index = 0; index < state.memory.texts.length; index++) '${index + 1}: ${state.memory.texts[index]}'];
    if (name == ':forget') return ['forgot ${state.memory.clear(prefix)}'];
    if (name == ':cycles' || name == ':coverage') {
      final lines = <String>[];
      for (final (label, number, ruleId) in ruleEntries(script.keywords[id!])) {
        final rule = script.rules[ruleId];
        final uses = rule.items.map((item) => '${state.itemUses[item]}').join(' ');
        final detail = name == ':coverage' ? 'hits ${state.hits[ruleId]} entries ${uses.isEmpty ? '-' : uses}' : rule.items.isEmpty ? 'empty' : 'next ${state.positions[ruleId] + 1}/${rule.items.length}';
        lines.add('$label $number: $detail');
      }
      return lines.isEmpty ? ['no rules'] : lines;
    }
    if (name == ':reset') { resetCycles(); return ['cycles reset']; }
    if (name == ':unused') { final numbers = [for (var index = 0; index < script.items.length; index++) if (state.itemUses[index] == 0) script.items[index].line]..sort(); return ['unused ${numbers.length}', ...grouped(numbers.map((number) => '$number').toList(), 12)]; }
    if (name == ':stats') return [countLine(state.session.turns, state.session.counts)];
    if (name == ':say' || name == ':explain') {
      if (isQuit(normalize(text))) return ['would quit'];
      final saved = state.copy(), result = decide(text);
      state = saved;
      return name == ':say' ? [result.$1] : result.$2;
    }
    final snapshot = state.session.undo;
    if (snapshot == null) return ['nothing to undo'];
    state = snapshot;
    return ['undone turn ${state.session.turns + 1}'];
  }
  void notes() {
    final session = state.session;
    transcript.addAll(['NOTES ${session.name}', '  ${countLine(session.turns, session.counts)}', '  topics: ${leaders(session.topics)}', '  words: ${leaders(session.words)}',
      '  memory: stored=${session.stored} recalled=${session.recalled} pending=${state.memory.texts.length}', '  unrecognized: ${session.unrecognized.isEmpty ? 'none' : session.unrecognized.join(' ')}']);
    totalTurns += session.turns;
    for (var index = 0; index < 5; index++) totalCounts[index] += session.counts[index];
  }
  void run(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('SESSION ')) {
        final name = line.substring(8);
        if (sessions > 0) { transcript.add(''); if (!script.persist.contains('cycles')) resetCycles(); if (!script.persist.contains('memory')) state.memory.clear('$name 0'); }
        sessions++;
        state.session = Session(name);
        transcript.add(line);
        final texts = script.texts['INITIAL']!;
        transcript.addAll(wrapReply(texts[(sessions - 1) % texts.length]));
      } else if (line.startsWith(':')) { transcript.add(line); transcript.addAll(command(line).map((text) => '  $text')); }
      else {
        transcript.add('YOU: $line');
        if (isQuit(normalize(line))) { final texts = script.texts['FINAL']!; transcript.addAll(wrapReply(texts[(sessions - 1) % texts.length])); notes(); }
        else respond(line);
      }
    }
    transcript.addAll(['', 'SUMMARY sessions=$sessions ${countLine(totalTurns, totalCounts)}']);
  }
  List<String> keywordStats() {
    final indices = List.generate(script.keywords.length, (index) => index)..sort((a, b) => state.keywordUses[a] != state.keywordUses[b] ? state.keywordUses[b].compareTo(state.keywordUses[a]) : script.keywords[a].word.compareTo(script.keywords[b].word));
    return ['keyword,rank,uses,replies,decomposition_hits', for (final id in indices) '${script.keywords[id].word},${script.keywords[id].rank},${state.keywordUses[id]},${state.keywordReplies[id]},${script.keywords[id].decomps.isEmpty ? '-' : script.keywords[id].decomps.map((rule) => state.hits[rule]).join('/')}'];
  }
}

void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final script = loadScript('input/script.txt');
  Directory('output').createSync(recursive: true);
  writeLines('lint.txt', lint(script));
  final chatbot = Chatbot(script)..run(readLines('input/dialogue.txt'));
  writeLines('transcript.txt', chatbot.transcript);
  writeLines('keyword_stats.csv', chatbot.keywordStats());
  writeLines('memory_log.txt', chatbot.state.memory.log);
}
