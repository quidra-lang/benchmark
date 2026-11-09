part of 'main.dart';

class Symbol {
  final String name, type, kind;
  final Declaration declaration;
  final bool array;
  final int size;
  int address = 0, slot = 0, reads = 0;
  final List<Position> references = [];
  final Set<Symbol> calls = {};
  Symbol(this.declaration, this.kind)
    : name = declaration.name.spelling,
      type = declaration.type,
      array = declaration.array,
      size = declaration.size?.integer ?? 0;
}

Never semanticError(Position p, String message) =>
    throw CompileError('semantic', message, p);
bool canComplete(Statement s) {
  switch (s.kind) {
    case 'return':
    case 'break':
    case 'continue':
      return false;
    case 'block':
      return s.statements.every(canComplete);
    case 'if':
      return s.elseStatement == null ||
          canComplete(s.thenStatement!) ||
          canComplete(s.elseStatement!);
  }
  return true;
}

class Semantics {
  final Program program;
  final List<Map<String, Symbol>> scopes = [];
  Declaration? function;
  int loops = 0;
  Semantics(this.program);
  Symbol symbol(Declaration d, String kind) {
    final value = Symbol(d, kind);
    d.symbol = value;
    program.symbols.add(value);
    return value;
  }

  Symbol? lookup(Token t, bool read) {
    Symbol? result;
    for (final scope in scopes.reversed) {
      final value = scope[t.spelling];
      if (value != null) {
        result = value;
        break;
      }
    }
    result ??= program.names[t.spelling];
    if (result != null) {
      result.references.add(t.position);
      if (read) result.reads++;
    }
    return result;
  }

  Symbol variable(Token t, bool array, bool read) {
    final s = lookup(t, read), name = t.spelling;
    if (s == null) semanticError(t.position, "undeclared identifier '$name'");
    if (s.kind == 'function')
      semanticError(t.position, "'$name' is a function, not a variable");
    if (array && !s.array) semanticError(t.position, "'$name' is not an array");
    if (!array && s.array)
      semanticError(t.position, "array '$name' used without index");
    return s;
  }

  String expression(Expr e, bool statement) {
    var type = '';
    final name = e.token.spelling, pos = e.position;
    switch (e.kind) {
      case 'integer':
      case 'read':
        type = 'int';
        break;
      case 'boolean':
        type = 'bool';
        break;
      case 'variable':
        e.referent = variable(e.token, false, true);
        type = e.referent!.type;
        break;
      case 'array':
        e.referent = variable(e.token, true, true);
        if (expression(e.children.first, false) != 'int')
          semanticError(pos, "index of '$name' must be int");
        type = 'int';
        break;
      case 'call':
        {
          final s = lookup(e.token, true);
          if (s == null) semanticError(pos, "undeclared function '$name'");
          if (s.kind != 'function')
            semanticError(pos, "'$name' is not a function");
          e.referent = s;
          final currentFunction = function;
          if (currentFunction != null) currentFunction.symbol!.calls.add(s);
          final parameters = s.declaration.parameters;
          if (e.children.length != parameters.length)
            semanticError(
              pos,
              "wrong number of arguments to '$name' (expected ${parameters.length}, found ${e.children.length})",
            );
          for (var j = 0; j < e.children.length; j++) {
            if (expression(e.children[j], false) != parameters[j].type)
              semanticError(
                pos,
                "argument ${j + 1} of '$name' must be ${parameters[j].type}",
              );
          }
          if (!statement && s.type == 'void')
            semanticError(pos, "void function '$name' used as a value");
          type = s.type;
          break;
        }
      case 'unary':
        {
          final operand = expression(e.children.first, false),
              required = e.token.spelling == '!' ? 'bool' : 'int';
          if (operand != required)
            semanticError(
              pos,
              "operator '${e.token.spelling}' requires $required operand",
            );
          type = operand;
          break;
        }
      case 'binary':
        {
          final left = expression(e.children[0], false),
              right = expression(e.children[1], false),
              op = e.token.spelling;
          if (wordIn('+ - * / % < <= > >=', op)) {
            if (left != 'int' || right != 'int')
              semanticError(pos, "operator '$op' requires int operands");
            type = wordIn('< <= > >=', op) ? 'bool' : 'int';
          } else if (op == '==' || op == '!=') {
            if (left != right)
              semanticError(
                pos,
                "operator '$op' requires operands of the same type",
              );
            type = 'bool';
          } else {
            if (left != 'bool' || right != 'bool')
              semanticError(pos, "operator '$op' requires bool operands");
            type = 'bool';
          }
          break;
        }
    }
    e.type = type;
    return type;
  }

  void declaration(Declaration d) {
    final name = d.name.spelling, pos = d.name.position, current = scopes.last;
    if (d.type == 'void')
      semanticError(pos, "variable '$name' cannot have type void");
    if (current.containsKey(name))
      semanticError(pos, "redeclaration of '$name'");
    final initial = d.initializer;
    if (initial != null && expression(initial, false) != d.type)
      semanticError(pos, "type mismatch in initialization of '$name'");
    current[name] = symbol(d, 'local');
  }

  void statement(Statement n) {
    final pos = n.token.position;
    switch (n.kind) {
      case 'declaration':
        declaration(n.declaration!);
        break;
      case 'assignment':
        {
          final name = n.token.spelling, index = n.index;
          n.referent = variable(n.token, index != null, false);
          if (index != null && expression(index, false) != 'int')
            semanticError(pos, "index of '$name' must be int");
          if (expression(n.expression!, false) != n.referent!.type)
            semanticError(pos, "type mismatch in assignment to '$name'");
          break;
        }
      case 'call':
        expression(n.expression!, true);
        break;
      case 'if':
      case 'while':
        if (expression(n.condition!, false) != 'bool')
          semanticError(pos, "condition of '${n.kind}' must be bool");
        if (n.kind == 'if') {
          statement(n.thenStatement!);
          final other = n.elseStatement;
          if (other != null) statement(other);
        } else {
          loops++;
          statement(n.body!);
          loops--;
        }
        break;
      case 'for':
        scopes.add({});
        final initial = n.init, condition = n.condition, update = n.update;
        if (initial != null) statement(initial);
        if (condition != null && expression(condition, false) != 'bool')
          semanticError(pos, "condition of 'for' must be bool");
        if (update != null) statement(update);
        loops++;
        statement(n.body!);
        loops--;
        scopes.removeLast();
        break;
      case 'break':
      case 'continue':
        if (loops == 0) semanticError(pos, "'${n.kind}' outside loop");
        break;
      case 'return':
        {
          final f = function!, expr = n.expression;
          if (f.type == 'void') {
            if (expr != null)
              semanticError(
                pos,
                "function '${f.name.spelling}' must not return a value",
              );
          } else {
            if (expr == null)
              semanticError(
                pos,
                "function '${f.name.spelling}' must return a value",
              );
            if (expression(expr, false) != f.type)
              semanticError(
                pos,
                "return value of '${f.name.spelling}' must be ${f.type}",
              );
          }
          break;
        }
      case 'print':
        for (var j = 0; j < n.expressions.length; j++) {
          if (expression(n.expressions[j], false) != 'int')
            semanticError(pos, "argument ${j + 1} of 'print' must be int");
        }
        break;
      case 'block':
        scopes.add({});
        for (final child in n.statements) {
          statement(child);
        }
        scopes.removeLast();
        break;
    }
  }

  void analyze() {
    for (final d in program.declarations) {
      final name = d.name.spelling, pos = d.name.position;
      if (!d.function) {
        if (d.array) {
          if (d.type != 'int')
            semanticError(pos, "array '$name' must have element type int");
          if (d.size!.integer == 0)
            semanticError(
              d.size!.position,
              "array '$name' must have a positive size",
            );
        } else if (d.type == 'void') {
          semanticError(pos, "variable '$name' cannot have type void");
        }
      }
      if (program.names.containsKey(name))
        semanticError(pos, "redeclaration of '$name'");
      if (d.function) {
        final seen = <String>{};
        for (final parameter in d.parameters) {
          final pname = parameter.name.spelling;
          if (parameter.type == 'void')
            semanticError(
              parameter.name.position,
              "parameter '$pname' cannot have type void",
            );
          if (!seen.add(pname))
            semanticError(parameter.name.position, "redeclaration of '$pname'");
        }
        program.names[name] = symbol(d, 'function');
      } else {
        final initial = d.initializer;
        if (initial != null) {
          Expr? first;
          void visit(Expr e) {
            if (wordIn('variable array call read', e.kind) &&
                (first == null || earlier(e.position, first!.position)))
              first = e;
            for (final child in e.children) {
              visit(child);
            }
          }

          visit(initial);
          final forbidden = first;
          if (forbidden != null)
            semanticError(
              forbidden.position,
              'global initializer must be constant',
            );
          if (expression(initial, false) != d.type)
            semanticError(pos, "type mismatch in initialization of '$name'");
        }
        program.names[name] = symbol(d, 'global');
      }
    }
    final main = program.names['main'];
    if (main == null || main.kind != 'function')
      semanticError(program.end.position, 'no main function');
    if (main.type != 'void' || main.declaration.parameters.isNotEmpty)
      semanticError(
        main.declaration.name.position,
        "main must be declared as 'void main()'",
      );
    for (final f in program.functions) {
      function = f;
      scopes.clear();
      scopes.add({});
      for (final parameter in f.parameters) {
        scopes.first[parameter.name.spelling] = symbol(parameter, 'parameter');
      }
      for (final s in f.body!.statements) {
        statement(s);
      }
      if (f.type != 'void' && canComplete(f.body!))
        semanticError(
          f.name.position,
          "missing return in function '${f.name.spelling}'",
        );
    }
  }
}
