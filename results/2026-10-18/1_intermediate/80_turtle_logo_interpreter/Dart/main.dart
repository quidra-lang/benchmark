import 'dart:io';
import 'dart:math' as math;

class LogoError implements Exception {
  final int line;
  final String reason;
  LogoError(this.line, this.reason);
}
class Token {
  final String kind, text;
  final int line;
  final bool sign;
  Token(this.kind, this.text, this.line, [this.sign = false]);
}
Never fail(Token token, String reason) => throw LogoError(token.line, reason);
typedef SourceLine = (String, int);
typedef Point = (int, int);

sealed class Input {}
sealed class Expression extends Input {
  final Token token;
  Expression(this.token);
}
class NumberExpression extends Expression {
  final int value;
  NumberExpression(super.token, this.value);
}
class VariableExpression extends Expression {
  final String name;
  VariableExpression(super.token, this.name);
}
class UnaryExpression extends Expression {
  final Expression value;
  UnaryExpression(super.token, this.value);
}
class BinaryExpression extends Expression {
  final Expression left, right;
  BinaryExpression(super.token, this.left, this.right);
}
class CallExpression extends Expression {
  final bool primitive;
  final List<Expression> inputs;
  CallExpression(super.token, this.primitive, this.inputs);
}
class QuotedWord extends Input {
  final String value;
  QuotedWord(this.value);
}
class CommandList extends Input {
  final List<Command> commands;
  CommandList(this.commands);
}
class Command {
  final Token token;
  final String name;
  final List<Input> inputs;
  Command(this.token, this.name, this.inputs);
}
class Procedure {
  final String name;
  final List<String> parameters;
  final Token token;
  final tokens = <Token>[];
  List<Command> body = [];
  Procedure(this.name, this.parameters, this.token);
}
class Environment {
  final Map<String, int> variables;
  bool? test;
  Environment(this.variables);
}
class Flow {
  final int? value;
  Flow(this.value);
}
class Extent {
  final int x1, y1, x2, y2;
  Extent(this.x1, this.y1, this.x2, this.y2);
}

final commandInputs = <String, String>{
  'FD': 'E', 'FORWARD': 'E', 'BK': 'E', 'BACK': 'E', 'RT': 'E', 'RIGHT': 'E',
  'LT': 'E', 'LEFT': 'E', 'SETH': 'E', 'SETHEADING': 'E', 'PU': '', 'PENUP': '',
  'PD': '', 'PENDOWN': '', 'PE': '', 'PENERASE': '', 'SETPEN': 'E', 'SETXY': 'EE',
  'SETX': 'E', 'SETY': 'E', 'HOME': '', 'CS': '', 'CLEARSCREEN': '', 'CLEAN': '',
  'FILL': '', 'LABEL': 'P', 'SNAPSHOT': '', 'REPEAT': 'EL', 'FOR': 'QEEL',
  'WHILE': 'EL', 'IF': 'EL', 'IFELSE': 'ELL', 'TEST': 'E', 'IFTRUE': 'L',
  'IFT': 'L', 'IFFALSE': 'L', 'IFF': 'L', 'STOP': '', 'OUTPUT': 'E', 'OP': 'E',
  'MAKE': 'QE', 'LOCAL': 'Q', 'LOCALMAKE': 'QE', 'TRACE': 'Q', 'UNTRACE': 'Q',
  'SEED': 'E', 'PRINT': 'P', 'PR': 'P'
};
final functionInputs = <String, int>{
  'XCOR': 0, 'YCOR': 0, 'HEADING': 0, 'REPCOUNT': 0, 'RANDOM': 1, 'ABS': 1,
  'NOT': 1, 'AND': 2, 'OR': 2, 'MAX': 2, 'MIN': 2
};
final aliases = <String, String>{
  'FORWARD': 'FD', 'BACK': 'BK', 'RIGHT': 'RT', 'LEFT': 'LT', 'SETHEADING': 'SETH',
  'PENUP': 'PU', 'PENDOWN': 'PD', 'PENERASE': 'PE', 'CLEARSCREEN': 'CS',
  'IFT': 'IFTRUE', 'IFF': 'IFFALSE', 'OP': 'OUTPUT', 'PR': 'PRINT'
};
final primitives = {...commandInputs.keys, ...functionInputs.keys, 'TO', 'END', 'MOD'};
final directions = <Point>[(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)];
bool name(String text) => text.isNotEmpty && text.codeUnitAt(0) >= 65 && text.codeUnitAt(0) <= 90
    && !RegExp(r'[^A-Z0-9_]').hasMatch(text);
List<Token> lex(String source, int line) {
  final text = source.split(';')[0].toUpperCase(), tokens = <Token>[];
  int i = 0;
  while (i < text.length) {
    if (text[i] == ' ') { i++; continue; }
    final start = i, first = text[i];
    if ('[]()+-*/=<>'.contains(first)) {
      i++;
      if (i < text.length && (first == '<' && ['=', '>'].contains(text[i]) || first == '>' && text[i] == '=')) i++;
      final sign = first == '-' && (start == 0 || ' [('.contains(text[start - 1]))
          && i < text.length && text[i] != ' ';
      tokens.add(Token('symbol', text.substring(start, i), line, sign));
    } else {
      while (i < text.length && !' []()+-*/=<>'.contains(text[i])) { i++; }
      final word = text.substring(start, i);
      String kind;
      if (!RegExp(r'[^0-9]').hasMatch(word)) { kind = 'number'; }
      else if (word.startsWith(':') && name(word.substring(1))) { kind = 'variable'; }
      else if (word.startsWith('"') && name(word.substring(1))) { kind = 'quote'; }
      else if (name(word)) { kind = 'word'; }
      else { throw LogoError(line, "bad token '$word'"); }
      tokens.add(Token(kind, word, line));
    }
  }
  return tokens;
}
(Map<String, Procedure>, List<Token>) extract(List<SourceLine> lines) {
  final procedures = <String, Procedure>{}, top = <Token>[];
  Procedure? current;
  for (final (text, line) in lines) {
    final tokens = lex(text, line);
    if (tokens.isEmpty) continue;
    final first = tokens.first;
    if (first.kind == 'word' && first.text == 'TO') {
      if (current != null) fail(first, 'TO inside definition of ${current.name}');
      if (tokens.length < 2 || tokens[1].kind != 'word') fail(first, 'bad procedure header');
      final procedureName = tokens[1].text;
      if (primitives.contains(procedureName)) fail(first, '$procedureName is a primitive');
      if (procedures.containsKey(procedureName)) fail(first, '$procedureName is already defined');
      final parameters = <String>[];
      for (final token in tokens.skip(2)) {
        if (token.kind != 'variable') fail(first, 'bad procedure header');
        if (parameters.contains(token.text.substring(1))) fail(first, 'duplicate input ${token.text}');
        parameters.add(token.text.substring(1));
      }
      current = Procedure(procedureName, parameters, first);
      procedures[procedureName] = current;
    } else if (tokens.length == 1 && first.kind == 'word' && first.text == 'END') {
      if (current == null) fail(first, 'END without TO');
      current = null;
    } else {
      (current == null ? top : current.tokens).addAll(tokens);
    }
  }
  if (current != null) fail(current.token, 'missing END for ${current.name}');
  return (procedures, top);
}

class Parser {
  final List<Token> tokens;
  final Map<String, Procedure> procedures;
  final bool inside;
  int at = 0;
  Parser(this.tokens, this.procedures, this.inside);
  Token? peek() => at < tokens.length ? tokens[at] : null;
  bool unknown(Token token) => token.kind == 'word' && !primitives.contains(token.text) && !procedures.containsKey(token.text);
  Token inputToken(Token owner) {
    final token = peek();
    if (token == null || token.text == ']' || token.text == ')') fail(owner, 'not enough inputs to ${owner.text}');
    if (unknown(token)) fail(token, "I don't know how to ${token.text}");
    return token;
  }
  Input input(String kind, Token owner) {
    final token = inputToken(owner);
    if (kind == 'L') {
      if (token.text != '[') fail(token, "${owner.text} doesn't like ${token.text} as input");
      at++;
      final commands = <Command>[];
      while (peek() != null && peek()!.text != ']') { commands.add(command()); }
      if (peek() == null) fail(token, 'missing ]');
      at++;
      return CommandList(commands);
    }
    if (kind == 'Q' || kind == 'P' && token.kind == 'quote') {
      if (token.kind != 'quote') fail(token, "${owner.text} doesn't like ${token.text} as input");
      at++;
      return QuotedWord(token.text.substring(1));
    }
    return expression(owner);
  }
  Expression expression(Token owner) => binary(owner, 0);
  Expression binary(Token owner, int level) {
    if (level == 3) return term(owner);
    Expression left = binary(owner, level + 1);
    final operators = level == 0 ? ['=', '<>', '<', '>', '<=', '>='] : level == 1 ? ['+', '-'] : ['*', '/', 'MOD'];
    while (peek() != null && operators.contains(peek()!.text) && !peek()!.sign) {
      final token = tokens[at++];
      final right = binary(token, level + 1);
      left = BinaryExpression(token, left, right);
    }
    return left;
  }
  Expression term(Token owner) {
    final token = inputToken(owner);
    at++;
    if (token.kind == 'number') return NumberExpression(token, int.parse(token.text));
    if (token.kind == 'variable') return VariableExpression(token, token.text.substring(1));
    if (token.text == '-') return UnaryExpression(token, term(token));
    if (token.text == '(') {
      final value = expression(token);
      if (peek() == null || peek()!.text != ')') fail(token, 'missing )');
      at++;
      return value;
    }
    if (token.kind == 'word' && (functionInputs.containsKey(token.text) || procedures.containsKey(token.text))) {
      final count = functionInputs[token.text] ?? procedures[token.text]!.parameters.length;
      return CallExpression(token, functionInputs.containsKey(token.text),
          List.generate(count, (_) => expression(token)));
    }
    fail(token, "${owner.text} doesn't like ${token.text} as input");
  }
  Command command() {
    final token = tokens[at++];
    if (token.text == ']') fail(token, 'unexpected ]');
    final next = peek();
    if (token.text == '(' && next != null && next.kind == 'word' && ['PRINT', 'PR'].contains(next.text)) {
      at++;
      final inputs = <Input>[];
      while (peek() == null || peek()!.text != ')') {
        if (peek() == null || peek()!.text == ']') fail(token, 'missing )');
        inputs.add(input('P', next));
      }
      at++;
      return Command(next, 'MULTIPRINT', inputs);
    }
    if (token.kind == 'word' && ['TO', 'END'].contains(token.text)) fail(token, 'misplaced ${token.text}');
    if (token.kind == 'word' && commandInputs.containsKey(token.text)) {
      if (!inside && ['STOP', 'OUTPUT', 'OP', 'LOCAL', 'LOCALMAKE'].contains(token.text)) {
        fail(token, 'can only use ${token.text} inside a procedure');
      }
      final inputs = [for (final kind in commandInputs[token.text]!.split('')) input(kind, token)];
      if (['TRACE', 'UNTRACE'].contains(token.text) && !procedures.containsKey((inputs[0] as QuotedWord).value)) {
        fail(tokens[at - 1], "I don't know how to ${(inputs[0] as QuotedWord).value}");
      }
      return Command(token, aliases[token.text] ?? token.text, inputs);
    }
    if (token.kind == 'word' && procedures.containsKey(token.text)) {
      return Command(token, 'CALL', List.generate(procedures[token.text]!.parameters.length, (_) => expression(token)));
    }
    if (unknown(token)) fail(token, "I don't know how to ${token.text}");
    fail(token, "you don't say what to do with ${token.text}");
  }
  List<Command> sequence() {
    final commands = <Command>[];
    while (peek() != null) { commands.add(command()); }
    return commands;
  }
}

int floorDivide(int numerator, int denominator) {
  final value = numerator ~/ denominator;
  return numerator < 0 && numerator % denominator != 0 ? value - 1 : value;
}
class Turtle {
  final Map<String, Procedure> procedures;
  final List<String> output;
  int x = 0, y = 0, heading = 0, random = 1;
  String pen = 'DOWN', character = '*';
  final canvas = <Point, String>{};
  final environments = <Environment>[Environment({})];
  final active = <String>[], repetitions = <int>[];
  final traced = <String>{};
  Turtle(this.procedures, this.output);
  Environment get current => environments.last;
  void make(String name, int value) {
    for (int i = environments.length - 1; i > 0; i--) {
      if (environments[i].variables.containsKey(name)) {
        environments[i].variables[name] = value;
        return;
      }
    }
    environments[0].variables[name] = value;
  }
  void apply(int x, int y) {
    if (pen == 'DOWN') { canvas[(x, y)] = character; }
    else if (pen == 'ERASE') { canvas.remove((x, y)); }
  }
  void move(int px, int py) {
    final x0 = x, y0 = y, dx = px - x, dy = py - y;
    final steps = math.max(dx.abs(), dy.abs());
    if (steps == 0) { apply(x0, y0); }
    else {
      for (int i = 0; i <= steps; i++) {
        apply(x0 + floorDivide(2 * i * dx + steps, 2 * steps),
            y0 + floorDivide(2 * i * dy + steps, 2 * steps));
      }
    }
    x = px;
    y = py;
  }
  Extent extent() {
    final first = canvas.keys.first;
    int x1 = first.$1, y1 = first.$2, x2 = x1, y2 = y1;
    for (final (x, y) in canvas.keys) {
      x1 = math.min(x1, x); y1 = math.min(y1, y);
      x2 = math.max(x2, x); y2 = math.max(y2, y);
    }
    return Extent(x1, y1, x2, y2);
  }
  void picture() {
    if (canvas.isEmpty) { output.add('CANVAS 0 0 0'); return; }
    final box = extent();
    output.add('CANVAS ${box.x2 - box.x1 + 1} ${box.y2 - box.y1 + 1} ${canvas.length}');
    for (int y = box.y2; y >= box.y1; y--) {
      final row = StringBuffer();
      for (int x = box.x1; x <= box.x2; x++) { row.write(canvas[(x, y)] ?? ' '); }
      final text = row.toString();
      int end = text.length;
      while (end > 0 && text[end - 1] == ' ') { end--; }
      output.add(text.substring(0, end));
    }
  }
  void fill() {
    if (canvas.isEmpty || canvas.containsKey((x, y))) return;
    final box = extent();
    if (x < box.x1 || x > box.x2 || y < box.y1 || y > box.y2) return;
    final queue = <Point>[(x, y)];
    canvas[(x, y)] = character;
    for (int i = 0; i < queue.length; i++) {
      final (cx, cy) = queue[i];
      for (final (a, b) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
        if (a >= box.x1 && a <= box.x2 && b >= box.y1 && b <= box.y2 && !canvas.containsKey((a, b))) {
          canvas[(a, b)] = character;
          queue.add((a, b));
        }
      }
    }
  }
  int? call(Token token, List<Expression> inputs) {
    final values = inputs.map(evaluate).toList();
    if (active.length >= 100) fail(token, 'recursion too deep');
    final trace = traced.contains(token.text), indent = ' ' * (2 * active.length);
    final procedure = procedures[token.text]!;
    if (trace) output.add('$indent( ${token.text}${values.isEmpty ? '' : ' ${values.join(' ')}'} )');
    active.add(token.text);
    environments.add(Environment({for (int i = 0; i < procedure.parameters.length; i++) procedure.parameters[i]: values[i]}));
    final result = sequence(procedure.body);
    environments.removeLast();
    active.removeLast();
    final value = result?.value;
    if (trace) output.add('$indent${token.text}${value == null ? ' stops' : ' outputs $value'}');
    return value;
  }
  int evaluate(Expression expression) {
    final token = expression.token;
    if (expression is NumberExpression) return expression.value;
    if (expression is VariableExpression) {
      for (int i = environments.length - 1; i >= 0; i--) {
        final value = environments[i].variables[expression.name];
        if (value != null) return value;
      }
      fail(token, '${expression.name} has no value');
    }
    if (expression is UnaryExpression) return -evaluate(expression.value);
    if (expression is BinaryExpression) {
      final a = evaluate(expression.left), b = evaluate(expression.right);
      if ((token.text == '/' || token.text == 'MOD') && b == 0) fail(token, "${token.text} doesn't like 0 as input");
      return switch (token.text) {
        '+' => a + b, '-' => a - b, '*' => a * b, '/' => a ~/ b, 'MOD' => a - b * (a ~/ b),
        '=' => a == b ? 1 : 0, '<>' => a != b ? 1 : 0, '<' => a < b ? 1 : 0,
        '>' => a > b ? 1 : 0, '<=' => a <= b ? 1 : 0, _ => a >= b ? 1 : 0
      };
    }
    final callExpression = expression as CallExpression;
    if (!callExpression.primitive) {
      final value = call(token, callExpression.inputs);
      if (value == null) fail(token, '${token.text} did not output');
      return value;
    }
    final values = callExpression.inputs.map(evaluate).toList();
    final a = values.isEmpty ? 0 : values[0], b = values.length < 2 ? 0 : values[1];
    switch (token.text) {
      case 'XCOR': return x;
      case 'YCOR': return y;
      case 'HEADING': return heading;
      case 'REPCOUNT':
        if (repetitions.isEmpty) fail(token, 'REPCOUNT outside REPEAT');
        return repetitions.last;
      case 'RANDOM':
        if (a < 1) fail(token, "RANDOM doesn't like $a as input");
        random = 48271 * random % 2147483647;
        return random % a;
      case 'ABS': return a.abs();
      case 'NOT': return a == 0 ? 1 : 0;
      case 'AND': return a != 0 && b != 0 ? 1 : 0;
      case 'OR': return a != 0 || b != 0 ? 1 : 0;
      case 'MAX': return math.max(a, b);
      default: return math.min(a, b);
    }
  }
  String item(Input input) => input is QuotedWord ? input.value : '${evaluate(input as Expression)}';
  Flow? sequence(List<Command> commands) {
    for (final command in commands) {
      final result = execute(command);
      if (result != null) return result;
    }
    return null;
  }
  Flow? execute(Command command) {
    final name = command.name, token = command.token, inputs = command.inputs;
    if (name == 'CALL') {
      final value = call(token, inputs.cast<Expression>());
      if (value != null) fail(token, "you don't say what to do with $value");
      return null;
    }
    if (name == 'PRINT' || name == 'MULTIPRINT') { output.add(inputs.map(item).join(' ')); return null; }
    if (name == 'LABEL') {
      final text = item(inputs[0]), direction = directions[heading ~/ 45];
      for (int i = 0; i < text.length; i++) { canvas[(x + i * direction.$1, y + i * direction.$2)] = text[i]; }
      return null;
    }
    if (name == 'WHILE') {
      while (evaluate(inputs[0] as Expression) != 0) {
        final result = sequence((inputs[1] as CommandList).commands);
        if (result != null) return result;
      }
      return null;
    }
    final values = <Object>[];
    for (final input in inputs) {
      values.add(input is QuotedWord ? input.value : input is CommandList ? input.commands : evaluate(input as Expression));
    }
    int number(int i) => values[i] as int;
    String word(int i) => values[i] as String;
    List<Command> list(int i) => values[i] as List<Command>;
    switch (name) {
      case 'FD': case 'BK':
        final amount = name == 'BK' ? -number(0) : number(0), direction = directions[heading ~/ 45];
        final sign = amount < 0 ? -1 : 1;
        apply(x, y);
        for (int i = 0; i < amount.abs(); i++) { x += sign * direction.$1; y += sign * direction.$2; apply(x, y); }
        break;
      case 'RT': case 'LT': case 'SETH':
        final a = number(0);
        if (a % 45 != 0) fail(token, "${token.text} doesn't like $a as input");
        heading = (name == 'SETH' ? a : heading + (name == 'LT' ? -a : a)) % 360;
        break;
      case 'PU': pen = 'UP'; break;
      case 'PD': pen = 'DOWN'; break;
      case 'PE': pen = 'ERASE'; break;
      case 'SETPEN':
        final a = number(0);
        if (a < 33 || a > 126) fail(token, "SETPEN doesn't like $a as input");
        character = String.fromCharCode(a);
        break;
      case 'SETXY': move(number(0), number(1)); break;
      case 'SETX': move(number(0), y); break;
      case 'SETY': move(x, number(0)); break;
      case 'HOME': move(0, 0); heading = 0; break;
      case 'CS': canvas.clear(); x = 0; y = 0; heading = 0; break;
      case 'CLEAN': canvas.clear(); break;
      case 'FILL': fill(); break;
      case 'SNAPSHOT': picture(); break;
      case 'MAKE': make(word(0), number(1)); break;
      case 'LOCAL': current.variables[word(0)] = 0; break;
      case 'LOCALMAKE': current.variables[word(0)] = number(1); break;
      case 'TRACE': traced.add(word(0)); break;
      case 'UNTRACE': traced.remove(word(0)); break;
      case 'SEED':
        final a = number(0);
        if (a < 1) fail(token, "SEED doesn't like $a as input");
        random = a;
        break;
      case 'STOP': return Flow(null);
      case 'OUTPUT': return Flow(number(0));
      case 'REPEAT':
        if (list(1).isEmpty) break;
        for (int k = 1; k <= number(0); k++) {
          repetitions.add(k);
          Flow? result;
          try { result = sequence(list(1)); } finally { repetitions.removeLast(); }
          if (result != null) return result;
        }
        break;
      case 'FOR':
        final first = number(1), last = number(2), step = first <= last ? 1 : -1;
        if (list(3).isEmpty) { make(word(0), last); break; }
        for (int value = first;; value += step) {
          make(word(0), value);
          final result = sequence(list(3));
          if (result != null) return result;
          if (value == last) break;
        }
        break;
      case 'IF': if (number(0) != 0) return sequence(list(1)); break;
      case 'IFELSE': return sequence(number(0) != 0 ? list(1) : list(2));
      case 'TEST': current.test = number(0) != 0; break;
      case 'IFTRUE': case 'IFFALSE':
        if (current.test == null) fail(token, '${token.text} without TEST');
        if (current.test == (name == 'IFTRUE')) return sequence(list(0));
        break;
    }
    return null;
  }
}

void run(String name, List<SourceLine> lines, List<String> output) {
  output.add('PROGRAM $name');
  Turtle? turtle;
  try {
    final (procedures, top) = extract(lines);
    for (final procedure in procedures.values) { procedure.body = Parser(procedure.tokens, procedures, true).sequence(); }
    final commands = Parser(top, procedures, false).sequence();
    turtle = Turtle(procedures, output);
    turtle.sequence(commands);
    output.add('TURTLE ${turtle.x} ${turtle.y} ${turtle.heading} ${turtle.pen} ${turtle.character}');
    turtle.picture();
  } on LogoError catch (error) {
    output.add('ERROR line ${error.line}: ${error.reason}');
    if (turtle != null) {
      int i = turtle.active.length - 1;
      while (i >= 0) {
        final name = turtle.active[i];
        int count = 0;
        while (i >= 0 && turtle.active[i] == name) { i--; count++; }
        output.add('  in $name${count > 1 ? ' x$count' : ''}');
      }
    }
  }
}
void main() {
  final output = <String>[];
  String name = '';
  List<SourceLine> source = [];
  int line = 0;
  while (true) {
    final text = stdin.readLineSync();
    if (text == null) break;
    line++;
    if (text == '#EOF' || text.startsWith('#PROGRAM ')) {
      if (name.isNotEmpty) run(name, source, output);
      if (text == '#EOF') break;
      name = text.substring(9);
      source = [];
    } else { source.add((text, line)); }
  }
  stdout.write('${output.join('\n')}\n');
}
