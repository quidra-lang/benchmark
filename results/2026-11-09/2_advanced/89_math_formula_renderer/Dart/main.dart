import 'dart:io';
import 'dart:math';
part 'lexer.dart';
part 'parser.dart';
part 'boxes.dart';
part 'layout.dart';
part 'canvas.dart';

class Formula {
  final int number;
  final String source;
  List<Token> tokens = [];
  List<Node> nodes = [];
  Token? tag, label;
  String tagString = '';
  Issue? error;
  final List<Issue> warnings = [];
  Formula(this.number, this.source);
}

class Typesetter {
  final Map<String, int> params;
  final Map<String, String> references;
  Typesetter(this.params, this.references);
  List<Box> boxes(List<Node> nodes, bool script) => [
    for (final n in nodes) typeset(n, script),
  ];
  Box typeset(Node n, bool script) {
    switch (n.kind) {
      case 'identifier':
      case 'number':
      case 'symbol':
      case 'command':
      case 'text':
      case 'reference':
        return atomBox(n, script, references);
      case 'row':
        {
          final (_, gaps) = spacing(n.items, script, params);
          return rowBox(boxes(n.items, script), gaps, 'row');
        }
      case 'script':
        {
          final baseNode = n.base!, base = typeset(baseNode, script);
          Box? sub, sup;
          var sw = 0, sh = 0, pw = 0, ph = 0;
          final subNode = n.sub, supNode = n.sup;
          if (subNode != null) {
            sub = typeset(subNode, true);
            sw = sub.width;
            sh = sub.height;
          }
          if (supNode != null) {
            sup = typeset(supNode, true);
            pw = sup.width;
            ph = sup.height;
          }
          final stacked =
              !script &&
              (baseNode.kind == 'command' &&
                      containsWord(
                        r'\sum \prod \lim \max \min',
                        baseNode.value,
                      ) ||
                  baseNode.kind == 'accent' &&
                      containsWord('overbrace underbrace', baseNode.value));
          if (stacked) {
            final width = max(base.width, max(sw, pw)),
                out = Box(
                  width,
                  ph + base.height + sh,
                  ph + base.baseline,
                  'limits',
                );
            out.add(base, center(base, width), ph, 'base: ');
            if (sub != null)
              out.add(sub, center(sub, width), ph + base.height, 'sub: ');
            if (sup != null) out.add(sup, center(sup, width), 0, 'sup: ');
            return out;
          }
          final bottomOfSup = base.baseline == 0 ? -1 : 0,
              topSup = bottomOfSup - ph + 1,
              topSub = base.descent == 0 ? base.height : base.height - 1,
              top = sup != null ? min(0, topSup) : 0,
              bottom = sub != null
                  ? max(base.height - 1, topSub + sh - 1)
                  : base.height - 1,
              out = Box(
                base.width + max(sw, pw),
                bottom - top + 1,
                base.baseline - top,
                'scripts',
              );
          out.add(base, 0, -top, 'base: ');
          if (sub != null) out.add(sub, base.width, topSub - top, 'sub: ');
          if (sup != null) out.add(sup, base.width, topSup - top, 'sup: ');
          return out;
        }
      case 'frac':
        {
          var a = typeset(n.items[0], script), b = typeset(n.items[1], script);
          if (!script) {
            final width = max(a.width, b.width) + 2,
                out = Box(width, a.height + 1 + b.height, a.height, 'frac');
            out.add(a, center(a, width), 0, 'num: ');
            out.add(b, center(b, width), a.height + 1, 'den: ');
            out.draw(repeated('-', width), 0, a.height);
            return out;
          }
          if (n.items[0].kind == 'row' || n.items[0].kind == 'frac')
            a = delimit(a, '(', ')');
          if (n.items[1].kind == 'row' || n.items[1].kind == 'frac')
            b = delimit(b, '(', ')');
          final slash = Box(1, 1, 0, 'atom "/"');
          slash.draw('/', 0, 0);
          return rowBox([a, slash, b], [0, 0], 'slash', ['num: ', '', 'den: ']);
        }
      case 'binom':
        {
          final a = typeset(n.items[0], script),
              b = typeset(n.items[1], script),
              width = max(a.width, b.width),
              height = a.height + 1 + b.height,
              out = Box(width + 2, height, a.height, 'binom');
          out.add(a, center(a, width) + 1, 0, 'upper: ');
          out.add(b, center(b, width) + 1, a.height + 1, 'lower: ');
          drawDelimiter(out, '(', 0, height);
          drawDelimiter(out, ')', width + 1, height);
          return out;
        }
      case 'overset':
      case 'underset':
        {
          final placed = typeset(n.items[0], true),
              base = typeset(n.items[1], script),
              width = max(placed.width, base.width),
              baseline = n.kind == 'overset'
                  ? placed.height + base.baseline
                  : base.baseline,
              out = Box(width, placed.height + base.height, baseline, n.kind);
          if (n.kind == 'overset') {
            out.add(placed, center(placed, width), 0, 'over: ');
            out.add(base, center(base, width), placed.height, 'base: ');
          } else {
            out.add(base, center(base, width), 0, 'base: ');
            out.add(placed, center(placed, width), base.height, 'under: ');
          }
          return out;
        }
      case 'sqrt':
      case 'root':
        {
          final body = typeset(n.items.last, script);
          Box? index;
          var e = 0, top = 0;
          if (n.kind == 'root') {
            index = typeset(n.items.first, true);
            e = max(0, index.width - 1);
            top = max(0, index.height - body.height);
          }
          final k = body.height,
              out = Box(
                e + k + 1 + body.width,
                k + 1 + top,
                body.baseline + 1 + top,
                n.kind,
              );
          out.draw(repeated('_', body.width), e + k + 1, top);
          out.draw('\\', e, k + top);
          for (var r = 1; r <= k; r++) {
            out.draw('/', e + k - r + 1, r + top);
          }
          if (index != null) {
            out.add(index, 0, k - index.height + top, 'index: ');
            out.add(body, e + k + 1, 1 + top, 'body: ');
          } else {
            out.add(body, e + k + 1, 1 + top);
          }
          return out;
        }
      case 'delim':
        return delimit(typeset(n.items.first, script), n.left, n.right);
      case 'matrix':
        {
          final rows = n.rows.length,
              cols = n.rows.first.length,
              cells = [for (final row in n.rows) boxes(row, script)],
              widths = List.filled(cols, 0),
              ascents = List.filled(rows, 0),
              descents = List.filled(rows, 0);
          for (var i = 0; i < rows; i++) {
            for (var j = 0; j < cols; j++) {
              final b = cells[i][j];
              widths[j] = max(widths[j], b.width);
              ascents[i] = max(ascents[i], b.baseline);
              descents[i] = max(descents[i], b.descent);
            }
          }
          final xs = List.filled(cols, 0), ys = List.filled(rows, 0);
          var bodyWidth = 0, bodyHeight = 0;
          for (var j = 0; j < cols; j++) {
            xs[j] = bodyWidth;
            bodyWidth += widths[j];
            if (j + 1 < cols) bodyWidth += params['col_gap']!;
          }
          for (var i = 0; i < rows; i++) {
            ys[i] = bodyHeight;
            bodyHeight += ascents[i] + descents[i] + 1;
            if (i + 1 < rows) bodyHeight += params['row_gap']!;
          }
          var shift = 0, width = bodyWidth;
          if (n.value != 'matrix') {
            shift = 2;
            width += 2;
            if (n.value != 'cases') width += 2;
          }
          final out = Box(
            width,
            bodyHeight,
            (bodyHeight - 1) ~/ 2,
            '${n.value} rows=$rows cols=$cols',
          );
          for (var i = 0; i < rows; i++) {
            for (var j = 0; j < cols; j++) {
              final b = cells[i][j],
                  offset = n.value == 'cases' ? 0 : center(b, widths[j]);
              out.add(
                b,
                xs[j] + offset + shift,
                ys[i] + ascents[i] - b.baseline,
                'cell ${i + 1},${j + 1}: ',
              );
            }
          }
          switch (n.value) {
            case 'pmatrix':
              drawDelimiter(out, '(', 0, bodyHeight);
              drawDelimiter(out, ')', bodyWidth + 3, bodyHeight);
              break;
            case 'bmatrix':
              drawDelimiter(out, '[', 0, bodyHeight);
              drawDelimiter(out, ']', bodyWidth + 3, bodyHeight);
              break;
            case 'vmatrix':
              drawDelimiter(out, '|', 0, bodyHeight);
              drawDelimiter(out, '|', bodyWidth + 3, bodyHeight);
              break;
            case 'cases':
              drawDelimiter(out, r'\{', 0, bodyHeight);
              break;
          }
          return out;
        }
      case 'accent':
        {
          final body = typeset(n.items.first, script);
          var width = body.width, baseline = body.baseline + 1;
          switch (n.value) {
            case 'hat':
            case 'dot':
            case 'tilde':
              width = max(width, 1);
              break;
            case 'vec':
              width = max(width, 2);
              break;
            case 'overbrace':
            case 'underbrace':
              width += 2;
              break;
          }
          if (n.value == 'underbrace') baseline = body.baseline;
          final out = Box(width, body.height + 1, baseline, n.value);
          switch (n.value) {
            case 'overline':
              out.draw(repeated('_', body.width), 0, 0);
              out.add(body, 0, 1);
              break;
            case 'hat':
            case 'dot':
            case 'tilde':
              out.draw(
                {'hat': '^', 'dot': '.', 'tilde': '~'}[n.value]!,
                (width - 1) ~/ 2,
                0,
              );
              out.add(body, 0, 1);
              break;
            case 'vec':
              out.draw('${repeated('-', width - 1)}>', 0, 0);
              out.add(body, 0, 1);
              break;
            case 'overbrace':
              out.draw('/${repeated('-', body.width)}\\', 0, 0);
              out.add(body, 1, 1);
              break;
            case 'underbrace':
              out.add(body, 1, 0);
              out.draw('\\${repeated('-', body.width)}/', 0, body.height);
              break;
          }
          return out;
        }
    }
    return Box(0, 1, 0, 'row');
  }

  String linear(Node n, bool script) {
    String parenthesize(Node child, bool mode, String kinds) {
      final value = linear(child, mode);
      return containsWord(kinds, child.kind) ? '($value)' : value;
    }

    switch (n.kind) {
      case 'identifier':
      case 'number':
      case 'symbol':
      case 'text':
        return n.value;
      case 'reference':
        return references[n.value] ?? '(??)';
      case 'command':
        return symbolCommands[n.value]!.display;
      case 'row':
        {
          final (_, gaps) = spacing(n.items, script, params);
          final out = StringBuffer();
          for (var i = 0; i < n.items.length; i++) {
            if (i > 0) out.write(repeated(' ', gaps[i - 1]));
            out.write(linear(n.items[i], script));
          }
          return out.toString();
        }
      case 'frac':
        return '${parenthesize(n.items[0], script, 'row frac')}/${parenthesize(n.items[1], script, 'row frac')}';
      case 'binom':
        return 'binom(${linear(n.items[0], script)}, ${linear(n.items[1], script)})';
      case 'overset':
      case 'underset':
        return '${n.kind}(${linear(n.items[0], true)}, ${linear(n.items[1], script)})';
      case 'script':
        {
          var out = parenthesize(n.base!, script, 'row frac script');
          final sub = n.sub, sup = n.sup;
          if (sub != null) out += '_${parenthesize(sub, true, 'row frac')}';
          if (sup != null) out += '^${parenthesize(sup, true, 'row frac')}';
          return out;
        }
      case 'sqrt':
        return 'sqrt(${linear(n.items.first, script)})';
      case 'root':
        return 'root(${linear(n.items[0], true)}, ${linear(n.items[1], script)})';
      case 'delim':
        return '${delimiterString(n.left)}${linear(n.items.first, script)}${delimiterString(n.right)}';
      case 'matrix':
        return '${n.value}[${[
          for (final row in n.rows) [for (final cell in row) linear(cell, script)].join(', '),
        ].join('; ')}]';
      case 'accent':
        return '${n.value}(${linear(n.items.first, script)})';
    }
    return '';
  }

  List<Line> breakLines(
    List<Node> nodes,
    List<Box> boxes,
    List<ElementTypes> types,
    List<int> gaps,
    int mode,
  ) {
    final breaks = <int>{};
    for (var i = 1; i < nodes.length; i++) {
      if (types[i].left == 'relation' ||
          mode >= 2 &&
              nodes[i].kind == 'symbol' &&
              (nodes[i].value == '+' || nodes[i].value == '-') &&
              types[i].left == 'binary' ||
          mode == 3 && types[i - 1].right == 'punctuation')
        breaks.add(i);
    }
    int widthOf(int start, int end) {
      var width = 0;
      for (var i = start; i < end; i++) {
        width += boxes[i].width;
        if (i + 1 < end) width += gaps[i];
      }
      return width;
    }

    final out = <Line>[];
    var alignment = -1, relationWidth = 0;
    for (var start = 0; start < nodes.length;) {
      var indent = 0;
      if (start > 0) {
        indent = params['indent']!;
        if (alignment >= 0) {
          indent = alignment;
          if (types[start].left != 'relation')
            indent += relationWidth + params['rel_space']!;
        }
      }
      var shortest = -1, chosen = -1;
      for (var end = start + 1; end <= nodes.length; end++) {
        if (end < nodes.length && !breaks.contains(end)) continue;
        if (shortest < 0) shortest = end;
        if (indent + widthOf(start, end) <= params['width']!) chosen = end;
      }
      if (chosen < 0) chosen = shortest;
      out.add(Line(start, chosen, indent, widthOf(start, chosen)));
      if (start == 0) {
        for (var i = 0; i < chosen; i++) {
          if (types[i].left == 'relation') {
            alignment = widthOf(0, i);
            if (i > 0) alignment += gaps[i - 1];
            relationWidth = boxes[i].width;
            break;
          }
        }
      }
      start = chosen;
    }
    return out;
  }

  (List<Placement>, List<Line>, int, int) placeFormula(Formula f) {
    final (types, gaps) = spacing(f.nodes, false, params);
    final elementBoxes = boxes(f.nodes, false);
    var lines = <Line>[];
    for (var mode = 1; mode <= 3; mode++) {
      lines = breakLines(f.nodes, elementBoxes, types, gaps, mode);
      if (lines.every((line) => line.indent + line.width <= params['width']!) ||
          mode == 3)
        break;
    }
    final roots = <Placement>[];
    var width = 0, height = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i],
          lineGaps = line.end - line.start > 1
              ? gaps.sublist(line.start, line.end - 1)
              : <int>[],
          b = rowBox(
            elementBoxes.sublist(line.start, line.end),
            lineGaps,
            'line ${i + 1}',
          );
      roots.add(Placement(b, line.indent, height));
      width = max(width, line.indent + b.width);
      height += b.height;
    }
    if (f.tagString.isNotEmpty) {
      final tag = Box(f.tagString.length, 1, 0, 'tag "${f.tagString}"');
      tag.draw(f.tagString, 0, 0);
      final x = params['width']! - tag.width, last = roots.last;
      var y = last.y + last.box.baseline;
      if (x < last.x + last.box.width + 2) {
        y = height;
        height++;
      }
      roots.add(Placement(tag, x, y));
      width = max(width, x + tag.width);
    }
    return (roots, lines, width, height);
  }
}

class Line {
  final int start, end, indent, width;
  Line(this.start, this.end, this.indent, this.width);
}

void walkNode(Node? n, void Function(Node) visit) {
  if (n == null) return;
  visit(n);
  for (final child in n.items) {
    walkNode(child, visit);
  }
  walkNode(n.base, visit);
  walkNode(n.sub, visit);
  walkNode(n.sup, visit);
  for (final row in n.rows) {
    for (final cell in row) {
      walkNode(cell, visit);
    }
  }
}

void collectWarnings(Formula f, Map<String, String> references) {
  for (final node in f.nodes) {
    walkNode(node, (n) {
      if (n.kind == 'identifier' && commandNames.contains(n.value))
        f.warnings.add(
          Issue(n.column, '${n.value} is a command name; write \\${n.value}'),
        );
      if (n.kind == 'reference' && !references.containsKey(n.value))
        f.warnings.add(Issue(n.column, 'undefined reference "${n.value}"'));
      const pairs = {'(': ')', '[': ']', '|': '|', r'\{': r'\}'};
      if (n.kind == 'delim' &&
          n.left != '.' &&
          n.right != '.' &&
          pairs[n.left] != n.right)
        f.warnings.add(
          Issue(n.rightColumn, '\\left${n.left} closed by \\right${n.right}'),
        );
    });
  }
  f.warnings.sort((a, b) => a.column.compareTo(b.column));
}

String tree(Node n) {
  switch (n.kind) {
    case 'identifier':
    case 'number':
    case 'command':
      return n.value;
    case 'symbol':
      return "'${n.value}'";
    case 'text':
      return '"${n.value}"';
    case 'reference':
      return '(eqref "${n.value}")';
    case 'script':
      if (n.sub != null && n.sup != null)
        return '(subsup ${tree(n.base!)} ${tree(n.sub!)} ${tree(n.sup!)})';
      if (n.sub != null) return '(sub ${tree(n.base!)} ${tree(n.sub!)})';
      return '(sup ${tree(n.base!)} ${tree(n.sup!)})';
    case 'delim':
      {
        String quote(String d) => d.length == 1 ? "'$d'" : d;
        return '(delim ${quote(n.left)} ${quote(n.right)} ${tree(n.items.first)})';
      }
    case 'matrix':
      return '(${n.value}${[for (final row in n.rows) ' [${row.map(tree).join(' ')}]'].join()})';
  }
  final name = n.kind == 'accent' ? n.value : n.kind;
  return '($name${[for (final child in n.items) ' ${tree(child)}'].join()})';
}

void writeLines(String path, List<String> lines) => File(
  'output/$path',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final params = <String, int>{};
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    params[a[0]] = int.parse(a[1]);
  }
  final formulas = <Formula>[],
      source = File('input/formulas.txt').readAsLinesSync();
  for (var i = 0; i < source.length; i++) {
    final f = Formula(i + 1, source[i]);
    final (tokens, error) = tokenize(f.source);
    f.tokens = tokens;
    f.error = error;
    if (f.error == null) f.error = checkBraces(tokens);
    if (f.error == null) {
      final p = Parser(tokens, f.source.length + 1);
      f.nodes = p.elements(true, false);
      if (p.error == null && p.peek().kind != 'eof') p.unexpected(p.peek());
      f.tag = p.tag;
      f.label = p.label;
      f.error = p.error;
    }
    formulas.add(f);
  }
  var counter = 0;
  final references = <String, String>{};
  for (final f in formulas) {
    if (f.error != null) continue;
    final tag = f.tag;
    if (tag != null) {
      f.tagString = '(${tag.value})';
    } else if (f.label != null) {
      counter++;
      f.tagString = '($counter)';
    }
  }
  for (final f in formulas) {
    final label = f.label;
    if (f.error != null || label == null) continue;
    if (references.containsKey(label.value)) {
      f.warnings.add(Issue(label.column, 'duplicate label "${label.value}"'));
    } else {
      references[label.value] = f.tagString;
    }
  }
  final t = Typesetter(params, references),
      rendered = <String>[],
      boxesReport = <String>[],
      trees = <String>[],
      errors = <String>[],
      kinds = <String, int>{};
  var totalBoxes = 0,
      maxDepth = 0,
      valid = 0,
      warningCount = 0,
      overfullCount = 0;
  void diagnostic(Formula f, Issue issue, bool warning) {
    errors.addAll([
      'formula ${f.number}, column ${issue.column}: ${warning ? 'warning: ' : ''}${issue.message}',
      '  ${f.source}',
      '${repeated(' ', issue.column + 1)}^',
    ]);
  }

  for (var i = 0; i < formulas.length; i++) {
    final f = formulas[i];
    if (i > 0) rendered.add('');
    rendered.add('formula ${f.number}');
    final error = f.error;
    if (error != null) {
      rendered.add('(error)');
      boxesReport.add('formula ${f.number}: error');
      trees.add('formula ${f.number}: error');
      diagnostic(f, error, false);
      continue;
    }
    valid++;
    collectWarnings(f, references);
    warningCount += f.warnings.length;
    for (final warning in f.warnings) {
      diagnostic(f, warning, true);
    }
    final (roots, lines, width, height) = t.placeFormula(f);
    rendered.addAll(drawCanvas(roots, width, height));
    final (boxLines, depth, counts) = describeBoxes(roots);
    totalBoxes += boxLines.length;
    maxDepth = max(maxDepth, depth);
    for (final entry in counts.entries) {
      kinds[entry.key] = (kinds[entry.key] ?? 0) + entry.value;
    }
    boxesReport.add(
      'formula ${f.number}: lines=${lines.length} width=$width height=$height boxes=${boxLines.length} depth=$depth',
    );
    boxesReport.addAll(boxLines);
    trees.add('formula ${f.number}: ${f.nodes.map(tree).join(' ')}');
    final linear = t.linear(Node('row', items: f.nodes), false).trimRight();
    trees.add(linear.isEmpty ? '  linear:' : '  linear: $linear');
    if (f.tagString.isNotEmpty) trees.add('  tag: ${f.tagString}');
    for (var j = 0; j < lines.length; j++) {
      final line = lines[j];
      if (line.indent + line.width > params['width']!) {
        overfullCount++;
        errors.add(
          'formula ${f.number}: line ${j + 1} is overfull (width ${line.indent + line.width} > ${params['width']})',
        );
      }
    }
  }
  boxesReport.add('summary: boxes=$totalBoxes max_depth=$maxDepth');
  final names = kinds.keys.toList()..sort();
  for (final name in names) {
    boxesReport.add('  $name: ${kinds[name]}');
  }
  errors.add(
    'formulas=${formulas.length} rendered=$valid errors=${formulas.length - valid} warnings=$warningCount overfull=$overfullCount',
  );
  Directory('output').createSync(recursive: true);
  writeLines('rendered.txt', rendered);
  writeLines('boxes.txt', boxesReport);
  writeLines('trees.txt', trees);
  writeLines('errors.txt', errors);
}
