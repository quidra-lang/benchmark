part of 'main.dart';

class Settings {
  final int n, emin, emax, h, b, q, seed, end, retry, attempts, sample;
  Settings(
    this.n,
    this.emin,
    this.emax,
    this.h,
    this.b,
    this.q,
    this.seed,
    this.end,
    this.retry,
    this.attempts,
    this.sample,
  );
}

class Control {
  final int time;
  final String kind;
  final List<String> args;
  Control(this.time, this.kind, this.args);
}

class Request {
  final int number, time, initial;
  final String command;
  int destination,
      scheduled,
      attempts = 0,
      redirects = 0,
      index = 0,
      term = 0,
      latency = 0;
  String status = '', result = '';
  bool abandoned = false;
  Request(this.number, this.time, this.initial, this.command)
    : destination = initial,
      scheduled = time;
}

int number(String s) => int.parse(s);
List<String> readLines(String path) => File(path).readAsLinesSync();
Settings readSettings() {
  final a = [
    for (final line in readLines('input/cluster.txt')) line.split(' '),
  ];
  return Settings(
    number(a[0][1]),
    number(a[1][1]),
    number(a[1][2]),
    number(a[2][1]),
    number(a[3][1]),
    number(a[4][1]),
    number(a[5][1]),
    number(a[6][1]),
    number(a[7][1]),
    number(a[8][1]),
    number(a[9][1]),
  );
}

(List<Control>, List<Request>) readScript() {
  final controls = <Control>[], requests = <Request>[];
  for (final line in readLines('input/script.txt')) {
    final a = line.split(' '), t = number(a[0]);
    if (a[1] == 'REQUEST') {
      requests.add(
        Request(requests.length + 1, t, number(a[2]), a.sublist(3).join(' ')),
      );
    } else {
      controls.add(Control(t, a[1], a.sublist(2)));
    }
  }
  return (controls, requests);
}

List<List<int>> parseGroups(List<String> a) => [
  for (final g in a) [for (final v in g.split(',')) number(v)],
];
