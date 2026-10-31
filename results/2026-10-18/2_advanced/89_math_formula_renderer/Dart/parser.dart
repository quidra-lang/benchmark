part of 'main.dart';

class Node {
  String kind, value, left = '', right = '';
  int column, rightColumn = 0;
  List<Node> items = [];
  List<List<Node>> rows = [];
  Node? base, sub, sup;
  Node(
    this.kind, {
    this.value = '',
    this.column = 0,
    List<Node>? items,
    this.base,
    this.sub,
    this.sup,
  }) {
    if (items != null) this.items = items;
  }
}

Node emptyRow() => Node('row');
Node collapse(List<Node> nodes) =>
    nodes.length == 1 ? nodes.first : Node('row', items: nodes);
Issue? checkBraces(List<Token> tokens) {
  final stack = <int>[];
  for (final t in tokens) {
    if (t.kind == '{') {
      stack.add(t.column);
    } else if (t.kind == '}') {
      if (stack.isEmpty) return Issue(t.column, 'unmatched }');
      stack.removeLast();
    }
  }
  return stack.isEmpty ? null : Issue(stack.last, 'unclosed {');
}

class Parser {
  final List<Token> tokens;
  final int end;
  int position = 0;
  Issue? error;
  Token? tag, label;
  Parser(this.tokens, this.end);
  Token peek() =>
      position == tokens.length ? Token('eof', '', end) : tokens[position];
  Token read() {
    final t = peek();
    if (position < tokens.length) position++;
    return t;
  }

  void fail(int column, String message) {
    error ??= Issue(column, message);
  }

  bool terminator(Token t) => containsWord('} & newline right end eof', t.kind);
  void unexpected(Token t) {
    fail(
      t.column,
      {
        'right': r'unexpected \right',
        'end': r'unexpected \end',
        '&': 'misplaced &',
        'newline': r'misplaced \\',
      }[t.kind]!,
    );
  }

  List<Node> elements(bool top, bool index) {
    final out = <Node>[];
    while (error == null) {
      final t = peek();
      if (terminator(t) || index && t.kind == 'symbol' && t.value == ']') break;
      if (t.kind == 'tag' || t.kind == 'label') {
        if (!top) {
          fail(t.column, 'misplaced \\${t.kind}');
          break;
        }
        if ((t.kind == 'tag' ? tag : label) != null) {
          fail(t.column, 'duplicate \\${t.kind}');
          break;
        }
        read();
        if (t.kind == 'tag') {
          tag = t;
        } else {
          label = t;
        }
        continue;
      }
      out.add(element());
    }
    return out;
  }

  Node element() {
    var base = emptyRow();
    var t = peek();
    if (t.kind != '^' && t.kind != '_') base = nucleus();
    Node? sub, sup;
    while (error == null && (peek().kind == '^' || peek().kind == '_')) {
      t = read();
      if (t.kind == '^') {
        if (sup != null) {
          fail(t.column, 'double superscript');
          break;
        }
        sup = argument('^');
      } else {
        if (sub != null) {
          fail(t.column, 'double subscript');
          break;
        }
        sub = argument('_');
      }
    }
    return sub == null && sup == null
        ? base
        : Node('script', base: base, sub: sub, sup: sup);
  }

  Node argument(String name) {
    if (error != null) return emptyRow();
    final t = peek();
    if (!containsWord(
      'identifier number symbol command text eqref { frac binom overset underset sqrt accent',
      t.kind,
    )) {
      fail(t.column, 'missing argument for $name');
      return emptyRow();
    }
    return nucleus();
  }

  String delimiter() {
    final t = read();
    if (t.kind == 'symbol' && containsWord('( ) [ ] | .', t.value) ||
        t.kind == 'command' && (t.value == r'\{' || t.value == r'\}'))
      return t.value;
    fail(t.column, 'invalid delimiter');
    return '.';
  }

  Node nucleus() {
    if (error != null) return emptyRow();
    final t = read(), n = Node(t.kind, value: t.value, column: t.column);
    switch (t.kind) {
      case 'identifier':
      case 'number':
      case 'symbol':
      case 'command':
      case 'text':
        return n;
      case 'eqref':
        n.kind = 'reference';
        return n;
      case '{':
        {
          final nodes = elements(false, false);
          if (error == null) {
            if (peek().kind == '}') {
              read();
            } else {
              unexpected(peek());
            }
          }
          return collapse(nodes);
        }
      case 'frac':
      case 'binom':
      case 'overset':
      case 'underset':
        {
          final first = argument('\\${t.kind}'),
              second = argument('\\${t.kind}');
          n.items = [first, second];
          return n;
        }
      case 'sqrt':
        {
          Node? index;
          if (peek().kind == 'symbol' && peek().value == '[') {
            final open = read(), nodes = elements(false, true);
            if (error == null) {
              if (peek().kind != 'symbol' || peek().value != ']') {
                fail(open.column, 'missing ]');
              } else {
                read();
              }
            }
            index = collapse(nodes);
          }
          final body = argument(r'\sqrt');
          if (index != null) {
            n.kind = 'root';
            n.items = [index, body];
          } else {
            n.items = [body];
          }
          return n;
        }
      case 'accent':
        n.items = [argument('\\${t.value}')];
        return n;
      case 'left':
        {
          n.kind = 'delim';
          n.left = delimiter();
          final body = elements(false, false);
          if (error == null) {
            if (peek().kind != 'right') {
              fail(t.column, r'missing \right');
            } else {
              final right = read();
              n.rightColumn = right.column;
              n.right = delimiter();
            }
          }
          n.items = [collapse(body)];
          return n;
        }
      case 'begin':
        {
          n.kind = 'matrix';
          final rows = <List<Node>>[[]];
          while (error == null) {
            final cells = elements(false, false);
            rows.last.add(collapse(cells));
            if (error != null) break;
            final close = read();
            if (close.kind == '&') continue;
            if (close.kind == 'newline') {
              rows.add([]);
              continue;
            }
            if (close.kind == 'end') {
              if (close.value != t.value)
                fail(close.column, r'mismatched \end');
              break;
            }
            fail(t.column, r'missing \end');
          }
          if (rows.length > 1) {
            final last = rows.last;
            if (last.length == 1 &&
                last.first.kind == 'row' &&
                last.first.items.isEmpty)
              rows.removeLast();
          }
          var width = 0;
          for (final row in rows) {
            width = max(width, row.length);
          }
          for (final row in rows) {
            while (row.length < width) {
              row.add(emptyRow());
            }
          }
          n.rows = rows;
          return n;
        }
    }
    return n;
  }
}
