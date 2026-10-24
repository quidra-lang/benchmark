import 'dart:io';
import 'dart:math' as math;

void main() {
    final out = StringBuffer();
    const commands = ['undo', 'type hello world', 'delete 5', 'type there', 'undo', 'undo', 'redo',
        'type friend', 'redo', 'delete 20', 'undo', 'redo', 'redo', 'type see you'];
    var current = '';
    final undo = <String>[], redo = <String>[];
    for (final command in commands) {
        out.write('$command => ');
        if (command == 'undo') {
            if (undo.isEmpty) {
                out.writeln('nothing to undo');
                continue;
            }
            redo.add(current);
            current = undo.removeLast();
        } else if (command == 'redo') {
            if (redo.isEmpty) {
                out.writeln('nothing to redo');
                continue;
            }
            undo.add(current);
            current = redo.removeLast();
        } else {
            undo.add(current);
            redo.clear();
            if (command.startsWith('type ')) {
                current += command.substring(5);
            } else {
                final n = int.parse(command.substring(7));
                current = current.substring(0, math.max(0, current.length - n));
            }
        }
        out.writeln('"$current"');
    }
    stdout.write(out);
}
