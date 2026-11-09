import 'dart:io';

enum Style { apa, ieee, chicago, mla }

class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

class LoadError implements Exception {
  final int line;
  final String message;
  const LoadError(this.line, this.message);
}

final knownFields = 'author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note'.split(' ');
final smallWords = 'a an and as at but by for from in into nor of on or over per so the to up via with yet'.split(' ').toSet();
final monthNames = 'January February March April May June July August September October November December'.split(' ');
final monthShort = 'Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.'.split(' ');

bool isLetter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool isDigit(int c) => c >= 48 && c <= 57;
bool isLower(int c) => c >= 97 && c <= 122;
bool isUpper(int c) => c >= 65 && c <= 90;
bool digits(String text) => text.isNotEmpty && text.codeUnits.every(isDigit);
int lowerCode(int c) => isUpper(c) ? c + 32 : c;
int upperCode(int c) => isLower(c) ? c - 32 : c;
String lower(String text) => String.fromCharCodes(text.codeUnits.map(lowerCode));
String plain(String text) => text.replaceAll('{', '').replaceAll('}', '');
String letters(String text) => String.fromCharCodes(text.codeUnits.where(isLetter));

List<String> splitTop(String text, String separator) {
  final result = <String>[];
  var depth = 0, start = 0, i = 0;
  while (i < text.length) {
    if (depth == 0 && text.startsWith(separator, i)) {
      result.add(text.substring(start, i));
      i += separator.length;
      start = i;
      continue;
    }
    if (text[i] == '{') depth++;
    if (text[i] == '}') depth--;
    i++;
  }
  result.add(text.substring(start));
  return result;
}

(String, int)? accent(String text, int i) {
  if (i + 1 >= text.length || text[i] != '\\') return null;
  final command = text[i + 1];
  if (command == '&') return ('&', 2);
  final symbol = "'\"`^~=.".contains(command);
  if (i + 4 < text.length && (symbol || 'cuvH'.contains(command)) &&
      text[i + 2] == '{' && isLetter(text.codeUnitAt(i + 3)) && text[i + 4] == '}') {
    return (text[i + 3], 5);
  }
  if (symbol && i + 2 < text.length && isLetter(text.codeUnitAt(i + 2))) return (text[i + 2], 3);
  return null;
}

String normalize(String text) {
  final result = StringBuffer();
  for (var i = 0; i < text.length;) {
    final wrapped = text[i] == '{' ? accent(text, i + 1) : null;
    if (wrapped != null && i + wrapped.$2 + 1 < text.length && text[i + wrapped.$2 + 1] == '}') {
      result.write(wrapped.$1);
      i += wrapped.$2 + 2;
    } else {
      final direct = accent(text, i);
      if (direct == null) {
        result.write(text[i++]);
      } else {
        result.write(direct.$1);
        i += direct.$2;
      }
    }
  }
  return result.toString().replaceAll('~', ' ').replaceAll(RegExp(' +'), ' ').trim();
}

String lowerOutside(String word) {
  final result = word.codeUnits.toList();
  var depth = 0;
  for (var i = 0; i < word.length; i++) {
    if (word[i] == '{') {
      depth++;
    } else if (word[i] == '}') {
      depth--;
    } else if (depth == 0) {
      result[i] = lowerCode(result[i]);
    }
  }
  return String.fromCharCodes(result);
}

String titleCase(String text, Style style) {
  if (style == Style.ieee) return text;
  if (style == Style.apa) {
    final result = text.codeUnits.toList();
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '{') {
        depth++;
      } else if (text[i] == '}') {
        depth--;
      } else if (depth == 0 && isLetter(result[i])) {
        result[i] = i == 0 || i >= 2 && text[i - 2] == ':' && text[i - 1] == ' '
            ? upperCode(result[i]) : lowerCode(result[i]);
      }
    }
    return String.fromCharCodes(result);
  }
  final words = splitTop(text, ' ');
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (word.startsWith('{')) continue;
    if (i > 0 && i + 1 < words.length && !words[i - 1].endsWith(':') && smallWords.contains(lower(letters(word)))) {
      words[i] = lowerOutside(word);
      continue;
    }
    var depth = 0;
    for (var j = 0; j < word.length; j++) {
      if (word[j] == '{') {
        depth++;
      } else if (word[j] == '}') {
        depth--;
      } else if (isLetter(word.codeUnitAt(j))) {
        if (depth == 0) words[i] = word.substring(0, j) + String.fromCharCode(upperCode(word.codeUnitAt(j))) + word.substring(j + 1);
        break;
      }
    }
  }
  return words.join(' ');
}

String listNames(List<String> names, String conjunction, {bool listB = false}) {
  if (names.length == 1) return names[0];
  if (listB && names.length == 2) return '${names[0]} $conjunction ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')}, $conjunction ${names.last}';
}

class Person {
  final String first, von, last, jr;
  const Person(this.first, this.von, this.last, this.jr);

  factory Person.parse(String text) {
    final parts = splitTop(text, ',').map((part) => part.trim()).toList();
    final words = splitTop(parts[0], ' ');
    var firstLower = -1, lastLower = -1;
    for (var i = 0; i + 1 < words.length; i++) {
      if (isLower(words[i].codeUnitAt(0))) {
        if (firstLower < 0) firstLower = i;
        lastLower = i;
      }
    }
    String join(int start, int end) => words.sublist(start, end).join(' ');
    if (parts.length == 1) {
      return firstLower < 0
          ? Person(join(0, words.length - 1), '', words.last, '')
          : Person(join(0, firstLower), join(firstLower, lastLower + 1), join(lastLower + 1, words.length), '');
    }
    return Person(parts.last, lastLower < 0 ? '' : join(0, lastLower + 1), join(lastLower + 1, words.length), parts.length == 3 ? parts[1] : '');
  }

  bool same(Person other) => first == other.first && von == other.von && last == other.last && jr == other.jr;
  String get surname => plain(von.isEmpty ? last : '$von $last');
  String get initials => plain(first).split(' ').where((word) => word.isNotEmpty).map((word) => word.split('-')
      .map((piece) => '${String.fromCharCode(upperCode(piece.codeUnits.firstWhere(isLetter)))}.').join('-')).join(' ');

  String format({required bool inverted, required bool useInitials}) {
    final given = useInitials ? initials : plain(first);
    var result = surname;
    if (first.isNotEmpty) result = inverted ? '$result, $given' : '$given $result';
    if (jr.isNotEmpty) result += ', ${plain(jr)}';
    return result;
  }
}

class NameList {
  final List<Person> names;
  final bool etAl;
  NameList(List<Person> names, this.etAl) : names = List.unmodifiable(names);

  factory NameList.parse(String text) {
    final parts = splitTop(text, ' and ');
    final etAl = parts.last == 'others';
    if (etAl) parts.removeLast();
    return NameList(parts.map(Person.parse).toList(), etAl);
  }

  bool get single => names.length == 1 && !etAl;
  bool same(NameList other) {
    if (etAl != other.etAl || names.length != other.names.length) return false;
    for (var i = 0; i < names.length; i++) {
      if (!names[i].same(other.names[i])) return false;
    }
    return true;
  }

  String authors(Style style) {
    final values = List.generate(names.length, (i) => names[i].format(
        inverted: style == Style.apa || style != Style.ieee && i == 0,
        useInitials: style == Style.apa || style == Style.ieee));
    return switch (style) {
      Style.apa when etAl => '${values.join(', ')}, et al.',
      Style.apa when values.length > 20 => '${values.take(19).join(', ')}, . . . ${values.last}',
      Style.apa => listNames(values, '&'),
      Style.ieee when etAl || values.length >= 7 => '${values[0]} et al.',
      Style.ieee => listNames(values, 'and', listB: true),
      Style.chicago when etAl || values.length >= 11 => '${values.take(7).join(', ')}, et al.',
      Style.chicago => listNames(values, 'and'),
      Style.mla when etAl || values.length >= 3 => '${values[0]}, et al.',
      Style.mla => listNames(values, 'and'),
    };
  }

  String editors(Style style) {
    final values = names.map((name) => name.format(inverted: false, useInitials: style == Style.apa || style == Style.ieee)).toList();
    return etAl ? '${values[0]} et al.' : listNames(values, style == Style.apa ? '&' : 'and', listB: true);
  }
}

class Entry {
  final String type, key;
  final Map<String, String> fields;
  final NameList? authors, editors;
  String suffix = '';

  Entry(this.type, this.key, Map<String, String> fields)
      : fields = Map.unmodifiable(fields),
        authors = fields.containsKey('author') ? NameList.parse(fields['author']!) : null,
        editors = fields.containsKey('editor') ? NameList.parse(fields['editor']!) : null;

  NameList get primary => authors ?? editors!;
  String value(String field) => plain(fields[field] ?? '');
  String year(Style style) => value('year') + (style == Style.apa || style == Style.chicago ? suffix : '');
  String get sortTitle {
    final title = lower(value('title'));
    for (final prefix in ['a ', 'an ', 'the ']) {
      if (title.startsWith(prefix)) return title.substring(prefix.length);
    }
    return title;
  }

  static int compare(Entry a, Entry b) {
    final left = [lower(plain(a.primary.names[0].last)), a.value('year'), a.sortTitle, a.key];
    final right = [lower(plain(b.primary.names[0].last)), b.value('year'), b.sortTitle, b.key];
    for (var i = 0; i < left.length; i++) {
      final order = left[i].compareTo(right[i]);
      if (order != 0) return order;
    }
    return 0;
  }
}

class Database {
  static const requiredFields = {
    'article': ['author', 'title', 'journal', 'year'],
    'book': ['author', 'title', 'publisher', 'year'],
    'inproceedings': ['author', 'title', 'booktitle', 'year'],
    'incollection': ['author', 'title', 'booktitle', 'publisher', 'year'],
    'techreport': ['author', 'title', 'institution', 'year'],
    'phdthesis': ['author', 'title', 'school', 'year'],
    'misc': ['author', 'title', 'year'],
  };
  final macros = <String, String>{};
  final entries = <Entry>[];
  final byKey = <String, Entry>{};
  final messages = <String>[];
  var macroCount = 0;

  Database(List<String> lines) {
    final monthKeys = 'jan feb mar apr may jun jul aug sep oct nov dec'.split(' ');
    for (var i = 0; i < monthKeys.length; i++) {
      macros[monthKeys[i]] = monthNames[i];
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('%')) continue;
      if (line.startsWith('@string{')) {
        final separator = line.indexOf(' = ');
        final name = line.substring(8, separator);
        try {
          final value = evaluate(line.substring(separator + 3, line.length - 1), i + 1);
          if (macros.containsKey(name)) throw LoadError(i + 1, 'duplicate macro');
          macros[name] = value;
          macroCount++;
        } on LoadError catch (error) {
          report(name, error);
        }
      } else {
        var end = i + 1;
        while (lines[end] != '}') {
          end++;
        }
        final brace = line.indexOf('{');
        final type = line.substring(1, brace), key = line.substring(brace + 1, line.length - 1);
        try {
          readEntry(lines, i, end, type, key);
        } on LoadError catch (error) {
          report(key, error);
        }
        i = end;
      }
    }
    assignSuffixes();
    messages.add('LOADED entries=${entries.length} macros=$macroCount errors=${messages.length}');
  }

  void report(String name, LoadError error) => messages.add('ERROR line ${error.line}: $name: ${error.message}');

  String evaluate(String expression, int line) {
    var depth = 0;
    for (final c in expression.codeUnits) {
      if (c == 123) depth++;
      if (c == 125) depth--;
      if (depth < 0) throw LoadError(line, 'unbalanced braces');
    }
    if (depth != 0) throw LoadError(line, 'unbalanced braces');
    final result = StringBuffer();
    for (final term in expression.split(' # ')) {
      if (term.startsWith('{') || term.startsWith('"')) {
        result.write(term.substring(1, term.length - 1));
      } else if (isDigit(term.codeUnitAt(0))) {
        result.write(term);
      } else if (macros.containsKey(term)) {
        result.write(macros[term]);
      } else {
        throw LoadError(line, "unknown macro '$term'");
      }
    }
    return result.toString();
  }

  void readEntry(List<String> lines, int start, int end, String type, String key) {
    final required = requiredFields[type];
    if (required == null) throw LoadError(start + 1, "unknown type '$type'");
    if (byKey.containsKey(key)) throw LoadError(start + 1, 'duplicate key');
    final fields = <String, String>{};
    for (var i = start + 1; i < end; i++) {
      final separator = lines[i].indexOf(' = ');
      final name = lines[i].substring(2, separator);
      var expression = lines[i].substring(separator + 3);
      if (expression.endsWith(',')) expression = expression.substring(0, expression.length - 1);
      final value = evaluate(expression, i + 1);
      if (fields.containsKey(name)) throw LoadError(i + 1, "duplicate field '$name'");
      fields[name] = normalize(value);
    }
    for (final field in required) {
      if (!fields.containsKey(field) && !(type == 'book' && field == 'author' && fields.containsKey('editor'))) {
        throw LoadError(end + 1, "missing field '$field'");
      }
    }
    final entry = Entry(type, key, fields);
    entries.add(entry);
    byKey[key] = entry;
  }

  void assignSuffixes() {
    final done = <Entry>{};
    for (final entry in entries) {
      if (done.contains(entry)) continue;
      final group = entries.where((other) => other.primary.same(entry.primary) && other.fields['year'] == entry.fields['year']).toList()
        ..sort((a, b) {
          final order = a.sortTitle.compareTo(b.sortTitle);
          return order == 0 ? a.key.compareTo(b.key) : order;
        });
      for (var i = 0; i < group.length; i++) {
        done.add(group[i]);
        if (group.length > 1) group[i].suffix = String.fromCharCode(97 + i);
      }
    }
  }
}

sealed class TemplatePart {
  const TemplatePart();
}

class LiteralPart extends TemplatePart {
  final String text;
  const LiteralPart(this.text);
}

class FieldPart extends TemplatePart {
  final String name;
  const FieldPart(this.name);
}

class OptionalPart extends TemplatePart {
  final List<TemplatePart> parts;
  const OptionalPart(this.parts);
}

class ReferenceFormatter {
  static const templates = [
    [
      '{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>',
      '{author}. ({year}). {title}< ({edition})>. {publisher}.',
      '{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>',
      '{author}. ({year}). {title}< (Report No. {number})>. {institution}.',
      '{author}. ({year}). {title} [Doctoral dissertation, {school}].',
      '{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>',
    ],
    [
      '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
      '{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.',
      '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
      '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
      '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
      '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>',
    ],
    [
      '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
      '{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.',
      '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
      '{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.',
      '{author}. {year}. "{title}." PhD diss., {school}.',
      '{author}. {year}. {title}.< {howpublished}.>< {note}.>',
    ],
    [
      '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
      '{author}. {title}.< {edition},> {publisher}, {year}.',
      '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
      '{author}. {title}. {institution}, {year}.< Technical Report {number}.>',
      '{author}. {title}. {year}. {school}, PhD dissertation.',
      '{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>',
    ],
  ];
  static final parsed = templates.map((style) => style.map(parse).toList()).toList();

  static List<TemplatePart> parse(String text) {
    var i = 0;
    List<TemplatePart> read() {
      final parts = <TemplatePart>[];
      while (i < text.length && text[i] != '>') {
        if (text[i] == '{') {
          final end = text.indexOf('}', i);
          parts.add(FieldPart(text.substring(i + 1, end)));
          i = end + 1;
        } else if (text[i] == '<') {
          i++;
          parts.add(OptionalPart(read()));
          i++;
        } else {
          parts.add(LiteralPart(text[i++]));
        }
      }
      return parts;
    }
    return read();
  }

  static String editorSuffix(Entry entry, Style style) {
    if (entry.authors != null) return '';
    final single = entry.primary.single;
    return switch (style) {
      Style.apa => single ? ' (Ed.)' : ' (Eds.)',
      Style.ieee => single ? ', Ed.' : ', Eds.',
      Style.chicago => single ? ', ed.' : ', eds.',
      Style.mla => single ? ', editor' : ', editors',
    };
  }

  static String edition(String value) {
    if (!digits(value)) return '$value ed.';
    final number = int.parse(value);
    final suffix = [11, 12, 13].contains(number % 100) ? 'th' : switch (number % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$value$suffix ed.';
  }

  static Map<String, String> values(Entry entry, Style style, bool repeated) {
    final result = entry.fields.map((key, value) => MapEntry(key, plain(value)));
    result['author'] = (repeated ? '---' : entry.primary.authors(style)) + editorSuffix(entry, style);
    result['editor'] = entry.editors?.editors(style) ?? '';
    result['eds'] = entry.editors == null ? '' : entry.editors!.single ? 'Ed.' : 'Eds.';
    result['title'] = plain(titleCase(entry.fields['title']!, style));
    result['year'] = entry.year(style);
    result['pp'] = '';
    if (entry.fields.containsKey('pages')) {
      result['pages'] = entry.value('pages').replaceAll('--', '-');
      result['pp'] = (result['pages']!.contains('-') ? 'pp. ' : 'p. ') + result['pages']!;
    }
    if (entry.fields.containsKey('edition')) result['edition'] = edition(entry.value('edition'));
    final month = entry.value('month');
    final index = monthNames.indexOf(month);
    result['mon'] = index < 0 ? month : monthShort[index];
    return result;
  }

  static String format(Entry entry, Style style, {int number = 0, bool repeated = false}) {
    final fields = values(entry, style, repeated);
    final result = StringBuffer();
    var last = '';
    void write(String text) {
      result.write(text);
      if (text.isNotEmpty) last = text[text.length - 1];
    }
    void render(List<TemplatePart> parts) {
      for (final part in parts) {
        switch (part) {
          case FieldPart(:final name):
            write(fields[name] ?? '');
          case OptionalPart(:final parts):
            if (parts.whereType<FieldPart>().every((field) => (fields[field.name] ?? '').isNotEmpty)) render(parts);
          case LiteralPart(:final text):
            if (text != '.' || last.isEmpty || !'.?!'.contains(last)) write(text);
        }
      }
    }
    final type = switch (entry.type) {
      'article' => 0, 'book' => 1, 'inproceedings' || 'incollection' => 2,
      'techreport' => 3, 'phdthesis' => 4, _ => 5,
    };
    render(parsed[style.index][type]);
    return (style == Style.ieee ? '[$number] ' : '') + result.toString();
  }
}

class Citation {
  final int start, end;
  final String kind;
  final List<Entry> entries;
  const Citation(this.start, this.end, this.kind, this.entries);
}

class CitationManager {
  final Database database;
  final record = <Entry>[];
  final recorded = <Entry>{};
  CitationManager(this.database);

  Entry lookup(String key) => database.byKey[key] ?? (throw CommandError("unknown key '$key'"));
  List<Entry> ieeeOrder() {
    final rest = database.entries.where((entry) => !recorded.contains(entry)).toList()..sort((a, b) => a.key.compareTo(b.key));
    return [...record, ...rest];
  }
  Map<Entry, int> ieeeNumbers() {
    final order = ieeeOrder();
    return {for (var i = 0; i < order.length; i++) order[i]: i + 1};
  }

  static String shortName(Entry entry, Style style, bool parenthetical) {
    final names = entry.primary.names.map((name) => name.surname).toList();
    if (entry.primary.etAl || names.length >= (style == Style.chicago ? 4 : 3)) return '${names[0]} et al.';
    if (names.length == 3) return '${names[0]}, ${names[1]}, and ${names[2]}';
    if (names.length == 2) return '${names[0]} ${style == Style.apa && parenthetical ? '&' : 'and'} ${names[1]}';
    return names[0];
  }

  static String numberRanges(List<int> numbers) {
    numbers.sort();
    final parts = <String>[];
    for (var i = 0; i < numbers.length;) {
      var end = i;
      while (end + 1 < numbers.length && numbers[end + 1] == numbers[end] + 1) {
        end++;
      }
      if (end - i >= 2) {
        parts.add('[${numbers[i]}]-[${numbers[end]}]');
      } else {
        for (var j = i; j <= end; j++) {
          parts.add('[${numbers[j]}]');
        }
      }
      i = end + 1;
    }
    return parts.join(', ');
  }

  static String citationText(Citation citation, Style style, Map<Entry, int> numbers) {
    var entries = citation.entries;
    if (citation.kind == 'citeauthor') return entries.map((entry) => shortName(entry, style, false)).join('; ');
    if (citation.kind == 'citeyear') return entries.map((entry) => entry.year(style)).join(', ');
    final parenthetical = citation.kind != 'citet';
    if (style == Style.ieee) {
      return parenthetical ? numberRanges(entries.map((entry) => numbers[entry]!).toList())
          : entries.map((entry) => '${shortName(entry, style, false)} [${numbers[entry]}]').join('; ');
    }
    if (style == Style.mla) {
      final text = entries.map((entry) => shortName(entry, style, parenthetical)).join('; ');
      return parenthetical ? '($text)' : text;
    }
    if (parenthetical) entries = entries.toList()..sort(Entry.compare);
    final groups = <String>[];
    for (var i = 0; i < entries.length;) {
      final name = shortName(entries[i], style, parenthetical);
      var end = i + 1;
      while (end < entries.length && shortName(entries[end], style, parenthetical) == name) {
        end++;
      }
      final years = entries.sublist(i, end).map((entry) => entry.year(style)).join(', ');
      groups.add(parenthetical ? name + (style == Style.apa ? ', ' : ' ') + years : '$name ($years)');
      i = end;
    }
    final joined = groups.join('; ');
    return parenthetical ? '($joined)' : joined;
  }

  String cite(String text, Style style) {
    final citations = <Citation>[];
    for (var start = text.indexOf('\\'); start >= 0;) {
      final brace = text.indexOf('{', start);
      final end = text.indexOf('}', brace);
      final seen = <String>{};
      final entries = <Entry>[];
      for (final key in text.substring(brace + 1, end).split(',')) {
        if (seen.add(key)) entries.add(lookup(key));
      }
      citations.add(Citation(start, end + 1, text.substring(start + 1, brace), entries));
      start = text.indexOf('\\', end + 1);
    }
    for (final citation in citations) {
      for (final entry in citation.entries) {
        if (recorded.add(entry)) record.add(entry);
      }
    }
    final numbers = ieeeNumbers();
    final result = StringBuffer();
    var position = 0;
    for (final citation in citations) {
      result.write(text.substring(position, citation.start));
      result.write(citationText(citation, style, numbers));
      position = citation.end;
    }
    result.write(text.substring(position));
    return result.toString();
  }

  static String baseKey(Entry entry) {
    final surname = lower(letters(plain(entry.primary.names[0].last)));
    final year = String.fromCharCodes(entry.fields['year']!.codeUnits.where(isDigit));
    var word = '';
    for (final part in entry.value('title').split(' ')) {
      final candidate = lower(letters(part));
      if (candidate.isNotEmpty && !smallWords.contains(candidate)) {
        word = candidate;
        break;
      }
    }
    return surname + year + word;
  }

  Iterable<String> keygen() sync* {
    final bases = database.entries.map(baseKey).toList();
    final counts = <String, int>{}, used = <String, int>{};
    for (final base in bases) {
      counts[base] = (counts[base] ?? 0) + 1;
    }
    for (var i = 0; i < bases.length; i++) {
      var generated = bases[i];
      if (counts[generated]! > 1) {
        final index = used[generated] ?? 0;
        used[generated] = index + 1;
        generated += String.fromCharCode(97 + index);
      }
      yield '${database.entries[i].key} -> $generated';
    }
  }

  static Iterable<String> warnings(Entry entry, Map<String, String> titles) sync* {
    if (entry.fields.containsKey('pages')) {
      final pages = entry.value('pages');
      if (pages.contains('-') && !pages.contains('--')) yield 'pages use a single hyphen';
      final parts = pages.split('-').where((part) => part.isNotEmpty).toList();
      if (parts.length == 2 && parts.every(digits) && int.parse(parts[0]) > int.parse(parts[1])) yield 'pages are reversed';
    }
    final year = entry.value('year');
    if (year.length != 4 || !digits(year)) yield 'year is not 4 digits';
    final title = entry.value('title');
    if (!title.codeUnits.any(isLower) && title.codeUnits.where(isUpper).length >= 2) yield 'title is all caps';
    if (entry.type == 'article' && !entry.fields.containsKey('doi')) yield 'article has no doi';
    final lowered = lower(title);
    if (titles.containsKey(lowered)) {
      yield 'same title as ${titles[lowered]}';
    } else {
      titles[lowered] = entry.key;
    }
    final unknown = entry.fields.keys.where((field) => !knownFields.contains(field)).toList()..sort();
    for (final field in unknown) {
      yield "unknown field '$field'";
    }
  }

  Iterable<String> check() sync* {
    final titles = <String, String>{};
    var count = 0;
    for (final entry in database.entries) {
      for (final warning in warnings(entry, titles)) {
        count++;
        yield 'WARN ${entry.key}: $warning';
      }
    }
    yield 'CHECK warnings=$count';
  }

  Iterable<String> export(Entry entry) sync* {
    yield '@${entry.type}{${entry.key},';
    final unknown = entry.fields.keys.where((field) => !knownFields.contains(field)).toList()..sort();
    final fields = [...knownFields.where(entry.fields.containsKey), ...unknown];
    for (var i = 0; i < fields.length; i++) {
      yield '  ${fields[i]} = {${entry.fields[fields[i]]}}${i + 1 == fields.length ? '' : ','}';
    }
    yield '}';
  }

  Iterable<String> stats() sync* {
    yield 'ENTRIES ${database.entries.length}';
    final types = <String, int>{}, years = <String, int>{};
    final authors = <String>{};
    final pairs = <(String, String), int>{};
    for (final entry in database.entries) {
      types[entry.type] = (types[entry.type] ?? 0) + 1;
      final year = entry.value('year');
      years[year] = (years[year] ?? 0) + 1;
      if (entry.authors == null) continue;
      final names = entry.authors!.names.map((name) => name.format(inverted: false, useInitials: false)).toSet().toList()..sort();
      authors.addAll(names);
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final pair = (names[i], names[j]);
          pairs[pair] = (pairs[pair] ?? 0) + 1;
        }
      }
    }
    for (final type in types.keys.toList()..sort()) {
      yield 'TYPE $type ${types[type]}';
    }
    for (final year in years.keys.toList()..sort()) {
      yield 'YEAR $year ${years[year]}';
    }
    yield 'AUTHORS ${authors.length}';
    if (pairs.isEmpty) {
      yield 'PAIR none';
    } else {
      final ranked = pairs.entries.toList()..sort((a, b) {
        final count = b.value.compareTo(a.value);
        if (count != 0) return count;
        final first = a.key.$1.compareTo(b.key.$1);
        return first == 0 ? a.key.$2.compareTo(b.key.$2) : first;
      });
      final best = ranked[0];
      yield 'PAIR ${best.key.$1} & ${best.key.$2} ${best.value}';
    }
  }

  List<String> execute(String line) {
    final firstSpace = line.indexOf(' ');
    final command = firstSpace < 0 ? line : line.substring(0, firstSpace);
    List<String> words;
    if ((command == 'CITE' || command == 'SEARCH') && firstSpace >= 0) {
      final secondSpace = line.indexOf(' ', firstSpace + 1);
      words = secondSpace < 0 ? [command, line.substring(firstSpace + 1)]
          : [command, line.substring(firstSpace + 1, secondSpace), line.substring(secondSpace + 1)];
    } else {
      words = line.split(' ');
    }
    final expected = switch (command) {
      'FORMAT' || 'CITE' || 'SEARCH' => 2,
      'BIBLIOGRAPHY' || 'EXPORT' => 1,
      'KEYGEN' || 'CHECK' || 'STATS' => 0,
      _ => throw CommandError("unknown command '$command'"),
    };
    if (command == 'FORMAT' ? words.length - 1 < expected : words.length - 1 != expected) {
      throw const CommandError('wrong number of arguments');
    }
    var style = Style.apa;
    if (command == 'FORMAT' || command == 'BIBLIOGRAPHY' || command == 'CITE') {
      style = switch (words[1]) {
        'APA' => Style.apa, 'IEEE' => Style.ieee, 'CHICAGO' => Style.chicago, 'MLA' => Style.mla,
        _ => throw CommandError("unknown style '${words[1]}'"),
      };
    }
    final output = <String>[];
    switch (command) {
      case 'FORMAT':
        final numbers = ieeeNumbers();
        for (final key in words.skip(2)) {
          final entry = database.byKey[key];
          output.add(entry == null ? "ERROR unknown key '$key'" : ReferenceFormatter.format(entry, style, number: numbers[entry]!));
        }
      case 'BIBLIOGRAPHY':
        output.add(style == Style.mla ? 'Works Cited' : 'References');
        final numbers = ieeeNumbers();
        final entries = style == Style.ieee ? ieeeOrder() : (database.entries.toList()..sort(Entry.compare));
        NameList? previous;
        for (final entry in entries) {
          final repeated = (style == Style.chicago || style == Style.mla) && (previous?.same(entry.primary) ?? false);
          output.add(ReferenceFormatter.format(entry, style, number: numbers[entry]!, repeated: repeated));
          previous = entry.primary;
        }
      case 'CITE':
        output.add(cite(words[2], style));
      case 'KEYGEN':
        output.addAll(keygen());
      case 'CHECK':
        output.addAll(check());
      case 'SEARCH':
        final needle = lower(words[2]);
        final matches = database.entries.where((entry) => entry.fields.containsKey(words[1]) && lower(entry.value(words[1])).contains(needle))
            .map((entry) => entry.key).toList();
        output.add(matches.isEmpty ? 'MATCHES 0' : 'MATCHES ${matches.length}: ${matches.join(' ')}');
      case 'EXPORT':
        output.addAll(export(lookup(words[1])));
      case 'STATS':
        output.addAll(stats());
    }
    return output;
  }
}

void main() {
  final lines = <String>[];
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == '%%') break;
    lines.add(line);
  }
  final database = Database(lines);
  for (final message in database.messages) {
    stdout.writeln(message);
  }
  final manager = CitationManager(database);
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try {
      for (final line in manager.execute(stdin.readLineSync()!)) {
        stdout.writeln(line);
      }
    } on CommandError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
