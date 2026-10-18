import 'dart:io';

void main() {
    final out = StringBuffer();
    const program = ['SET A 1', 'SET B 1', 'SET D 8', 'MUL A B', 'PRINT A', 'ADD B 1', 'SUB D 1',
        'JNZ D -4', 'SET A 1071', 'SET B 462', 'SET C A', 'MOD C B', 'SET A B', 'SET B C', 'JNZ B -4',
        'PRINT A', 'HALT'];
    final registers = List.filled(4, 0);
    var pc = 0, executed = 0;
    int value(String token) => token.length == 1 && 'ABCD'.contains(token) ? registers[token.codeUnitAt(0) - 65] : int.parse(token);
    while (pc >= 0 && pc < program.length) {
        final tokens = program[pc].split(' '), op = tokens[0];
        executed++;
        if (op == 'HALT')
            break;
        if (op == 'PRINT') {
            out.writeln(value(tokens[1]));
            pc++;
            continue;
        }
        if (op == 'JNZ') {
            pc += value(tokens[1]) != 0 ? int.parse(tokens[2]) : 1;
            continue;
        }
        final r = tokens[1].codeUnitAt(0) - 65, x = value(tokens[2]);
        switch (op) {
            case 'SET':
            registers[r] = x;
            break;
            case 'ADD':
            registers[r] += x;
            break;
            case 'SUB':
            registers[r] -= x;
            break;
            case 'MUL':
            registers[r] *= x;
            break;
            case 'MOD':
            registers[r] %= x;
            break;
        }
        pc++;
    }
    out.writeln('executed: $executed');
    stdout.write(out);
}
