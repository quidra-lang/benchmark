part of 'main.dart';

class Scenario {
  final String name, protocol, l1, l2;
  final int order;
  Scenario(this.name, this.protocol, this.l1, this.l2, this.order);
}

class Region {
  final String name;
  final int first, last;
  Region(this.name, this.first, this.last);
}

class Config {
  int n = 0,
      line = 0,
      l1Size = 0,
      l1Ways = 0,
      l2Size = 0,
      l2Ways = 0,
      l1Sets = 0,
      l2Sets = 0,
      t1 = 0,
      t2 = 0,
      tm = 0,
      tb = 0,
      interval = 0,
      top = 0;
  final List<Scenario> scenarios = [];
  String primary = '';
  final List<Region> regions = [];
  final List<int> watch = [];
}

int number(String s) => int.tryParse(s) ?? 0;
int hexNumber(String s) => int.parse(s, radix: 16);
bool decimal(String s) =>
    s.isNotEmpty &&
    !(s.length > 1 && s[0] == '0') &&
    s.codeUnits.every((c) => c >= 48 && c <= 57);
bool hexDigits(String s) =>
    s.length == 8 &&
    s.codeUnits.every((c) => c >= 48 && c <= 57 || c >= 97 && c <= 102);
String address(int a) => a.toRadixString(16).padLeft(8, '0');
List<String> readLines(String path) => File(path).readAsLinesSync();
Config readConfig() {
  final c = Config();
  for (final line in readLines('input/config.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'CORES':
        c.n = number(a[1]);
        break;
      case 'LINE':
        c.line = number(a[1]);
        break;
      case 'L1':
        c.l1Size = number(a[1]);
        c.l1Ways = number(a[2]);
        break;
      case 'L2':
        c.l2Size = number(a[1]);
        c.l2Ways = number(a[2]);
        break;
      case 'LATENCY':
        c.t1 = number(a[1]);
        c.t2 = number(a[2]);
        c.tm = number(a[3]);
        c.tb = number(a[4]);
        break;
      case 'SCENARIO':
        c.scenarios.add(Scenario(a[1], a[2], a[3], a[4], c.scenarios.length));
        break;
      case 'PRIMARY':
        c.primary = a[1];
        break;
      case 'INTERVAL':
        c.interval = number(a[1]);
        break;
      case 'TOP':
        c.top = number(a[1]);
        break;
      case 'REGION':
        c.regions.add(Region(a[1], hexNumber(a[2]), hexNumber(a[3])));
        break;
      case 'WATCH':
        c.watch.add(hexNumber(a[1]) ~/ c.line);
        break;
    }
  }
  c.l1Sets = c.l1Size ~/ (c.line * c.l1Ways);
  c.l2Sets = c.l2Size ~/ (c.line * c.l2Ways);
  return c;
}

void writeLines(String name, List<String> lines) {
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
