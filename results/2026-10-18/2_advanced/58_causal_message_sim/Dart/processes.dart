part of 'main.dart';

class Action {
  final String kind, argument, value;
  Action(this.kind, this.argument, [this.value = '']);
}

class Scheduled {
  final int time, period;
  final Action action;
  Scheduled(this.time, this.period, this.action);
}

class Rule {
  final String tag;
  final Action action;
  Rule(this.tag, this.action);
}

class Program {
  int initial = 0;
  final scheduled = <Scheduled>[], rules = <Rule>[];
}

class ProcessState {
  final int index, initial;
  int balance,
      l = 0,
      incoming = 0,
      outgoing = 0,
      refused = 0,
      minimum,
      maxHeld = 0;
  final List<int> v, b, next;
  final List<Map<int, Packet>> buffers;
  final hold = <MessageCopy>[],
      events = <Event>[],
      delivered = <MessageCopy>[],
      counts = <String, int>{};
  final List<Rule> rules;
  ProcessState(this.index, Program program, int n)
    : initial = program.initial,
      balance = program.initial,
      minimum = program.initial,
      v = List.filled(n, 0),
      b = List.filled(n, 0),
      next = List.filled(n, 1),
      buffers = List.generate(n, (_) => <int, Packet>{}),
      rules = program.rules;
}

Action parseAction(List<String> a) =>
    Action(a[0], a[1], a.length > 2 ? a[2] : '');
List<Program> readPrograms(Network network) {
  final out = List.generate(network.names.length, (_) => Program());
  var current = -1;
  for (final line in readLines('input/programs.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'PROCESS':
        current = network.index[a[1]]!;
        out[current].initial = int.parse(a[3]);
      case 'END':
        current = -1;
      case 'AT':
        var period = 0, start = 2;
        if (a[2] == 'EVERY') {
          period = int.parse(a[3]);
          start = 4;
        }
        out[current].scheduled.add(
          Scheduled(int.parse(a[1]), period, parseAction(a.sublist(start))),
        );
      case 'ON':
        out[current].rules.add(Rule(a[1], parseAction(a.sublist(2))));
    }
  }
  return out;
}

int balanceAt(ProcessState p, int count) =>
    count == 0 ? p.initial : p.events[count - 1].balance;
