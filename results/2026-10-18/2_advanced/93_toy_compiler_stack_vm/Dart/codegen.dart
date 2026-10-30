part of 'main.dart';

class Instruction {
  String op;
  int a, b;
  final Position position;
  final Declaration? callee;
  Instruction(this.op, this.position, {this.a = 0, this.b = 0, this.callee});
  Instruction.copy(Instruction s)
    : op = s.op,
      a = s.a,
      b = s.b,
      position = s.position,
      callee = s.callee;
}

class BasicBlock {
  final int first, last;
  final List<int> successors = [];
  BasicBlock(this.first, this.last);
}

class Unit {
  final String name;
  final Declaration? function;
  final List<Instruction> code;
  int start = 0, slots = 0, stack = 0;
  final List<BasicBlock> blocks = [];
  Unit(this.name, {this.function, List<Instruction>? code, this.slots = 0})
    : code = code ?? [];
}

bool jump(String op) => op == 'JUMP' || op == 'JUMPF' || op == 'JUMPT';
bool conditional(String op) => op == 'JUMPF' || op == 'JUMPT';
bool transfer(String op) =>
    op == 'JUMP' || op == 'RET' || op == 'RETV' || op == 'HALT';

class Generator {
  final Unit unit;
  final List<int> labels = [];
  final List<(int, int)> loops = [];
  Generator(this.unit);
  void emit(
    String op,
    Position p, {
    int a = 0,
    int b = 0,
    Declaration? callee,
  }) => unit.code.add(Instruction(op, p, a: a, b: b, callee: callee));
  int label() {
    final id = labels.length;
    labels.add(-1);
    return id;
  }

  void place(int id) {
    labels[id] = unit.code.length;
  }

  void to(String op, int target, Position p) => emit(op, p, a: target);
  void patch() {
    for (final instruction in unit.code) {
      if (jump(instruction.op)) instruction.a = labels[instruction.a];
    }
  }

  void expression(Expr e) {
    final pos = e.position;
    switch (e.kind) {
      case 'integer':
      case 'boolean':
        emit('PUSH', pos, a: e.value);
        break;
      case 'read':
        emit('READ', pos);
        break;
      case 'variable':
        {
          final symbol = e.referent!, global = symbol.kind == 'global';
          emit(
            global ? 'LOADG' : 'LOADL',
            pos,
            a: global ? symbol.address : symbol.slot,
          );
          break;
        }
      case 'array':
        expression(e.children.first);
        emit('LOADA', pos, a: e.referent!.address, b: e.referent!.size);
        break;
      case 'call':
        for (final argument in e.children) {
          expression(argument);
        }
        emit(
          'CALL',
          pos,
          b: e.children.length,
          callee: e.referent!.declaration,
        );
        break;
      case 'unary':
        expression(e.children.first);
        emit(e.token.spelling == '!' ? 'NOT' : 'NEG', pos);
        break;
      case 'binary':
        {
          final op = e.token.spelling;
          if (op == '&&' || op == '||') {
            final first = label(), last = label();
            expression(e.children[0]);
            to(op == '||' ? 'JUMPT' : 'JUMPF', first, pos);
            expression(e.children[1]);
            to('JUMP', last, pos);
            place(first);
            emit('PUSH', pos, a: op == '||' ? 1 : 0);
            place(last);
          } else {
            expression(e.children[0]);
            expression(e.children[1]);
            emit(
              {
                '+': 'ADD',
                '-': 'SUB',
                '*': 'MUL',
                '/': 'DIV',
                '%': 'MOD',
                '<': 'LT',
                '<=': 'LE',
                '>': 'GT',
                '>=': 'GE',
                '==': 'EQ',
                '!=': 'NE',
              }[op]!,
              pos,
            );
          }
          break;
        }
    }
  }

  void statement(Statement? s) {
    if (s == null) return;
    final pos = s.token.position;
    switch (s.kind) {
      case 'declaration':
        {
          final d = s.declaration!, initial = d.initializer;
          if (initial == null) {
            emit('PUSH', d.name.position);
          } else {
            expression(initial);
          }
          emit('STOREL', d.name.position, a: d.symbol!.slot);
          break;
        }
      case 'assignment':
        {
          final symbol = s.referent!, index = s.index;
          if (index != null) {
            expression(index);
            expression(s.expression!);
            emit('STOREA', pos, a: symbol.address, b: symbol.size);
          } else {
            expression(s.expression!);
            final global = symbol.kind == 'global';
            emit(
              global ? 'STOREG' : 'STOREL',
              pos,
              a: global ? symbol.address : symbol.slot,
            );
          }
          break;
        }
      case 'call':
        expression(s.expression!);
        if (s.expression!.type != 'void') emit('POP', pos);
        break;
      case 'print':
        for (final e in s.expressions) {
          expression(e);
        }
        emit('PRINT', pos, a: s.expressions.length);
        break;
      case 'return':
        final e = s.expression;
        if (e == null) {
          emit('RET', pos);
        } else {
          expression(e);
          emit('RETV', pos);
        }
        break;
      case 'block':
        for (final child in s.statements) {
          statement(child);
        }
        break;
      case 'if':
        {
          final other = label();
          expression(s.condition!);
          to('JUMPF', other, pos);
          statement(s.thenStatement);
          if (s.elseStatement != null) {
            final last = label();
            to('JUMP', last, pos);
            place(other);
            statement(s.elseStatement);
            place(last);
          } else {
            place(other);
          }
          break;
        }
      case 'while':
        {
          final first = label(), last = label();
          place(first);
          expression(s.condition!);
          to('JUMPF', last, pos);
          loops.add((last, first));
          statement(s.body);
          loops.removeLast();
          to('JUMP', first, pos);
          place(last);
          break;
        }
      case 'for':
        {
          final first = label(), update = label(), last = label();
          statement(s.init);
          place(first);
          final condition = s.condition;
          if (condition != null) {
            expression(condition);
            to('JUMPF', last, pos);
          }
          loops.add((last, update));
          statement(s.body);
          loops.removeLast();
          place(update);
          statement(s.update);
          to('JUMP', first, pos);
          place(last);
          break;
        }
      case 'break':
      case 'continue':
        final loop = loops.last;
        to('JUMP', s.kind == 'break' ? loop.$1 : loop.$2, pos);
        break;
    }
  }
}

void walkStatements(Statement? s, void Function(Statement) visit) {
  if (s == null) return;
  visit(s);
  for (final child in s.statements) {
    walkStatements(child, visit);
  }
  for (final child in [
    s.thenStatement,
    s.elseStatement,
    s.body,
    s.init,
    s.update,
  ]) {
    walkStatements(child, visit);
  }
}

(List<Unit>, int) generate(Program program, Set<Symbol> reachable) {
  var cells = 0;
  for (final d in program.globals) {
    d.symbol!.address = cells;
    cells += d.array ? d.size!.integer : 1;
  }
  final init = Unit('<init>'), units = [init];
  var g = Generator(init);
  for (final d in program.globals) {
    final initial = d.initializer;
    if (initial != null) {
      g.expression(initial);
      g.emit('STOREG', d.name.position, a: d.symbol!.address);
    }
  }
  final main = program.names['main']!.declaration;
  g.emit('CALL', main.name.position, callee: main);
  g.emit('HALT', main.name.position);
  g.patch();
  for (final f in program.functions) {
    if (!reachable.contains(f.symbol)) continue;
    final slots = [for (final parameter in f.parameters) parameter.symbol!],
        locals = <Declaration>[];
    walkStatements(f.body, (s) {
      if (s.kind == 'declaration') locals.add(s.declaration!);
    });
    locals.sort((a, b) => comparePositions(a.name.position, b.name.position));
    slots.addAll(locals.map((d) => d.symbol!));
    for (var i = 0; i < slots.length; i++) {
      slots[i].slot = i;
    }
    f.slots = slots;
    final unit = Unit(f.name.spelling, function: f, slots: slots.length);
    g = Generator(unit);
    g.emit('ENTER', f.name.position, a: unit.slots);
    g.statement(f.body);
    if (f.type == 'void') g.emit('RET', f.body!.close!.position);
    g.patch();
    units.add(unit);
  }
  return (units, cells);
}
