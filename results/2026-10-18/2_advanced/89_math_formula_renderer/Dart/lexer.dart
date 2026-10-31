part of 'main.dart';

class Token {
  final String kind, value;
  final int column;
  Token(this.kind, this.value, this.column);
}

class Issue {
  final int column;
  final String message;
  Issue(this.column, this.message);
}

class SymbolInfo {
  final String display, type;
  const SymbolInfo(this.display, this.type);
}

final greekNames =
    'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega'
        .split(' ');
final greek = greekNames.toSet();
final symbolCommands = <String, SymbolInfo>{
  for (final name in greekNames) '\\$name': SymbolInfo(name, 'ordinary'),
  for (final name
      in 'sin cos tan log ln exp det lim max min sum prod int'.split(' '))
    '\\$name': SymbolInfo(name, 'operator'),
  for (final entry in {
    'cdot': '*',
    'times': 'x',
    'pm': '+-',
    'mp': '-+',
  }.entries)
    '\\${entry.key}': SymbolInfo(entry.value, 'binary'),
  for (final entry in {
    'leq': '<=',
    'geq': '>=',
    'neq': '!=',
    'approx': '~=',
    'to': '->',
  }.entries)
    '\\${entry.key}': SymbolInfo(entry.value, 'relation'),
  for (final entry in {
    'infty': 'oo',
    'ldots': '...',
    'cdots': '...',
    'quad': '  ',
    ',': ' ',
  }.entries)
    '\\${entry.key}': SymbolInfo(entry.value, 'ordinary'),
  r'\{': const SymbolInfo('{', 'open'),
  r'\}': const SymbolInfo('}', 'close'),
};
final commandNames = {
  for (final name in symbolCommands.keys)
    if (name.length > 2) name.substring(1),
};
bool isLetter(String c) =>
    c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 ||
    c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
bool isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
bool containsWord(String words, String value) =>
    words.split(' ').contains(value);
(List<Token>, Issue?) tokenize(String line) {
  final tokens = <Token>[];
  for (var i = 0; i < line.length;) {
    final c = line[i], column = i + 1;
    if (c == ' ') {
      i++;
      continue;
    }
    if (isLetter(c)) {
      var j = i + 1;
      while (j < line.length && isLetter(line[j])) {
        j++;
      }
      tokens.add(Token('identifier', line.substring(i, j), column));
      i = j;
      continue;
    }
    if (isDigit(c)) {
      var j = i + 1;
      while (j < line.length && isDigit(line[j])) {
        j++;
      }
      if (j + 1 < line.length && line[j] == '.' && isDigit(line[j + 1])) {
        j += 2;
        while (j < line.length && isDigit(line[j])) {
          j++;
        }
      }
      tokens.add(Token('number', line.substring(i, j), column));
      i = j;
      continue;
    }
    if ("+-*/=<>:()[],;.!|'".contains(c)) {
      tokens.add(Token('symbol', c, column));
      i++;
      continue;
    }
    if ('{}^_&'.contains(c)) {
      tokens.add(Token(c, c, column));
      i++;
      continue;
    }
    if (c != '\\') return (<Token>[], Issue(column, 'invalid character $c'));
    if (i + 1 < line.length && line[i + 1] == '\\') {
      tokens.add(Token('newline', '', column));
      i += 2;
      continue;
    }
    if (i + 1 < line.length && '{},'.contains(line[i + 1])) {
      tokens.add(Token('command', line.substring(i, i + 2), column));
      i += 2;
      continue;
    }
    var j = i + 1;
    while (j < line.length && isLetter(line[j])) {
      j++;
    }
    if (j == i + 1) return (<Token>[], Issue(column, 'invalid command'));
    final name = line.substring(i + 1, j);
    i = j;
    if (containsWord('text begin end tag label eqref', name)) {
      while (i < line.length && line[i] == ' ') {
        i++;
      }
      if (i == line.length || line[i] != '{')
        return (<Token>[], Issue(i + 1, 'expected {'));
      final end = line.indexOf('}', i + 1);
      if (end < 0) return (<Token>[], Issue(column, 'unterminated argument'));
      final value = line.substring(i + 1, end);
      i = end + 1;
      if ((name == 'begin' || name == 'end') &&
          !containsWord('matrix pmatrix bmatrix vmatrix cases', value))
        return (<Token>[], Issue(column, 'unknown environment "$value"'));
      tokens.add(Token(name, value, column));
      continue;
    }
    final value = '\\$name';
    if (symbolCommands.containsKey(value)) {
      tokens.add(Token('command', value, column));
    } else if (containsWord(
      'overline hat vec dot tilde overbrace underbrace',
      name,
    )) {
      tokens.add(Token('accent', name, column));
    } else if (containsWord(
      'frac binom overset underset sqrt left right',
      name,
    )) {
      tokens.add(Token(name, '', column));
    } else {
      return (<Token>[], Issue(column, 'unknown command \\$name'));
    }
  }
  return (tokens, null);
}
