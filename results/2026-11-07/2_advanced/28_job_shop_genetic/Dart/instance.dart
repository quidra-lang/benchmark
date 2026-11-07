import 'dart:io';
import 'dart:math' as math;

class Operation {
  final int ident, job, index, machine, duration, head, previous, next;
  int tail = 0;
  Operation(
    this.ident,
    this.job,
    this.index,
    this.machine,
    this.duration,
    this.head,
    this.previous,
    this.next,
  );
  String get code => 'J$job-$index';
}

class Job {
  final int number;
  final List<int> operations;
  final int work;
  Job(this.number, this.operations, this.work);
}

class Machine {
  final int number;
  final List<int> operations;
  int load = 0, head = 1 << 30, tail = 1 << 30;
  Machine(this.number, this.operations, List<Operation> all) {
    for (final id in operations) {
      final o = all[id];
      load += o.duration;
      head = math.min(head, o.head);
      tail = math.min(tail, o.tail);
    }
  }
  int get bound => head + load + tail;
}

class Instance {
  final int machineCount;
  final jobs = <Job>[];
  final byJob = <int, Job>{};
  final operations = <Operation>[];
  final durations = <int>[];
  final machines = <Machine>[];
  final errors = <String>[];
  Instance(this.machineCount);
}

Instance loadInstance() {
  final lines = File('input/instance.txt').readAsLinesSync();
  final first = lines.first.split(' ').map(int.parse).toList();
  final instance = Instance(first[1]);
  for (var j = 1; j <= first[0]; j++) {
    final steps = <(int, int)>[], used = <int>{};
    var valid = true;
    final tokens = lines[j].split(' ');
    for (var k = 0; k < tokens.length; k++) {
      final pair = tokens[k].split(':').map(int.parse).toList(),
          m = int.parse(tokens[k].split(':')[0]),
          d = int.parse(tokens[k].split(':')[1]);
      final reason = m < 1 || m > instance.machineCount
          ? 'unknown machine $m'
          : d < 1 || d > 99
          ? 'bad duration $d'
          : used.contains(m)
          ? 'repeated machine $m'
          : null;
      if (reason != null) {
        instance.errors.add('job $j operation ${k + 1}: $reason');
        valid = false;
        break;
      }
      used.add(m);
      steps.add((pair[0], pair[1]));
    }
    if (!valid) continue;
    final ids = <int>[];
    var work = 0;
    for (var k = 0; k < steps.length; k++) {
      final id = instance.operations.length, step = steps[k];
      instance.operations.add(
        Operation(
          id,
          j,
          k + 1,
          step.$1,
          step.$2,
          work,
          k > 0 ? id - 1 : -1,
          k + 1 < steps.length ? id + 1 : -1,
        ),
      );
      instance.durations.add(step.$2);
      ids.add(id);
      work += step.$2;
    }
    for (final id in ids) {
      final o = instance.operations[id];
      o.tail = work - o.head - o.duration;
    }
    final job = Job(j, ids, work);
    instance.jobs.add(job);
    instance.byJob[j] = job;
  }
  for (var m = 1; m <= instance.machineCount; m++) {
    instance.machines.add(
      Machine(m, [
        for (final o in instance.operations)
          if (o.machine == m) o.ident,
      ], instance.operations),
    );
  }
  return instance;
}
