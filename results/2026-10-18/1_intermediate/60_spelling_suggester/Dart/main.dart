import 'dart:io';
import 'dart:math';

const adjacentKeys = {
  'a': 'qswz',
  'b': 'ghnv',
  'c': 'dfvx',
  'd': 'cefrsx',
  'e': 'drsw',
  'f': 'cdgrtv',
  'g': 'bfhtvy',
  'h': 'bgjnuy',
  'i': 'jkou',
  'j': 'hikmnu',
  'k': 'ijlmo',
  'l': 'kop',
  'm': 'jkn',
  'n': 'bhjm',
  'o': 'iklp',
  'p': 'lo',
  'q': 'aw',
  'r': 'deft',
  's': 'adewxz',
  't': 'fgry',
  'u': 'hijy',
  'v': 'bcfg',
  'w': 'aeqs',
  'x': 'cdsz',
  'y': 'ghtu',
  'z': 'asx',
};
const soundexGroups = [
  ('bfpv', '1'),
  ('cgjkqsxz', '2'),
  ('dt', '3'),
  ('l', '4'),
  ('mn', '5'),
  ('r', '6'),
  ('aeiouy', '0'),
];
final soundexDigits = {
  for (final (letters, digit) in soundexGroups)
    for (final letter in letters.split('')) letter: digit,
};
final letterRun = RegExp('[A-Za-z]+');
final sentenceMark = RegExp('[.!?]');
final wordPattern = RegExp(r'^[A-Za-z]{1,30}$');
final numberPattern = RegExp(r'^[0-9]{1,7}$');
const findingKinds = ['unknown', 'case', 'capital', 'repeats'];
const counterNames = [
  'checked',
  'unknown',
  'case',
  'capital',
  'repeats',
  'corrected',
];
const optionMaximums = {'LIMIT': 3, 'SUGGESTIONS': 10};
const keyboardModes = ['ON', 'OFF'];
const maxWordLength = 30;
const maxFrequency = 1000000;
const maxListed = 20;
const reportSize = 10;

typedef Candidate = ({String word, int frequency, int distance});

typedef UndoRecord = ({
  String name,
  Map<String, int> dictionary,
  Set<String> ignored,
  Map<String, String> rules,
});

class CommandError implements Exception {
  final String message;

  CommandError(this.message);
}

String wordArgument(String text) {
  if (!wordPattern.hasMatch(text)) {
    throw CommandError('BAD WORD $text');
  }
  return text.toLowerCase();
}

int numberArgument(String text, int minimum, int maximum) {
  if (!numberPattern.hasMatch(text)) {
    throw CommandError('BAD NUMBER $text');
  }
  final value = int.parse(text);
  if (value < minimum || value > maximum) {
    throw CommandError('BAD NUMBER $text');
  }
  return value;
}

String decimalText(int numerator, int denominator, int digits) {
  final scale = pow(10, digits).toInt();
  final value = (2 * numerator * scale + denominator) ~/ (2 * denominator);
  final fraction = (value % scale).toString().padLeft(digits, '0');
  return '${value ~/ scale}.$fraction';
}

int byDecreasingValue(MapEntry<String, int> a, MapEntry<String, int> b) =>
    a.value != b.value ? b.value - a.value : a.key.compareTo(b.key);

int compareCandidates(Candidate a, Candidate b) {
  if (a.distance != b.distance) {
    return a.distance - b.distance;
  }
  if (a.frequency != b.frequency) {
    return b.frequency - a.frequency;
  }
  return a.word.compareTo(b.word);
}

bool isUpperCase(String character) => character != character.toLowerCase();

bool isLowerCase(String character) => character != character.toUpperCase();

String capitalizeFirst(String word) =>
    word[0].toUpperCase() + word.substring(1);

String applyCase(String tokenText, String word) {
  if (tokenText.length >= 2 && tokenText == tokenText.toUpperCase()) {
    return word.toUpperCase();
  }
  if (isUpperCase(tokenText[0])) {
    return capitalizeFirst(word);
  }
  return word;
}

class Token {
  final int number;
  final String text;
  final String word;
  final int end;
  final String gap;
  final bool sentenceStart;
  final bool repeat;

  Token(
    this.number,
    this.text,
    this.word,
    this.end,
    this.gap, {
    required this.sentenceStart,
    required this.repeat,
  });

  bool get mixedCase =>
      text.substring(1).split('').any(isUpperCase) &&
      text != text.toUpperCase();
}

List<Token> tokenize(String text) {
  final tokens = <Token>[];
  var position = 0;
  for (final match in letterRun.allMatches(text)) {
    final tokenText = match[0]!;
    final word = tokenText.toLowerCase();
    final gap = text.substring(position, match.start);
    final previous = tokens.lastOrNull;
    tokens.add(
      Token(
        tokens.length + 1,
        tokenText,
        word,
        match.end,
        gap,
        sentenceStart: previous == null || gap.contains(sentenceMark),
        repeat:
            previous != null &&
            word == previous.word &&
            gap == ' ' * gap.length,
      ),
    );
    position = match.end;
  }
  return tokens;
}

int gapCost(bool keyboard) => keyboard ? 2 : 1;

int substitutionCost(String first, String second, bool keyboard) {
  if (first == second) {
    return 0;
  }
  if (!keyboard) {
    return 1;
  }
  return adjacentKeys[first]!.contains(second) ? 1 : 2;
}

bool isSwap(String first, String second, int i, int j) =>
    i >= 2 &&
    j >= 2 &&
    first[i - 1] == second[j - 2] &&
    first[i - 2] == second[j - 1];

List<List<int>> distanceTable(String first, String second, bool keyboard) {
  final gap = gapCost(keyboard);
  final rows = first.length;
  final columns = second.length;
  final table = List.generate(rows + 1, (_) => List.filled(columns + 1, 0));
  for (var i = 0; i <= rows; i++) {
    table[i][0] = i * gap;
  }
  for (var j = 0; j <= columns; j++) {
    table[0][j] = j * gap;
  }
  for (var i = 1; i <= rows; i++) {
    for (var j = 1; j <= columns; j++) {
      var best = min(table[i - 1][j], table[i][j - 1]) + gap;
      best = min(
        best,
        table[i - 1][j - 1] +
            substitutionCost(first[i - 1], second[j - 1], keyboard),
      );
      if (isSwap(first, second, i, j)) {
        best = min(best, table[i - 2][j - 2] + 1);
      }
      table[i][j] = best;
    }
  }
  return table;
}

int editDistance(String first, String second, bool keyboard) =>
    distanceTable(first, second, keyboard)[first.length][second.length];

int prefixDistance(String word, String other, bool keyboard) =>
    distanceTable(word, other, keyboard)[word.length].reduce(min);

(int, List<String>) editOperations(String first, String second, bool keyboard) {
  final table = distanceTable(first, second, keyboard);
  final gap = gapCost(keyboard);
  final operations = <String>[];
  var i = first.length;
  var j = second.length;
  while (i > 0 || j > 0) {
    if (i >= 1 &&
        j >= 1 &&
        table[i][j] ==
            table[i - 1][j - 1] +
                substitutionCost(first[i - 1], second[j - 1], keyboard)) {
      if (first[i - 1] != second[j - 1]) {
        operations.add('sub:${first[i - 1]}>${second[j - 1]}');
      }
      i--;
      j--;
    } else if (isSwap(first, second, i, j) &&
        table[i][j] == table[i - 2][j - 2] + 1) {
      operations.add('swap:${first[i - 2]}${first[i - 1]}');
      i -= 2;
      j -= 2;
    } else if (i >= 1 && table[i][j] == table[i - 1][j] + gap) {
      operations.add('del:${first[i - 1]}');
      i--;
    } else {
      operations.add('ins:${second[j - 1]}');
      j--;
    }
  }
  return (table[first.length][second.length], operations.reversed.toList());
}

String soundex(String word) {
  final first = word[0];
  var code = first.toUpperCase();
  var previous = 'hw'.contains(first) ? '0' : soundexDigits[first]!;
  for (final letter in word.substring(1).split('')) {
    if ('hw'.contains(letter)) {
      continue;
    }
    final digit = soundexDigits[letter]!;
    if (digit != '0' && digit != previous) {
      code += digit;
    }
    previous = digit;
  }
  return '${code}000'.substring(0, 4);
}

int compareSegmentations(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return first.length - second.length;
  }
  for (var i = 0; i < first.length; i++) {
    final order = first[i].compareTo(second[i]);
    if (order != 0) {
      return order;
    }
  }
  return 0;
}

(int, List<String>?) segment(String word, Map<String, int> dictionary) {
  final length = word.length;
  final ways = List.filled(length + 1, 0);
  final best = List<List<String>?>.filled(length + 1, null);
  ways[length] = 1;
  best[length] = [];
  for (var start = length - 1; start >= 0; start--) {
    for (var end = start + 1; end <= length; end++) {
      final piece = word.substring(start, end);
      if (!dictionary.containsKey(piece) || ways[end] == 0) {
        continue;
      }
      ways[start] += ways[end];
      final candidate = [piece, ...best[end]!];
      final current = best[start];
      if (current == null || compareSegmentations(candidate, current) < 0) {
        best[start] = candidate;
      }
    }
  }
  return (ways[0], best[0]);
}

class SpellChecker {
  Map<String, int> dictionary;
  Set<String> ignored = {};
  Map<String, String> rules = {};
  var keyboard = false;
  var baseLimit = 2;
  var suggestionCount = 5;
  final undoHistory = <UndoRecord>[];
  final unknownLog = <String, int>{};
  final correctionLog = <(String, String), int>{};
  final counters = {for (final name in counterNames) name: 0};
  final output = StringBuffer();
  late final Map<String, void Function(String)> textCommands = {
    'CHECK': check,
    'CORRECT': correct,
    'FIX': fix,
    'PROFILE': profile,
    'LEARN': learn,
  };
  late final Map<String, (int, void Function(List<String>))> argumentCommands =
      {
        'SUGGEST': (1, suggest),
        'DIST': (2, dist),
        'SOUNDEX': (1, soundexCode),
        'SOUNDS': (1, sounds),
        'SPLIT': (1, split),
        'PREFIX': (2, prefix),
        'COMPLETE': (2, complete),
        'LIST': (2, listWords),
        'WORD': (1, wordInfo),
        'ADD': (2, add),
        'REMOVE': (1, remove),
        'IGNORE': (1, ignore),
        'UNIGNORE': (1, unignore),
        'RULE': (2, rule),
        'UNRULE': (1, unrule),
        'RULES': (0, (_) => showRules()),
        'KEYBOARD': (1, keyboardMode),
        'SET': (2, setOption),
        'UNDO': (0, (_) => undo()),
        'REPORT': (0, (_) => report()),
        'HISTORY': (0, (_) => history()),
        'STATS': (0, (_) => stats()),
      };

  SpellChecker(this.dictionary);

  void emit(String head, [Iterable<String> items = const []]) {
    output.writeln([head, ...items].join(' '));
  }

  int get limit => keyboard ? 2 * baseLimit : baseLimit;

  bool isKnown(String word) =>
      dictionary.containsKey(word) || ignored.contains(word);

  List<String> frequencyOrder() {
    final entries = dictionary.entries.toList()..sort(byDecreasingValue);
    return [for (final entry in entries) entry.key];
  }

  int requireEntry(String word) =>
      dictionary[word] ?? (throw CommandError('NOT FOUND $word'));

  List<Candidate> candidates(String word) {
    final gap = gapCost(keyboard);
    final found = <Candidate>[];
    for (final MapEntry(key: other, value: frequency) in dictionary.entries) {
      if (other == word || (other.length - word.length).abs() * gap > limit) {
        continue;
      }
      final distance = editDistance(word, other, keyboard);
      if (distance <= limit) {
        found.add((word: other, frequency: frequency, distance: distance));
      }
    }
    return found..sort(compareCandidates);
  }

  String? correction(String word) {
    if (isKnown(word)) {
      return null;
    }
    if (rules[word] case final target?) {
      return target;
    }
    return candidates(word).firstOrNull?.word;
  }

  void recordUndo(String name) {
    undoHistory.add((
      name: name,
      dictionary: Map.of(dictionary),
      ignored: Set.of(ignored),
      rules: Map.of(rules),
    ));
  }

  void logCorrection(String word, String replacement) {
    correctionLog.update(
      (word, replacement),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    counters.update('corrected', (count) => count + 1);
  }

  String unknownFinding(Token token) {
    final prefix = 'UNKNOWN ${token.number} ${token.text}';
    if (rules[token.word] case final target?) {
      return '$prefix RULE $target';
    }
    final found = candidates(token.word);
    if (found.isEmpty) {
      return '$prefix NONE';
    }
    return [
      prefix,
      'SUGGEST',
      for (final candidate in found.take(suggestionCount)) candidate.word,
    ].join(' ');
  }

  void check(String text) {
    final tokens = tokenize(text);
    final findings = <(String, String)>[];
    for (final token in tokens) {
      if (!isKnown(token.word)) {
        findings.add(('unknown', unknownFinding(token)));
        unknownLog.update(token.word, (count) => count + 1, ifAbsent: () => 1);
      }
      if (token.mixedCase) {
        findings.add(('case', 'CASE ${token.number} ${token.text}'));
      }
      if (token.sentenceStart && isLowerCase(token.text[0])) {
        findings.add(('capital', 'CAPITAL ${token.number} ${token.text}'));
      }
      if (token.repeat) {
        findings.add(('repeats', 'REPEAT ${token.number} ${token.text}'));
      }
    }
    final counts = {
      for (final kind in findingKinds)
        kind: findings.where((finding) => finding.$1 == kind).length,
    };
    counters.update('checked', (count) => count + tokens.length);
    for (final kind in findingKinds) {
      counters.update(kind, (count) => count + counts[kind]!);
    }
    emit('CHECK words=${tokens.length}', [
      for (final kind in findingKinds) '$kind=${counts[kind]}',
    ]);
    for (final (_, line) in findings) {
      emit(line);
    }
  }

  void correct(String text) {
    final result = StringBuffer();
    var position = 0;
    var changed = 0;
    for (final token in tokenize(text)) {
      final replacement = correction(token.word);
      if (replacement == null) {
        result.write('${token.gap}${token.text}');
      } else {
        result.write('${token.gap}${applyCase(token.text, replacement)}');
        logCorrection(token.word, replacement);
        changed++;
      }
      position = token.end;
    }
    result.write(text.substring(position));
    emit('CORRECT changed=$changed: $result');
  }

  void fix(String text) {
    final result = StringBuffer();
    var position = 0;
    var removed = 0;
    var replaced = 0;
    var recased = 0;
    for (final token in tokenize(text)) {
      position = token.end;
      if (token.repeat) {
        removed++;
        continue;
      }
      final replacement = correction(token.word);
      var fixed = applyCase(token.text, replacement ?? token.word);
      if (token.sentenceStart && isLowerCase(fixed[0])) {
        fixed = capitalizeFirst(fixed);
      }
      if (replacement != null) {
        logCorrection(token.word, replacement);
        replaced++;
      } else if (fixed != token.text) {
        recased++;
      }
      result.write('${token.gap}$fixed');
    }
    result.write(text.substring(position));
    emit('FIX removed=$removed replaced=$replaced recased=$recased: $result');
  }

  void profile(String text) {
    final tokens = tokenize(text);
    final distinct = tokens.map((token) => token.word).toSet().length;
    final unknown = tokens.where((token) => !isKnown(token.word)).length;
    final sentences = tokens.where((token) => token.sentenceStart).length;
    final characters = tokens.fold(0, (sum, token) => sum + token.text.length);
    final (rate, average, longest) = tokens.isEmpty
        ? ('0.0', '0.00', '-')
        : (
            decimalText(100 * unknown, tokens.length, 1),
            decimalText(characters, tokens.length, 2),
            tokens.reduce((a, b) => b.text.length > a.text.length ? b : a).word,
          );
    emit('PROFILE', [
      'words=${tokens.length}',
      'distinct=$distinct',
      'unknown=$unknown',
      'rate=$rate',
      'avglen=$average',
      'longest=$longest',
      'sentences=$sentences',
    ]);
  }

  void learn(String text) {
    recordUndo('LEARN');
    var updated = 0;
    var added = 0;
    var skipped = 0;
    for (final token in tokenize(text)) {
      if (token.word.length > maxWordLength) {
        skipped++;
      } else if (dictionary.containsKey(token.word)) {
        dictionary.update(token.word, (frequency) => frequency + 1);
        updated++;
      } else {
        dictionary[token.word] = 1;
        ignored.remove(token.word);
        added++;
      }
    }
    emit('LEARN updated=$updated added=$added skipped=$skipped');
  }

  void suggest(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (isKnown(word)) {
      emit('SUGGEST $word KNOWN');
    } else if (rules[word] case final target?) {
      emit('SUGGEST $word RULE $target');
    } else {
      final found = candidates(word);
      emit('SUGGEST $word found=${found.length}', [
        for (final candidate in found.take(suggestionCount))
          '${candidate.word}:${candidate.distance}',
      ]);
    }
  }

  void dist(List<String> arguments) {
    final first = wordArgument(arguments[0]);
    final second = wordArgument(arguments[1]);
    final (distance, operations) = editOperations(first, second, keyboard);
    emit('DIST $first $second $distance', operations);
  }

  void soundexCode(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    emit('SOUNDEX $word ${soundex(word)}');
  }

  void sounds(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final code = soundex(word);
    final matches = [
      for (final other in frequencyOrder())
        if (other != word && soundex(other) == code) other,
    ];
    emit(
      'SOUNDS $word $code count=${matches.length}',
      matches.take(reportSize),
    );
  }

  void split(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final (ways, best) = segment(word, dictionary);
    if (best == null) {
      emit('SPLIT $word ways=0 -> NONE');
    } else {
      emit('SPLIT $word ways=$ways ->', best);
    }
  }

  void prefix(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final count = numberArgument(arguments[1], 1, maxListed);
    final matches = [
      for (final other in frequencyOrder())
        if (other.startsWith(word)) other,
    ];
    emit('PREFIX $word count=${matches.length}', [
      for (final other in matches.take(count)) '$other:${dictionary[other]}',
    ]);
  }

  void complete(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final count = numberArgument(arguments[1], 1, maxListed);
    final threshold = limit ~/ 2;
    final matches = <Candidate>[];
    for (final MapEntry(key: other, value: frequency) in dictionary.entries) {
      final distance = prefixDistance(word, other, keyboard);
      if (distance <= threshold) {
        matches.add((word: other, frequency: frequency, distance: distance));
      }
    }
    matches.sort(compareCandidates);
    emit('COMPLETE $word count=${matches.length}', [
      for (final match in matches.take(count))
        '${match.word}:${match.distance}',
    ]);
  }

  void listWords(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final count = numberArgument(arguments[1], 1, maxListed);
    final matches = [
      for (final other in dictionary.keys)
        if (other.compareTo(word) >= 0) other,
    ]..sort();
    emit('LIST $word count=${matches.length}', [
      for (final other in matches.take(count)) '$other:${dictionary[other]}',
    ]);
  }

  void wordInfo(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final frequency = requireEntry(word);
    final rank = frequencyOrder().indexOf(word) + 1;
    emit('WORD', [
      word,
      'freq=$frequency',
      'rank=$rank',
      'soundex=${soundex(word)}',
      'neighbors=${candidates(word).length}',
    ]);
  }

  void add(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final frequency = numberArgument(arguments[1], 1, maxFrequency);
    if (dictionary.containsKey(word)) {
      throw CommandError('DUPLICATE $word');
    }
    recordUndo('ADD');
    dictionary[word] = frequency;
    ignored.remove(word);
    emit('ADD $word $frequency');
  }

  void remove(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final frequency = requireEntry(word);
    recordUndo('REMOVE');
    dictionary.remove(word);
    emit('REMOVE $word $frequency');
  }

  void ignore(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (dictionary.containsKey(word)) {
      throw CommandError('IN DICTIONARY $word');
    }
    if (ignored.contains(word)) {
      throw CommandError('ALREADY IGNORED $word');
    }
    recordUndo('IGNORE');
    ignored.add(word);
    emit('IGNORE $word');
  }

  void unignore(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (!ignored.contains(word)) {
      throw CommandError('NOT IGNORED $word');
    }
    recordUndo('UNIGNORE');
    ignored.remove(word);
    emit('UNIGNORE $word');
  }

  void rule(List<String> arguments) {
    final source = wordArgument(arguments[0]);
    final target = wordArgument(arguments[1]);
    if (dictionary.containsKey(source)) {
      throw CommandError('IN DICTIONARY $source');
    }
    if (!dictionary.containsKey(target)) {
      throw CommandError('NOT FOUND $target');
    }
    recordUndo('RULE');
    final previous = rules[source];
    rules[source] = target;
    if (previous == null) {
      emit('RULE $source $target');
    } else {
      emit('RULE $source $target REPLACED $previous');
    }
  }

  void unrule(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (!rules.containsKey(word)) {
      throw CommandError('NO RULE $word');
    }
    recordUndo('UNRULE');
    final target = rules.remove(word);
    emit('UNRULE $word $target');
  }

  void showRules() {
    final sources = rules.keys.toList()..sort();
    emit('RULES count=${rules.length}', [
      for (final source in sources) '$source>${rules[source]}',
    ]);
  }

  void keyboardMode(List<String> arguments) {
    final mode = arguments[0];
    if (!keyboardModes.contains(mode)) {
      throw CommandError('BAD MODE $mode');
    }
    keyboard = mode == 'ON';
    emit('KEYBOARD $mode');
  }

  void setOption(List<String> arguments) {
    final option = arguments[0];
    final maximum =
        optionMaximums[option] ?? (throw CommandError('BAD OPTION $option'));
    final value = numberArgument(arguments[1], 1, maximum);
    if (option == 'LIMIT') {
      baseLimit = value;
    } else {
      suggestionCount = value;
    }
    emit('SET $option $value');
  }

  void undo() {
    if (undoHistory.isEmpty) {
      throw CommandError('NOTHING TO UNDO');
    }
    final record = undoHistory.removeLast();
    dictionary = record.dictionary;
    ignored = record.ignored;
    rules = record.rules;
    emit('UNDO ${record.name}');
  }

  void report() {
    final entries = unknownLog.entries.toList()..sort(byDecreasingValue);
    emit('REPORT distinct=${entries.length}', [
      for (final entry in entries.take(reportSize))
        '${entry.key}:${entry.value}',
    ]);
  }

  void history() {
    final entries = correctionLog.entries.toList()
      ..sort((a, b) {
        if (a.value != b.value) {
          return b.value - a.value;
        }
        final order = a.key.$1.compareTo(b.key.$1);
        return order != 0 ? order : a.key.$2.compareTo(b.key.$2);
      });
    emit('HISTORY distinct=${entries.length}', [
      for (final MapEntry(key: (word, replacement), value: count)
          in entries.take(reportSize))
        '$word>$replacement:$count',
    ]);
  }

  void stats() {
    final top = frequencyOrder().first;
    final characters = dictionary.keys.fold(
      0,
      (sum, word) => sum + word.length,
    );
    final total = dictionary.values.fold(
      0,
      (sum, frequency) => sum + frequency,
    );
    emit('STATS', [
      'words=${dictionary.length}',
      'total=$total',
      'avglen=${decimalText(characters, dictionary.length, 2)}',
      'top=$top:${dictionary[top]}',
      'ignored=${ignored.length}',
      'rules=${rules.length}',
      'keyboard=${keyboard ? 'ON' : 'OFF'}',
      'limit=$limit',
      'suggestions=$suggestionCount',
      'undo=${undoHistory.length}',
    ]);
    emit('SESSION', [
      for (final name in counterNames) '$name=${counters[name]}',
    ]);
  }

  void execute(String line) {
    final space = line.indexOf(' ');
    final name = space < 0 ? line : line.substring(0, space);
    final rest = space < 0 ? null : line.substring(space + 1);
    try {
      if (textCommands[name] case final handler?) {
        if (rest == null) {
          throw CommandError('BAD ARGUMENTS $name');
        }
        handler(rest);
      } else if (argumentCommands[name] case (final arity, final handler)?) {
        final arguments = rest?.split(' ') ?? [];
        if (arguments.length != arity) {
          throw CommandError('BAD ARGUMENTS $name');
        }
        handler(arguments);
      } else {
        throw CommandError('UNKNOWN COMMAND $name');
      }
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
  }
}

void main() {
  final dictionary = <String, int>{};
  final wordCount = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < wordCount; i++) {
    final [word, frequency] = stdin.readLineSync()!.split(' ');
    dictionary[word] = int.parse(frequency);
  }
  final checker = SpellChecker(dictionary);
  final commandCount = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < commandCount; i++) {
    checker.execute(stdin.readLineSync()!);
  }
  stdout.write(checker.output);
}
