part of 'main.dart';

class Position {
  final String file;
  final int line;
  Position(this.file, this.line);
  @override
  String toString() => '$file:$line';
}

const variadicName = '__VA_ARGS__';
const builtins = {'__LINE__', '__FILE__', '__COUNTER__'};

class Macro {
  final String name;
  final Position position;
  final bool mainFile;
  bool function = false, variadic = false;
  final List<String> parameters = [];
  List<Token> replacement = [];
  int expanded = 0, tested = 0;
  Macro(this.name, this.position, this.mainFile);
  String signature() {
    if (!function) return name;
    final params = List<String>.of(parameters);
    if (variadic) params[params.length - 1] = '...';
    return '$name(${params.join(', ')})';
  }

  bool identical(Macro other) {
    if (function != other.function ||
        variadic != other.variadic ||
        parameters.length != other.parameters.length ||
        replacement.length != other.replacement.length)
      return false;
    for (var i = 0; i < parameters.length; i++) {
      if (parameters[i] != other.parameters[i]) return false;
    }
    for (var i = 0; i < replacement.length; i++) {
      final t = replacement[i], u = other.replacement[i];
      if (t.spelling != u.spelling || t.space != u.space) return false;
    }
    return true;
  }
}

String? checkName(List<Token> tokens, String directive) {
  if (tokens.isEmpty) return 'no macro name given in #$directive directive';
  if (tokens.first.kind != 'identifier')
    return 'macro names must be identifiers';
  final name = tokens.first.spelling;
  if (name == 'defined') return '"defined" cannot be used as a macro name';
  if (builtins.contains(name))
    return directive == 'define'
        ? 'cannot redefine builtin macro "$name"'
        : 'cannot undefine builtin macro "$name"';
  return null;
}

class DefinitionError implements Exception {
  final String message;
  DefinitionError(this.message);
}

Never definitionError(String message) => throw DefinitionError(message);
Macro parseDefinition(List<Token> tokens, Position pos, bool main) {
  final error = checkName(tokens, 'define');
  if (error != null) definitionError(error);
  final m = Macro(tokens.first.spelling, pos, main);
  if (m.name == variadicName)
    definitionError(
      '"__VA_ARGS__" can only appear in the expansion of a variadic macro',
    );
  var index = 1;
  if (index < tokens.length &&
      tokens[index].spelling == '(' &&
      !tokens[index].space) {
    m.function = true;
    index++;
    if (index == tokens.length)
      definitionError("missing ')' in macro parameter list");
    if (tokens[index].spelling == ')') {
      index++;
    } else {
      final seen = <String>{};
      while (true) {
        if (index == tokens.length)
          definitionError("missing ')' in macro parameter list");
        final token = tokens[index++];
        var parameter = token.spelling;
        if (parameter == '...') {
          m.variadic = true;
          parameter = variadicName;
        } else if (token.kind == 'identifier') {
          if (parameter == variadicName)
            definitionError(
              '"__VA_ARGS__" can only appear in the expansion of a variadic macro',
            );
          if (seen.contains(parameter))
            definitionError('duplicate macro parameter "$parameter"');
        } else {
          definitionError('expected parameter name, found "$parameter"');
        }
        seen.add(parameter);
        m.parameters.add(parameter);
        if (index == tokens.length)
          definitionError("missing ')' in macro parameter list");
        final next = tokens[index++].spelling;
        if (next == ')') break;
        if (m.variadic)
          definitionError('expected \')\' after "...", found "$next"');
        if (next != ',')
          definitionError('expected \',\' or \')\', found "$next"');
      }
    }
  }
  m.replacement = tokens.sublist(index);
  if (m.replacement.isNotEmpty) {
    m.replacement[0] = m.replacement[0].copy(space: false);
    if (m.replacement.first.spelling == '##' ||
        m.replacement.last.spelling == '##')
      definitionError("'##' cannot appear at either end of a macro expansion");
  }
  final parameters = m.parameters.toSet();
  for (var i = 0; i < m.replacement.length; i++) {
    final token = m.replacement[i];
    if (token.kind == 'identifier' &&
        token.spelling == variadicName &&
        !m.variadic)
      definitionError(
        '"__VA_ARGS__" can only appear in the expansion of a variadic macro',
      );
    if (token.spelling == '#' &&
        m.function &&
        (i + 1 == m.replacement.length ||
            m.replacement[i + 1].kind != 'identifier' ||
            !parameters.contains(m.replacement[i + 1].spelling)))
      definitionError("'#' is not followed by a macro parameter");
  }
  return m;
}
