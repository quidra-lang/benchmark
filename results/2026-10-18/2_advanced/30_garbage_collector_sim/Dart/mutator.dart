part of 'main.dart';

const commandNames = [
  'ALLOC',
  'PUSH',
  'LOAD',
  'POP',
  'SET',
  'OVERWRITE',
  'CHECKPOINT',
];

class CollectorEntry {
  final String name, type;
  final int young, age;
  CollectorEntry(this.name, this.type, this.young, this.age);
}

class Config {
  int heapSize = 0, width = 0;
  final collectors = <CollectorEntry>[], maps = <String>{}, windows = <int>[];
}

class Command {
  final int line;
  final String name;
  int pointers = 0, data = 0, slot = 0, field = 0, source = -1, count = 0;
  String label = '';
  Command(this.line, this.name);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
Config readConfig() {
  final config = Config();
  for (final text in readLines('input/config.txt')) {
    final t = text.split(' ');
    switch (t[0]) {
      case 'HEAP':
        config.heapSize = int.parse(t[1]);
      case 'WIDTH':
        config.width = int.parse(t[1]);
      case 'COLLECTOR':
        config.collectors.add(
          CollectorEntry(
            t[1],
            t[2],
            t.length > 3 ? int.parse(t[3]) : 0,
            t.length > 4 ? int.parse(t[4]) : 0,
          ),
        );
      case 'MAPS':
        config.maps.addAll(t.skip(1));
      case 'MMU':
        config.windows.addAll(t.skip(1).map(int.parse));
    }
  }
  return config;
}

bool isNumber(String token) => RegExp(r'^(0|[1-9][0-9]{0,3})$').hasMatch(token);
bool isLabel(String token) => RegExp(r'^[a-z0-9_]{1,16}$').hasMatch(token);
(Command?, String?) parseLine(int number, String text) {
  final tokens = text.split(' '),
      forms = {
        'ALLOC': 'nn',
        'PUSH': 'r',
        'LOAD': 'nn',
        'POP': 'n',
        'SET': 'nnr',
        'OVERWRITE': 'nr',
        'CHECKPOINT': 'l',
      };
  final form = forms[tokens.first];
  if (form == null || tokens.length != form.length + 1) return (null, 'syntax');
  for (var i = 0; i < form.length; i++) {
    final kind = form[i], token = tokens[i + 1];
    if (kind == 'n' && !isNumber(token) ||
        kind == 'r' && token != '-' && !isNumber(token) ||
        kind == 'l' && !isLabel(token))
      return (null, 'syntax');
  }
  final c = Command(number, tokens[0]);
  int source(String token) => token == '-' ? -1 : int.parse(token);
  switch (c.name) {
    case 'ALLOC':
      c.pointers = int.parse(tokens[1]);
      c.data = int.parse(tokens[2]);
    case 'PUSH':
      c.source = source(tokens[1]);
    case 'LOAD':
      c.slot = int.parse(tokens[1]);
      c.field = int.parse(tokens[2]);
    case 'POP':
      c.count = int.parse(tokens[1]);
    case 'SET':
      c.slot = int.parse(tokens[1]);
      c.field = int.parse(tokens[2]);
      c.source = source(tokens[3]);
    case 'OVERWRITE':
      c.slot = int.parse(tokens[1]);
      c.source = source(tokens[2]);
    case 'CHECKPOINT':
      c.label = tokens[1];
  }
  if (c.name == 'ALLOC' && (c.pointers > 6 || c.data > 24) ||
      c.name == 'POP' && c.count == 0)
    return (null, 'range');
  return (c, null);
}
