import 'dart:io';

const systems = ['HEPBURN', 'TRADITIONAL', 'KUNREI', 'NIHON', 'WAPURO'];
const rowNames = ['a', 'ka', 'sa', 'ta', 'na', 'ha', 'ma', 'ya', 'ra', 'wa', 'ga', 'za', 'da',
  'ba', 'pa'];
const baseRows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5];
const rowText = [
  'a i u e o', 'ka ki ku ke ko', 'sa si su se so', 'ta ti tu te to',
  'na ni nu ne no', 'ha hi hu he ho', 'ma mi mu me mo', 'ya yu yo',
  'ra ri ru re ro', 'wa wi we wo', 'ga gi gu ge go', 'za zi zu ze zo',
  'da di du de do', 'ba bi bu be bo', 'pa pi pu pe po',
];
const gojuonText = 'a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N';
const irohaText = 'i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N';
const moraN = 108, moraQ = 109, moraL = 110;

class LanguageError implements Exception {
  final String message;
  LanguageError(this.message);
}

bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool upper(int c) => c >= 65 && c <= 90;
bool wordCharacter(int c) => letter(c) || c == 39 || c == 45;
bool vowel(String c) => c.isNotEmpty && 'aiueo'.contains(c);
class Syllable {
  final String id, dan;
  final int row;
  Syllable(this.id, this.row, this.dan);
}

String spelling(String id, int system) {
  if (system == 3)
    return id;
  if (system == 2) {
    const changes = {
      'di': 'zi',
      'du': 'zu',
      'wi': 'i',
      'we': 'e',
      'wo': 'o',
      'dya': 'zya',
      'dyu': 'zyu',
      'dyo': 'zyo'
    };
    return changes[id] ?? id;
  }
  final hepburn = system == 0 || system == 1;
  const common = { 'si': 'shi', 'ti': 'chi', 'tu': 'tsu', 'hu': 'fu', 'zi': 'ji' };
  if (common.containsKey(id))
    return common[id]!;
  if (hepburn) {
    const extra = { 'di': 'ji', 'du': 'zu', 'wi': 'i', 'we': 'e', 'wo': 'o' };
    if (extra.containsKey(id))
      return extra[id]!;
  }
  if (id.length == 3) {
    final prefix = id.substring(0, 2), last = id.substring(2);
    if (prefix == 'sy')
      return 'sh$last';
    if (prefix == 'ty')
      return 'ch$last';
    if (prefix == 'zy' || hepburn && prefix == 'dy')
      return 'j$last';
  }
  return id;
}

class Mora {
  final int id, column;
  Mora(this.id, this.column);
}

class Element {
  final int base, voice, size;
  Element(this.base, this.voice, this.size);
}

class Word {
  final String original;
  final int start, end, ordinal;
  int pattern = 0; // lowercase, title, uppercase
  List<Mora> morae = [];
  List<Element> elements = [];
  Word(this.original, this.start, this.end, this.ordinal);
}

class Engine {
  final table = <Syllable>[];
  final gojuon = gojuonText.split(' '), iroha = irohaText.split(' ');
  late final List<List<String>> spellings;
  String longMode = 'KEEP', caseMode = 'KEEP', order = 'GOJUON';
  Engine() {
    for (var row = 0; row < rowText.length; row++) {
      for (final id in rowText[row].split(' ')) {
        table.add(Syllable(id, row, id.substring(id.length - 1)));
      }
    }
    for (final row in [1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14]) {
      final stem = table.firstWhere((m) => m.row == row && m.dan == 'i').id;
      for (final dan in ['ya', 'yu', 'yo']) {
        table.add(Syllable(stem.substring(0, stem.length - 1) + dan, row, dan));
      }
    }
    spellings = [for (var s = 0; s < 5; s++)[for (final mora in table) spelling(mora.id, s)]];
  }
  Never columnError(int column, String message) => throw LanguageError('col $column: $message');
  List<Word> words(String text) {
    final result = <Word>[];
    var i = 0;
    while (i < text.length) {
      if (!wordCharacter(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      while (i < text.length && wordCharacter(text.codeUnitAt(i)))
        i++;
      result.add(Word(text.substring(start, i), start, i, result.length));
    }
    return result;
  }

  void checkCase(Word word) {
    final codes = word.original.codeUnits, letters = codes.where(letter).toList();
    if (letters.every((c) => !upper(c))) {
      word.pattern = 0;
      return;
    }
    if (upper(codes.first) && codes.skip(1).where(letter).every((c) => !upper(c))) {
      word.pattern = 1;
      return;
    }
    if (letters.length >= 2 && letters.every(upper)) {
      word.pattern = 2;
      return;
    }
    columnError(word.start + 1, 'mixed case');
  }

  (int, int)? match(String text, int position, int system) {
    (int, int)? best;
    for (var id = 0; id < table.length; id++) {
      final choices = system == 5 ? [0, 2, 3, 4] : [system];
      for (final s in choices) {
        final candidate = spellings[s][id];
        if (text.startsWith(candidate, position) && (best == null || candidate.length > best.$2)) {
          best = (id, candidate.length);
        }
      }
    }
    return best;
  }
  List<Mora> parse(String original, int start, int system) {
    final text = original.toLowerCase(), result = <Mora>[];
    var p = 0;
    while (p < text.length) {
      final c = text[p], next = p + 1 < text.length ? text[p + 1] : '';
      final column = start + p + 1;
      if (c == '-') {
        if (result.isEmpty || result.last.id >= moraN)
          columnError(column, 'misplaced long mark');
        result.add(Mora(moraL, column));
        p++;
        continue;
      }
      if (c == "'")
        columnError(column, 'misplaced apostrophe');
      final syllable = match(text, p, system);
      if (syllable != null) {
        result.add(Mora(syllable.$1, column));
        p += syllable.$2;
        continue;
      }
      if ((system == 4 || system == 5) && text.startsWith('xtu', p)) {
        result.add(Mora(moraQ, column));
        p += 3;
        continue;
      }
      if (c == 'n') {
        var advance = 1;
        if (system == 5) {
          final third = p + 2 < text.length ? text[p + 2] : '';
          if (next == "'" || next == 'n' && !vowel(third) && third != 'y' && third != "'")
            advance = 2;
        } else if (system == 4) {
          if (next == 'n')
            advance = 2;
        } else if (next == "'") {
          advance = 2;
        }
        result.add(Mora(moraN, column));
        p += advance;
        continue;
      }
      if ((system == 1 || system == 5) && c == 'm' && next.isNotEmpty && 'bmp'.contains(next)) {
        result.add(Mora(moraN, column));
        p++;
        continue;
      }
      if (letter(c.codeUnitAt(0)) && !'aiueon'.contains(c) && next == c && match(text, p + 1, system) != null) {
        result.add(Mora(moraQ, column));
        p++;
        continue;
      }
      if ((system == 0 || system == 1 || system == 5) && c == 't' && text.startsWith('ch', p + 1) && match(text,
        p + 1, system) != null) {
        result.add(Mora(moraQ, column));
        p++;
        continue;
      }
      columnError(column, 'unknown syllable');
    }
    return result;
  }

  String moraVowel(int id) => table[id].id.substring(table[id].id.length - 1);
  List<bool> pairs(List<Mora> morae) {
    final result = List.filled(morae.length, false);
    var i = 0;
    while (i + 1 < morae.length) {
      final a = morae[i].id, b = morae[i + 1].id;
      if (a < moraN && b < 5) {
        final v = moraVowel(a), following = table[b].id;
        if (v == following || v == 'o' && following == 'u' || v == 'e' && following == 'i') {
          result[i + 1] = true;
          i += 2;
          continue;
        }
      }
      i++;
    }
    return result;
  }
  List<bool> longElements(List<Mora> morae) {
    final paired = pairs(morae), result = List.filled(morae.length, false);
    for (var i = 0; i < morae.length; i++) {
      if (morae[i].id == moraL) {
        result[i] = true;
        continue;
      }
      if (!paired[i])
        continue;
      final v = moraVowel(morae[i - 1].id), following = table[morae[i].id].id;
      result[i] = v == 'o' && (following == 'o' || following == 'u') || v == 'u' && following == 'u';
    }
    return result;
  }
  List<String> parts(List<Mora> morae, int target, String longSetting) {
    final long = longElements(morae), result = <String>[];
    for (var i = 0; i < morae.length; i++) {
      final mora = morae[i], nextId = i + 1 < morae.length ? morae[i + 1].id : -1;
      final next = nextId >= 0 && nextId < moraN ? spellings[target][nextId] : '';
      final first = next.isEmpty ? '' : next[0];
      if (long[i]) {
        final v = moraVowel(morae[i - 1].id);
        result.add(switch (longSetting) {
          'KEEP' => mora.id == moraL ? '-' : spellings[target][mora.id],
          'DROP' => '',
          'PASSPORT' => v == 'o' && !vowel(first) ? 'h' : '',
          'HYPHEN' => '-',
          _ => v,
        });
      } else if (mora.id < moraN) {
        result.add(spellings[target][mora.id]);
      } else if (mora.id == moraN) {
        if (target == 4) {
          result.add(nextId == moraN || vowel(first) || first == 'y' || first == 'n' ? 'nn' : 'n');
        } else if (target == 1 && first.isNotEmpty && 'bmp'.contains(first)) {
          result.add('m');
        } else {
          result.add(vowel(first) || first == 'y' ? "n'" : 'n');
        }
      } else {
        if (first.isNotEmpty && !'aiueon'.contains(first)) {
          result.add((target == 0 || target == 1) && next.startsWith('ch') ? 't' : first);
        } else if (target == 4) {
          result.add('xtu');
        } else {
          columnError(mora.column, 'small tsu cannot be written');
        }
      }
    }
    return result;
  }

  String write(Word word, int target, { bool canonical = false, List<Mora>? morae }) {
    final raw = parts(morae ?? word.morae, target, canonical ? 'KEEP' : longMode).join();
    final pattern = canonical || caseMode == 'KEEP' ? word.pattern : caseMode == 'LOWER' ? 0 : caseMode == 'TITLE' ? 1 : 2;
    return pattern == 0 ? raw : pattern == 1 ? raw[0].toUpperCase() + raw.substring(1) : raw.toUpperCase();
  }

  bool sameMorae(List<Mora> a, List<Mora> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].id == b[i].id].every((x)
    => x);
  List<Mora> loose(Word word) {
    final long = longElements(word.morae);
    return [for (var i = 0; i < word.morae.length; i++) if (!long[i]) word.morae[i]];
  }

  String devoiced(String id) {
    const from = 'gzdbp', to = 'ksthh';
    final i = from.indexOf(id[0]);
    return i < 0 ? id : to[i] + id.substring(1);
  }

  void collate(Word word) {
    final result = <Element>[];
    void add(String base, int voice, int size) => result.add(Element(gojuon.indexOf(base), voice,
      size));
    for (final mora in word.morae) {
      if (mora.id == moraL)
        continue;
      if (mora.id == moraN) {
        add('N', 0, 0);
        continue;
      }
      if (mora.id == moraQ) {
        add('tu', 0, 1);
        continue;
      }
      final m = table[mora.id], voice = m.row >= 10 && m.row <= 13 ? 1 : m.row == 14 ? 2 : 0;
      if (mora.id < 72) {
        add(devoiced(m.id), voice, 0);
      } else {
        add(devoiced(m.id[0] + 'i'), voice, 0);
        add(m.id.substring(1), 0, 1);
      }
    }
    word.elements = result;
  }

  int compareSequence(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0)
        return c;
    }
    return a.length.compareTo(b.length);
  }

  int compareWords(Word a, Word b) {
    final rank = [for (final base in gojuon) order == 'GOJUON' ? gojuon.indexOf(base) : iroha.indexOf(base)];
    final sequencesA = [a.elements.map((e) => rank[e.base]).toList(), a.elements.map((e) => e.voice).toList(),
      a.elements.map((e) => e.size).toList(), a.morae.map((m) => m.id == moraL ? 1 : 0).toList()];
    final sequencesB = [b.elements.map((e) => rank[e.base]).toList(), b.elements.map((e) => e.voice).toList(),
      b.elements.map((e) => e.size).toList(), b.morae.map((m) => m.id == moraL ? 1 : 0).toList()];
    for (var i = 0; i < 4; i++) {
      final c = compareSequence(sequencesA[i], sequencesB[i]);
      if (c != 0)
        return c;
    }
    return a.ordinal.compareTo(b.ordinal);
  }
  List<int> pattern(String text, int system) {
    if (text.codeUnits.any((c) => !(c >= 97 && c <= 122 || c == 39 || c == 45 || c == 63 || c == 42)))
      throw LanguageError('invalid pattern');
    final result = <int>[];
    var start = 0;
    try {
      for (var i = 0; i <= text.length; i++) {
        if (i == text.length || text[i] == '?' || text[i] == '*') {
          if (i > start)
            result.addAll(parse(text.substring(start, i), start, system).map((m) => m.id));
          if (i < text.length)
            result.add(text[i] == '?' ? -1 : -2);
          start = i + 1;
        }
      }
    } on LanguageError {
      throw LanguageError('invalid pattern');
    }
    return result;
  }

  bool matches(List<int> pattern, List<Mora> morae) {
    var previous = List.filled(morae.length + 1, false);
    previous[0] = true;
    for (final token in pattern) {
      final current = List.filled(morae.length + 1, false);
      for (var j = 0; j <= morae.length; j++) {
        current[j] = token == -2 ? previous[j] || j > 0 && current[j - 1] : j > 0 && previous[j - 1] && (token == -1
          || token == morae[j - 1].id);
      }
      previous = current;
    }
    return previous.last;
  }

  String execute(String line) {
    const commands = ['SET', 'TABLE', 'CONVERT', 'NORMALIZE', 'REVERSE', 'VALID', 'DETECT', 'DIFF',
      'SAME', 'MORAE', 'SYLLABLES', 'ROW', 'STATS', 'SORT', 'INDEX', 'FIND', 'HAIKU', 'KAIBUN', 'SHIRITORI'];
    final firstSpace = line.indexOf(' '), op = firstSpace < 0 ? line : line.substring(0, firstSpace);
    if (!commands.contains(op))
      throw LanguageError('unknown command $op');
    final fixed = op == 'SET' || op == 'TABLE';
    final argumentCount = ['CONVERT', 'DIFF', 'SAME', 'FIND'].contains(op) ? 2 : ['NORMALIZE', 'DETECT'].contains(op) ? 0 : 1;
    List<String> args;
    String text = '';
    if (fixed) {
      final split = line.split(' ');
      if (split.length < 3)
        throw LanguageError('missing argument');
      if (split.length > 3)
        throw LanguageError('too many arguments');
      args = split.skip(1).toList();
    } else {
      args = [];
      var cursor = firstSpace;
      if (cursor < 0)
        throw LanguageError('missing argument');
      for (var i = 0; i < argumentCount; i++) {
        final end = line.indexOf(' ', cursor + 1);
        if (end < 0)
          throw LanguageError('missing argument');
        args.add(line.substring(cursor + 1, end));
        cursor = end;
      }
      text = line.substring(cursor + 1);
    }
    var system = 0, target = 0;
    final systemCount = op == 'TABLE' ? 1 : fixed || ['NORMALIZE', 'DETECT'].contains(op) ? 0 : ['CONVERT',
      'DIFF', 'SAME'].contains(op) ? 2 : 1;
    for (var i = 0; i < systemCount; i++) {
      final value = systems.indexOf(args[i]);
      if (value < 0)
        throw LanguageError('unknown system ${args[i]}');
      if (i == 0)
        system = value;
      else target = value;
    }
    if (op == 'SET') {
      const allowed = {
        'LONG': ['KEEP', 'DROP', 'PASSPORT', 'HYPHEN', 'DOUBLE'],
        'CASE': ['KEEP', 'LOWER', 'UPPER', 'TITLE'],
        'ORDER': ['GOJUON', 'IROHA']
      };
      if (!allowed.containsKey(args[0]))
        throw LanguageError('unknown option ${args[0]}');
      if (!allowed[args[0]]!.contains(args[1]))
        throw LanguageError('unknown value ${args[1]}');
      if (args[0] == 'LONG')
        longMode = args[1];
      else if (args[0] == 'CASE') caseMode = args[1];
      else order = args[1];
      return '${args[0]}=${args[1]}';
    }
    if (op == 'TABLE') {
      final row = rowNames.indexOf(args[1]);
      if (row < 0)
        throw LanguageError('unknown row ${args[1]}');
      return [for (var i = 0; i < table.length; i++) if (table[i].row == row) spellings[system][i]].join(' ');
    }
    final findPattern = op == 'FIND' ? pattern(args[1], system) : <int>[];
    final slash = op == 'SAME' || op == 'HAIKU';
    const separators = ' 0123456789.,!?;:()"';
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (!wordCharacter(c) && !separators.contains(text[i]) && !(slash && text[i] == '/'))
        columnError(i + 1, 'invalid character');
    }
    final parsed = words(text), lines = text.split('/');
    if (op == 'SAME' && (lines.length != 2 || lines.any((part) => words(part).isEmpty)))
      throw LanguageError('expected two texts');
    if (op == 'HAIKU' && (!(lines.length == 3 || lines.length == 5) || lines.any((part) => words(part).isEmpty)))
      throw LanguageError('expected 3 or 5 lines');
    if (parsed.isEmpty)
      throw LanguageError('no words');
    for (final word in parsed)
      checkCase(word);
    if (op == 'DETECT') {
      final results = <String>[];
      for (var s = 0; s < 5; s++) {
        var verdict = 'canonical';
        try {
          for (final word in parsed)
            word.morae = parse(word.original, word.start, s);
          if (parsed.any((word) => write(word, s, canonical: true) != word.original))
            verdict = 'readable';
        } on LanguageError {
          verdict = 'error';
        }
        results.add('${systems[s]}=$verdict');
      }
      return results.join(' ');
    }
    final slashPosition = op == 'SAME' ? text.indexOf('/') : -1;
    for (final word in parsed)
      word.morae = parse(word.original, word.start, op == 'NORMALIZE' ? 5 : op == 'SAME' && word.start > slashPosition ? target : system);
    if (['CONVERT', 'NORMALIZE', 'REVERSE'].contains(op)) {
      final output = StringBuffer();
      var cursor = 0;
      for (final word in parsed) {
        output.write(text.substring(cursor, word.start));
        List<Mora>? reversed;
        if (op == 'REVERSE') {
          reversed = [for (var i = 0; i < word.morae.length; i++) word.morae[i].id == moraL ? Mora('aiueo'.indexOf(moraVowel(word.morae[i - 1].id)),
            word.morae[i].column): word.morae[i]].reversed.toList();
        }
        output.write(write(word, op == 'NORMALIZE' ? 0 : op == 'REVERSE' ? system : target, morae: reversed));
        cursor = word.end;
      }
      output.write(text.substring(cursor));
      return output.toString();
    }
    if (op == 'VALID') {
      for (final word in parsed) {
        final canonical = write(word, system, canonical: true);
        if (canonical == word.original)
          continue;
        var i = 0;
        while (i < canonical.length && i < word.original.length && canonical[i] == word.original[i])
          i++;
        return 'INVALID col ${word.start + i + 1}: expected $canonical';
      }
      return 'VALID';
    }
    if (op == 'DIFF') {
      final differences = <String>[];
      for (final word in parsed) {
        final a = write(word, system), b = write(word, target);
        if (a != b)
          differences.add('$a>$b');
      }
      return '${differences.length} of ${parsed.length}${differences.isEmpty ? '' : ': ${differences.join(' ')}'}';
    }
    if (op == 'SAME') {
      final left = parsed.where((w) => w.start < slashPosition).toList(), right = parsed.where((w) => w.start > slashPosition).toList();
      var exact = true;
      for (var i = 0; i < left.length && i < right.length; i++) {
        if (!sameMorae(loose(left[i]), loose(right[i])))
          return 'DIFFERENT at word ${i + 1}';
        if (!sameMorae(left[i].morae, right[i].morae))
          exact = false;
      }
      if (left.length != right.length)
        return 'DIFFERENT at word ${(left.length < right.length ? left.length : right.length) + 1}';
      return exact ? 'EXACT' : 'LOOSE';
    }
    if (op == 'MORAE') {
      final total = parsed.fold(0, (s, w) => s + w.morae.length);
      String display(int id) => id < moraN ? spellings[system][id] : id == moraN ? 'N' : id == moraQ ? 'Q' : '-';
      return '$total: ${parsed.map((w) => w.morae.map((m) => display(m.id)).join('.')).join(' ')}';
    }
    if (op == 'SYLLABLES') {
      var total = 0;
      final result = <String>[];
      for (final word in parsed) {
        final paired = pairs(word.morae), written = parts(word.morae, system, 'KEEP'), out = StringBuffer();
        for (var i = 0; i < word.morae.length; i++) {
          if (i == 0 || word.morae[i].id < moraN && !paired[i]) {
            if (i > 0)
              out.write('.');
            total++;
          }
          out.write(written[i]);
        }
        result.add(out.toString());
      }
      return '$total: ${result.join(' ')}';
    }
    if (op == 'ROW') {
      final result = <String>[];
      for (final word in parsed) {
        for (final mora in word.morae) {
          final id = mora.id;
          result.add(id < moraN ? '${spellings[system][id]}: ${rowNames[table[id].row]} ${table[id].dan}' : '${id == moraN ? 'N' : id == moraQ ? 'Q' : '-'}: special');
        }
      }
      return result.join(', ');
    }
    if (op == 'STATS') {
      var total = 0, voiced = 0, semi = 0, contracted = 0;
      final rows = List.filled(10, 0), special = List.filled(3, 0);
      for (final word in parsed) {
        for (final mora in word.morae) {
          total++;
          if (mora.id >= moraN) {
            special[mora.id - moraN]++;
            continue;
          }
          final row = table[mora.id].row;
          rows[baseRows[row]]++;
          if (row >= 10 && row <= 13)
            voiced++;
          if (row == 14)
            semi++;
          if (mora.id >= 72)
            contracted++;
        }
      }
      return ['morae=$total', for (var i = 0; i < 10; i++) if (rows[i] > 0) '${rowNames[i]}=${rows[i]}',
        'voiced=$voiced', 'semivoiced=$semi', 'contracted=$contracted', 'N=${special[0]}', 'Q=${special[1]}',
        'L=${special[2]}'].join(' ');
    }
    if (op == 'FIND') {
      final found = parsed.where((word) => matches(findPattern, word.morae)).toList();
      return '${found.length} of ${parsed.length}${found.isEmpty ? '' : ': ${found.map((w) => w.original).join(' ')}'}';
    }
    if (op == 'HAIKU') {
      final counts = List.filled(lines.length, 0);
      for (final word in parsed)
        counts[text.substring(0, word.start).split('/').length - 1] += word.morae.length;
      const expected = [5, 7, 5, 7, 7];
      final ok = [for (var i = 0; i < counts.length; i++) counts[i] == expected[i]].every((x) => x);
      return '${ok ? 'OK' : 'NG'} ${counts.length == 3 ? 'haiku' : 'tanka'} ${counts.join('-')}';
    }
    for (final word in parsed)
      collate(word);
    if (op == 'SORT' || op == 'INDEX') {
      parsed.sort(compareWords);
      if (op == 'SORT')
        return parsed.map((w) => w.original).join(' ');
      final groups = <String>[];
      String? previous;
      var group = <String>[];
      for (final word in parsed) {
        final base = gojuon[word.elements.first.base];
        final heading = order == 'IROHA' || base == 'N' ? base : rowNames[table.firstWhere((m) => m.id == base).row];
        if (heading != previous) {
          if (previous != null)
            groups.add('$previous: ${group.join(' ')}');
          previous = heading;
          group = [];
        }
        group.add(word.original);
      }
      groups.add('$previous: ${group.join(' ')}');
      return groups.join('; ');
    }
    if (op == 'KAIBUN') {
      final sequence = parsed.expand((w) => w.elements).map((e) => e.base).toList();
      final palindrome = [for (var i = 0; i < sequence.length ~/ 2; i++) sequence[i] == sequence[sequence.length - 1 - i]].every((x)
        => x);
      return '${palindrome ? 'YES' : 'NO'} ${sequence.map((b) => gojuon[b]).join('.')}';
    }
    for (var i = 0; i < parsed.length; i++) {
      final word = parsed[i], head = word.elements.first.base, tail = word.elements.last.base;
      if (i > 0 && head != parsed[i - 1].elements.last.base) {
        final previous = gojuon[parsed[i - 1].elements.last.base];
        final expected = previous == 'N' ? 'N' : spellings[system][table.indexWhere((m) => m.id == previous)];
        return 'NG ${i + 1}: ${word.original} must start with $expected';
      }
      if (parsed.take(i).any((earlier) => sameMorae(earlier.morae, word.morae)))
        return 'NG ${i + 1}: ${word.original} is repeated';
      if (gojuon[tail] == 'N')
        return 'NG ${i + 1}: ${word.original} ends with N';
    }
    return 'OK ${parsed.length}';
  }
}

void main() {
  final engine = Engine(), count = int.parse(stdin.readLineSync()!);
  final output = StringBuffer();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      output.writeln(engine.execute(line));
    } on LanguageError catch (error) {
      output.writeln('ERROR ${error.message}');
    }
  }
  stdout.write(output);
}
