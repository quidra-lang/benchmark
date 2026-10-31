part of 'main.dart';

class CollectedArguments {
  final Map<String, List<Token>> raw;
  final int consumed;
  final Token closing;
  CollectedArguments(this.raw, this.consumed, this.closing);
}

class SubstitutionItem {
  final List<Token> tokens;
  final Token? operator;
  SubstitutionItem.sequence(this.tokens) : operator = null;
  SubstitutionItem.paste(Token token) : tokens = [], operator = token;
}

class Expander {
  final Map<String, Macro> macros;
  final void Function(Position, String, String) diagnostic;
  int counter = 0;
  final Map<String, int> builtinCounts = {};
  Expander(this.macros, this.diagnostic);
  void error(Inclusion context, Token t, String message) =>
      diagnostic(context.position(t.line), 'error', message);
  Token builtin(Token t, Inclusion context) {
    builtinCounts[t.spelling] = (builtinCounts[t.spelling] ?? 0) + 1;
    var kind = 'number', spelling = '';
    switch (t.spelling) {
      case '__FILE__':
        kind = 'string';
        spelling = '"${context.displayFile}"';
        break;
      case '__LINE__':
        spelling = '${context.position(t.line).line}';
        break;
      case '__COUNTER__':
        spelling = '${counter++}';
        break;
    }
    return Token(kind, spelling, t.line, space: t.space);
  }

  CollectedArguments? collect(
    Queue<Token> pending,
    Macro m,
    Token t,
    Inclusion context,
  ) {
    final source = pending.toList(),
        arguments = <List<Token>>[[]],
        separators = <Token>[];
    var nesting = 0, consumed = 0;
    Token? closing;
    for (var index = 1; index < source.length; index++) {
      final current = source[index];
      if (current.spelling == ')' && nesting == 0) {
        closing = current;
        consumed = index + 1;
        break;
      }
      if (current.spelling == ',' && nesting == 0) {
        separators.add(current);
        arguments.add([]);
      } else {
        if (current.spelling == '(') {
          nesting++;
        } else if (current.spelling == ')') {
          nesting--;
        }
        arguments.last.add(current);
      }
    }
    if (closing == null) {
      error(
        context,
        t,
        'unterminated argument list invoking macro "${m.name}"',
      );
      return null;
    }
    final count = arguments.length,
        fixed = m.parameters.length - (m.variadic ? 1 : 0);
    String? message;
    if (!m.variadic &&
        fixed == 0 &&
        (count != 1 || arguments.first.isNotEmpty)) {
      message = 'macro "${m.name}" passed $count arguments, but takes just 0';
    } else if (count < fixed) {
      message =
          'macro "${m.name}" requires $fixed arguments, but only $count given';
    } else if (count > fixed && !m.variadic) {
      message =
          'macro "${m.name}" passed $count arguments, but takes just $fixed';
    }
    if (message != null) {
      error(context, t, message);
      return null;
    }
    final raw = <String, List<Token>>{
      for (var i = 0; i < fixed; i++) m.parameters[i]: List.of(arguments[i]),
    };
    if (m.variadic) {
      final variable = <Token>[];
      for (var i = fixed; i < count; i++) {
        if (i > fixed) variable.add(separators[i - 1]);
        variable.addAll(arguments[i]);
      }
      raw[variadicName] = variable;
    }
    return CollectedArguments(raw, consumed, closing);
  }

  Token stringize(List<Token> tokens, Token sharp) {
    final value = StringBuffer('"');
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (i > 0 && t.space) value.write(' ');
      var spelling = t.spelling;
      if (t.kind == 'string' || t.kind == 'character')
        spelling = spelling.replaceAll('\\', r'\\').replaceAll('"', r'\"');
      value.write(spelling);
    }
    value.write('"');
    return Token('string', value.toString(), sharp.line, space: sharp.space);
  }

  List<Token> paste(Token left, Token right, Token t, Inclusion context) {
    if (left.kind == 'placemarker') return [right.copy(space: left.space)];
    if (right.kind == 'placemarker') return [left];
    final spelling = left.spelling + right.spelling,
        kind = singleToken(spelling);
    if (kind != null)
      return [
        Token(
          kind,
          spelling,
          left.line,
          space: left.space,
          hide: left.hide.intersection(right.hide),
        ),
      ];
    error(
      context,
      t,
      'pasting "${left.spelling}" and "${right.spelling}" does not give a valid preprocessing token',
    );
    return [left, right.copy(space: false)];
  }

  List<Token> substitute(
    Macro m,
    Map<String, List<Token>> raw,
    Token t,
    Set<String> hide,
    Inclusion context,
  ) {
    final replacement = m.replacement,
        items = <SubstitutionItem>[],
        expanded = <String, List<Token>>{};
    for (var index = 0; index < replacement.length;) {
      final current = replacement[index];
      if (current.spelling == '#' && m.function) {
        final parameter = replacement[index + 1].spelling;
        items.add(
          SubstitutionItem.sequence([stringize(raw[parameter]!, current)]),
        );
        index += 2;
        continue;
      }
      if (current.spelling == '##') {
        items.add(SubstitutionItem.paste(current));
      } else if (current.kind == 'identifier' &&
          raw.containsKey(current.spelling)) {
        final adjacent =
                index > 0 && replacement[index - 1].spelling == '##' ||
                index + 1 < replacement.length &&
                    replacement[index + 1].spelling == '##',
            argument = raw[current.spelling]!;
        final sequence = List<Token>.of(
          adjacent
              ? argument
              : expanded.putIfAbsent(
                  current.spelling,
                  () => expand(argument, context),
                ),
        );
        if (sequence.isNotEmpty) {
          sequence[0] = sequence[0].copy(space: current.space);
        } else {
          sequence.add(
            Token('placemarker', '', current.line, space: current.space),
          );
        }
        items.add(SubstitutionItem.sequence(sequence));
      } else {
        items.add(SubstitutionItem.sequence([current]));
      }
      index++;
    }
    final pasted = <Token>[];
    for (var index = 0; index < items.length;) {
      final item = items[index];
      if (item.operator == null) {
        pasted.addAll(item.tokens);
        index++;
        continue;
      }
      final left = pasted.removeLast(),
          rightItem = items[index + 1],
          operator = rightItem.operator,
          right = operator == null ? rightItem.tokens : [operator];
      pasted.addAll(paste(left, right.first, t, context));
      pasted.addAll(right.skip(1));
      index += 2;
    }
    final result = <Token>[];
    var carry = false;
    for (final current in pasted) {
      if (current.kind == 'placemarker') {
        carry = carry || current.space;
        continue;
      }
      result.add(
        current.copy(
          line: t.line,
          space: current.space || carry,
          hide: {...current.hide, ...hide},
        ),
      );
      carry = false;
    }
    if (result.isNotEmpty) result[0] = result[0].copy(space: t.space);
    return result;
  }

  List<Token> expand(List<Token> sequence, Inclusion context) {
    final pending = ListQueue<Token>.of(sequence), result = <Token>[];
    while (pending.isNotEmpty) {
      final t = pending.removeFirst();
      if (t.kind != 'identifier' || t.hide.contains(t.spelling)) {
        result.add(t);
        continue;
      }
      if (builtins.contains(t.spelling)) {
        result.add(builtin(t, context));
        continue;
      }
      final m = macros[t.spelling];
      if (m == null ||
          m.function && (pending.isEmpty || pending.first.spelling != '(')) {
        result.add(t);
        continue;
      }
      var raw = <String, List<Token>>{}, hide = {...t.hide, m.name};
      if (m.function) {
        final collected = collect(pending, m, t, context);
        if (collected == null) {
          result.add(t);
          continue;
        }
        raw = collected.raw;
        for (var i = 0; i < collected.consumed; i++) {
          pending.removeFirst();
        }
        hide = {...t.hide.intersection(collected.closing.hide), m.name};
      }
      final replacement = substitute(m, raw, t, hide, context);
      m.expanded++;
      if (replacement.isEmpty && t.space && pending.isNotEmpty) {
        final first = pending.removeFirst();
        pending.addFirst(first.copy(space: true));
      }
      for (final token in replacement.reversed) {
        pending.addFirst(token);
      }
    }
    return result;
  }
}
