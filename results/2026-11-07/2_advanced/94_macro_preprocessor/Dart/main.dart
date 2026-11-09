import 'dart:collection';
import 'dart:io';
part 'lexer.dart';
part 'definitions.dart';
part 'expression.dart';
part 'expander.dart';
part 'include_manager.dart';

class ConditionalBlock {
  final String kind;
  final Position start;
  final bool parent;
  bool chosen = false, active = false, elseSeen = false;
  int? skipStart;
  ConditionalBlock(this.kind, this.start, this.parent);
}

class Inclusion {
  final FileData source;
  final int depth;
  String displayFile;
  int offset = 0;
  final List<ConditionalBlock> stack = [];
  final List<Token> segment = [];
  Inclusion(this.source, this.depth) : displayFile = source.path;
  Position position(int physical) => Position(displayFile, physical + offset);
  bool get skipping => stack.isNotEmpty && !stack.last.active;
}

class Header {
  final String rendering, name;
  final bool quoted;
  Header(this.rendering, this.name, this.quoted);
}

class DirectiveError implements Exception {
  final String message;
  DirectiveError(this.message);
}

(Header?, int) readHeader(List<Token> tokens, int index) {
  if (index >= tokens.length) return (null, index);
  final t = tokens[index];
  if (t.kind == 'string' || t.kind == 'header')
    return (
      Header(
        t.spelling,
        t.spelling.substring(1, t.spelling.length - 1),
        t.spelling.startsWith('"'),
      ),
      index + 1,
    );
  if (t.spelling == '<') {
    var end = index + 1;
    while (end < tokens.length && tokens[end].spelling != '>') {
      end++;
    }
    if (end == tokens.length)
      throw DirectiveError('missing terminating > character');
    final rendering = '<${render(tokens.sublist(index + 1, end))}>';
    return (
      Header(rendering, rendering.substring(1, rendering.length - 1), false),
      end + 1,
    );
  }
  return (null, index);
}

bool separatorNeeded(String left, String right) {
  if (left == '/' && (right[0] == '/' || right[0] == '*')) return true;
  final (_, _, end) = readToken(left + right, 0, false);
  return end != left.length;
}

String outputRender(List<Token> tokens) => [
  for (var i = 0; i < tokens.length; i++)
    '${i > 0 && (tokens[i].space || separatorNeeded(tokens[i - 1].spelling, tokens[i].spelling)) ? ' ' : ''}${tokens[i].spelling}',
].join();
String following(String heading, List<String> items) =>
    '$heading${[for (final item in items) ' $item'].join()}';
bool decimalToken(Token t) =>
    t.kind == 'number' &&
    t.spelling.isNotEmpty &&
    t.spelling.split('').every(digit);

class TestResult {
  final bool valid, wasExpanded;
  final int value;
  final List<Token> expanded;
  TestResult({
    this.valid = false,
    this.wasExpanded = false,
    this.value = 0,
    List<Token>? expanded,
  }) : expanded = expanded ?? [];
}

String testDescription(String name, TestResult test) {
  var description = 'not taken (error)';
  if (test.valid) {
    description = test.value != 0 ? 'taken' : 'not taken';
    if (name == 'if' || name == 'elif') description += ' (value ${test.value})';
  }
  if (test.wasExpanded) description += ' [${outputRender(test.expanded)}]';
  return description;
}

class Preprocessor {
  final Map<String, Macro> macros = {};
  final Set<String> everDefined = {}, poisoned = {};
  final Map<String, List<Macro?>> saved = {};
  final IncludeManager manager = IncludeManager();
  late final Expander expander = Expander(macros, diagnostic);
  final List<String> output = [],
      history = [],
      diagnostics = [],
      tree = ['main.c'],
      conditionals = [],
      regions = [];
  final Map<String, int> diagnosticCounts = {}, conditionCounts = {};
  Position previous = Position('', 0);
  void diagnostic(Position pos, String kind, String message) {
    diagnostics.add('$pos: $kind: $message');
    diagnosticCounts[kind] = (diagnosticCounts[kind] ?? 0) + 1;
  }

  void event(Position pos, String content) => history.add('$pos: $content');
  void poisonCheck(Inclusion c, List<Token> tokens) {
    for (final t in tokens) {
      if (t.kind == 'identifier' && poisoned.contains(t.spelling))
        diagnostic(
          c.position(t.line),
          'error',
          'attempt to use poisoned "${t.spelling}"',
        );
    }
  }

  void unusedCheck(Macro m) {
    if (m.mainFile && m.expanded == 0 && m.tested == 0)
      diagnostic(m.position, 'warning', 'macro "${m.name}" is not used');
  }

  void define(List<Token> tokens, Position pos, bool main) {
    Macro m;
    try {
      m = parseDefinition(tokens, pos, main);
    } on DefinitionError catch (error) {
      diagnostic(pos, 'error', error.message);
      return;
    }
    final old = macros[m.name];
    var operation = 'define';
    if (old == null) {
      macros[m.name] = m;
      everDefined.add(m.name);
    } else if (old.identical(m)) {
      operation = 'identical';
    } else {
      unusedCheck(old);
      diagnostic(
        pos,
        'warning',
        '"${m.name}" redefined (previous definition at ${old.position})',
      );
      macros[m.name] = m;
      everDefined.add(m.name);
      operation = 'redefine';
    }
    event(pos, '$operation ${m.signature()}');
  }

  void undefine(List<Token> tokens, Position pos) {
    final error = checkName(tokens, 'undef');
    if (error != null) {
      diagnostic(pos, 'error', error);
      return;
    }
    if (tokens.length > 1)
      diagnostic(pos, 'warning', 'extra tokens at end of #undef directive');
    final name = tokens.first.spelling, old = macros[name];
    if (old != null) {
      unusedCheck(old);
      macros.remove(name);
      event(pos, 'undef $name');
    } else {
      event(pos, 'undef $name (not defined)');
    }
  }

  void processDefines() {
    final lines = File('input/defines.txt').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final index = line.indexOf('='),
          text = index < 0
              ? '$line 1'
              : '${line.substring(0, index)} ${line.substring(index + 1)}';
      define(lexDefinition(text, i + 1), Position('defines.txt', i + 1), false);
    }
  }

  void marker(String file, int line, [int flag = 0]) {
    output.add('# $line "$file"${flag != 0 ? ' $flag' : ''}');
    previous = Position(file, line - 1);
  }

  void outputLine(Inclusion c, int physical, String text) {
    final position = c.position(physical);
    if (position.file == previous.file &&
        previous.line < position.line &&
        position.line <= previous.line + 8) {
      for (var i = previous.line + 1; i < position.line; i++) {
        output.add('');
      }
    } else {
      marker(position.file, position.line);
    }
    output.add(text);
    previous = position;
    c.source.outputLines++;
  }

  void flush(Inclusion c) {
    final segment = List<Token>.of(c.segment);
    c.segment.clear();
    if (segment.isEmpty) return;
    poisonCheck(c, segment);
    final expanded = expander.expand(segment, c);
    for (var start = 0; start < expanded.length;) {
      var end = start + 1;
      while (end < expanded.length &&
          expanded[end].line == expanded[start].line) {
        end++;
      }
      outputLine(
        c,
        expanded[start].line,
        outputRender(expanded.sublist(start, end)),
      );
      start = end;
    }
  }

  bool macroDefined(String name) {
    final m = macros[name];
    if (m != null) {
      m.tested++;
      return true;
    }
    return builtins.contains(name) || name == '__has_include';
  }

  List<Token> replaceOperators(List<Token> operands) {
    final replaced = <Token>[];
    for (var position = 0; position < operands.length;) {
      final t = operands[position];
      var index = position + 1, value = false;
      if (t.kind == 'identifier' && t.spelling == 'defined') {
        final parenthesized =
            index < operands.length && operands[index].spelling == '(';
        if (parenthesized) index++;
        if (index == operands.length || operands[index].kind != 'identifier')
          throw DirectiveError('operator "defined" requires an identifier');
        final name = operands[index++].spelling;
        if (parenthesized) {
          if (index == operands.length || operands[index].spelling != ')')
            throw DirectiveError('missing \')\' after "defined"');
          index++;
        }
        value = macroDefined(name);
      } else if (t.kind == 'identifier' && t.spelling == '__has_include') {
        if (index == operands.length || operands[index].spelling != '(')
          throw DirectiveError('missing \'(\' after "__has_include"');
        final (header, next) = readHeader(operands, index + 1);
        if (header == null || header.name.isEmpty)
          throw DirectiveError(
            'operator "__has_include" requires a header-name',
          );
        index = next;
        if (index == operands.length || operands[index].spelling != ')')
          throw DirectiveError('missing \')\' after "__has_include" operand');
        index++;
        value = manager.search(header.name, header.quoted) != null;
      } else {
        replaced.add(t);
        position++;
        continue;
      }
      replaced.add(Token('number', value ? '1' : '0', t.line, space: t.space));
      position = index;
    }
    return replaced;
  }

  TestResult test(
    Inclusion c,
    LogicalLine line,
    String name,
    List<Token> operands,
  ) {
    final pos = c.position(line.tokens.first.line);
    poisonCheck(c, operands);
    if (name != 'if' && name != 'elif') {
      if (operands.isEmpty) {
        diagnostic(pos, 'error', 'no macro name given in #$name directive');
        return TestResult();
      }
      if (operands.first.kind != 'identifier') {
        diagnostic(pos, 'error', 'macro names must be identifiers');
        return TestResult();
      }
      if (operands.length > 1)
        diagnostic(pos, 'warning', 'extra tokens at end of #$name directive');
      var defined = macroDefined(operands.first.spelling);
      if (name == 'ifndef' || name == 'elifndef') defined = !defined;
      return TestResult(valid: true, value: defined ? 1 : 0);
    }
    List<Token> replaced;
    try {
      replaced = replaceOperators(operands);
    } on DirectiveError catch (error) {
      diagnostic(pos, 'error', error.message);
      return TestResult();
    }
    final expanded = expander.expand(replaced, c);
    try {
      final expression = parseCondition(expanded, name),
          value = evaluateCondition(
            expression,
            (message) => diagnostic(pos, 'warning', message),
          );
      return TestResult(
        valid: true,
        value: value,
        wasExpanded: true,
        expanded: expanded,
      );
    } on ExpressionError catch (error) {
      diagnostic(pos, 'error', error.message);
      return TestResult(wasExpanded: true, expanded: expanded);
    }
  }

  void closeRegion(Inclusion c, ConditionalBlock block, int end) {
    final start = block.skipStart;
    if (start != null && end >= start) {
      final first = c.position(start), last = c.position(end);
      regions.add(
        '${first.file}:${first.line}-${last.line} lines=${end - start + 1}',
      );
      c.source.skippedLines += end - start + 1;
    }
    block.skipStart = null;
  }

  void conditionalRecord(
    Position pos,
    int depth,
    String name,
    List<Token> operands,
    String description,
  ) {
    final directive = '#$name${operands.isEmpty ? '' : ' ${render(operands)}'}';
    conditionals.add(
      '$pos: ${List.filled(2 * depth, ' ').join()}$directive => $description',
    );
    for (final pair in [
      ('taken', 'taken'),
      ('not taken', 'not_taken'),
      ('skipped', 'skipped'),
      ('not evaluated', 'not_evaluated'),
      ('closes', 'endif'),
    ]) {
      if (description.startsWith(pair.$1)) {
        conditionCounts[pair.$2] = (conditionCounts[pair.$2] ?? 0) + 1;
        break;
      }
    }
  }

  void conditional(
    Inclusion c,
    LogicalLine line,
    String name,
    List<Token> operands,
  ) {
    final pos = c.position(line.tokens.first.line);
    if (wordIn('if ifdef ifndef', name)) {
      final parent = !c.skipping, block = ConditionalBlock(name, pos, parent);
      var description = 'skipped';
      if (parent) {
        final result = test(c, line, name, operands);
        if (result.valid && result.value != 0) {
          block.chosen = true;
          block.active = true;
        } else {
          block.skipStart = line.end + 1;
        }
        description = testDescription(name, result);
      }
      conditionalRecord(pos, c.stack.length, name, operands, description);
      c.stack.add(block);
      return;
    }
    if (c.stack.isEmpty) {
      diagnostic(pos, 'error', '#$name without #if');
      return;
    }
    final block = c.stack.last, depth = c.stack.length - 1;
    closeRegion(c, block, line.start - 1);
    var description = '';
    if (name == 'endif') {
      c.stack.removeLast();
      if (block.parent && operands.isNotEmpty)
        diagnostic(pos, 'warning', 'extra tokens at end of #endif directive');
      description = 'closes #${block.kind} at line ${block.start.line}';
    } else {
      if (block.elseSeen) diagnostic(pos, 'error', '#$name after #else');
      if (name == 'else') {
        if (block.parent && operands.isNotEmpty)
          diagnostic(pos, 'warning', 'extra tokens at end of #else directive');
        block.elseSeen = true;
        if (block.parent) {
          block.active = !block.chosen;
          block.chosen = true;
          description = block.active ? 'taken' : 'not taken';
        } else {
          block.active = false;
          description = 'skipped';
        }
      } else if (!block.parent) {
        block.active = false;
        description = 'skipped';
      } else if (block.chosen) {
        block.active = false;
        description = 'not evaluated';
      } else {
        final result = test(c, line, name, operands);
        block.active = result.valid && result.value != 0;
        if (block.active) block.chosen = true;
        description = testDescription(name, result);
      }
      if (block.parent && !block.active) block.skipStart = line.end + 1;
    }
    conditionalRecord(pos, depth, name, operands, description);
  }

  void include(Inclusion c, LogicalLine line, List<Token> operands) {
    final pos = c.position(line.tokens.first.line);
    Header? header;
    int consumed;
    var sequence = operands;
    try {
      final first = readHeader(sequence, 0);
      header = first.$1;
      consumed = first.$2;
      if (header == null && sequence.isNotEmpty) {
        sequence = expander.expand(sequence, c);
        final expanded = readHeader(sequence, 0);
        header = expanded.$1;
        consumed = expanded.$2;
      }
      if (header == null)
        throw DirectiveError('#include expects "FILENAME" or <FILENAME>');
      if (consumed < sequence.length)
        diagnostic(pos, 'warning', 'extra tokens at end of #include directive');
      if (header.name.isEmpty)
        throw DirectiveError('empty filename in #include');
    } on DirectiveError catch (error) {
      diagnostic(pos, 'error', error.message);
      return;
    }
    final target = header!,
        prefix =
            '${List.filled(2 * (c.depth + 1), ' ').join()}${line.tokens.first.line}: ',
        path = manager.search(target.name, target.quoted);
    if (path == null) {
      tree.add('$prefix${target.rendering} [not found]');
      diagnostic(pos, 'error', 'cannot find include file ${target.rendering}');
      return;
    }
    final old = manager.files[path];
    if (old != null && old.once) {
      tree.add('$prefix$path [skipped: pragma once]');
      old.skipped++;
      return;
    }
    if (old != null && old.guard.isNotEmpty && macros.containsKey(old.guard)) {
      tree.add('$prefix$path [skipped: guard ${old.guard}]');
      old.skipped++;
      return;
    }
    if (c.depth + 1 > 8) {
      tree.add('$prefix$path [too deep]');
      diagnostic(pos, 'error', '#include nested too deeply');
      return;
    }
    tree.add('$prefix$path');
    marker(path, 1, 1);
    processFile(path, c.depth + 1);
    final next = c.position(line.end + 1);
    marker(next.file, next.line, 2);
  }

  void lineDirective(Inclusion c, LogicalLine line, List<Token> operands) {
    final pos = c.position(line.tokens.first.line);
    if (operands.isEmpty || !decimalToken(operands.first))
      operands = expander.expand(operands, c);
    if (operands.isEmpty ||
        operands.length > 2 ||
        !decimalToken(operands.first) ||
        operands.length == 2 && operands[1].kind != 'string') {
      diagnostic(pos, 'error', 'invalid #line directive');
      return;
    }
    final number = int.parse(operands.first.spelling);
    if (number < 1 || number > 2147483647) {
      diagnostic(pos, 'error', 'line number out of range');
      return;
    }
    c.offset = number - (line.end + 1);
    if (operands.length == 2)
      c.displayFile = operands[1].spelling.substring(
        1,
        operands[1].spelling.length - 1,
      );
  }

  void macroPragma(Position pos, List<Token> operands, String operation) {
    if (operands.length != 4 ||
        operands[1].spelling != '(' ||
        operands[2].kind != 'string' ||
        operands[3].spelling != ')') {
      diagnostic(pos, 'error', 'invalid #pragma $operation directive');
      return;
    }
    final quoted = operands[2].spelling,
        name = quoted.substring(1, quoted.length - 1),
        stack = saved.putIfAbsent(name, () => []);
    if (operation == 'push_macro') {
      stack.add(macros[name]);
      event(pos, 'push $name');
      return;
    }
    if (stack.isEmpty) {
      diagnostic(pos, 'warning', 'no matching push_macro for "$name"');
      return;
    }
    final m = stack.removeLast();
    if (m == null) {
      macros.remove(name);
      event(pos, 'pop $name (undefined)');
    } else {
      macros[name] = m;
      event(pos, 'pop $name');
    }
  }

  void pragma(Inclusion c, LogicalLine line, List<Token> operands) {
    final pos = c.position(line.tokens.first.line),
        name = operands.isNotEmpty && operands.first.kind == 'identifier'
            ? operands.first.spelling
            : '';
    if (name == 'once') {
      if (operands.length > 1)
        diagnostic(
          pos,
          'warning',
          'extra tokens at end of #pragma once directive',
        );
      if (c.depth == 0) diagnostic(pos, 'warning', '#pragma once in main file');
      c.source.once = true;
    } else if (operands.length >= 2 &&
        operands[0].spelling == 'GCC' &&
        operands[1].spelling == 'poison') {
      if (operands.skip(2).any((t) => t.kind != 'identifier')) {
        diagnostic(pos, 'error', 'invalid #pragma GCC poison directive');
        return;
      }
      for (final t in operands.skip(2)) {
        if (macros.containsKey(t.spelling))
          diagnostic(
            pos,
            'warning',
            'poisoning existing macro "${t.spelling}"',
          );
        poisoned.add(t.spelling);
      }
    } else if (name == 'push_macro' || name == 'pop_macro') {
      macroPragma(pos, operands, name);
    } else {
      outputLine(
        c,
        line.tokens.first.line,
        '#pragma${operands.isEmpty ? '' : ' ${render(operands)}'}',
      );
    }
  }

  void directive(
    Inclusion c,
    LogicalLine line,
    String name,
    List<Token> operands,
  ) {
    if (line.tokens.length == 1) return;
    final poisoning =
        name == 'pragma' &&
        operands.length >= 2 &&
        operands[0].spelling == 'GCC' &&
        operands[1].spelling == 'poison';
    if (!poisoning) poisonCheck(c, operands);
    final pos = c.position(line.tokens.first.line);
    switch (name) {
      case 'define':
        define(operands, pos, c.depth == 0);
        break;
      case 'undef':
        undefine(operands, pos);
        break;
      case 'include':
        include(c, line, operands);
        break;
      case 'line':
        lineDirective(c, line, operands);
        break;
      case 'error':
      case 'warning':
        diagnostic(
          pos,
          name,
          '#$name${operands.isEmpty ? '' : ' ${render(operands)}'}',
        );
        break;
      case 'pragma':
        pragma(c, line, operands);
        break;
      default:
        diagnostic(
          pos,
          'error',
          'invalid preprocessing directive #${line.tokens[1].spelling}',
        );
        break;
    }
  }

  void processFile(String path, int depth) {
    final source = manager.load(path);
    source.entered++;
    final c = Inclusion(source, depth);
    for (final line in source.lines) {
      final tokens = line.tokens,
          isDirective = tokens.isNotEmpty && tokens.first.spelling == '#',
          name = directiveName(tokens),
          operands = tokens.length > 2 ? tokens.sublist(2) : <Token>[];
      if (isDirective &&
          wordIn('if ifdef ifndef elif elifdef elifndef else endif', name)) {
        flush(c);
        conditional(c, line, name, operands);
      } else if (c.skipping) {
        continue;
      } else if (isDirective) {
        flush(c);
        directive(c, line, name, operands);
      } else {
        c.segment.addAll(tokens);
      }
    }
    flush(c);
    for (final block in c.stack) {
      closeRegion(c, block, source.physicalLines);
    }
    for (final block in c.stack) {
      diagnostic(block.start, 'error', 'unterminated #${block.kind}');
    }
  }

  List<String> includeReport() {
    final out = [...tree, '', '== files =='],
        paths = manager.files.keys.toList()..sort();
    for (final path in paths) {
      final f = manager.files[path]!;
      out.add(
        '$path entered=${f.entered} skipped=${f.skipped} lines=${f.physicalLines} output_lines=${f.outputLines} skipped_lines=${f.skippedLines} guard=${f.guard.isEmpty ? '-' : f.guard} once=${f.once ? 'yes' : 'no'}',
      );
    }
    out.add('');
    var current = 'main.o:', hasPath = false;
    for (final path in manager.order) {
      if (current.length + 1 + path.length > 76 && hasPath) {
        out.add('$current \\');
        current = ' ';
        hasPath = false;
      }
      current += ' $path';
      hasPath = true;
    }
    out.add(current);
    return out;
  }

  List<String> macroReport() {
    final out = ['== history ==', ...history, '', '== table =='],
        references = <String, List<String>>{};
    for (final entry in macros.entries) {
      final m = entry.value,
          parameters = m.parameters.toSet(),
          names = {
            for (final t in m.replacement)
              if (t.kind == 'identifier' &&
                  macros.containsKey(t.spelling) &&
                  !parameters.contains(t.spelling))
                t.spelling,
          };
      references[entry.key] = names.toList()..sort();
    }
    bool recursive(String name) {
      final pending = List<String>.of(references[name]!), seen = <String>{};
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (current == name) return true;
        if (seen.add(current)) pending.addAll(references[current]!);
      }
      return false;
    }

    var objects = 0;
    final names = macros.keys.toList()..sort();
    for (final name in names) {
      final m = macros[name]!;
      out.add(
        '#define ${m.signature()}${m.replacement.isEmpty ? '' : ' ${render(m.replacement)}'}',
      );
      out.add(
        '  at ${m.position} expanded=${m.expanded} tested=${m.tested} recursive=${recursive(name) ? 'yes' : 'no'}',
      );
      out.add(following('  refs:', references[name]!));
      if (!m.function) objects++;
    }
    final undefined =
        everDefined.where((name) => !macros.containsKey(name)).toList()..sort();
    out.addAll([
      '',
      'macros=${macros.length} object_like=$objects function_like=${macros.length - objects}',
      following('undefined:', undefined),
      'builtins: __COUNTER__=${expander.builtinCounts['__COUNTER__'] ?? 0} __FILE__=${expander.builtinCounts['__FILE__'] ?? 0} __LINE__=${expander.builtinCounts['__LINE__'] ?? 0}',
    ]);
    return out;
  }

  List<String> conditionalReport() => [
    ...conditionals,
    '',
    '== skipped regions ==',
    ...regions,
    '',
    'directives=${conditionals.length} taken=${conditionCounts['taken'] ?? 0} not_taken=${conditionCounts['not_taken'] ?? 0} skipped=${conditionCounts['skipped'] ?? 0} not_evaluated=${conditionCounts['not_evaluated'] ?? 0} endif=${conditionCounts['endif'] ?? 0} regions=${regions.length}',
  ];
  void run() {
    processDefines();
    marker('main.c', 1);
    processFile('main.c', 0);
    final names = macros.keys.toList()..sort();
    for (final name in names) {
      unusedCheck(macros[name]!);
    }
    diagnostics.add(
      'errors=${diagnosticCounts['error'] ?? 0} warnings=${diagnosticCounts['warning'] ?? 0}',
    );
    Directory('output').createSync(recursive: true);
    writeLines('preprocessed.txt', output);
    writeLines('includes.txt', includeReport());
    writeLines('macros.txt', macroReport());
    writeLines('conditionals.txt', conditionalReport());
    writeLines('diagnostics.txt', diagnostics);
  }
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync('${lines.map((line) => line.trimRight()).join('\n')}\n');
void main() => Preprocessor().run();
