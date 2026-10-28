part of 'main.dart';

class Grammar {
  List<String> order = [];
  final rules = <String, List<List<String>>>{};
  String start = '';
  final declared = <String>{};
  bool hasDeclaration = false;
  final words = <String, int>{};
  final diagnostics = <String>[];
}

class LexToken {
  final String kind, value;
  final int start, end;
  LexToken(this.kind, this.value, this.start, this.end);
}

class ParsedLine {
  final String kind, symbol;
  final List<List<String>> alternatives;
  final List<String> words;
  final int error;
  ParsedLine({
    this.kind = '',
    this.symbol = '',
    this.alternatives = const [],
    this.words = const [],
    this.error = 0,
  });
}

bool isNonterminal(String s) => s.startsWith('<') && s.endsWith('>');
bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool wordCharacter(int c) => letter(c) || c >= 48 && c <= 57 || c == 95;
List<LexToken> lexLine(String line) {
  final tokens = <LexToken>[];
  var i = 0;
  while (i < line.length) {
    if (line[i] == ' ') {
      i++;
      continue;
    }
    if (line[i] == '#') {
      break;
    }
    final start = i;
    var kind = 'invalid', value = line[i], end = i + 1;
    if (line[i] == '<') {
      var j = i + 1;
      if (j < line.length && letter(line.codeUnitAt(j))) {
        j++;
        while (j < line.length && wordCharacter(line.codeUnitAt(j))) {
          j++;
        }
        if (j < line.length && line[j] == '>') {
          kind = 'nonterminal';
          value = line.substring(i, j + 1);
          end = j + 1;
        }
      }
    } else if (line[i] == '"') {
      var j = i + 1;
      while (j < line.length && line[j] != ' ' && line[j] != '"') {
        j++;
      }
      if (j > i + 1 && j < line.length && line[j] == '"') {
        kind = 'terminal';
        value = line.substring(i + 1, j);
        end = j + 1;
      }
    } else if (letter(line.codeUnitAt(i))) {
      var j = i + 1;
      while (j < line.length && wordCharacter(line.codeUnitAt(j))) {
        j++;
      }
      kind = 'word';
      value = line.substring(i, j);
      end = j;
    } else if (line.startsWith('::=', i)) {
      kind = 'definition';
      value = '::=';
      end = i + 3;
    } else if (line[i] == '|') {
      kind = 'separator';
      value = '|';
    } else if (line[i] == '%') {
      var j = i + 1;
      while (j < line.length && letter(line.codeUnitAt(j))) {
        j++;
      }
      final name = line.substring(i + 1, j);
      if (['empty', 'start', 'token'].contains(name)) {
        kind = 'directive';
        value = '%$name';
        end = j;
      }
    }
    i = end;
    tokens.add(LexToken(kind, value, start + 1, end));
    if (kind == 'invalid') {
      break;
    }
  }
  return tokens;
}

int errorColumn(List<LexToken> tokens, int cursor) =>
    cursor < tokens.length ? tokens[cursor].start : tokens.last.end + 1;
(List<List<String>>, int) alternativeList(List<LexToken> tokens, int cursor) {
  final alternatives = <List<String>>[];
  while (true) {
    if (cursor >= tokens.length) {
      return ([], errorColumn(tokens, cursor));
    }
    final first = tokens[cursor], rhs = <String>[];
    if (first.kind == 'directive' && first.value == '%empty') {
      cursor++;
      if (cursor < tokens.length && tokens[cursor].kind != 'separator') {
        return ([], errorColumn(tokens, cursor));
      }
    } else if (['nonterminal', 'word', 'terminal'].contains(first.kind)) {
      while (cursor < tokens.length &&
          ['nonterminal', 'word', 'terminal'].contains(tokens[cursor].kind)) {
        rhs.add(tokens[cursor].value);
        cursor++;
      }
    } else {
      return ([], errorColumn(tokens, cursor));
    }
    alternatives.add(rhs);
    if (cursor == tokens.length) {
      return (alternatives, 0);
    }
    if (tokens[cursor].kind != 'separator') {
      return ([], errorColumn(tokens, cursor));
    }
    cursor++;
  }
}

ParsedLine parseLine(List<LexToken> tokens) {
  if (tokens.isEmpty) {
    return ParsedLine(kind: 'blank');
  }
  final first = tokens.first;
  if (first.kind == 'nonterminal') {
    if (tokens.length < 2 || tokens[1].kind != 'definition') {
      return ParsedLine(error: errorColumn(tokens, 1));
    }
    final (alternatives, error) = alternativeList(tokens, 2);
    return ParsedLine(
      kind: 'rule',
      symbol: first.value,
      alternatives: alternatives,
      error: error,
    );
  }
  if (first.kind == 'separator') {
    final (alternatives, error) = alternativeList(tokens, 1);
    return ParsedLine(
      kind: 'continuation',
      alternatives: alternatives,
      error: error,
    );
  }
  if (first.kind == 'directive' && first.value == '%start') {
    if (tokens.length < 2 || tokens[1].kind != 'nonterminal') {
      return ParsedLine(error: errorColumn(tokens, 1));
    }
    if (tokens.length > 2) {
      return ParsedLine(error: errorColumn(tokens, 2));
    }
    return ParsedLine(kind: 'start', symbol: tokens[1].value);
  }
  if (first.kind == 'directive' && first.value == '%token') {
    if (tokens.length < 2) {
      return ParsedLine(error: errorColumn(tokens, 1));
    }
    for (var i = 1; i < tokens.length; i++) {
      if (tokens[i].kind != 'word') {
        return ParsedLine(error: errorColumn(tokens, i));
      }
    }
    return ParsedLine(
      kind: 'declaration',
      words: tokens.skip(1).map((t) => t.value).toList(),
    );
  }
  return ParsedLine(error: errorColumn(tokens, 0));
}

String notation(List<String> rhs) => rhs.isEmpty ? '%empty' : rhs.join(' ');
String productionNotation(String lhs, List<String> rhs) =>
    '$lhs -> ${notation(rhs)}';
List<String> readLines(String path) => File(path).readAsLinesSync();
Grammar parseGrammar() {
  final g = Grammar(), lines = readLines('input/grammar.bnf');
  var attachment = '';
  for (var i = 0; i < lines.length; i++) {
    final tokens = lexLine(lines[i]),
        parsed = parseLine(tokens),
        lineNumber = i + 1;
    if (parsed.error > 0) {
      g.diagnostics.add(
        'line $lineNumber: syntax error at column ${parsed.error}',
      );
      attachment = '';
      continue;
    }
    if (parsed.kind == 'blank') {
      continue;
    }
    var symbol = parsed.symbol;
    switch (parsed.kind) {
      case 'rule':
        attachment = symbol;
        if (!g.rules.containsKey(symbol)) {
          g.order.add(symbol);
          g.rules[symbol] = [];
        }
      case 'continuation':
        if (attachment.isEmpty) {
          g.diagnostics.add('line $lineNumber: continuation without a rule');
          continue;
        }
        symbol = attachment;
      case 'start':
        attachment = '';
        if (g.start.isEmpty) {
          g.start = symbol;
        } else {
          g.diagnostics.add('line $lineNumber: duplicate %start');
        }
      case 'declaration':
        attachment = '';
        g.hasDeclaration = true;
        g.declared.addAll(parsed.words);
    }
    if (parsed.kind == 'rule' || parsed.kind == 'continuation') {
      for (final token in tokens) {
        if (token.kind == 'word') {
          g.words.putIfAbsent(token.value, () => lineNumber);
        }
      }
      for (final rhs in parsed.alternatives) {
        if (g.rules[symbol]!.any((old) => listEqual(old, rhs))) {
          g.diagnostics.add(
            'line $lineNumber: duplicate alternative ${productionNotation(symbol, rhs)}',
          );
        } else {
          g.rules[symbol]!.add(rhs);
        }
      }
    }
  }
  if (g.start.isEmpty) {
    g.start = g.order.first;
  }
  return g;
}
