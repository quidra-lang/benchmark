part of 'main.dart';

const settingNames = [
  'layering',
  'width',
  'promotion',
  'heuristic',
  'sweeps',
  'node_sep',
  'dummy_sep',
  'layer_gap',
  'direction',
  'sifting',
  'reduce',
  'restarts',
  'seed',
];

class Settings {
  String layering = 'longest',
      promotion = 'off',
      heuristic = 'barycenter',
      direction = 'TB',
      sifting = 'off',
      reduce = 'off';
  int width = 4,
      sweeps = 12,
      nodeSep = 2,
      dummySep = 1,
      layerGap = 3,
      restarts = 0,
      seed = 1;
  Settings();
  Settings.from(Settings s)
    : layering = s.layering,
      promotion = s.promotion,
      heuristic = s.heuristic,
      direction = s.direction,
      sifting = s.sifting,
      reduce = s.reduce,
      width = s.width,
      sweeps = s.sweeps,
      nodeSep = s.nodeSep,
      dummySep = s.dummySep,
      layerGap = s.layerGap,
      restarts = s.restarts,
      seed = s.seed;
  List<String> values() => [
    layering,
    '$width',
    promotion,
    heuristic,
    '$sweeps',
    '$nodeSep',
    '$dummySep',
    '$layerGap',
    direction,
    sifting,
    reduce,
    '$restarts',
    '$seed',
  ];
  bool set(String name, String value) {
    const options = {
      'layering': ['longest', 'coffman'],
      'promotion': ['on', 'off'],
      'heuristic': ['barycenter', 'median'],
      'direction': ['TB', 'BT', 'LR', 'RL'],
      'sifting': ['on', 'off'],
      'reduce': ['on', 'off'],
    };
    final choices = options[name];
    if (choices != null) {
      if (!choices.contains(value)) return false;
      switch (name) {
        case 'layering':
          layering = value;
          break;
        case 'promotion':
          promotion = value;
          break;
        case 'heuristic':
          heuristic = value;
          break;
        case 'direction':
          direction = value;
          break;
        case 'sifting':
          sifting = value;
          break;
        case 'reduce':
          reduce = value;
          break;
      }
      return true;
    }
    const ranges = {
      'width': (1, 40),
      'sweeps': (0, 50),
      'node_sep': (1, 9),
      'dummy_sep': (1, 9),
      'layer_gap': (2, 9),
      'restarts': (0, 9),
      'seed': (1, 2147483646),
    };
    final bounds = ranges[name];
    if (bounds == null || !integerWord.hasMatch(value)) return false;
    final number = int.parse(value);
    if (number < bounds.$1 || number > bounds.$2) return false;
    switch (name) {
      case 'width':
        width = number;
        break;
      case 'sweeps':
        sweeps = number;
        break;
      case 'node_sep':
        nodeSep = number;
        break;
      case 'dummy_sep':
        dummySep = number;
        break;
      case 'layer_gap':
        layerGap = number;
        break;
      case 'restarts':
        restarts = number;
        break;
      case 'seed':
        seed = number;
        break;
    }
    return true;
  }
}

final integerWord = RegExp(r'^[0-9]{1,10}$');

class NodeData {
  final int id;
  final String label;
  NodeData(this.id, this.label);
}

class RawEdge {
  final int from, to;
  RawEdge(this.from, this.to);
}

class Block {
  final String name;
  final Settings settings;
  final List<NodeData> nodes = [];
  final List<RawEdge> edges = [];
  bool hasPath = false;
  int pathFrom = 0, pathTo = 0, selfLoops = 0, duplicates = 0, errorLine = 0;
  String error = '';
  Block(this.name, this.settings);
}

List<Block> readBlocks() {
  final defaults = Settings();
  for (final line in lines('input/params.txt')) {
    if (ignored(line)) continue;
    final a = line.split(' ');
    defaults.set(a[0], a[1]);
  }
  final out = <Block>[];
  Block? current;
  var declared = <int>{}, accepted = <(int, int)>{};
  final source = lines('input/graphs.txt');
  for (var index = 0; index < source.length; index++) {
    final line = source[index];
    if (ignored(line)) continue;
    final a = line.split(' ');
    if (a[0] == 'GRAPH') {
      current = Block(a[1], Settings.from(defaults));
      out.add(current);
      declared = {};
      accepted = {};
      continue;
    }
    final block = current!;
    if (block.error.isNotEmpty) continue;
    var reason = '';
    switch (a[0]) {
      case 'OPTION':
        if (!block.settings.set(a[1], a[2])) reason = 'bad_option';
        break;
      case 'NODE':
        {
          final id = int.parse(a[1]);
          if (declared.contains(id)) {
            reason = 'duplicate_node';
          } else if (block.nodes.length == 40) {
            reason = 'too_many_nodes';
          } else {
            declared.add(id);
            block.nodes.add(NodeData(id, a[2]));
          }
          break;
        }
      case 'EDGE':
        {
          final from = int.parse(a[1]), to = int.parse(a[2]);
          if (!declared.contains(from) || !declared.contains(to)) {
            reason = 'unknown_node';
          } else if (from == to) {
            block.selfLoops++;
          } else if (accepted.contains((from, to))) {
            block.duplicates++;
          } else {
            accepted.add((from, to));
            block.edges.add(RawEdge(from, to));
          }
          break;
        }
      case 'PATH':
        {
          final from = int.parse(a[1]), to = int.parse(a[2]);
          if (!declared.contains(from) || !declared.contains(to)) {
            reason = 'unknown_node';
          } else {
            block.hasPath = true;
            block.pathFrom = from;
            block.pathTo = to;
          }
          break;
        }
      case 'END':
        if (block.nodes.isEmpty) reason = 'no_nodes';
        break;
    }
    if (reason.isNotEmpty) {
      block.error = reason;
      block.errorLine = index + 1;
    }
  }
  for (final block in out) {
    block.nodes.sort((a, b) => a.id.compareTo(b.id));
  }
  return out;
}

List<String> lines(String path) => File(path).readAsLinesSync();
bool ignored(String s) => s.isEmpty || s.startsWith('#');
