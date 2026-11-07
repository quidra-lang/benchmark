import 'dart:io';
import 'dart:math';
part 'lexer.dart';
part 'parser.dart';
part 'doc_builder.dart';
part 'printer.dart';
part 'report.dart';

String repeated(String s, int count) => List.filled(count, s).join();

class Profile {
  final int width, indent, maxBlank, commentColumn;
  final bool allman, spaces, keywordSpace, indentCases, addBraces, removeParens;
  Profile(Map<String, String> values)
    : width = int.parse(values['width']!),
      indent = int.parse(values['indent']!),
      maxBlank = int.parse(values['max_blank_lines']!),
      commentColumn = int.parse(values['comment_column']!),
      allman = values['brace_style'] == 'allman',
      spaces = values['space_around_operators'] == 'yes',
      keywordSpace = values['space_after_keyword'] == 'yes',
      indentCases = values['indent_case_labels'] == 'yes',
      addBraces = values['add_braces'] == 'yes',
      removeParens = values['remove_parens'] == 'yes';
}

class Source {
  final String header, name, profile;
  final List<String> lines = [];
  Source(this.header, this.name, this.profile);
}

class FormatResult {
  List<String> lines = [];
  final FileError? error;
  final Doc? document, functionDoc;
  final String functionName;
  final int comments;
  FormatResult({
    this.error,
    this.document,
    this.functionDoc,
    this.functionName = '',
    this.comments = 0,
  });
}

int attachComments(List<Token> tokens, List<Lexeme> items) {
  final next = List<Token?>.filled(items.length, null);
  Token? following;
  for (var i = items.length - 1; i >= 0; i--) {
    next[i] = following;
    final token = items[i].token;
    if (token != null) following = token;
  }
  Token? previous;
  var count = 0;
  for (var i = 0; i < items.length; i++) {
    final item = items[i], token = item.token;
    if (token != null) {
      previous = token;
      continue;
    }
    count++;
    final c = item.comment!;
    var n = next[i];
    if (previous != null &&
        previous.line == c.line &&
        (n == null || n.line > c.line)) {
      previous.trailing.add(c);
      previous.originalTrailing = true;
    } else {
      c.own =
          c.kind == 'line' ||
          i + 1 == items.length ||
          items[i + 1].line > c.line;
      n ??= tokens.last;
      n.leading.add(c);
    }
  }
  return count;
}

FileError? checkComments(Node root, List<Token> tokens) {
  final allowed = {tokens.length - 1}, trailing = <int>{};
  void walk(Node n) {
    switch (n.kind) {
      case 'program':
        for (final item in n.elements) {
          allowed.add(item.first);
        }
        break;
      case 'block':
        allowed.add(n.close!.index);
        for (final s in n.elements) {
          allowed.add(s.first);
        }
        break;
      case 'switchbody':
        allowed.add(n.close!.index);
        for (final clause in n.elements) {
          allowed.add(clause.token!.index);
          for (final s in clause.elements) {
            allowed.add(s.first);
          }
        }
        break;
      case 'if':
      case 'while':
      case 'for':
        final body = n.body!;
        if (body.kind != 'block') allowed.add(body.first);
        final other = n.elseNode;
        if (n.kind == 'if' &&
            other != null &&
            other.kind != 'block' &&
            other.kind != 'if')
          allowed.add(other.first);
        break;
      case 'list':
        for (final element in n.elements) {
          allowed.add(element.first);
        }
        final comma = n.trailing;
        if (comma != null) trailing.add(comma.index);
        break;
    }
    for (final child in nodeChildren(n)) {
      walk(child);
    }
  }

  walk(root);
  for (final token in tokens) {
    for (final comment in token.leading) {
      if (trailing.contains(token.index) ||
          comment.own && !allowed.contains(token.index))
        return FileError(comment, 'comment not allowed here');
    }
  }
  return null;
}

class Builder {
  final Profile profile;
  final List<Token> tokens;
  Doc? firstFunction;
  String functionName = '';
  Builder(this.profile, this.tokens);
  Doc space() => text(profile.spaces ? ' ' : '');
  Doc operatorLine() => marker(profile.spaces ? 'line' : 'softline');
  Doc keywordSpace() => text(profile.keywordSpace ? ' ' : '');
  Doc braceSeparator() => profile.allman ? marker('hardline') : text(' ');
  Doc separator(int blank) => cat([
    marker('hardline'),
    for (var i = 0; i < min(blank, profile.maxBlank); i++) marker('hardline'),
  ]);
  int preBlank(Token t) =>
      t.leading.isNotEmpty ? t.leading.first.blank : t.blank;
  Doc comments(List<Comment> comments, int? lastBlank) {
    final docs = <Doc>[];
    for (var i = 0; i < comments.length; i++) {
      final c = comments[i];
      docs.add(text(c.text));
      final nextBlank = i + 1 < comments.length
          ? comments[i + 1].blank
          : lastBlank;
      if (nextBlank != null) docs.add(c.own ? separator(nextBlank) : text(' '));
    }
    return cat(docs);
  }

  Doc trailingPart(Token t) => t.trailing.isEmpty
      ? text('')
      : suffix(t.trailing.map((c) => c.text).join(' '));
  Doc tokenLeading(Token t, List<Comment> leading) =>
      cat([comments(leading, t.blank), text(t.text), trailingPart(t)]);
  Doc token(Token? t) => t == null ? text('') : tokenLeading(t, t.leading);
  (List<Comment>, List<Comment>) splitClosing(Token t) {
    var last = -1;
    for (var i = 0; i < t.leading.length; i++) {
      if (t.leading[i].own) last = i;
    }
    return (t.leading.sublist(0, last + 1), t.leading.sublist(last + 1));
  }

  Doc whole(Node root) {
    final docs = <Doc>[];
    for (var i = 0; i < root.elements.length; i++) {
      final item = root.elements[i];
      if (i > 0) docs.add(separator(preBlank(tokens[item.first])));
      final d = statement(item);
      docs.add(d);
      if (item.kind == 'function' && firstFunction == null) {
        firstFunction = d;
        functionName = item.name!.text;
      }
    }
    final end = tokens.last;
    if (end.leading.isNotEmpty) {
      if (root.elements.isNotEmpty)
        docs.add(separator(end.leading.first.blank));
      docs.add(comments(end.leading, null));
    }
    return cat(docs);
  }

  Doc list(Node n) {
    if (n.elements.isEmpty) return cat([token(n.open), token(n.close)]);
    var force = text('');
    for (var i = n.open!.index; i < n.close!.index; i++) {
      if (tokens[i].originalTrailing) {
        force = marker('break_parent');
        break;
      }
    }
    final inside = <Doc>[marker('softline')];
    for (var i = 0; i < n.elements.length; i++) {
      if (i > 0) inside.addAll([token(n.commas[i - 1]), marker('line')]);
      final element = n.elements[i];
      inside.add(
        n.value == 'arguments' ? expression(element, 0) : statement(element),
      );
    }
    if (n.value == 'initializer') {
      inside.add(ifBreak(',', ''));
      final trailing = n.trailing;
      if (trailing != null) inside.add(trailingPart(trailing));
    }
    return group([
      force,
      token(n.open),
      nest(profile.indent, inside),
      marker('softline'),
      token(n.close),
    ]);
  }

  Doc block(Node n) {
    final (h, g) = splitClosing(n.close!);
    if (n.elements.isEmpty && h.isEmpty)
      return cat([token(n.open), tokenLeading(n.close!, g)]);
    final inside = <Doc>[marker('hardline')];
    for (var i = 0; i < n.elements.length; i++) {
      final s = n.elements[i];
      if (i > 0) inside.add(separator(preBlank(tokens[s.first])));
      inside.add(statement(s));
    }
    if (h.isNotEmpty) {
      if (n.elements.isNotEmpty) inside.add(separator(h.first.blank));
      inside.add(comments(h, null));
    }
    return cat([
      token(n.open),
      nest(profile.indent, inside),
      marker('hardline'),
      tokenLeading(n.close!, g),
    ]);
  }

  Doc body(Node n) {
    if (n.kind == 'block') return cat([braceSeparator(), block(n)]);
    if (profile.addBraces)
      return cat([
        braceSeparator(),
        text('{'),
        nest(profile.indent, [marker('hardline'), statement(n)]),
        marker('hardline'),
        text('}'),
      ]);
    return nest(profile.indent, [marker('hardline'), statement(n)]);
  }

  Doc declaration(Node n) {
    final docs = <Doc>[token(n.token), text(' '), token(n.name)];
    for (final d in n.dimensions) {
      docs.add(token(d.open));
      final expr = d.expr;
      if (expr != null) docs.add(expression(expr, 0));
      docs.add(token(d.close));
    }
    if (n.op != null) {
      docs.addAll([space(), token(n.op), space()]);
      final init = n.init!;
      docs.add(init.kind == 'list' ? list(init) : expression(init, 0));
    }
    docs.add(token(n.semi));
    return cat(docs);
  }

  Doc simple(Node n) => n.kind == 'assignment'
      ? cat([
          expression(n.left!, 0),
          space(),
          token(n.op),
          space(),
          expression(n.right!, 0),
        ])
      : expression(n.expr!, 0);
  Doc statement(Node n) {
    switch (n.kind) {
      case 'function':
        return cat([
          token(n.token),
          text(' '),
          token(n.name),
          list(n.init!),
          marker('hardline'),
          block(n.body!),
        ]);
      case 'parameter':
      case 'declaration':
        return declaration(n);
      case 'list':
        return list(n);
      case 'block':
        return block(n);
      case 'assignment':
      case 'simple':
        return cat([simple(n), token(n.semi)]);
      case 'return':
        {
          final docs = <Doc>[token(n.token)], expr = n.expr;
          if (expr != null) docs.addAll([text(' '), expression(expr, 0)]);
          docs.add(token(n.semi));
          return cat(docs);
        }
      case 'break':
      case 'continue':
        return cat([token(n.token), token(n.semi)]);
      case 'while':
        return cat([
          token(n.token),
          keywordSpace(),
          token(n.open),
          expression(n.expr!, 0),
          token(n.close),
          body(n.body!),
        ]);
      case 'for':
        {
          final parts = <Doc>[],
              init = n.init,
              condition = n.cond,
              update = n.update;
          if (init != null)
            parts.add(
              init.kind == 'declaration' ? declaration(init) : simple(init),
            );
          parts.add(token(n.semi));
          if (condition != null)
            parts.addAll([marker('line'), expression(condition, 0)]);
          parts.add(token(n.semi2));
          if (update != null) parts.addAll([marker('line'), simple(update)]);
          return cat([
            token(n.token),
            keywordSpace(),
            token(n.open),
            group([align(parts)]),
            token(n.close),
            body(n.body!),
          ]);
        }
      case 'if':
        {
          final before = n.body!,
              docs = <Doc>[
                token(n.token),
                keywordSpace(),
                token(n.open),
                expression(n.expr!, 0),
                token(n.close),
                body(before),
              ],
              other = n.elseNode;
          if (other != null) {
            final separator =
                !profile.allman && (before.kind == 'block' || profile.addBraces)
                ? text(' ')
                : marker('hardline');
            docs.addAll([separator, token(n.elseToken)]);
            if (other.kind == 'if') {
              docs.addAll([text(' '), statement(other)]);
            } else {
              docs.add(body(other));
            }
          }
          return cat(docs);
        }
      case 'switch':
        {
          final content = n.body!;
          final (h, g) = splitClosing(content.close!);
          final head = cat([
            token(n.token),
            keywordSpace(),
            token(n.open),
            expression(n.expr!, 0),
            token(n.close),
            braceSeparator(),
            token(content.open),
          ]);
          if (content.elements.isEmpty && h.isEmpty)
            return cat([head, tokenLeading(content.close!, g)]);
          final inside = <Doc>[marker('hardline')];
          for (var i = 0; i < content.elements.length; i++) {
            final clause = content.elements[i];
            if (i > 0) inside.add(separator(preBlank(clause.token!)));
            final parts = <Doc>[token(clause.token)], expr = clause.expr;
            if (expr != null) parts.addAll([text(' '), expression(expr, 0)]);
            parts.add(token(clause.colon));
            if (clause.elements.isNotEmpty) {
              final statements = <Doc>[marker('hardline')];
              for (var j = 0; j < clause.elements.length; j++) {
                final s = clause.elements[j];
                if (j > 0) statements.add(separator(preBlank(tokens[s.first])));
                statements.add(statement(s));
              }
              parts.add(nest(profile.indent, statements));
            }
            inside.add(cat(parts));
          }
          if (h.isNotEmpty) {
            if (content.elements.isNotEmpty)
              inside.add(separator(h.first.blank));
            inside.add(comments(h, null));
          }
          return cat([
            head,
            nest(profile.indentCases ? profile.indent : 0, inside),
            marker('hardline'),
            tokenLeading(content.close!, g),
          ]);
        }
    }
    return expression(n, 0);
  }

  Node opening(Node original, int required) {
    var n = original;
    if (!profile.removeParens) return n;
    while (n.kind == 'paren' &&
        expressionLevel(n.expr!) >= required &&
        n.open!.leading.isEmpty &&
        n.close!.leading.isEmpty) {
      final inner = n.expr!,
          first = tokens[inner.first],
          last = tokens[inner.last];
      first.trailing = [...n.open!.trailing, ...first.trailing];
      last.trailing.addAll(n.close!.trailing);
      n.open!.trailing = [];
      n.close!.trailing = [];
      n = inner;
    }
    return n;
  }

  bool postfix(Node n) =>
      n.kind == 'call' || n.kind == 'index' || n.kind == 'member';
  Doc postfixDocument(Node n) => switch (n.kind) {
    'call' => list(n.init!),
    'index' => cat([token(n.open), expression(n.expr!, 0), token(n.close)]),
    _ => cat([token(n.op), token(n.name)]),
  };
  Doc expression(Node original, int required) {
    final n = opening(original, required);
    switch (n.kind) {
      case 'atom':
        return token(n.token);
      case 'paren':
        return cat([token(n.open), expression(n.expr!, 0), token(n.close)]);
      case 'unary':
        return cat([token(n.op), expression(n.expr!, 8)]);
      case 'binary':
        {
          final level = expressionLevel(n),
              operators = <Token>[],
              operands = <Node>[];
          var head = n;
          while (head.kind == 'binary' && expressionLevel(head) == level) {
            operators.add(head.op!);
            operands.add(head.right!);
            head = opening(head.left!, level);
          }
          final inside = <Doc>[];
          for (var i = operators.length - 1; i >= 0; i--) {
            inside.addAll([
              operatorLine(),
              token(operators[i]),
              space(),
              expression(operands[i], level + 1),
            ]);
          }
          return group([expression(head, level), nest(profile.indent, inside)]);
        }
      case 'conditional':
        {
          final inside = <Doc>[];
          var current = n;
          while (true) {
            inside.addAll([
              operatorLine(),
              token(current.op),
              space(),
              expression(current.thenNode!, 0),
              operatorLine(),
              token(current.colon),
              space(),
            ]);
            final other = opening(current.elseNode!, 0);
            if (other.kind == 'conditional') {
              inside.add(expression(other.expr!, 1));
              current = other;
            } else {
              inside.add(expression(other, 0));
              break;
            }
          }
          return group([expression(n.expr!, 1), nest(profile.indent, inside)]);
        }
      case 'call':
      case 'index':
      case 'member':
        {
          final reversed = <Node>[];
          var head = n;
          while (postfix(head)) {
            reversed.add(head);
            head = opening(head.left!, 8);
          }
          final operations = reversed.reversed.toList(),
              segments = <List<Node>>[[]];
          for (final op in operations) {
            if (op.kind == 'member') segments.add([]);
            segments.last.add(op);
          }
          var count = 0, first = -1;
          for (var i = 1; i < segments.length; i++) {
            if (segments[i].any((op) => op.kind == 'call')) {
              count++;
              if (first < 0) first = i;
            }
          }
          final docs = <Doc>[expression(head, 8)];
          if (count < 2) {
            for (final op in operations) {
              docs.add(postfixDocument(op));
            }
            return cat(docs);
          }
          for (var i = 0; i < first; i++) {
            for (final op in segments[i]) {
              docs.add(postfixDocument(op));
            }
          }
          final inside = <Doc>[];
          for (var i = first; i < segments.length; i++) {
            inside.add(marker('softline'));
            for (final op in segments[i]) {
              inside.add(postfixDocument(op));
            }
          }
          docs.add(nest(profile.indent, inside));
          return group(docs);
        }
    }
    return text('');
  }
}

FormatResult format(List<String> source, Profile profile) {
  final (tokens, items, error) = lex(source);
  if (error != null) return FormatResult(error: error);
  final comments = attachComments(tokens, items),
      parser = Parser(tokens),
      root = parser.program();
  if (parser.error != null) return FormatResult(error: parser.error);
  final positionError = checkComments(root, tokens);
  if (positionError != null) return FormatResult(error: positionError);
  final builder = Builder(profile, tokens),
      document = builder.whole(root),
      result = FormatResult(
        document: document,
        functionDoc: builder.firstFunction,
        functionName: builder.functionName,
        comments: comments,
      );
  if (root.elements.isNotEmpty || tokens.last.leading.isNotEmpty)
    result.lines = printDoc(document, profile.width, profile.commentColumn);
  return result;
}

Map<String, Profile> readProfiles() {
  final profiles = <String, Profile>{};
  var name = '', values = <String, String>{};
  void save() {
    if (name.isNotEmpty) profiles[name] = Profile(values);
  }

  for (final line in File('input/style.txt').readAsLinesSync()) {
    if (line.isEmpty) continue;
    if (line.startsWith('[')) {
      save();
      name = line.substring(1, line.length - 1);
      values = {};
    } else {
      final equals = line.indexOf('=');
      values[line.substring(0, equals)] = line.substring(equals + 1);
    }
  }
  save();
  return profiles;
}

List<Source> readSources() {
  final out = <Source>[];
  for (final line in File('input/sources.txt').readAsLinesSync()) {
    if (line.startsWith('=== ')) {
      final a = line.split(' ');
      out.add(Source(line, a[1], a[2]));
    } else {
      out.last.lines.add(line);
    }
  }
  return out;
}

void writeLines(String path, List<String> lines) => File(
  'output/$path',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final profiles = readProfiles(),
      formatted = <String>[],
      idempotency = <String>[],
      diagnostics = <String>[],
      trees = <String>[],
      changes = <String>[];
  for (final source in readSources()) {
    final profile = profiles[source.profile]!,
        result = format(source.lines, profile),
        original = source.lines.map((line) => line.trimRight()).toList();
    formatted.add(source.header);
    trees.add('=== ${source.name}');
    changes.add('=== ${source.name}');
    final error = result.error;
    if (error != null) {
      formatted.addAll(original);
      idempotency.add('${source.name}: skipped (syntax error)');
      diagnostics.add(
        '${source.name}:${error.line}:${error.column}: error: ${error.message}',
      );
      trees.add('syntax error');
      changes.add('skipped (syntax error)');
      continue;
    }
    formatted.addAll(result.lines);
    final second = format(result.lines, profile), secondError = second.error;
    if (secondError != null) {
      idempotency.add(
        '${source.name}: unstable (second pass: ${secondError.line}:${secondError.column}: ${secondError.message})',
      );
    } else {
      var difference = -1;
      for (var i = 0; i < min(result.lines.length, second.lines.length); i++) {
        if (result.lines[i] != second.lines[i]) {
          difference = i + 1;
          break;
        }
      }
      if (difference < 0 && result.lines.length != second.lines.length)
        difference = min(result.lines.length, second.lines.length) + 1;
      idempotency.add(
        difference < 0
            ? '${source.name}: stable'
            : '${source.name}: unstable at line $difference',
      );
    }
    var longest = 0;
    for (var i = 0; i < result.lines.length; i++) {
      final line = result.lines[i];
      longest = max(longest, line.length);
      if (line.length > profile.width)
        diagnostics.add(
          '${source.name}:${i + 1}: warning: line too long (${line.length} > ${profile.width})',
        );
    }
    final (groups, broken, forced) = groupMetrics(result.document!);
    trees.add(
      'metrics lines=${result.lines.length} longest=$longest comments=${result.comments} groups=$groups broken=$broken forced=$forced',
    );
    final function = result.functionDoc;
    if (function == null) {
      trees.add('no function');
    } else {
      trees.add('function ${result.functionName}');
      trees.addAll(docTree(function, 0));
    }
    changes.addAll(diffLines(original, result.lines));
  }
  if (diagnostics.isEmpty) diagnostics.add('no diagnostics');
  Directory('output').createSync(recursive: true);
  writeLines('formatted.txt', formatted);
  writeLines('idempotency.txt', idempotency);
  writeLines('diagnostics.txt', diagnostics);
  writeLines('doc_tree.txt', trees);
  writeLines('changes.txt', changes);
}
