import 'dart:io';
import 'dart:math' as math;
part 'document_parser.dart';
part 'hyphenation.dart';
part 'line_breaker.dart';
part 'page_builder.dart';
part 'renderer.dart';

List<String> readLines(String path) => File(path).readAsLinesSync();
List<String> wordsIn(String text) =>
    text.split(' ').where((w) => w.isNotEmpty).toList();
(String, String) splitLabel(String text) {
  if (text.endsWith('}')) {
    final i = text.lastIndexOf(' {#');
    if (i >= 0)
      return (text.substring(0, i), text.substring(i + 3, text.length - 1));
  }
  return (text, '');
}

class TextLine {
  String text;
  final footnotes = <int>[], indexes = <int>[];
  int? anchor;
  bool chapterStart = false;
  TextLine(this.text);
}

class BreakPosition {
  final (int, int) start, end;
  final bool midword, appendHyphen;
  BreakPosition(this.start, this.end, this.midword, this.appendHyphen);
}

class MeasuredLine {
  final int start, end, length, capacity;
  final List<String> pieces;
  final List<(int, int, int)> ranges;
  final bool last, midword;
  MeasuredLine(
    this.start,
    this.end,
    this.pieces,
    this.ranges,
    this.length,
    this.capacity,
    this.last,
    this.midword,
  );
  int get slack => capacity - length;
}

class TextMetrics {
  final List<String> words;
  final int firstCapacity, laterCapacity;
  final offsets = <int>[],
      breaks = <BreakPosition>[BreakPosition((0, 0), (0, 0), false, false)];
  TextMetrics(
    this.words,
    this.firstCapacity,
    this.laterCapacity,
    Hyphenation dictionary,
  ) {
    var offset = 0;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      offsets.add(offset);
      offset += word.length + 1;
      for (final (position, appendHyphen) in dictionary.splitPoints(word)) {
        breaks.add(
          BreakPosition((i, position), (i, position), true, appendHyphen),
        );
      }
      breaks.add(BreakPosition((i + 1, 0), (i, word.length), false, false));
    }
  }
  int get end => breaks.length - 1;
  int capacity(int start) => start == 0 ? firstCapacity : laterCapacity;
  int length(int start, int end) {
    final a = breaks[start].start, b = breaks[end].end;
    return offsets[b.$1] +
        b.$2 -
        offsets[a.$1] -
        a.$2 +
        (breaks[end].appendHyphen ? 1 : 0);
  }

  int slack(int start, int end) => capacity(start) - length(start, end);
  MeasuredLine measure(int start, int end) {
    final a = breaks[start].start,
        b = breaks[end].end,
        pieces = <String>[],
        ranges = <(int, int, int)>[];
    for (var word = a.$1; word <= b.$1; word++) {
      final first = word == a.$1 ? a.$2 : 0,
          last = word == b.$1 ? b.$2 : words[word].length;
      pieces.add(words[word].substring(first, last));
      ranges.add((word, first, last));
    }
    if (breaks[end].appendHyphen) pieces[pieces.length - 1] += '-';
    return MeasuredLine(
      start,
      end,
      pieces,
      ranges,
      length(start, end),
      capacity(start),
      end == this.end,
      breaks[end].midword,
    );
  }
}

class TextResult {
  final List<TextLine> lines;
  final List<MeasuredLine> broken;
  final int cost;
  TextResult(this.lines, this.broken, this.cost);
}

class IndexEntry {
  final String name;
  final marks = <int>[],
      references = <String>{},
      children = <String, IndexEntry>{};
  IndexEntry(this.name);
}

class Page {
  final List<TextLine> content;
  final List<int> footnotes;
  final int height;
  final bool endsByForce, blank;
  int serial = 0, bodyNumber = 0;
  bool chapterStart = false;
  String display = '', header = '', footer = '';
  List<String> body = [];
  Page({
    this.content = const [],
    this.footnotes = const [],
    this.height = 0,
    this.endsByForce = false,
    this.blank = false,
  });
}

class LayoutResult {
  final String method;
  final bodies = <int, TextResult>{};
  final Map<int, TextResult> footnotes;
  final warningTexts = <(String, TextResult, bool)>[],
      generated = <(Block, List<TextLine>)>[];
  List<Page> pages = [];
  int frontMatter = 0;
  Map<int, Page> blockPages = {};
  Map<int, int> markPages = {};
  Map<String, String> labelValues = {};
  LayoutResult(this.method, this.footnotes);
}

class Typesetter {
  final Document document;
  final Map<String, int> params;
  final Hyphenation dictionary;
  final labels = <String, Block>{},
      bibliography = <String, BibEntry>{},
      indexEntries = <String, IndexEntry>{};
  final bibOrder = <BibEntry>[],
      citedEntries = <BibEntry>[],
      bodyBlocks = <Block>[],
      headings = <Block>[],
      numberedTables = <Block>[],
      footnotes = <String>[],
      indexMarks = <String>[];
  Typesetter(this.document, this.params, List<String> dictionaryLines)
    : dictionary = Hyphenation(
        dictionaryLines,
        document.hyphenation,
        params['left_min']!,
        params['right_min']!,
      ) {
    registerDocument();
    checkDocument();
    assignBibliographyLabels();
    prepareIndex();
    final ordered = document.warnings.indexed.toList()
      ..sort((a, b) {
        final cmp = a.$2.$1.compareTo(b.$2.$1);
        return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
      });
    document.warnings.clear();
    document.warnings.addAll(ordered.map((p) => p.$2));
  }
  void warn(int line, String message) {
    document.warnings.add((line, message));
  }

  void registerDocument() {
    var chapter = 0, section = 0, tableNumber = 0;
    Block? previous;
    for (var index = 0; index < document.blocks.length; index++) {
      final b = document.blocks[index], kind = document.blocks[index].kind;
      b.id = index;
      if (kind == 'h1' || kind == 'h2') {
        final (text, label) = splitLabel(b.argument);
        b.text = text;
        b.label = label;
        if (kind == 'h1') {
          chapter++;
          section = 0;
          b.number = '$chapter';
          if (index > 0) b.pageBreak = true;
        } else {
          section++;
          b.number = '$chapter.$section';
        }
        headings.add(b);
      } else if (kind == 'enum') {
        b.enumNumber = previous?.kind == 'enum' ? previous!.enumNumber + 1 : 1;
        b.number = '${b.enumNumber}';
      } else if (kind == 'table') {
        final (caption, label) = splitLabel(b.caption);
        b.caption = caption;
        b.label = label;
        if (caption.isNotEmpty) {
          tableNumber++;
          b.number = '$tableNumber';
          numberedTables.add(b);
        }
      }
      if (b.label.isNotEmpty) {
        if (labels.containsKey(b.label)) {
          warn(b.line, 'duplicate label ${b.label}');
          b.label = '';
        } else {
          labels[b.label] = b;
        }
      }
      if (kind == 'paragraph' &&
          (previous?.kind == 'h1' || previous?.kind == 'h2'))
        b.indent = 0;
      if (bodyKinds.contains(kind)) {
        bodyBlocks.add(b);
        b.paragraphNumber = bodyBlocks.length;
      }
      previous = b;
    }
    for (final entry in document.bibliography) {
      if (bibliography.containsKey(entry.key)) {
        warn(entry.line, 'duplicate bibliography key ${entry.key}');
      } else {
        bibliography[entry.key] = entry;
        bibOrder.add(entry);
      }
    }
  }

  void checkTable(Block b) {
    final count = b.columns.length;
    for (final (line, text) in b.innerLines) {
      var cells = text.split('|').map((c) => c.trim()).toList();
      if (cells.length != count) {
        warn(line, 'table row has ${cells.length} cells, expected $count');
        while (cells.length < count) {
          cells.add('');
        }
        cells = cells.take(count).toList();
      }
      b.rows.add(cells);
    }
    b.tableLines = formatTable(b.rows, b.columns, b.caption, b.number);
    final excess =
        b.tableLines.map((line) => line.length).reduce(math.max) - b.width;
    if (excess > 0) warn(b.line, 'table too wide by $excess');
  }

  InlineToken acceptCommand(String name, String argument, int line) {
    var number = 0;
    switch (name) {
      case 'ref' || 'page':
        if (!labels.containsKey(argument))
          warn(line, 'undefined label $argument');
      case 'cite':
        for (final key in argument.split(',')) {
          final entry = bibliography[key];
          if (entry == null) {
            warn(line, 'undefined citation $key');
          } else {
            entry.cited = true;
          }
        }
      case 'fn':
        footnotes.add(argument);
        number = footnotes.length;
      case 'idx':
        indexMarks.add(argument);
        number = indexMarks.length;
    }
    return InlineToken(name, argument: argument, number: number);
  }

  List<InlineToken> parseBodyLine(String text, int line) {
    final tokens = <InlineToken>[];
    var position = 0;
    while (position < text.length) {
      final opening = text.indexOf('{', position);
      if (opening < 0) {
        tokens.add(InlineToken('text', text: text.substring(position)));
        break;
      }
      if (opening > position)
        tokens.add(
          InlineToken('text', text: text.substring(position, opening)),
        );
      final closing = text.indexOf('}', opening + 1);
      if (closing < 0) {
        warn(line, 'unclosed brace');
        tokens.add(InlineToken('text', text: text.substring(opening)));
        break;
      }
      final content = text.substring(opening + 1, closing);
      final (name, argument, separator) = cut(content, ':');
      if (separator &&
          argument.isNotEmpty &&
          {'ref', 'page', 'fn', 'idx', 'cite'}.contains(name)) {
        tokens.add(acceptCommand(name, argument, line));
      } else {
        warn(line, 'bad command {$content}');
      }
      position = closing + 1;
    }
    return tokens;
  }

  void checkDocument() {
    for (final b in document.blocks) {
      if (b.kind == 'table') {
        checkTable(b);
      } else if (b.kind == 'verbatim') {
        for (final (line, text) in b.innerLines) {
          final excess = text.length - b.width;
          if (excess > 0) warn(line, 'verbatim line too long by $excess');
        }
      } else if (bodyKinds.contains(b.kind)) {
        for (var i = 0; i < b.bodyLines.length; i++) {
          final (line, text) = b.bodyLines[i];
          if (i > 0) b.tokens.add(InlineToken('text', text: ' '));
          b.tokens.addAll(parseBodyLine(text, line));
        }
      }
    }
    for (final entry in bibOrder) {
      if (!entry.cited)
        warn(entry.line, 'unused bibliography entry ${entry.key}');
    }
  }

  void assignBibliographyLabels() {
    for (final entry in bibOrder) {
      if (!entry.cited) continue;
      final surnames = entry.author.split(' and ');
      var base = '';
      if (surnames.length == 1) {
        base = surnames[0].substring(0, math.min(3, surnames[0].length));
      } else {
        for (final name in surnames.take(
          surnames.length >= 5 ? 3 : surnames.length,
        )) {
          base += name[0];
        }
        if (surnames.length >= 5) base += '+';
      }
      entry.baseLabel = base + entry.year.substring(2);
      citedEntries.add(entry);
    }
    citedEntries.sort((a, b) {
      for (final pair in [
        (a.baseLabel, b.baseLabel),
        (a.author, b.author),
        (a.title, b.title),
        (a.key, b.key),
      ]) {
        final cmp = pair.$1.compareTo(pair.$2);
        if (cmp != 0) return cmp;
      }
      return 0;
    });
    var start = 0;
    while (start < citedEntries.length) {
      var end = start + 1;
      while (end < citedEntries.length &&
          citedEntries[end].baseLabel == citedEntries[start].baseLabel) {
        end++;
      }
      for (var i = start; i < end; i++) {
        final entry = citedEntries[i];
        entry.label =
            entry.baseLabel +
            (end - start > 1 ? String.fromCharCode(97 + i - start) : '');
      }
      start = end;
    }
  }

  void prepareIndex() {
    for (var i = 0; i < indexMarks.length; i++) {
      final (entryPart, reference, hasReference) = cut(indexMarks[i], '|');
      final (parentName, childName, hasChild) = cut(entryPart, '!');
      final parent = indexEntries.putIfAbsent(
            parentName,
            () => IndexEntry(parentName),
          ),
          entry = hasChild
              ? parent.children.putIfAbsent(
                  childName,
                  () => IndexEntry(childName),
                )
              : parent;
      if (hasReference) {
        entry.references.add(reference);
      } else {
        entry.marks.add(i + 1);
      }
    }
  }

  String citationText(String argument) {
    final labels = <String>{};
    var undefined = false;
    for (final key in argument.split(',')) {
      final entry = bibliography[key];
      if (entry == null) {
        undefined = true;
      } else {
        labels.add(entry.label);
      }
    }
    final parts = labels.toList()..sort();
    if (undefined) parts.add('?');
    return '[${parts.join(', ')}]';
  }

  (List<String>, Map<int, List<(String, int, int)>>) expandBody(
    Block b,
    Map<String, String> pageValues,
  ) {
    final parts = <String>[], marks = <(int, String, int)>[];
    var offset = 0;
    for (final token in b.tokens) {
      var text = token.text;
      switch (token.kind) {
        case 'idx':
          marks.add((offset - 1, 'idx', token.number));
          continue;
        case 'fn':
          marks.add((offset, 'fn', token.number));
          text = '[${token.number}]';
        case 'ref':
          text = labels[token.argument]?.number ?? '??';
        case 'page':
          text = pageValues[token.argument] ?? '??';
        case 'cite':
          text = citationText(token.argument);
      }
      parts.add(text);
      offset += text.length;
    }
    final expanded = parts.join(),
        matches = RegExp(r'[^ ]+').allMatches(expanded).toList(),
        words = <String>[],
        starts = <int>[];
    for (final match in matches) {
      words.add(expanded.substring(match.start, match.end));
      starts.add(match.start);
    }
    final wordMarks = <int, List<(String, int, int)>>{};
    for (final (offset, kind, number) in marks) {
      var word = starts.length - 1;
      while (starts[word] > offset) {
        word--;
      }
      wordMarks.putIfAbsent(word, () => []).add((
        kind,
        number,
        offset - starts[word],
      ));
    }
    return (words, wordMarks);
  }

  void placeMarks(
    TextLine line,
    MeasuredLine measured,
    Map<int, List<(String, int, int)>> marks,
  ) {
    for (final (word, first, last) in measured.ranges) {
      for (final (kind, number, position)
          in marks[word] ?? <(String, int, int)>[]) {
        if (first <= position && position < last) {
          if (kind == 'fn') {
            line.footnotes.add(number);
          } else {
            line.indexes.add(number);
          }
        }
      }
    }
  }

  TextResult layOutText(
    List<String> words,
    (int, int) capacities,
    String alignment,
    (String, String) prefixes,
    String method, [
    Map<int, List<(String, int, int)>> marks = const {},
  ]) {
    final metrics = TextMetrics(
      words,
      capacities.$1,
      capacities.$2,
      dictionary,
    );
    final (breaking, cost) = breakText(metrics, method, params);
    final lines = <TextLine>[], broken = <MeasuredLine>[];
    var start = 0;
    for (var i = 0; i < breaking.length; i++) {
      final end = breaking[i], measured = metrics.measure(start, breaking[i]);
      final text = displayLine(
            measured.pieces,
            measured.slack,
            alignment,
            measured.last,
          ),
          prefix = i == 0 ? prefixes.$1 : prefixes.$2,
          line = TextLine('$prefix$text');
      placeMarks(line, measured, marks);
      lines.add(line);
      broken.add(measured);
      start = end;
    }
    return TextResult(lines, broken, cost);
  }

  ((int, int), (String, String)) bodyFormat(Block b) {
    final width = b.width;
    switch (b.kind) {
      case 'paragraph':
        return ((width - b.indent, width), (' ' * b.indent, ''));
      case 'item':
        return ((width - 2, width - 2), ('- ', '  '));
      case 'enum':
        return (
          (width - 4, width - 4),
          ('${b.enumNumber.toString().padLeft(2)}. ', '    '),
        );
      case 'quote':
        return ((width - 8, width - 8), ('    ', '    '));
      default:
        return (
          (width - 12, width - 12),
          (b.term.length <= 10 ? b.term.padRight(12) : ' ' * 12, ' ' * 12),
        );
    }
  }

  TextResult layOutBody(Block b, Map<String, String> pages, String method) {
    final (words, marks) = expandBody(b, pages);
    final (capacities, prefixes) = bodyFormat(b);
    final result = layOutText(
      words,
      capacities,
      b.align,
      prefixes,
      method,
      marks,
    );
    if (b.kind == 'term' && b.term.length >= 11)
      result.lines.insert(0, TextLine(b.term));
    return result;
  }

  Map<int, TextResult> layOutFootnotes(String method) {
    final result = <int, TextResult>{};
    for (var i = 0; i < footnotes.length; i++) {
      final prefix = '[${i + 1}] ',
          capacity = document.pageWidth - '[${i + 1}] '.length;
      result[i + 1] = layOutText(
        wordsIn(footnotes[i]),
        (capacity, capacity),
        'left',
        (prefix, ' ' * prefix.length),
        method,
      );
    }
    return result;
  }

  TextResult layOutReference(BibEntry entry, int width, String method) {
    final margin = citedEntries.map((e) => e.label.length).reduce(math.max) + 3,
        text = '${entry.author}. ${entry.year}. ${entry.title}';
    final capacity = width - margin,
        prefix = '[${entry.label}]'.padRight(margin);
    return layOutText(
      wordsIn(text),
      (capacity, capacity),
      'left',
      (prefix, ' ' * margin),
      method,
    );
  }

  String pageList(List<int> numbers) {
    final ordered = numbers.toSet().toList()..sort(), parts = <String>[];
    var index = 0;
    while (index < ordered.length) {
      var last = index;
      while (last + 1 < ordered.length &&
          ordered[last + 1] == ordered[last] + 1) {
        last++;
      }
      if (last - index >= 2) {
        parts.add('${ordered[index]}-${ordered[last]}');
      } else {
        parts.addAll(ordered.sublist(index, last + 1).map((v) => '$v'));
      }
      index = last + 1;
    }
    return parts.join(', ');
  }

  String indexEntryLine(IndexEntry entry, Map<int, int> pages, bool child) {
    var text = '${child ? '  ' : ''}${entry.name}';
    final numbers = [
      for (final number in entry.marks)
        if (pages.containsKey(number)) pages[number]!,
    ];
    if (numbers.isNotEmpty) text += ', ${pageList(numbers)}';
    if (entry.references.isNotEmpty) {
      final refs = entry.references.toList()..sort();
      text += ', see ${refs.join(', ')}';
    }
    return text;
  }

  List<String> indexNames(Map<String, IndexEntry> entries) =>
      entries.keys.toList()..sort((a, b) {
        final cmp = a.toLowerCase().compareTo(b.toLowerCase());
        return cmp != 0 ? cmp : a.compareTo(b);
      });
  List<String> indexLines(Map<int, int> pages) {
    final lines = <String>[];
    String? previous;
    for (final name in indexNames(indexEntries)) {
      final entry = indexEntries[name]!,
          group = isLetter(name[0]) ? name[0].toUpperCase() : 'Symbols';
      if (group != previous) {
        lines.add(group);
        previous = group;
      }
      lines.add(indexEntryLine(entry, pages, false));
      for (final child in indexNames(entry.children)) {
        lines.add(indexEntryLine(entry.children[child]!, pages, true));
      }
    }
    return lines;
  }

  List<String> contentsLines(Block b, Map<int, Page> pages) {
    final entries = b.kind == 'toc' ? headings : numberedTables,
        lines = <String>[];
    for (final entry in entries) {
      final left = b.kind == 'toc'
              ? '${entry.kind == 'h2' ? '  ' : ''}${entry.number} ${entry.text}'
              : 'Table ${entry.number}. ${entry.caption}',
          number = pages[entry.id]?.display ?? '??';
      final dots = b.width - left.length - number.length - 2;
      lines.add('$left ${'.' * dots} $number');
    }
    return lines;
  }

  void addLayoutBlock(
    List<LayoutBlock> layout,
    Block source,
    String kind,
    List<TextLine> lines, {
    bool list = false,
    bool first = true,
  }) {
    if (first) {
      lines.first.anchor = source.id;
      lines.first.chapterStart = source.kind == 'h1';
    }
    layout.add(LayoutBlock(kind, lines, list, first && source.pageBreak));
  }

  List<TextLine> textLines(List<String> texts) =>
      texts.map(TextLine.new).toList();
  List<LayoutBlock> buildLayoutBlocks(
    Map<String, String> pageValues,
    String method,
    LayoutResult result,
  ) {
    final layout = <LayoutBlock>[];
    for (final b in document.blocks) {
      final kind = b.kind;
      if (bodyKinds.contains(kind)) {
        final body = layOutBody(b, pageValues, method);
        result.bodies[b.id] = body;
        result.warningTexts.add((
          'paragraph ${b.paragraphNumber}',
          body,
          b.align == 'justify',
        ));
        addLayoutBlock(
          layout,
          b,
          'flow',
          body.lines,
          list: {'item', 'enum', 'term'}.contains(kind),
        );
        continue;
      }
      switch (kind) {
        case 'title' || 'author':
          final text = kind == 'title' ? b.argument.toUpperCase() : b.argument;
          addLayoutBlock(
            layout,
            b,
            'heading',
            textLines(['${' ' * ((b.width - text.length) ~/ 2)}$text']),
          );
        case 'h1' || 'h2':
          final text =
                  '${b.number} ${kind == 'h1' ? b.text.toUpperCase() : b.text}',
              rule = kind == 'h1' ? '=' : '-';
          addLayoutBlock(
            layout,
            b,
            'heading',
            textLines([text, rule * text.length]),
          );
        case 'table':
          addLayoutBlock(layout, b, 'solid', textLines(b.tableLines));
        case 'verbatim':
          addLayoutBlock(
            layout,
            b,
            'flow',
            textLines(b.innerLines.map((line) => line.$2).toList()),
          );
        case 'toc' || 'lot' || 'index':
          final title = {
            'toc': 'CONTENTS',
            'lot': 'TABLES',
            'index': 'INDEX',
          }[kind]!;
          addLayoutBlock(
            layout,
            b,
            'heading',
            textLines([title, '=' * title.length]),
          );
          final entries = kind == 'index'
                  ? indexLines({})
                  : contentsLines(b, {}),
              lines = textLines(entries);
          addLayoutBlock(layout, b, 'flow', lines, first: false);
          result.generated.add((b, lines));
        case 'bibliography':
          addLayoutBlock(
            layout,
            b,
            'heading',
            textLines(['REFERENCES', '==========']),
          );
          for (final entry in citedEntries) {
            final reference = layOutReference(entry, b.width, method);
            result.warningTexts.add((
              'reference ${entry.label}',
              reference,
              false,
            ));
            addLayoutBlock(
              layout,
              b,
              'flow',
              reference.lines,
              list: true,
              first: false,
            );
          }
      }
    }
    return layout;
  }

  String roman(int number) =>
      '${'x' * (number ~/ 10)}${['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix'][number % 10]}';
  void numberPages(List<Page> pages, LayoutResult result) {
    final numbered = <Page>[];
    for (final page in pages) {
      final chapterStart =
          page.content.isNotEmpty && page.content.first.chapterStart;
      var serial = numbered.length + 1;
      if (chapterStart && serial.isEven) {
        final blank = Page(blank: true, endsByForce: true);
        blank.serial = serial;
        numbered.add(blank);
        serial++;
      }
      page.serial = serial;
      page.chapterStart = chapterStart;
      numbered.add(page);
    }
    final blockPages = <int, Page>{};
    for (final page in numbered) {
      for (final line in page.content) {
        if (line.anchor != null) blockPages[line.anchor!] = page;
      }
    }
    final frontMatter = headings.isEmpty
            ? 0
            : blockPages[headings.first.id]!.serial - 1,
        markPages = <int, int>{};
    for (final page in numbered) {
      page.bodyNumber = page.serial - frontMatter;
      page.display = page.serial <= frontMatter
          ? roman(page.serial)
          : '${page.bodyNumber}';
      for (final line in page.content) {
        for (final mark in line.indexes) {
          markPages[mark] = page.bodyNumber;
        }
      }
    }
    result.pages = numbered;
    result.frontMatter = frontMatter;
    result.blockPages = blockPages;
    result.markPages = markPages;
    result.labelValues = {
      for (final entry in labels.entries)
        entry.key: blockPages[entry.value.id]!.display,
    };
  }

  LayoutResult layoutOnce(Map<String, String> pageValues, String method) {
    final notes = layOutFootnotes(method), result = LayoutResult(method, notes);
    final blocks = buildLayoutBlocks(pageValues, method, result),
        heights = {
          for (final entry in notes.entries)
            entry.key: entry.value.lines.length,
        };
    final pages = choosePages(
      blocks,
      heights,
      document.height,
      params['orphan_lines']!,
      params['widow_lines']!,
    );
    numberPages(pages, result);
    for (var number = 1; number <= footnotes.length; number++) {
      result.warningTexts.add(('footnote $number', notes[number]!, false));
    }
    return result;
  }

  void completeGeneratedLines(LayoutResult result) {
    for (final (b, records) in result.generated) {
      final texts = b.kind == 'index'
          ? indexLines(result.markPages)
          : contentsLines(b, result.blockPages);
      for (var i = 0; i < texts.length; i++) {
        records[i].text = texts[i];
      }
    }
  }

  void assemblePages(LayoutResult result) {
    var chapter = '', section = '';
    final height = document.height,
        total = result.pages.length - result.frontMatter;
    for (final page in result.pages) {
      if (page.blank) {
        page.body = List.filled(height, '');
        continue;
      }
      for (final line in page.content) {
        if (line.anchor == null) continue;
        final b = document.blocks[line.anchor!];
        if (b.kind == 'h1') {
          chapter = '${b.number} ${b.text}';
          section = '';
        } else if (b.kind == 'h2') {
          section = '${b.number} ${b.text}';
        }
      }
      final values = [page.display, '$total', chapter, section];
      if (!page.chapterStart)
        page.header = runningHead(
          document.header,
          values,
          document.pageWidth,
          page.serial,
        );
      page.footer = runningHead(
        document.footer,
        values,
        document.pageWidth,
        page.serial,
      );
      final content = page.content.map((line) => line.text).toList(),
          noteLines = [
            for (final number in page.footnotes)
              for (final line in result.footnotes[number]!.lines) line.text,
          ];
      page.body = noteLines.isEmpty
          ? [...content, ...List.filled(height - content.length, '')]
          : [
              ...content,
              ...List.filled(
                height - content.length - noteLines.length - 1,
                '',
              ),
              '----------',
              ...noteLines,
            ];
    }
  }

  bool sameValues(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);
  LayoutResult layout(String method) {
    var values = {for (final label in labels.keys) label: '??'};
    while (true) {
      final result = layoutOnce(values, method);
      if (sameValues(result.labelValues, values)) {
        completeGeneratedLines(result);
        assemblePages(result);
        return result;
      }
      values = result.labelValues;
    }
  }

  List<String> layoutWarnings(LayoutResult result) {
    final warnings = <String>[];
    for (final (name, text, justify) in result.warningTexts) {
      for (var i = 0; i < text.broken.length; i++) {
        final line = text.broken[i];
        if (line.slack < 0) {
          warnings.add('$name line ${i + 1}: overfull by ${-line.slack}');
        } else if (justify &&
            !line.last &&
            line.slack >= params['underfull_slack']!) {
          warnings.add('$name line ${i + 1}: underfull, slack ${line.slack}');
        }
      }
    }
    for (final page in result.pages) {
      if (page.blank || page.endsByForce) continue;
      final empty = document.height - page.height;
      if (empty >= params['underfull_page']!)
        warnings.add('page ${page.serial}: underfull, $empty empty lines');
    }
    var hyphenated = 0;
    for (final b in bodyBlocks) {
      for (final line in result.bodies[b.id]!.broken) {
        if (line.midword) hyphenated++;
      }
    }
    warnings.add('${result.pages.length} pages, $hyphenated hyphenated lines');
    return warnings.map((message) => '${result.method}: $message').toList();
  }

  String statistics(LayoutResult optimal, LayoutResult greedy) {
    final lines = ['paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy'],
        totals = List.filled(4, 0);
    for (final b in bodyBlocks) {
      final kp = optimal.bodies[b.id]!, g = greedy.bodies[b.id]!;
      final values = [kp.broken.length, kp.cost, g.broken.length, g.cost];
      for (var i = 0; i < 4; i++) {
        totals[i] += values[i];
      }
      lines.add('${b.paragraphNumber},${values.join(',')}');
    }
    lines.add('total,${totals.join(',')}');
    return '${lines.join('\n')}\n';
  }
}

void main() {
  final params = <String, int>{};
  for (final line in readLines('input/params.txt')) {
    final words = line.split(' ');
    params[words[0]] = int.parse(words[1]);
  }
  final t = Typesetter(
        parseDocument(readLines('input/document.txt')),
        params,
        readLines('input/hyphenation.txt'),
      ),
      optimal = t.layout('kp'),
      greedy = t.layout('greedy');
  final warnings = [
    for (final (number, message) in t.document.warnings)
      'line $number: $message',
    ...t.layoutWarnings(optimal),
    ...t.layoutWarnings(greedy),
  ];
  Directory('output').createSync(recursive: true);
  File('output/pages.txt').writeAsStringSync(pagesText(optimal.pages));
  File('output/greedy_pages.txt').writeAsStringSync(pagesText(greedy.pages));
  File('output/stats.csv').writeAsStringSync(t.statistics(optimal, greedy));
  File('output/log.txt').writeAsStringSync('${warnings.join('\n')}\n');
}
