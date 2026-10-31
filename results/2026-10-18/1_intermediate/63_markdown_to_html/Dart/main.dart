import 'dart:io';

const punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
const whitespace = ' \n';
const tocMarker = '\u0000toc\u0000';

String escapeHtml(String text) => text.replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
String stripTags(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '');
String normalize(String text) => text.toLowerCase().replaceAll(RegExp(r'[ \n]+'), ' ').trim();
String charAt(String text, int at) => at < text.length ? text[at] : '';
int skipSpace(String text, int at) {
  while (at < text.length && whitespace.contains(text[at])) { at++; }
  return at;
}
(String, int) escapedRead(String text, int at, String stops) {
  final value = StringBuffer();
  while (at < text.length && !stops.contains(text[at])) {
    if (text[at] == r'\' && at + 1 < text.length && punctuation.contains(text[at + 1])) { at++; }
    value.write(text[at++]);
  }
  return (value.toString(), at);
}
int runEnd(String text, int at) {
  final char = text[at++];
  while (at < text.length && text[at] == char) { at++; }
  return at;
}

class Reference {
  final String url;
  final String? title;
  const Reference(this.url, this.title);
}
class Fence {
  final String fence, info;
  const Fence(this.fence, this.info);
}
class ListMarker {
  final String marker, content;
  final bool ordered;
  final int start;
  const ListMarker(this.marker, this.ordered, this.start, this.content);
}
enum BlockKind { heading, paragraph, code, quote, alert, list, table, rule, toc }
class Block {
  final BlockKind kind;
  final String text, language;
  final int level, start;
  final bool ordered;
  final List<String> lines, header, alignments;
  final List<Block> blocks;
  final List<List<Block>> items;
  final List<List<String>> rows;
  const Block(this.kind, {this.text = '', this.language = '', this.level = 0,
    this.start = 1, this.ordered = false, this.lines = const [], this.header = const [],
    this.alignments = const [], this.blocks = const [], this.items = const [], this.rows = const []});
}
Fence? openingFence(String line) {
  if (!line.startsWith('`') && !line.startsWith('~')) return null;
  final end = runEnd(line, 0);
  final info = line.substring(end).trim();
  if (end < 3 || (line[0] == '`' && info.contains('`'))) return null;
  return Fence(line.substring(0, end), info);
}
Block? atxHeading(String line) {
  final match = RegExp(r'^(#{1,6})(?: |$)').firstMatch(line);
  if (match == null) return null;
  final level = match[1]!.length;
  var text = line.substring(level).trim();
  final trimmed = text.replaceFirst(RegExp(r'#+$'), '');
  if (trimmed.isEmpty || trimmed.endsWith(' ')) text = trimmed.trim();
  return Block(BlockKind.heading, level: level, text: text);
}
bool isRule(String line) => RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$').hasMatch(line.replaceAll(' ', ''));
ListMarker? listMarker(String line) {
  if (isRule(line)) return null;
  final match = RegExp(r'^(?:([-*+])|([0-9]{1,9})([.)])) +').firstMatch(line);
  if (match == null) return null;
  return ListMarker(match[1] ?? match[3]!, match[2] != null,
      match[2] == null ? 1 : int.parse(match[2]!), line.substring(match.end));
}
bool interruptsParagraph(String line) => !line.startsWith(' ') &&
    (openingFence(line) != null || atxHeading(line) != null || isRule(line) ||
     line.startsWith('>') || listMarker(line) != null);
List<String> splitCells(String line) {
  var text = line.trim();
  if (text.startsWith('|')) text = text.substring(1);
  final cells = <String>[''];
  var finalSeparator = false, at = 0;
  while (at < text.length) {
    final char = text[at++];
    finalSeparator = false;
    if (char == r'\' && at < text.length) {
      cells[cells.length - 1] += (text[at] == '|' ? '' : r'\') + text[at++];
    } else if (char == '|') {
      cells.add('');
      finalSeparator = true;
    } else { cells[cells.length - 1] += char; }
  }
  if (finalSeparator) cells.removeLast();
  return cells.map((cell) => cell.trim()).toList();
}

class BlockParser {
  final references = <String, Reference>{};
  final footnotes = <String, String>{};

  bool definition(String line) {
    final note = RegExp(r'^\[\^([A-Za-z0-9_-]+)\]:(.*)$').firstMatch(line);
    if (note != null && note[2]!.trim().isNotEmpty) {
      footnotes.putIfAbsent(note[1]!.toLowerCase(), () => note[2]!.trim());
      return true;
    }
    if (!line.startsWith('[')) return false;
    final close = line.indexOf(']');
    if (close < 0 || charAt(line, close + 1) != ':') return false;
    final label = line.substring(1, close);
    if (label.contains('[') || label.trim().isEmpty || label.startsWith('^')) return false;
    final (url, end) = escapedRead(line, skipSpace(line, close + 2), ' ');
    if (url.isEmpty) return false;
    final at = skipSpace(line, end);
    String? title;
    if (at < line.length) {
      if (at == end || !'"\''.contains(line[at])) return false;
      final quoted = escapedRead(line, at + 1, line[at]);
      if (quoted.$2 != line.length - 1) return false;
      title = quoted.$1;
    }
    references.putIfAbsent(normalize(label), () => Reference(url, title));
    return true;
  }

  List<Block> parse(List<String> lines) {
    final blocks = <Block>[];
    var at = 0;
    while (at < lines.length) {
      final line = lines[at];
      if (line.isEmpty) { at++; continue; }
      if (line.startsWith('    ')) {
        var end = at;
        while (end < lines.length && (lines[end].isEmpty || lines[end].startsWith('    '))) { end++; }
        while (lines[end - 1].isEmpty) { end--; }
        blocks.add(Block(BlockKind.code, lines: lines.sublist(at, end)
            .map((row) => row.isEmpty ? '' : row.substring(4)).toList()));
        at = end;
        continue;
      }
      if (!line.startsWith(' ')) {
        final fence = openingFence(line);
        if (fence != null) {
          final code = <String>[];
          at++;
          while (at < lines.length) {
            final row = lines[at++];
            if (row.length >= fence.fence.length && row.split('').every((char) => char == fence.fence[0])) break;
            code.add(row);
          }
          blocks.add(Block(BlockKind.code, language: fence.info.split(' ')[0], lines: code));
          continue;
        }
        final heading = atxHeading(line);
        if (heading != null) { blocks.add(heading); at++; continue; }
        if (isRule(line)) { blocks.add(const Block(BlockKind.rule)); at++; continue; }
        if (line.startsWith('>')) {
          final content = <String>[];
          while (at < lines.length && lines[at].startsWith('>')) {
            content.add(lines[at++].substring(1).replaceFirst(RegExp(r'^ '), ''));
          }
          final alert = RegExp(r'^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$').firstMatch(content[0]);
          blocks.add(alert == null ? Block(BlockKind.quote, blocks: parse(content))
              : Block(BlockKind.alert, text: alert[1]!, blocks: parse(content.sublist(1))));
          continue;
        }
        final first = listMarker(line);
        if (first != null) {
          var marker = first;
          final items = <List<Block>>[];
          while (true) {
            final content = <String>[marker.content];
            at++;
            while (at < lines.length && lines[at].startsWith('  ')) { content.add(lines[at++].substring(2)); }
            items.add(parse(content));
            var next = at;
            while (next < lines.length && lines[next].isEmpty) { next++; }
            final following = next < lines.length ? listMarker(lines[next]) : null;
            if (following == null || following.marker != first.marker || following.ordered != first.ordered) break;
            marker = following;
            at = next;
          }
          blocks.add(Block(BlockKind.list, ordered: first.ordered, start: first.start, items: items));
          continue;
        }
        if (definition(line)) { at++; continue; }
        if (at + 1 < lines.length && line.contains('|') && lines[at + 1].contains('|')) {
          final header = splitCells(line), delimiters = splitCells(lines[at + 1]);
          if (header.length == delimiters.length && delimiters.every((cell) => RegExp(r'^:?-+:?$').hasMatch(cell))) {
            final alignments = delimiters.map((cell) => cell.startsWith(':')
                ? (cell.endsWith(':') ? 'center' : 'left') : cell.endsWith(':') ? 'right' : '').toList();
            final rows = <List<String>>[];
            at += 2;
            while (at < lines.length && lines[at].isNotEmpty && lines[at].contains('|')) {
              final cells = splitCells(lines[at++]).take(header.length).toList();
              while (cells.length < header.length) { cells.add(''); }
              rows.add(cells);
            }
            blocks.add(Block(BlockKind.table, alignments: alignments, header: header, rows: rows));
            continue;
          }
        }
      }
      final text = <String>[line.replaceFirst(RegExp(r'^ +'), '')];
      var level = 0;
      at++;
      while (at < lines.length && lines[at].isNotEmpty) {
        final row = lines[at];
        if (RegExp(r'^(?:={3,}|-{3,})$').hasMatch(row)) { level = row[0] == '=' ? 1 : 2; at++; break; }
        if (interruptsParagraph(row)) break;
        text.add(row.replaceFirst(RegExp(r'^ +'), ''));
        at++;
      }
      final combined = text.join('\n');
      blocks.add(level != 0 ? Block(BlockKind.heading, level: level, text: combined)
          : combined == '[TOC]' ? const Block(BlockKind.toc) : Block(BlockKind.paragraph, text: combined));
    }
    return blocks;
  }
}

int backtickCloser(String text, int at, int length) {
  while ((at = text.indexOf('`', at)) != -1) {
    final end = runEnd(text, at);
    if (end - at == length) return at;
    at = end;
  }
  return -1;
}
int closingBracket(String text, int at) {
  var depth = 0;
  while (at < text.length) {
    final char = text[at];
    if (char == r'\') { at += 2; continue; }
    if (char == '`') {
      final end = runEnd(text, at);
      final close = backtickCloser(text, end, end - at);
      at = close == -1 ? end : close + end - at;
      continue;
    }
    if (char == '[') { depth++; }
    else if (char == ']' && --depth == 0) { return at; }
    at++;
  }
  return -1;
}
class Piece {
  final String html, char;
  final int length;
  final bool canOpen, canClose;
  const Piece.text(this.html) : char = '', length = 0, canOpen = false, canClose = false;
  const Piece.delimiter(this.char, this.length, this.canOpen, this.canClose) : html = '';
}
String emphasis(List<Piece> pieces, int start, int end) {
  final html = StringBuffer();
  for (var at = start; at < end; at++) {
    final piece = pieces[at];
    if (piece.char.isEmpty) { html.write(piece.html); continue; }
    var close = at + 1;
    if (piece.canOpen) {
      while (close < end) {
        final candidate = pieces[close];
        if (candidate.char == piece.char && candidate.length == piece.length && candidate.canClose) break;
        close++;
      }
    } else { close = end; }
    if (close == end) { html.write(piece.char * piece.length); continue; }
    final tags = piece.char == '~' ? ('<del>', '</del>')
        : piece.length == 1 ? ('<em>', '</em>') : piece.length == 2 ? ('<strong>', '</strong>')
        : ('<em><strong>', '</strong></em>');
    html.write(tags.$1 + emphasis(pieces, at + 1, close) + tags.$2);
    at = close;
  }
  return html.toString();
}
class TocEntry {
  final int level;
  final String id, label;
  final children = <TocEntry>[];
  TocEntry(this.level, this.id, this.label);
}
class NumberedNote {
  final int number;
  int count = 0;
  NumberedNote(this.number);
}
class Destination {
  final Reference reference;
  final int end;
  const Destination(this.reference, this.end);
}

class Renderer {
  final Map<String, Reference> references;
  final Map<String, String> footnotes;
  final usedIds = <String>{};
  final headings = <TocEntry>[];
  final numberedNotes = <String, NumberedNote>{};
  Renderer(this.references, this.footnotes);

  Destination? destination(String text, int at, String label) {
    if (charAt(text, at) == '[') {
      final close = text.indexOf(']', at + 1);
      if (close != -1 && !text.substring(at + 1, close).contains('[')) {
        final key = text.substring(at + 1, close);
        final reference = references[normalize(key.isEmpty ? label : key)];
        return reference == null ? null : Destination(reference, close + 1);
      }
    } else if (charAt(text, at) == '(') {
      final (url, end) = escapedRead(text, skipSpace(text, at + 1), ' \n)');
      var next = skipSpace(text, end), valid = true;
      String? title;
      if (next > end && next < text.length && '"\''.contains(text[next])) {
        final quoted = escapedRead(text, next + 1, text[next]);
        if (quoted.$2 == text.length) { valid = false; }
        else { title = quoted.$1; next = skipSpace(text, quoted.$2 + 1); }
      }
      if (valid && charAt(text, next) == ')') return Destination(Reference(url, title), next + 1);
    }
    final reference = references[normalize(label)];
    return reference == null ? null : Destination(reference, at);
  }
  (String, int)? bracket(String text, int at, bool links, bool notes) {
    if (links && notes && text.startsWith('[^', at)) {
      final close = text.indexOf(']', at + 2);
      if (close != -1) {
        final name = text.substring(at + 2, close).toLowerCase();
        if (footnotes.containsKey(name)) return (footnoteReference(name), close + 1);
      }
    }
    final image = text[at] == '!';
    if (!image && !links) return null;
    final opening = at + (image ? 1 : 0);
    final close = closingBracket(text, opening);
    if (close == -1) return null;
    final label = text.substring(opening + 1, close);
    final dest = destination(text, close + 1, label);
    if (dest == null) return null;
    final reference = dest.reference, content = inline(label, links: false, notes: false);
    final title = reference.title == null ? '' : ' title="${escapeHtml(reference.title!)}"';
    final url = escapeHtml(reference.url);
    return (image ? '<img src="$url" alt="${stripTags(content)}"$title />'
        : '<a href="$url"$title>$content</a>', dest.end);
  }
  String inline(String text, {bool links = true, bool notes = true}) {
    final pieces = <Piece>[];
    var at = 0;
    while (at < text.length) {
      final char = text[at], following = charAt(text, at + 1);
      if (char == r'\') {
        if (following.isNotEmpty && punctuation.contains(following)) { pieces.add(Piece.text(escapeHtml(following))); at += 2; }
        else if (following == '\n') { pieces.add(const Piece.text('<br />\n')); at += 2; }
        else { pieces.add(const Piece.text(r'\')); at++; }
        continue;
      }
      if (char == '`') {
        final end = runEnd(text, at);
        final close = backtickCloser(text, end, end - at);
        if (close == -1) { pieces.add(Piece.text(text.substring(at, end))); at = end; }
        else {
          var code = text.substring(end, close).replaceAll('\n', ' ');
          if (code.startsWith(' ') && code.endsWith(' ') && RegExp(r'[^ ]').hasMatch(code)) code = code.substring(1, code.length - 1);
          pieces.add(Piece.text('<code>${escapeHtml(code)}</code>'));
          at = close + end - at;
        }
        continue;
      }
      if (links && char == '<') {
        final close = text.indexOf('>', at + 1);
        if (close != -1) {
          final target = text.substring(at + 1, close);
          var href = '';
          final clean = !RegExp(r'[ \n<]').hasMatch(target);
          if (clean && RegExp(r'^(?:http://.+|https://.+)$').hasMatch(target)) href = target;
          else if (clean && RegExp(r'^[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$').hasMatch(target)) href = 'mailto:$target';
          if (href.isNotEmpty) {
            pieces.add(Piece.text('<a href="${escapeHtml(href)}">${escapeHtml(target)}</a>'));
            at = close + 1;
            continue;
          }
        }
      }
      if (links && (text.startsWith('http://', at) || text.startsWith('https://', at))
          && (at == 0 || ' \n*_~('.contains(text[at - 1]))) {
        var end = at;
        while (end < text.length && !' \n<'.contains(text[end])) { end++; }
        while (end > at && '.,:;!?*_~)'.contains(text[end - 1])) { end--; }
        final url = text.substring(at, end);
        if (url != 'http://' && url != 'https://') {
          pieces.add(Piece.text('<a href="${escapeHtml(url)}">${escapeHtml(url)}</a>'));
          at = end;
          continue;
        }
      }
      if (char == '[' || (char == '!' && following == '[')) {
        final result = bracket(text, at, links, notes);
        if (result != null) { pieces.add(Piece.text(result.$1)); at = result.$2; continue; }
        pieces.add(Piece.text(char)); at++; continue;
      }
      if ('*_~'.contains(char)) {
        final end = runEnd(text, at);
        final length = end - at;
        final before = at == 0 ? ' ' : text[at - 1], after = end == text.length ? ' ' : text[end];
        var canOpen = !whitespace.contains(after), canClose = !whitespace.contains(before);
        if (char == '_' && RegExp(r'^[A-Za-z0-9]$').hasMatch(before) && RegExp(r'^[A-Za-z0-9]$').hasMatch(after)) canOpen = canClose = false;
        pieces.add((char != '~' && length <= 3) || (char == '~' && length == 2)
            ? Piece.delimiter(char, length, canOpen, canClose) : Piece.text(char * length));
        at = end;
        continue;
      }
      pieces.add(Piece.text(escapeHtml(char))); at++;
    }
    return emphasis(pieces, 0, pieces.length);
  }
  String renderBlocks(List<Block> blocks) => blocks.map((block) => render(block) + '\n').join();
  String render(Block block) {
    switch (block.kind) {
      case BlockKind.heading: return heading(block.level, block.text);
      case BlockKind.paragraph: return '<p>${inline(block.text)}</p>';
      case BlockKind.rule: return '<hr />';
      case BlockKind.toc: return tocMarker;
      case BlockKind.code: {
        final attribute = block.language.isEmpty ? '' : ' class="language-${escapeHtml(block.language)}"';
        return '<pre><code$attribute>${block.lines.map((line) => escapeHtml(line) + '\n').join()}</code></pre>';
      }
      case BlockKind.quote: return '<blockquote>\n${renderBlocks(block.blocks)}</blockquote>';
      case BlockKind.alert: {
        final kind = block.text.toLowerCase(), title = block.text[0] + block.text.substring(1).toLowerCase();
        return '<div class="alert alert-$kind">\n<p class="alert-title">$title</p>\n${renderBlocks(block.blocks)}</div>';
      }
      case BlockKind.list: {
        final tag = block.ordered ? 'ol' : 'ul', attribute = block.ordered && block.start != 1 ? ' start="${block.start}"' : '';
        return '<$tag$attribute>\n${block.items.map((item) => renderItem(item) + '\n').join()}</$tag>';
      }
      case BlockKind.table: {
        var html = '<table>\n<thead>\n<tr>\n${tableCells('th', block.alignments, block.header)}</tr>\n</thead>\n';
        if (block.rows.isNotEmpty) {
          html += '<tbody>\n${block.rows.map((row) => '<tr>\n${tableCells('td', block.alignments, row)}</tr>\n').join()}</tbody>\n';
        }
        return '$html</table>';
      }
    }
  }
  String heading(int level, String text) {
    final start = text.lastIndexOf(' {#');
    String id;
    if (text.endsWith('}') && start != -1 && !text.substring(start + 3, text.length - 1).contains('\n') && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text.substring(start + 3, text.length - 1))) {
      id = text.substring(start + 3, text.length - 1);
      text = text.substring(0, start).replaceFirst(RegExp(r' +$'), '');
    } else {
      var base = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_ \n-]'), '').replaceAll(RegExp(r'[ \n]'), '-');
      if (base.isEmpty) base = 'heading';
      id = base;
      for (var suffix = 1; usedIds.contains(id); suffix++) { id = '$base-$suffix'; }
    }
    usedIds.add(id);
    final html = inline(text);
    headings.add(TocEntry(level, id, stripTags(html)));
    return '<h$level id="$id">$html</h$level>';
  }
  String renderItem(List<Block> blocks) {
    var html = '<li>';
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block.kind == BlockKind.paragraph) {
        var text = block.text;
        if (index == 0 && text.length > 4 && RegExp(r'^(?:\[ \]|\[x\]|\[X\]) ').hasMatch(text)) {
          html += text[1] == ' ' ? '<input type="checkbox" disabled="" /> ' : '<input type="checkbox" checked="" disabled="" /> ';
          text = text.substring(4);
        }
        html += inline(text);
      } else {
        if (!html.endsWith('\n')) html += '\n';
        html += render(block) + '\n';
      }
    }
    return '$html</li>';
  }
  String tableCells(String tag, List<String> alignments, List<String> cells) {
    final html = StringBuffer();
    for (var index = 0; index < cells.length; index++) {
      final style = alignments[index].isEmpty ? '' : ' style="text-align:${alignments[index]}"';
      html.write('<$tag$style>${inline(cells[index])}</$tag>\n');
    }
    return html.toString();
  }
  String tocList(List<TocEntry> entries) => '<ul>\n' + entries.map((entry) => '<li><a href="#${entry.id}">${entry.label}</a>'
      + (entry.children.isEmpty ? '' : '\n${tocList(entry.children)}\n') + '</li>\n').join() + '</ul>';
  String tableOfContents() {
    if (headings.isEmpty) return '<nav class="toc">\n</nav>';
    final roots = <TocEntry>[], parents = <TocEntry>[];
    for (final heading in headings) {
      while (parents.isNotEmpty && parents.last.level >= heading.level) { parents.removeLast(); }
      (parents.isEmpty ? roots : parents.last.children).add(heading);
      parents.add(heading);
    }
    return '<nav class="toc">\n${tocList(roots)}\n</nav>';
  }
  String referenceId(int number, int count) => 'fnref-$number' + (count == 1 ? '' : '-$count');
  String footnoteReference(String name) {
    final note = numberedNotes.putIfAbsent(name, () => NumberedNote(numberedNotes.length + 1));
    note.count++;
    return '<sup id="${referenceId(note.number, note.count)}"><a href="#fn-${note.number}">${note.number}</a></sup>';
  }
  String footnoteList() {
    var html = '<section class="footnotes">\n<ol>\n';
    for (final entry in numberedNotes.entries) {
      final note = entry.value, body = inline(footnotes[entry.key]!, notes: false), backlinks = <String>[];
      for (var count = 1; count <= note.count; count++) { backlinks.add('<a href="#${referenceId(note.number, count)}">&#8617;</a>'); }
      html += '<li id="fn-${note.number}">$body ${backlinks.join(' ')}</li>\n';
    }
    return '$html</ol>\n</section>\n';
  }
  String document(List<Block> blocks) {
    final html = renderBlocks(blocks), toc = tableOfContents();
    return html.replaceAll(tocMarker, toc) + (numberedNotes.isEmpty ? '' : footnoteList());
  }
}

void main() {
  final lines = <String>[];
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == '@@END@@') break;
    lines.add(line);
  }
  final parser = BlockParser();
  final blocks = parser.parse(lines);
  stdout.write(Renderer(parser.references, parser.footnotes).document(blocks));
}
