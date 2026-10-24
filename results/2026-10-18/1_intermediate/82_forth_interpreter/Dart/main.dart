import 'dart:io';

class ForthError implements Exception {
  final String word, reason;
  final int? code;
  ForthError(this.word, this.reason, [this.code]);
}
Never fail(String word, String reason, [int? code]) => throw ForthError(word, reason, code);
final compileOnly = 'IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT" [\'] {:'.split(' ').toSet();
final interpretOnly = {':', ':NONAME', 'FORGET'};
final special = {...compileOnly, ...interpretOnly, '."', '(', r'\', 'TO', 'IS'};
final builtinNames = '+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER \' EXECUTE CATCH THROW ABORT WORDS'.split(' ');

class Word {
  final String name, kind;
  final int here, address;
  int value = 0, localCount = 0;
  int? deferred;
  DoesPart? does;
  String rawName;
  bool anonymous = false;
  final actions = <Action>[];
  final locals = <String, int>{};
  Word(this.name, this.kind, this.here) : address = here, rawName = name;
}
class DoesPart {
  final Word definition;
  final int start;
  DoesPart(this.definition, this.start);
}
class Action {
  final String kind, raw, text, operation;
  final int value, slot;
  int target;
  final bool conditional, increment;
  final Word? word;
  final List<int> slots;
  Action(this.kind, this.raw, {this.text = '', this.operation = '', this.value = 0,
    this.slot = 0, this.target = 0, this.conditional = false, this.increment = false,
    this.word, this.slots = const []});
}
class Control {
  final String kind;
  final int index, begin;
  final leaves = <int>[], endofs = <int>[];
  Control(this.kind, this.index, [this.begin = 0]);
}
int quotient(int a, int b) {
  final q = a ~/ b;
  return a.remainder(b) != 0 && (a < 0) != (b < 0) ? q - 1 : q;
}
class Forth {
  List<int> stack = [], returns = [];
  final memory = <int>[10];
  final dictionary = <Word>[], tokens = <Word>[];
  final Map<String, Word> builtins = {for (final name in builtinNames) name: Word(name, 'builtin', 0)};
  Word? compiling;
  List<Control> control = [];
  int depth = 0, position = 0;
  String pending = '', line = '';
  final output = <String>[];

  String? read() {
    while (position < line.length && line[position] == ' ') { position++; }
    if (position == line.length) return null;
    final start = position;
    while (position < line.length && line[position] != ' ') { position++; }
    return line.substring(start, position);
  }
  String readName(String raw) => read() ?? (fail(raw, 'missing name', -16));
  Word? lookup(String name) {
    name = name.toUpperCase();
    for (int i = dictionary.length - 1; i >= 0; i--) {
      if (dictionary[i].name == name) return dictionary[i];
    }
    return builtins[name];
  }
  int? number(String raw, [int? radix]) {
    if (raw.length == 3 && raw[0] == "'" && raw[2] == "'") return raw.codeUnitAt(1);
    String text = raw.toUpperCase();
    int base;
    if (r'$#%'.contains(text[0])) {
      base = text[0] == r'$' ? 16 : text[0] == '#' ? 10 : 2;
      text = text.substring(1);
    } else {
      base = radix ?? memory[0];
      if (base < 2 || base > 36) fail(raw, 'invalid base', -40);
    }
    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);
    if (text.isEmpty) return null;
    int value = 0;
    for (final code in text.codeUnits) {
      final digit = code >= 48 && code <= 57 ? code - 48 : code >= 65 && code <= 90 ? code - 55 : -1;
      if (digit < 0 || digit >= base) return null;
      value = value * base + digit;
    }
    return negative ? -value : value;
  }
  void checkName(String name) {
    if (special.contains(name.toUpperCase()) || number(name, 10) != null) fail(name, 'invalid name', -19);
  }
  List<int> pop(int count, String raw) {
    if (stack.length < count) fail(raw, 'stack underflow', -4);
    final values = stack.sublist(stack.length - count);
    stack.length -= count;
    return values;
  }
  void push(int value, String raw) {
    stack.add(value);
    if (stack.length > 1000) fail(raw, 'stack overflow', -3);
  }
  void pushMany(List<int> values, String raw) {
    for (final value in values) { push(value, raw); }
  }
  void needReturns(int count, String raw) {
    if (returns.length < count) fail(raw, 'return stack underflow', -6);
  }
  void pushReturn(int value, String raw) {
    returns.add(value);
    if (returns.length > 1000) fail(raw, 'return stack overflow', -5);
  }
  int address(int value, String raw) {
    if (value < 0 || value % 8 != 0 || value >= memory.length * 8) fail(raw, 'invalid address', -9);
    return value ~/ 8;
  }
  bool validToken(int value) => value >= 1 && value <= tokens.length;
  int xt(Word word) {
    int index = tokens.indexOf(word);
    if (index < 0) { tokens.add(word); index = tokens.length - 1; }
    return index + 1;
  }
  String format(int value, String raw) {
    final base = memory[0];
    if (base < 2 || base > 36) fail(raw, 'invalid base', -40);
    return value.toRadixString(base).toUpperCase();
  }
  void flush() {
    int end = pending.length;
    while (end > 0 && pending[end - 1] == ' ') { end--; }
    output.add(pending.substring(0, end));
    pending = '';
  }
  void executeToken(int value, String raw) {
    if (!validToken(value)) fail(raw, 'invalid argument', -24);
    final word = tokens[value - 1];
    execute(word, word.name);
  }
  void define(String kind, String raw) {
    final name = readName(raw);
    checkName(name);
    final value = kind == 'CONSTANT' || kind == 'VALUE' ? pop(1, raw)[0] : 0;
    final word = Word(name.toUpperCase(), kind.toLowerCase(), memory.length * 8)..value = value;
    dictionary.add(word);
    if (kind == 'VARIABLE' || kind == 'VALUE') memory.add(value);
  }
  void execute(Word word, String raw) {
    while (word.kind == 'defer') {
      final token = word.deferred;
      if (token == null) fail(raw, 'deferred word not set', -21);
      if (!validToken(token)) fail(raw, 'invalid argument', -24);
      word = tokens[token - 1];
      raw = word.name;
    }
    switch (word.kind) {
      case 'builtin': builtin(word.name, raw); return;
      case 'colon': definition(word, 0, raw); return;
      case 'constant': push(word.value, raw); return;
      case 'value': push(memory[word.address ~/ 8], raw); return;
      case 'create': case 'variable':
        push(word.address, raw);
        if (word.does != null) definition(word.does!.definition, word.does!.start, raw);
        return;
    }
  }
  void builtin(String name, String raw) {
    if (['CREATE', 'VARIABLE', 'CONSTANT', 'VALUE', 'DEFER'].contains(name)) { define(name, raw); return; }
    if (name == "'") {
      final name = readName(raw), word = lookup(name);
      if (word == null) fail(name, 'undefined word', -13);
      push(xt(word), raw);
      return;
    }
    if (name == 'EXECUTE') { executeToken(pop(1, raw)[0], raw); return; }
    if (name == 'CATCH') {
      final token = pop(1, raw)[0];
      if (!validToken(token)) fail(raw, 'invalid argument', -24);
      final savedStack = List<int>.of(stack), returnCount = returns.length, savedDepth = depth;
      try { executeToken(token, raw); }
      on ForthError catch (error) {
        if (error.code == null) rethrow;
        stack = savedStack;
        if (returns.length > returnCount) returns.length = returnCount;
        depth = savedDepth;
        push(error.code!, raw);
        return;
      }
      push(0, raw);
      return;
    }
    if (name == 'THROW') {
      final value = pop(1, raw)[0];
      if (value != 0) fail(raw, 'exception $value', value);
      return;
    }
    if (name == 'ABORT') fail(raw, 'aborted', -1);
    if (name == 'WORDS') { for (final word in dictionary.reversed) { pending += '${word.name} '; } return; }
    if (name == 'CR') { flush(); return; }
    if (name == 'SPACE') { pending += ' '; return; }
    if (name == 'DEPTH') { push(stack.length, raw); return; }
    if (name == 'HERE') { push(memory.length * 8, raw); return; }
    if (name == 'BASE') { push(0, raw); return; }
    if (name == 'HEX' || name == 'DECIMAL') { memory[0] = name == 'HEX' ? 16 : 10; return; }
    if (name == 'TRUE' || name == 'FALSE' || name == 'BL') { push(name == 'TRUE' ? -1 : name == 'FALSE' ? 0 : 32, raw); return; }
    if (name == '.S') {
      final count = format(stack.length, raw), values = stack.map((value) => format(value, raw)).toList();
      pending += '<$count> ${values.isEmpty ? '' : '${values.join(' ')} '}';
      return;
    }
    if (name == 'PICK' || name == 'ROLL') {
      final n = pop(1, raw)[0];
      if (n < 0) fail(raw, 'invalid argument', -24);
      if (n >= stack.length) fail(raw, 'stack underflow', -4);
      final index = stack.length - 1 - n, value = stack[index];
      if (name == 'ROLL') stack.removeAt(index);
      push(value, raw);
      return;
    }
    final arity = ['*/', '*/MOD', 'ROT', '-ROT', 'WITHIN'].contains(name) ? 3
        : ['2SWAP', '2OVER'].contains(name) ? 4
        : ['+', '-', '*', '/', 'MOD', '/MOD', '=', '<>', '<', '>', 'MIN', 'MAX', 'AND', 'OR', 'XOR',
            'SWAP', 'OVER', 'NIP', 'TUCK', '2DUP', '2DROP', '.R', '!', '+!'].contains(name) ? 2 : 1;
    final values = pop(arity, raw), a = values[0];
    final b = values.length > 1 ? values[1] : 0, c = values.length > 2 ? values[2] : 0, d = values.length > 3 ? values[3] : 0;
    int flag(bool condition) => condition ? -1 : 0;
    switch (name) {
      case '+': push(a + b, raw); break;
      case '-': push(a - b, raw); break;
      case '*': push(a * b, raw); break;
      case '/': case 'MOD': case '/MOD': case '*/': case '*/MOD':
        final n = name.startsWith('*/') ? a * b : a, divisor = name.startsWith('*/') ? c : b;
        if (divisor == 0) fail(raw, 'division by zero', -10);
        final q = quotient(n, divisor);
        final r = n - divisor * q;
        if (['MOD', '/MOD', '*/MOD'].contains(name)) push(r, raw);
        if (name != 'MOD') push(q, raw);
        break;
      case 'NEGATE': push(-a, raw); break;
      case 'ABS': push(a.abs(), raw); break;
      case 'MIN': push(a < b ? a : b, raw); break;
      case 'MAX': push(a > b ? a : b, raw); break;
      case '1+': push(a + 1, raw); break;
      case '1-': push(a - 1, raw); break;
      case '2*': push(2 * a, raw); break;
      case '2/': push(quotient(a, 2), raw); break;
      case '=': push(flag(a == b), raw); break;
      case '<>': push(flag(a != b), raw); break;
      case '<': push(flag(a < b), raw); break;
      case '>': push(flag(a > b), raw); break;
      case '0=': push(flag(a == 0), raw); break;
      case '0<>': push(flag(a != 0), raw); break;
      case '0<': push(flag(a < 0), raw); break;
      case '0>': push(flag(a > 0), raw); break;
      case 'WITHIN': push(flag(b <= a && a < c), raw); break;
      case 'AND': push(a & b, raw); break;
      case 'OR': push(a | b, raw); break;
      case 'XOR': push(a ^ b, raw); break;
      case 'INVERT': push(~a, raw); break;
      case 'DUP': pushMany([a, a], raw); break;
      case '?DUP': pushMany(a == 0 ? [a] : [a, a], raw); break;
      case 'DROP': case '2DROP': break;
      case 'SWAP': pushMany([b, a], raw); break;
      case 'OVER': pushMany([a, b, a], raw); break;
      case 'ROT': pushMany([b, c, a], raw); break;
      case '-ROT': pushMany([c, a, b], raw); break;
      case 'NIP': push(b, raw); break;
      case 'TUCK': pushMany([b, a, b], raw); break;
      case '2DUP': pushMany([a, b, a, b], raw); break;
      case '2SWAP': pushMany([c, d, a, b], raw); break;
      case '2OVER': pushMany([a, b, c, d, a, b], raw); break;
      case '.': pending += '${format(a, raw)} '; break;
      case '.R': pending += format(a, raw).padLeft(b > 0 ? b : 0, ' '); break;
      case '?': pending += '${format(memory[address(a, raw)], raw)} '; break;
      case 'EMIT':
        if (a < 32 || a > 126) fail(raw, 'invalid argument', -24);
        pending += String.fromCharCode(a);
        break;
      case 'SPACES': if (a > 0) pending += ' ' * a; break;
      case '!': memory[address(b, raw)] = a; break;
      case '@': push(memory[address(a, raw)], raw); break;
      case '+!': final index = address(b, raw); memory[index] += a; break;
      case ',': memory.add(a); break;
      case 'ALLOT':
        if (a < 0 || a % 8 != 0) fail(raw, 'invalid argument', -24);
        memory.addAll(List.filled(a ~/ 8, 0));
        break;
      case 'CELLS': push(8 * a, raw); break;
      case 'CELL+': push(a + 8, raw); break;
    }
  }
  void definition(Word definition, int start, String raw) {
    if (depth == 100) fail(raw, 'nesting too deep', -7);
    depth++;
    final returnCount = returns.length, locals = List.filled(definition.localCount, 0);
    for (int pc = start; pc < definition.actions.length; pc++) {
      final action = definition.actions[pc], word = action.raw;
      switch (action.kind) {
        case 'literal': push(action.value, word); break;
        case 'call': execute(action.word!, word); break;
        case 'write': pending += action.text; break;
        case 'abort': if (pop(1, word)[0] != 0) fail(word, action.text, -2); break;
        case 'exit': pc = definition.actions.length; break;
        case 'recurse': this.definition(definition, 0, word); break;
        case 'does':
          final newest = dictionary.isEmpty ? null : dictionary.last;
          if (newest == null || newest.kind != 'create') fail(word, 'no CREATE word', -31);
          newest.does = DoesPart(definition, pc + 1);
          pc = definition.actions.length;
          break;
        case 'local-get': push(locals[action.slot], word); break;
        case 'local-set': locals[action.slot] = pop(1, word)[0]; break;
        case 'locals':
          final values = pop(action.slots.length, word);
          for (int i = 0; i < action.slots.length; i++) { locals[action.slots[i]] = values[i]; }
          break;
        case 'value-set': memory[action.word!.address ~/ 8] = pop(1, word)[0]; break;
        case 'defer-set':
          final value = pop(1, word)[0];
          if (!validToken(value)) fail(word, 'invalid argument', -24);
          action.word!.deferred = value;
          break;
        case 'branch': if (pop(1, word)[0] == 0) pc = action.target - 1; break;
        case 'jump': pc = action.target - 1; break;
        case 'loop-enter':
          final values = pop(2, word), limit = values[0], index = values[1];
          if (action.conditional && limit == index) { pc = action.target - 1; }
          else { pushReturn(limit, word); pushReturn(index, word); }
          break;
        case 'loop-next':
          final step = action.increment ? 1 : pop(1, word)[0];
          needReturns(2, word);
          final index = returns.last, limit = returns[returns.length - 2], next = returns.last + step;
          if ((index - limit < 0) != (next - limit < 0)) { returns.length -= 2; }
          else { returns[returns.length - 1] = next; pc = action.target - 1; }
          break;
        case 'leave': needReturns(2, word); returns.length -= 2; pc = action.target - 1; break;
        case 'of':
          final values = pop(2, word);
          if (values[0] != values[1]) { push(values[0], word); pc = action.target - 1; }
          break;
        case 'endcase': pop(1, word); break;
        case 'return':
          if (action.operation == '>R') { pushReturn(pop(1, word)[0], word); }
          else {
            final count = action.operation == 'J' ? 3 : action.operation == 'UNLOOP' ? 2 : 1;
            needReturns(count, word);
            if (action.operation == 'UNLOOP') { returns.length -= 2; }
            else if (action.operation == 'R>') { push(returns.removeLast(), word); }
            else { push(returns[returns.length - count], word); }
          }
          break;
      }
    }
    if (returns.length > returnCount) returns.length = returnCount;
    depth--;
  }
  int emit(Action action) {
    final index = compiling!.actions.length;
    compiling!.actions.add(action);
    return index;
  }
  Never mismatch(String raw) => fail(raw, 'control structure mismatch');
  void compile(String raw) {
    final name = raw.toUpperCase(), definition = compiling!;
    final top = control.isEmpty ? null : control.last, index = definition.actions.length;
    if (name == ';') {
      if (top != null) {
        final kind = top.kind == 'ELSE' ? 'IF' : top.kind == 'WHILE' ? 'BEGIN' : top.kind;
        fail(raw, 'unclosed $kind');
      }
      compiling = null;
      if (definition.anonymous) { push(xt(definition), raw); } else { dictionary.add(definition); }
      return;
    }
    if (name == '{:') {
      final words = <String>[];
      bool closed = false;
      while (true) {
        final word = read();
        if (word == null) break;
        if (word.toUpperCase() == ':}') { closed = true; break; }
        words.add(word);
      }
      if (!closed) fail(raw, 'unterminated locals');
      final marker = words.indexOf('--'), names = marker < 0 ? words : words.sublist(0, marker), slots = <int>[];
      for (final name in names) { checkName(name); }
      for (final name in names) {
        final slot = definition.localCount++;
        definition.locals[name.toUpperCase()] = slot;
        slots.add(slot);
      }
      emit(Action('locals', raw, slots: slots));
      return;
    }
    if (name == "[']") {
      final name = readName(raw), word = lookup(name);
      if (word == null) fail(name, 'undefined word', -13);
      emit(Action('literal', raw, value: xt(word)));
      return;
    }
    if (name == 'DOES>') { if (control.isNotEmpty) mismatch(raw); emit(Action('does', raw)); return; }
    if (name == 'EXIT' || name == 'RECURSE') { emit(Action(name.toLowerCase(), raw)); return; }
    if (['>R', 'R>', 'R@', 'I', 'J', 'UNLOOP'].contains(name)) { emit(Action('return', raw, operation: name)); return; }
    if (name == 'IF') { control.add(Control('IF', emit(Action('branch', raw)))); return; }
    if (name == 'ELSE') {
      if (top == null || top.kind != 'IF') mismatch(raw);
      emit(Action('jump', raw));
      definition.actions[top.index].target = index + 1;
      control[control.length - 1] = Control('ELSE', index);
      return;
    }
    if (name == 'THEN') {
      if (top == null || !['IF', 'ELSE'].contains(top.kind)) mismatch(raw);
      emit(Action('noop', raw)); definition.actions[top.index].target = index + 1; control.removeLast(); return;
    }
    if (name == 'BEGIN') { emit(Action('noop', raw)); control.add(Control('BEGIN', index)); return; }
    if (name == 'UNTIL' || name == 'AGAIN') {
      if (top == null || top.kind != 'BEGIN') mismatch(raw);
      emit(Action(name == 'UNTIL' ? 'branch' : 'jump', raw, target: top.index + 1)); control.removeLast(); return;
    }
    if (name == 'WHILE') {
      if (top == null || top.kind != 'BEGIN') mismatch(raw);
      emit(Action('branch', raw)); control[control.length - 1] = Control('WHILE', index, top.index); return;
    }
    if (name == 'REPEAT') {
      if (top == null || top.kind != 'WHILE') mismatch(raw);
      emit(Action('jump', raw, target: top.begin + 1)); definition.actions[top.index].target = index + 1; control.removeLast(); return;
    }
    if (name == 'DO' || name == '?DO') {
      emit(Action('loop-enter', raw, conditional: name == '?DO')); control.add(Control(name, index)); return;
    }
    if (name == 'LOOP' || name == '+LOOP') {
      if (top == null || !['DO', '?DO'].contains(top.kind)) mismatch(raw);
      emit(Action('loop-next', raw, increment: name == 'LOOP', target: top.index + 1));
      definition.actions[top.index].target = index + 1;
      for (final leave in top.leaves) { definition.actions[leave].target = index + 1; }
      control.removeLast(); return;
    }
    if (name == 'LEAVE') {
      Control? loop;
      for (final record in control.reversed) {
        if (record.kind == 'DO' || record.kind == '?DO') { loop = record; break; }
      }
      if (loop == null) mismatch(raw);
      loop.leaves.add(emit(Action('leave', raw))); return;
    }
    if (name == 'CASE') { emit(Action('noop', raw)); control.add(Control('CASE', index)); return; }
    if (name == 'OF') {
      if (top == null || top.kind != 'CASE') mismatch(raw);
      emit(Action('of', raw)); control.add(Control('OF', index)); return;
    }
    if (name == 'ENDOF') {
      if (top == null || top.kind != 'OF') mismatch(raw);
      emit(Action('jump', raw)); definition.actions[top.index].target = index + 1;
      control.removeLast(); control.last.endofs.add(index); return;
    }
    if (name == 'ENDCASE') {
      if (top == null || top.kind != 'CASE') mismatch(raw);
      emit(Action('endcase', raw));
      for (final endof in top.endofs) { definition.actions[endof].target = index + 1; }
      control.removeLast(); return;
    }
    if (definition.locals.containsKey(name)) { emit(Action('local-get', raw, slot: definition.locals[name]!)); return; }
    final word = lookup(name);
    if (word != null) { emit(Action('call', raw, word: word)); return; }
    final value = number(raw);
    if (value == null) fail(raw, 'undefined word', -13);
    emit(Action('literal', raw, value: value));
  }
  void assign(String raw, String kind) {
    final name = readName(raw), normalized = name.toUpperCase();
    final definition = compiling;
    if (kind == 'TO' && definition != null && definition.locals.containsKey(normalized)) {
      emit(Action('local-set', raw, slot: definition.locals[normalized]!)); return;
    }
    final word = lookup(name);
    if (word == null) fail(name, 'undefined word', -13);
    if (word.kind != (kind == 'TO' ? 'value' : 'defer')) fail(name, kind == 'TO' ? 'not a value' : 'not deferred');
    if (definition != null) { emit(Action(kind == 'TO' ? 'value-set' : 'defer-set', raw, word: word)); }
    else {
      final value = pop(1, raw)[0];
      if (kind == 'TO') { memory[word.address ~/ 8] = value; }
      else {
        if (!validToken(value)) fail(raw, 'invalid argument', -24);
        word.deferred = value;
      }
    }
  }
  void process(String raw) {
    final name = raw.toUpperCase();
    if (name == r'\') { position = line.length; return; }
    if (name == '(') {
      final end = line.indexOf(')', position);
      if (end < 0) fail(raw, 'unterminated comment');
      position = end + 1; return;
    }
    if (compiling == null && compileOnly.contains(name)) fail(raw, 'compile only');
    if (compiling != null && interpretOnly.contains(name)) fail(raw, 'interpret only');
    if (name == '."' || name == 'ABORT"') {
      if (position == line.length) fail(raw, 'unterminated string');
      final start = position + 1, end = line.indexOf('"', position + 1);
      if (end < 0) fail(raw, 'unterminated string');
      final text = line.substring(start, end);
      position = end + 1;
      if (compiling == null) { pending += text; } else { emit(Action(name == '."' ? 'write' : 'abort', raw, text: text)); }
      return;
    }
    if (name == 'TO' || name == 'IS') { assign(raw, name); return; }
    if (name == ':' || name == ':NONAME') {
      final wordName = name == ':' ? readName(raw) : raw;
      if (name == ':') checkName(wordName);
      compiling = Word(name == ':' ? wordName.toUpperCase() : ':NONAME', 'colon', memory.length * 8)
        ..rawName = wordName
        ..anonymous = name == ':NONAME';
      control = []; return;
    }
    if (name == 'FORGET') {
      final name = readName(raw), normalized = name.toUpperCase();
      int index = dictionary.length - 1;
      while (index >= 0 && dictionary[index].name != normalized) { index--; }
      if (index < 0) fail(name, 'undefined word', -13);
      memory.length = dictionary[index].here ~/ 8;
      dictionary.length = index;
      return;
    }
    if (compiling != null) { compile(raw); return; }
    final word = lookup(name);
    if (word != null) { execute(word, raw); return; }
    final value = number(raw);
    if (value == null) fail(raw, 'undefined word', -13);
    push(value, raw);
  }
  void run(String text) {
    line = text;
    position = 0;
    try {
      while (true) {
        final word = read();
        if (word == null) break;
        process(word);
      }
    } on ForthError catch (error) {
      if (pending.isNotEmpty) flush();
      output.add('ERROR ${error.word}: ${error.reason}');
      stack = []; returns = []; depth = 0; compiling = null; control = [];
    }
    if (pending.isNotEmpty) flush();
  }
}
void main() {
  final forth = Forth();
  while (true) {
    final line = stdin.readLineSync();
    if (line == null) break;
    if (line == 'BYE') {
      if (forth.compiling != null) forth.output.add('ERROR ${forth.compiling!.rawName}: unterminated definition');
      break;
    }
    forth.run(line);
  }
  if (forth.output.isNotEmpty) stdout.write('${forth.output.join('\n')}\n');
}
