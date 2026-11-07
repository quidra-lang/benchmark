part of 'main.dart';

const instructionKinds = [
  'copy',
  'bin',
  'load',
  'store',
  'goto',
  'if',
  'param',
  'call',
  'return',
  'read',
  'print',
];
typedef Operand = (String?, int);
Operand operand(String text) =>
    text.startsWith('-') || text.codeUnitAt(0) >= 48 && text.codeUnitAt(0) <= 57
    ? (null, int.parse(text))
    : (text, 0);
Operand constant(int n) => (null, n);

extension OperandProperties on Operand {
  bool get isConstant => $1 == null;
  String get variable => $1 ?? '';
  int get value => $2;
  String get text => isConstant ? '$value' : $1!;
}

typedef Expression = (String, String, Operand, Operand);

extension ExpressionProperties on Expression {
  String get kind => $1;
  String get operation => $2;
  Operand get a => $3;
  Operand get b => $4;
  String get text =>
      kind == 'load' ? '$operation[${a.text}]' : '${a.text}$operation${b.text}';
  bool uses(String name) =>
      !a.isConstant && a.variable == name ||
      kind == 'bin' && !b.isConstant && b.variable == name;
}

class Instruction {
  String kind, destination, operation, name;
  Operand a, b;
  bool hasA;
  int count, number = 0;
  Instruction(
    this.kind, {
    this.destination = '',
    this.operation = '',
    this.name = '',
    this.a = const ('', 0),
    this.b = const ('', 0),
    this.hasA = false,
    this.count = 0,
  });
  Instruction copy() => Instruction(
    kind,
    destination: destination,
    operation: operation,
    name: name,
    a: a,
    b: b,
    hasA: hasA,
    count: count,
  )..number = number;
  List<Operand> get operands => switch (kind) {
    'copy' || 'load' || 'param' || 'print' => [a],
    'bin' || 'if' || 'store' => [a, b],
    'return' => hasA ? [a] : [],
    _ => [],
  };
  void setOperands(List<Operand> values) {
    if (values.isNotEmpty) a = values[0];
    if (values.length > 1) b = values[1];
  }

  List<String> get used => [
    for (final value in operands)
      if (!value.isConstant) value.variable,
  ];
  Expression? get expression => switch (kind) {
    'bin' => ('bin', operation, a, b),
    'load' => ('load', name, a, const ('', 0)),
    _ => null,
  };
  String get text => switch (kind) {
    'copy' => '$destination = ${a.text}',
    'bin' => '$destination = ${a.text} $operation ${b.text}',
    'load' => '$destination = $name[${a.text}]',
    'store' => '$name[${a.text}] = ${b.text}',
    'goto' => 'goto $name',
    'if' => 'if ${a.text} $operation ${b.text} goto $name',
    'param' || 'print' => '$kind ${a.text}',
    'call' =>
      '${destination.isEmpty ? '' : '$destination = '}call $name $count',
    'return' => hasA ? 'return ${a.text}' : 'return',
    'read' => 'read $destination',
    _ => throw StateError('unknown instruction'),
  };
}

class CodeLine {
  final String label;
  final Instruction? instruction;
  CodeLine.label(this.label) : instruction = null;
  CodeLine.instruction(this.instruction) : label = '';
}

class FunctionCode {
  final String name;
  List<String> parameters;
  List<CodeLine> code;
  int temporarySerial = 0, preheaderSerial = 0;
  FunctionCode(this.name, {this.parameters = const [], List<CodeLine>? code})
    : code = code ?? [];
  FunctionCode copy() =>
      FunctionCode(
          name,
          parameters: List.of(parameters),
          code: [
            for (final line in code)
              line.instruction == null
                  ? CodeLine.label(line.label)
                  : CodeLine.instruction(line.instruction!.copy()),
          ],
        )
        ..temporarySerial = temporarySerial
        ..preheaderSerial = preheaderSerial;
}

class ArrayDeclaration {
  final String name;
  final int size;
  ArrayDeclaration(this.name, this.size);
}

class Program {
  final List<ArrayDeclaration> arrays;
  List<FunctionCode> functions;
  Program({List<ArrayDeclaration>? arrays, List<FunctionCode>? functions})
    : arrays = arrays ?? [],
      functions = functions ?? [];
  Program copy() => Program(
    arrays: List.of(arrays),
    functions: functions.map((f) => f.copy()).toList(),
  );
}

List<String> words(String text) =>
    text.split(' ').where((s) => s.isNotEmpty).toList();
List<String> readLines(String path) => File(path).readAsLinesSync();
(String, Operand) arrayOperand(String text) {
  final i = text.indexOf('[');
  return (
    text.substring(0, i),
    operand(text.substring(i + 1, text.length - 1)),
  );
}

Program parseProgram() {
  final program = Program();
  FunctionCode? function;
  for (final line in readLines('input/program.tac')) {
    final a = words(line);
    if (a.isEmpty || a[0].startsWith('#')) continue;
    if (a[0] == 'array') {
      program.arrays.add(ArrayDeclaration(a[1], int.parse(a[2])));
      continue;
    }
    if (a[0] == 'func') {
      function = FunctionCode(a[1], parameters: a.skip(2).toList());
      program.functions.add(function);
      continue;
    }
    if (a[0] == 'end') continue;
    if (a.length == 1 && a[0].endsWith(':')) {
      function!.code.add(CodeLine.label(a[0].substring(0, a[0].length - 1)));
      continue;
    }
    Instruction instruction;
    switch (a[0]) {
      case 'goto':
        instruction = Instruction('goto', name: a[1]);
      case 'if':
        instruction = Instruction(
          'if',
          a: operand(a[1]),
          operation: a[2],
          b: operand(a[3]),
          name: a[5],
        );
      case 'param':
      case 'print':
        instruction = Instruction(a[0], a: operand(a[1]));
      case 'read':
        instruction = Instruction('read', destination: a[1]);
      case 'return':
        instruction = Instruction(
          'return',
          hasA: a.length == 2,
          a: a.length == 2 ? operand(a[1]) : const ('', 0),
        );
      case 'call':
        instruction = Instruction('call', name: a[1], count: int.parse(a[2]));
      default:
        if (a[0].contains('[')) {
          final (name, index) = arrayOperand(a[0]);
          instruction = Instruction(
            'store',
            name: name,
            a: index,
            b: operand(a[2]),
          );
        } else if (a[2] == 'call') {
          instruction = Instruction(
            'call',
            destination: a[0],
            name: a[3],
            count: int.parse(a[4]),
          );
        } else if (a.length == 5) {
          instruction = Instruction(
            'bin',
            destination: a[0],
            a: operand(a[2]),
            operation: a[3],
            b: operand(a[4]),
          );
        } else if (a[2].contains('[')) {
          final (name, index) = arrayOperand(a[2]);
          instruction = Instruction(
            'load',
            destination: a[0],
            name: name,
            a: index,
          );
        } else {
          instruction = Instruction(
            'copy',
            destination: a[0],
            a: operand(a[2]),
          );
        }
    }
    function!.code.add(CodeLine.instruction(instruction));
  }
  return program;
}

List<String> functionLines(FunctionCode function) => [
  'func ${function.name}${function.parameters.isEmpty ? '' : ' ${function.parameters.join(' ')}'}',
  for (final line in function.code)
    line.instruction == null
        ? '${line.label}:'
        : '    ${line.instruction!.text}',
  'end',
];
List<String> programLines(Program program) {
  final result = [
    for (final array in program.arrays) 'array ${array.name} ${array.size}',
  ];
  for (var i = 0; i < program.functions.length; i++) {
    if (i > 0 || program.arrays.isNotEmpty) result.add('');
    result.addAll(functionLines(program.functions[i]));
  }
  return result;
}

int calculate(String op, int a, int b) => switch (op) {
  '+' => a + b,
  '-' => a - b,
  '*' => a * b,
  '/' => a ~/ b,
  '%' => a - (a ~/ b) * b,
  '<' => a < b ? 1 : 0,
  '<=' => a <= b ? 1 : 0,
  '>' => a > b ? 1 : 0,
  '>=' => a >= b ? 1 : 0,
  '==' => a == b ? 1 : 0,
  '!=' => a != b ? 1 : 0,
  _ => throw StateError('unknown operation'),
};
