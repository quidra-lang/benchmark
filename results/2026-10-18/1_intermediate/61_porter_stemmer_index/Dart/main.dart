import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final tokenPattern = RegExp(r'[A-Za-z]+');
final wordPattern = RegExp(r'^[A-Za-z]{1,30}$');
final numberPattern = RegExp(r'^[0-9]{1,7}$');
final prefixTermPattern = RegExp(r'^[A-Za-z]{1,30}\*$');
final lexemePattern = RegExp(r'[()]|[^ ()]+');
const vowels = 'aeiou';
const stepNames = ['1a', '1b', '1c', '2', '3', '4', '5a', '5b'];
const step4Suffixes = [
  'al',
  'ance',
  'ence',
  'er',
  'ic',
  'able',
  'ible',
  'ant',
  'ement',
  'ment',
  'ent',
  'ion',
  'ou',
  'ism',
  'ate',
  'iti',
  'ous',
  'ive',
  'ize',
];
const kwicWidth = 30;
const maxCount = 100;
const maxDocumentNumber = 999;
const maxLineNumber = 999;

class CommandError implements Exception {
  final String message;

  CommandError(this.message);
}

String letterPattern(String word) {
  final kinds = <String>[];
  for (var index = 0; index < word.length; index++) {
    final letter = word[index];
    final vowel =
        vowels.contains(letter) ||
        (letter == 'y' && index > 0 && kinds.last == 'C');
    kinds.add(vowel ? 'V' : 'C');
  }
  return kinds.join();
}

int measure(String word) => 'VC'.allMatches(letterPattern(word)).length;

bool hasVowel(String word) => letterPattern(word).contains('V');

bool endsDouble(String word) =>
    letterPattern(word).endsWith('CC') &&
    word[word.length - 1] == word[word.length - 2];

bool endsCvc(String word) =>
    letterPattern(word).endsWith('CVC') &&
    !'wxy'.contains(word[word.length - 1]);

bool always(String remainder) => true;

bool measureAboveZero(String remainder) => measure(remainder) > 0;

bool measureAboveOne(String remainder) => measure(remainder) > 1;

bool ionCondition(String remainder) =>
    measure(remainder) > 1 &&
    (remainder.endsWith('s') || remainder.endsWith('t'));

bool finalECondition(String remainder) {
  final value = measure(remainder);
  return value > 1 || (value == 1 && !endsCvc(remainder));
}

class Rule {
  final String suffix;
  final String replacement;
  final bool Function(String) condition;

  const Rule(this.suffix, this.replacement, this.condition);
}

List<Rule> rulesWith(
  bool Function(String) condition,
  Map<String, String> replacements,
) => [
  for (final MapEntry(key: suffix, value: replacement) in replacements.entries)
    Rule(suffix, replacement, condition),
];

final ruleTables = <String, List<Rule>>{
  '1a': rulesWith(always, {'sses': 'ss', 'ies': 'i', 'ss': 'ss', 's': ''}),
  '1b': [
    Rule('eed', 'ee', measureAboveZero),
    Rule('ed', '', hasVowel),
    Rule('ing', '', hasVowel),
  ],
  '1c': [Rule('y', 'i', hasVowel)],
  '2': rulesWith(measureAboveZero, {
    'ational': 'ate',
    'tional': 'tion',
    'enci': 'ence',
    'anci': 'ance',
    'izer': 'ize',
    'abli': 'able',
    'alli': 'al',
    'entli': 'ent',
    'eli': 'e',
    'ousli': 'ous',
    'ization': 'ize',
    'ation': 'ate',
    'ator': 'ate',
    'alism': 'al',
    'iveness': 'ive',
    'fulness': 'ful',
    'ousness': 'ous',
    'aliti': 'al',
    'iviti': 'ive',
    'biliti': 'ble',
  }),
  '3': rulesWith(measureAboveZero, {
    'icate': 'ic',
    'ative': '',
    'alize': 'al',
    'iciti': 'ic',
    'ical': 'ic',
    'ful': '',
    'ness': '',
  }),
  '4': [
    for (final suffix in step4Suffixes)
      Rule(suffix, '', suffix == 'ion' ? ionCondition : measureAboveOne),
  ],
  '5a': [Rule('e', '', finalECondition)],
};

(String, String?) applyRules(String word, List<Rule> rules) {
  final matching = rules.where((rule) => word.endsWith(rule.suffix));
  if (matching.isEmpty) return (word, null);
  final rule = matching.reduce(
    (longest, rule) =>
        rule.suffix.length > longest.suffix.length ? rule : longest,
  );
  final remainder = word.substring(0, word.length - rule.suffix.length);
  if (!rule.condition(remainder)) return (word, null);
  return (remainder + rule.replacement, rule.suffix);
}

String tidyStep1b(String word) {
  if (['at', 'bl', 'iz'].any(word.endsWith)) return '${word}e';
  if (endsDouble(word) && !'lsz'.contains(word[word.length - 1])) {
    return word.substring(0, word.length - 1);
  }
  if (measure(word) == 1 && endsCvc(word)) return '${word}e';
  return word;
}

String applyStep(String name, String word) {
  if (name == '5b') {
    if (measure(word) > 1 && endsDouble(word) && word.endsWith('l')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }
  final (result, suffix) = applyRules(word, ruleTables[name]!);
  if (name == '1b' && (suffix == 'ed' || suffix == 'ing'))
    return tidyStep1b(result);
  return result;
}

(String, List<(String, String)>) stemmingSteps(String word) {
  final changes = <(String, String)>[];
  var current = word;
  if (word.length > 2) {
    for (final name in stepNames) {
      final result = applyStep(name, current);
      if (result != current) changes.add((name, result));
      current = result;
    }
  }
  return (current, changes);
}

String porterStem(String word) {
  final (stem, _) = stemmingSteps(word);
  return stem;
}

String yesNo(bool flag) => flag ? 'YES' : 'NO';

String wordArgument(String text) {
  if (!wordPattern.hasMatch(text)) throw CommandError('BAD WORD $text');
  return text.toLowerCase();
}

int numberArgument(String text, int minimum, int maximum) {
  if (!numberPattern.hasMatch(text)) throw CommandError('BAD NUMBER $text');
  final value = int.parse(text);
  if (value < minimum || value > maximum)
    throw CommandError('BAD NUMBER $text');
  return value;
}

List<String> splitArguments(String name, String rest) {
  if (name == 'SEARCH') return [rest];
  if (name == 'APPEND') {
    final space = rest.indexOf(' ');
    return space < 0
        ? [rest]
        : [rest.substring(0, space), rest.substring(space + 1)];
  }
  return rest.split(' ');
}

int byCount(MapEntry<String, int> left, MapEntry<String, int> right) {
  final byValue = right.value.compareTo(left.value);
  return byValue != 0 ? byValue : left.key.compareTo(right.key);
}

int? closestDistance(List<int> positions, List<int> others, bool sameStem) {
  final List<int> gaps;
  if (sameStem) {
    gaps = [
      for (var index = 1; index < positions.length; index++)
        positions[index] - positions[index - 1],
    ];
  } else {
    // The closest pair of different stems is adjacent in the merged order.
    final merged = [
      for (final position in positions) (position: position, source: 0),
      for (final other in others) (position: other, source: 1),
    ]..sort((left, right) => left.position.compareTo(right.position));
    gaps = [
      for (var index = 1; index < merged.length; index++)
        if (merged[index - 1].source != merged[index].source)
          merged[index].position - merged[index - 1].position,
    ];
  }
  return gaps.isEmpty ? null : gaps.reduce(min);
}

(int, int) jaccard(int common, int union) {
  if (union == 0) return (0, 1);
  final divisor = common.gcd(union);
  return (common ~/ divisor, union ~/ divisor);
}

enum LexemeKind { and, or, not, open, close, term, prefix }

typedef QueryItem = ({LexemeKind kind, String spelling});

typedef QueryResult = (String canonical, Set<int> documents);

const symbols = {
  'AND': LexemeKind.and,
  'OR': LexemeKind.or,
  'NOT': LexemeKind.not,
  '(': LexemeKind.open,
  ')': LexemeKind.close,
};

const conjunctionContinuations = {
  LexemeKind.and,
  LexemeKind.not,
  LexemeKind.open,
  LexemeKind.term,
  LexemeKind.prefix,
};

QueryItem classify(String lexeme) {
  final symbol = symbols[lexeme];
  if (symbol != null) return (kind: symbol, spelling: lexeme);
  if (wordPattern.hasMatch(lexeme)) {
    return (kind: LexemeKind.term, spelling: lexeme.toLowerCase());
  }
  if (prefixTermPattern.hasMatch(lexeme)) {
    return (
      kind: LexemeKind.prefix,
      spelling: lexeme.substring(0, lexeme.length - 1).toLowerCase(),
    );
  }
  throw CommandError('BAD TERM $lexeme');
}

class Token {
  final String text;
  final int line;
  final int position;
  final int start;
  late final String form = text.toLowerCase();
  late final String stem = porterStem(form);

  Token(this.text, this.line, this.position, this.start);

  int get end => start + text.length;
}

class Document {
  final int number;
  final lines = <String>[];
  final tokens = <Token>[];

  Document(this.number);

  List<Token> addLine(String text) {
    lines.add(text);
    final added = <Token>[];
    for (final match in tokenPattern.allMatches(text)) {
      final token = Token(
        match[0]!,
        lines.length,
        tokens.length + 1,
        match.start,
      );
      tokens.add(token);
      added.add(token);
    }
    return added;
  }

  List<Token> lineTokens(int lineNumber) =>
      tokens.where((token) => token.line == lineNumber).toList();

  String reference(Token token) => '$number:${token.line}:${token.position}';
}

typedef Occurrence = ({Document document, Token token});

int documentCount(List<Occurrence> occurrences) =>
    occurrences.map((occurrence) => occurrence.document.number).toSet().length;

class QueryParser {
  final List<QueryItem> items;
  final Map<int, Set<String>> stemSets;
  var position = 0;

  QueryParser(this.items, this.stemSets);

  LexemeKind? peek() => position < items.length ? items[position].kind : null;

  QueryItem take() {
    if (position >= items.length) throw CommandError('SYNTAX');
    return items[position++];
  }

  QueryResult parse() {
    final result = expression();
    if (position < items.length) throw CommandError('SYNTAX');
    return result;
  }

  QueryResult expression() {
    var (canonical, documents) = conjunction();
    while (peek() == LexemeKind.or) {
      position++;
      final (right, rightDocuments) = conjunction();
      canonical = '($canonical OR $right)';
      documents = documents.union(rightDocuments);
    }
    return (canonical, documents);
  }

  QueryResult conjunction() {
    var (canonical, documents) = negation();
    while (conjunctionContinuations.contains(peek())) {
      if (peek() == LexemeKind.and) position++;
      final (right, rightDocuments) = negation();
      canonical = '($canonical AND $right)';
      documents = documents.intersection(rightDocuments);
    }
    return (canonical, documents);
  }

  QueryResult negation() {
    if (peek() == LexemeKind.not) {
      position++;
      final (canonical, documents) = negation();
      return ('(NOT $canonical)', stemSets.keys.toSet().difference(documents));
    }
    return element();
  }

  QueryResult element() {
    final item = take();
    switch (item.kind) {
      case LexemeKind.open:
        final result = expression();
        if (take().kind != LexemeKind.close) throw CommandError('SYNTAX');
        return result;
      case LexemeKind.term:
        final stem = porterStem(item.spelling);
        return (stem, documentsWhere((stems) => stems.contains(stem)));
      case LexemeKind.prefix:
        return (
          '${item.spelling}*',
          documentsWhere(
            (stems) => stems.any((stem) => stem.startsWith(item.spelling)),
          ),
        );
      default:
        throw CommandError('SYNTAX');
    }
  }

  Set<int> documentsWhere(bool Function(Set<String>) condition) => {
    for (final MapEntry(key: number, value: stems) in stemSets.entries)
      if (condition(stems)) number,
  };
}

typedef Command = ({
  int minimum,
  int maximum,
  void Function(List<String>) handler,
});

class SearchEngine {
  final Set<String> stopwords;
  final documents = SplayTreeMap<int, Document>();
  final output = StringBuffer();
  late final Map<String, Command> handlers = {
    'STEM': (minimum: 1, maximum: 10, handler: stemWords),
    'STEPS': (minimum: 1, maximum: 1, handler: showSteps),
    'MEASURE': (minimum: 1, maximum: 1, handler: showMeasure),
    'INDEX': (minimum: 0, maximum: 1, handler: showIndex),
    'SEARCH': (minimum: 1, maximum: 1, handler: search),
    'PHRASE': (minimum: 2, maximum: 10, handler: phrase),
    'NEAR': (minimum: 3, maximum: 3, handler: near),
    'TOP': (minimum: 1, maximum: 2, handler: top),
    'KWIC': (minimum: 1, maximum: 1, handler: kwic),
    'TF': (minimum: 2, maximum: 2, handler: termFrequency),
    'DF': (minimum: 1, maximum: 1, handler: documentFrequency),
    'VARIANTS': (minimum: 1, maximum: 1, handler: variants),
    'SIMILAR': (minimum: 2, maximum: 2, handler: similar),
    'RANK': (minimum: 2, maximum: 11, handler: rank),
    'INFO': (minimum: 1, maximum: 1, handler: info),
    'LINE': (minimum: 2, maximum: 2, handler: showLine),
    'STATS': (minimum: 0, maximum: 0, handler: stats),
    'STOP': (minimum: 1, maximum: 1, handler: stop),
    'UNSTOP': (minimum: 1, maximum: 1, handler: unstop),
    'APPEND': (minimum: 2, maximum: 2, handler: append),
    'DELETE': (minimum: 1, maximum: 1, handler: delete),
  };

  SearchEngine(this.stopwords);

  void emit(String head, [List<String> items = const []]) {
    output.writeln([head, ...items].join(' '));
  }

  Document addDocument(int number) => documents[number] = Document(number);

  bool isStopword(String word) => stopwords.contains(word);

  bool isIndexed(Token token) => !stopwords.contains(token.form);

  List<Token> indexedTokens(Document document) =>
      document.tokens.where(isIndexed).toList();

  Map<String, int> termFrequencies(Document document) {
    final counts = <String, int>{};
    for (final token in indexedTokens(document)) {
      counts.update(token.stem, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Set<String> stemSet(Document document) =>
      termFrequencies(document).keys.toSet();

  Map<String, int> totalFrequencies() {
    final totals = <String, int>{};
    for (final document in documents.values) {
      for (final MapEntry(key: stem, value: count) in termFrequencies(
        document,
      ).entries) {
        totals.update(stem, (total) => total + count, ifAbsent: () => count);
      }
    }
    return totals;
  }

  Map<String, List<Occurrence>> occurrenceMap() {
    final occurrences = <String, List<Occurrence>>{};
    for (final document in documents.values) {
      for (final token in indexedTokens(document)) {
        occurrences.putIfAbsent(token.stem, () => []).add((
          document: document,
          token: token,
        ));
      }
    }
    return occurrences;
  }

  List<Occurrence> occurrencesOf(String stem) => occurrenceMap()[stem] ?? [];

  List<int> stemPositions(Document document, String stem) => [
    for (final token in indexedTokens(document))
      if (token.stem == stem) token.position,
  ];

  int formCount(String form) => documents.values
      .expand((document) => document.tokens)
      .where((token) => token.form == form)
      .length;

  bool tokenMatches(Token token, String target) =>
      target == '?' || (isIndexed(token) && token.stem == target);

  String describeToken(Token token) =>
      isIndexed(token) ? '${token.form}/${token.stem}' : '${token.form}/-';

  String termArgument(String text) {
    final word = wordArgument(text);
    if (isStopword(word)) throw CommandError('STOPWORD $word');
    return porterStem(word);
  }

  Document documentArgument(String text) {
    final number = numberArgument(text, 1, maxDocumentNumber);
    final document = documents[number];
    if (document == null) throw CommandError('NO DOC $number');
    return document;
  }

  void stemWords(List<String> arguments) {
    final words = arguments.map(wordArgument).toList();
    emit('STEM', [for (final word in words) '$word:${porterStem(word)}']);
  }

  void showSteps(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    final (_, changes) = stemmingSteps(word);
    if (changes.isEmpty) {
      emit('STEPS $word NONE');
    } else {
      emit('STEPS $word', [
        for (final (name, result) in changes) '$name:$result',
      ]);
    }
  }

  void showMeasure(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    emit('MEASURE $word', [
      letterPattern(word),
      'm=${measure(word)}',
      'vowel=${yesNo(hasVowel(word))}',
      'double=${yesNo(endsDouble(word))}',
      'cvc=${yesNo(endsCvc(word))}',
    ]);
  }

  void showIndex(List<String> arguments) {
    final prefix = arguments.isEmpty ? '' : wordArgument(arguments[0]);
    final occurrences = occurrenceMap();
    final stems =
        occurrences.keys.where((stem) => stem.startsWith(prefix)).toList()
          ..sort();
    emit('INDEX stems=${stems.length}');
    for (final stem in stems) {
      final found = occurrences[stem]!;
      emit('$stem df=${documentCount(found)}', [
        for (final (:document, :token) in found) document.reference(token),
      ]);
    }
  }

  void search(List<String> arguments) {
    final items = [
      for (final match in lexemePattern.allMatches(arguments[0]))
        classify(match[0]!),
    ];
    final stemSets = {
      for (final document in documents.values)
        document.number: stemSet(document),
    };
    final (canonical, matches) = QueryParser(items, stemSets).parse();
    for (final (:kind, :spelling) in items) {
      if (kind == LexemeKind.term && isStopword(spelling)) {
        throw CommandError('STOPWORD $spelling');
      }
    }
    emit('SEARCH $canonical count=${matches.length}', [
      for (final number in matches.toList()..sort()) '$number',
    ]);
  }

  void phrase(List<String> arguments) {
    final words = arguments.map(wordArgument).toList();
    if (words.every(isStopword)) throw CommandError('STOPWORDS ONLY');
    final targets = [
      for (final word in words) isStopword(word) ? '?' : porterStem(word),
    ];
    final matches = <String>[];
    for (final document in documents.values) {
      final tokens = document.tokens;
      for (var start = 0; start + targets.length <= tokens.length; start++) {
        final matched = Iterable<int>.generate(targets.length).every(
          (offset) => tokenMatches(tokens[start + offset], targets[offset]),
        );
        if (matched) matches.add(document.reference(tokens[start]));
      }
    }
    emit('PHRASE "${targets.join(' ')}" matches=${matches.length}', matches);
  }

  void near(List<String> arguments) {
    final first = termArgument(arguments[0]);
    final second = termArgument(arguments[1]);
    final limit = numberArgument(arguments[2], 1, maxCount);
    final found = <String>[];
    for (final document in documents.values) {
      final distance = closestDistance(
        stemPositions(document, first),
        stemPositions(document, second),
        first == second,
      );
      if (distance != null && distance <= limit)
        found.add('${document.number}:$distance');
    }
    emit('NEAR $first $second $limit count=${found.length}', found);
  }

  void top(List<String> arguments) {
    final limit = numberArgument(arguments[0], 1, maxCount);
    final Map<String, int> counts;
    final String header;
    if (arguments.length == 2) {
      final document = documentArgument(arguments[1]);
      counts = termFrequencies(document);
      header = 'TOP $limit doc=${document.number}';
    } else {
      counts = totalFrequencies();
      header = 'TOP $limit';
    }
    final ranked = counts.entries.toList()..sort(byCount);
    emit(header, [
      for (final entry in ranked.take(limit)) '${entry.key}:${entry.value}',
    ]);
  }

  void kwic(List<String> arguments) {
    final stem = termArgument(arguments[0]);
    final found = occurrencesOf(stem);
    emit('KWIC $stem count=${found.length}');
    for (final (:document, :token) in found) {
      final text = document.lines[token.line - 1];
      final before = text.substring(
        max(0, token.start - kwicWidth),
        token.start,
      );
      final after = text.substring(
        token.end,
        min(text.length, token.end + kwicWidth),
      );
      emit(
        '|${before.padLeft(kwicWidth)}[${token.text}]${after.padRight(kwicWidth)}| '
        '${document.reference(token)}',
      );
    }
  }

  void termFrequency(List<String> arguments) {
    final document = documentArgument(arguments[0]);
    final stem = termArgument(arguments[1]);
    emit('TF ${document.number} $stem ${termFrequencies(document)[stem] ?? 0}');
  }

  void documentFrequency(List<String> arguments) {
    final stem = termArgument(arguments[0]);
    emit('DF $stem ${documentCount(occurrencesOf(stem))}');
  }

  void variants(List<String> arguments) {
    final stem = termArgument(arguments[0]);
    final forms = SplayTreeMap<String, int>();
    for (final occurrence in occurrencesOf(stem)) {
      forms.update(
        occurrence.token.form,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    emit('VARIANTS $stem count=${forms.length}', [
      for (final MapEntry(key: form, value: count) in forms.entries)
        '$form:$count',
    ]);
  }

  void similar(List<String> arguments) {
    final document = documentArgument(arguments[0]);
    final limit = numberArgument(arguments[1], 1, maxCount);
    final stems = stemSet(document);
    final scores = <({int number, int numerator, int denominator})>[];
    for (final other in documents.values) {
      if (identical(other, document)) continue;
      final otherStems = stemSet(other);
      final (numerator, denominator) = jaccard(
        stems.intersection(otherStems).length,
        stems.union(otherStems).length,
      );
      scores.add((
        number: other.number,
        numerator: numerator,
        denominator: denominator,
      ));
    }
    scores.sort((left, right) {
      final byScore = (right.numerator * left.denominator).compareTo(
        left.numerator * right.denominator,
      );
      return byScore != 0 ? byScore : left.number.compareTo(right.number);
    });
    emit('SIMILAR ${document.number}', [
      for (final score in scores.take(limit))
        '${score.number}:${score.numerator}/${score.denominator}',
    ]);
  }

  void rank(List<String> arguments) {
    final limit = numberArgument(arguments[0], 1, maxCount);
    final query = {
      for (final argument in arguments.skip(1)) termArgument(argument),
    };
    final ranked = <({int number, int matched, int total})>[];
    for (final document in documents.values) {
      final counts = termFrequencies(document);
      final matched = query.where(counts.containsKey).length;
      final total = query.fold<int>(
        0,
        (sum, stem) => sum + (counts[stem] ?? 0),
      );
      if (matched > 0)
        ranked.add((number: document.number, matched: matched, total: total));
    }
    ranked.sort((left, right) {
      if (left.matched != right.matched)
        return right.matched.compareTo(left.matched);
      if (left.total != right.total) return right.total.compareTo(left.total);
      return left.number.compareTo(right.number);
    });
    emit('RANK count=${ranked.length}', [
      for (final entry in ranked.take(limit))
        '${entry.number}:${entry.matched}:${entry.total}',
    ]);
  }

  void info(List<String> arguments) {
    final document = documentArgument(arguments[0]);
    final counts = termFrequencies(document);
    final ranked = counts.entries.toList()..sort(byCount);
    final top = ranked.isEmpty
        ? '-'
        : '${ranked.first.key}:${ranked.first.value}';
    final indexed = counts.values.fold<int>(0, (sum, count) => sum + count);
    emit('INFO ${document.number}', [
      'lines=${document.lines.length}',
      'tokens=${document.tokens.length}',
      'indexed=$indexed',
      'stems=${counts.length}',
      'top=$top',
    ]);
  }

  void showLine(List<String> arguments) {
    final document = documentArgument(arguments[0]);
    final lineNumber = numberArgument(arguments[1], 1, maxLineNumber);
    if (lineNumber > document.lines.length) {
      throw CommandError('NO LINE ${document.number}:$lineNumber');
    }
    final tokens = document.lineTokens(lineNumber);
    emit(
      'LINE ${document.number}:$lineNumber tokens=${tokens.length}',
      tokens.map(describeToken).toList(),
    );
  }

  void stats(List<String> arguments) {
    final all = documents.values;
    emit('STATS', [
      'docs=${all.length}',
      'lines=${all.fold<int>(0, (sum, document) => sum + document.lines.length)}',
      'tokens=${all.fold<int>(0, (sum, document) => sum + document.tokens.length)}',
      'indexed=${all.fold<int>(0, (sum, document) => sum + indexedTokens(document).length)}',
      'stems=${totalFrequencies().length}',
      'stopwords=${stopwords.length}',
    ]);
  }

  void stop(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (isStopword(word)) throw CommandError('ALREADY STOPWORD $word');
    stopwords.add(word);
    emit('STOP $word unindexed=${formCount(word)}');
  }

  void unstop(List<String> arguments) {
    final word = wordArgument(arguments[0]);
    if (!isStopword(word)) throw CommandError('NOT STOPWORD $word');
    stopwords.remove(word);
    emit('UNSTOP $word indexed=${formCount(word)}');
  }

  void append(List<String> arguments) {
    final number = numberArgument(arguments[0], 1, maxDocumentNumber);
    final created = !documents.containsKey(number);
    final document = documents[number] ?? addDocument(number);
    final tokens = document.addLine(arguments[1]);
    final indexed = tokens.where(isIndexed).length;
    emit('APPEND $number', [
      'line=${document.lines.length}',
      'tokens=${tokens.length}',
      'indexed=$indexed',
      'new=${yesNo(created)}',
    ]);
  }

  void delete(List<String> arguments) {
    final document = documentArgument(arguments[0]);
    documents.remove(document.number);
    emit(
      'DELETE ${document.number} lines=${document.lines.length} tokens=${document.tokens.length}',
    );
  }

  void execute(String line) {
    final space = line.indexOf(' ');
    final name = space < 0 ? line : line.substring(0, space);
    try {
      final command = handlers[name];
      if (command == null) throw CommandError('UNKNOWN COMMAND $name');
      final arguments = space < 0
          ? <String>[]
          : splitArguments(name, line.substring(space + 1));
      if (arguments.length < command.minimum ||
          arguments.length > command.maximum) {
        throw CommandError('BAD ARGUMENTS $name');
      }
      command.handler(arguments);
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
  }
}

Future<void> main() async {
  final lines = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  final engine = SearchEngine(lines[0].split(' ').skip(1).toSet());
  var index = 1;
  while (lines[index].startsWith('DOC ')) {
    final document = engine.addDocument(int.parse(lines[index].substring(4)));
    index++;
    while (lines[index] != 'ENDDOC') {
      document.addLine(lines[index]);
      index++;
    }
    index++;
  }
  for (final line in lines.skip(index)) {
    if (line == 'END') break;
    engine.execute(line);
  }
  stdout.write(engine.output);
}
