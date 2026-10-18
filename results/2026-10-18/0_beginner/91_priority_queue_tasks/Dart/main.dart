import 'dart:io';

class Task {
    final String name;
    final int priority, sequence;
    Task(this.name, this.priority, this.sequence);
}

bool before(Task a, Task b) => a.priority != b.priority ? a.priority < b.priority : a.sequence < b.sequence;
class Heap {
    final items = <Task>[];
    void push(Task task) {
        var i = items.length;
        items.add(task);
        while (i > 0) {
            final p = (i - 1) ~/ 2;
            if (!before(items[i], items[p]))
                break;
            final t = items[i];
            items[i] = items[p];
            items[p] = t;
            i = p;
        }
    }

    Task pop() {
        final result = items.first, last = items.removeLast();
        if (items.isNotEmpty) {
            items[0] = last;
            var i = 0;
            while (2 * i + 1 < items.length) {
                var child = 2 * i + 1;
                if (child + 1 < items.length && before(items[child + 1], items[child]))
                    child++;
                if (!before(items[child], items[i]))
                    break;
                final t = items[i];
                items[i] = items[child];
                items[child] = t;
                i = child;
            }
        }
        return result;
    }
}

void main() {
    final out = StringBuffer();
    const operations = ['add email 3', 'add backup 5', 'add deploy 1', 'run', 'add report 3', 'add test 2',
        'add lint 3', 'run', 'run', 'add cleanup 5', 'add review 2', 'run', 'add build 1', 'add docs 4',
        'run', 'run'];
    final heap = Heap();
    var sequence = 0;
    for (final operation in operations) {
        final tokens = operation.split(' ');
        if (tokens[0] == 'add') {
            heap.push(Task(tokens[1], int.parse(tokens[2]), sequence++));
        } else {
            final task = heap.pop();
            out.writeln('run: ${task.name} (priority ${task.priority})');
        }
    }
    final remaining = <String>[];
    while (heap.items.isNotEmpty)
        remaining.add(heap.pop().name);
    out.writeln('remaining: ${remaining.join(' ')}');
    stdout.write(out);
}
