part of 'main.dart';

const bodyKinds = {'paragraph', 'item', 'enum', 'quote', 'term'},
    settingNames = {'width', 'indent', 'align'},
    preambleNames = {'page', 'header', 'footer'},
    blockNames = {
      'title',
      'author',
      'h1',
      'h2',
      'item',
      'enum',
      'quote',
      'term',
      'table',
      'verbatim',
      'toc',
      'lot',
      'index',
      'bibliography',
    },
    emptyArgumentNames = {
      'newpage',
      'verbatim',
      'toc',
      'lot',
      'index',
      'bibliography',
    };
final dictionaryWord = RegExp(r'^[a-z]+(-[a-z]+)*$');
(String, String, bool) cut(String text, String separator) {
  final i = text.indexOf(separator);
  return i < 0
      ? (text, '', false)
      : (text.substring(0, i), text.substring(i + separator.length), true);
}

class InlineToken {
  final String kind, text, argument;
  final int number;
  InlineToken(this.kind, {this.text = '', this.argument = '', this.number = 0});
}

class Block {
  final String kind, argument, align;
  final int line, width;
  int indent, id = 0, paragraphNumber = 0, enumNumber = 0;
  bool pageBreak;
  String term = '',
      columns = '',
      caption = '',
      text = '',
      label = '',
      number = '';
  final bodyLines = <(int, String)>[],
      innerLines = <(int, String)>[],
      tokens = <InlineToken>[],
      rows = <List<String>>[];
  List<String> tableLines = [];
  Block(
    this.kind,
    this.line,
    this.argument,
    this.width,
    this.indent,
    this.align,
    this.pageBreak,
  );
}

class BibEntry {
  final int line;
  final String key, author, year, title;
  String baseLabel = '', label = '';
  bool cited = false;
  BibEntry(this.line, this.key, this.author, this.year, this.title);
}

class Document {
  final blocks = <Block>[],
      warnings = <(int, String)>[],
      hyphenation = <String>[],
      bibliography = <BibEntry>[];
  int height = 40, pageWidth = 60;
  List<String> header = ['', '', ''], footer = ['', '', ''];
}

bool validArgument(String name, String argument) {
  switch (name) {
    case 'width' || 'indent' || 'page':
      if (!RegExp(r'^[0-9]{1,9}$').hasMatch(argument)) return false;
      final value = int.parse(argument),
          limits = {
            'width': (20, 80),
            'indent': (0, 8),
            'page': (10, 100),
          }[name]!;
      return limits.$1 <= value && value <= limits.$2;
    case 'align':
      return {'left', 'right', 'center', 'justify'}.contains(argument);
    case 'header' || 'footer':
      return '|'.allMatches(argument).length == 2;
    case 'hyphenation':
      return argument.isNotEmpty &&
          argument.split(' ').every(dictionaryWord.hasMatch);
    case 'bib':
      final (key, fields, found) = cut(argument, ' ');
      final parts = fields.split('|');
      return found &&
          RegExp(r'^[a-z0-9]+$').hasMatch(key) &&
          parts.length == 3 &&
          parts[0].isNotEmpty &&
          parts[2].isNotEmpty &&
          RegExp(r'^[0-9]{4}$').hasMatch(parts[1]);
    case 'term':
      final (term, description, found) = cut(argument, '|');
      return found && term.isNotEmpty && description.isNotEmpty;
    case 'table':
      return RegExp(r'^[lrc]+$').hasMatch(cut(argument, ' ').$1);
    default:
      return emptyArgumentNames.contains(name)
          ? argument.isEmpty
          : argument.isNotEmpty;
  }
}

Document parseDocument(List<String> lines) {
  final d = Document(), accepted = <String>{};
  var width = 60, indent = 0, align = 'left', pending = false;
  Block? open, inner;
  Block create(String kind, int line, [String argument = '']) {
    if (d.blocks.isEmpty) d.pageWidth = width;
    final b = Block(kind, line, argument, width, indent, align, pending);
    pending = false;
    d.blocks.add(b);
    return b;
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index], number = index + 1;
    if (inner != null) {
      if (line == '.end') {
        inner = null;
      } else {
        inner.innerLines.add((number, line));
      }
      continue;
    }
    if (line.isEmpty) {
      open = null;
      continue;
    }
    if (!line.startsWith('.')) {
      open ??= create('paragraph', number);
      open.bodyLines.add((number, line));
      continue;
    }
    open = null;
    final (name, argument, _) = cut(line.substring(1), ' ');
    String? warning;
    if (!settingNames.contains(name) &&
        !preambleNames.contains(name) &&
        !blockNames.contains(name) &&
        !{'newpage', 'hyphenation', 'bib'}.contains(name)) {
      warning = 'unknown directive .$name';
    } else if (!validArgument(name, argument)) {
      warning = 'bad argument for .$name';
    } else if (preambleNames.contains(name) && d.blocks.isNotEmpty) {
      warning = '.$name ignored after the preamble';
    } else if (preambleNames.contains(name) && accepted.contains(name)) {
      warning = 'duplicate .$name';
    }
    if (warning != null) {
      d.warnings.add((number, warning));
      continue;
    }
    if (settingNames.contains(name)) {
      if (name == 'align') {
        align = argument;
      } else if (name == 'width') {
        width = int.parse(argument);
      } else {
        indent = int.parse(argument);
      }
    } else if (preambleNames.contains(name)) {
      accepted.add(name);
      if (name == 'page') {
        d.height = int.parse(argument);
      } else if (name == 'header') {
        d.header = argument.split('|');
      } else {
        d.footer = argument.split('|');
      }
    } else if (name == 'newpage') {
      pending = true;
    } else if (name == 'hyphenation') {
      d.hyphenation.addAll(argument.split(' '));
    } else if (name == 'bib') {
      final (key, fields, _) = cut(argument, ' ');
      final parts = fields.split('|');
      d.bibliography.add(BibEntry(number, key, parts[0], parts[1], parts[2]));
    } else {
      final b = create(name, number, argument);
      if ({'item', 'enum', 'quote'}.contains(name)) {
        b.bodyLines.add((number, argument));
        open = b;
      } else if (name == 'term') {
        final (term, description, _) = cut(argument, '|');
        b.term = term;
        b.bodyLines.add((number, description));
        open = b;
      } else if (name == 'table') {
        final (columns, caption, _) = cut(argument, ' ');
        b.columns = columns;
        b.caption = caption;
        inner = b;
      } else if (name == 'verbatim') {
        inner = b;
      }
    }
  }
  if (inner != null) d.warnings.add((inner.line, 'unterminated ${inner.kind}'));
  return d;
}
