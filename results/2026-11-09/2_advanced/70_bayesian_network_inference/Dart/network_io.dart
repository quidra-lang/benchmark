part of 'main.dart';

class Variable {
  final String name;
  final List<String> states;
  final List<int> parents = [];
  List<List<double>> given = [], learned = [], theta = [];
  List<List<int>> counts = [];
  String source = '';
  Variable(this.name, this.states);
}

class Settings {
  double alpha = 0;
  String method = '';
  final List<int> order = [];
  int enumeration = 0, seed = 0;
}

class Network {
  final List<Variable> variables = [];
  final List<List<int>> samples = [];
  final List<String> queries = [];
  final Settings settings = Settings();
  final Map<String, int> names = {};
}

Network readInput() {
  final n = Network(),
      lines = File('input/network.txt')
          .readAsLinesSync()
          .where((s) => s.isNotEmpty && !s.startsWith('#'))
          .toList();
  for (var pos = 0; pos < lines.length; pos++) {
    final a = lines[pos].split(' ');
    switch (a[0]) {
      case 'VARIABLE':
        n.names[a[1]] = n.variables.length;
        n.variables.add(Variable(a[1], a.skip(2).toList()));
        break;
      case 'PARENTS':
        n.variables[n.names[a[1]]!].parents.addAll(
          a.skip(2).map((s) => n.names[s]!),
        );
        break;
      case 'CPT':
        final v = n.names[a[1]]!,
            rows = assignmentCount(n.variables[n.names[a[1]]!].parents, n);
        for (var r = 0; r < rows; r++) {
          pos++;
          n.variables[v].given.add(
            lines[pos].split(' ').map(double.parse).toList(),
          );
        }
        break;
    }
  }
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'PSEUDOCOUNT':
        n.settings.alpha = double.parse(a[1]);
        break;
      case 'ELIMINATION':
        n.settings.method = a[1].toLowerCase();
        break;
      case 'ORDER':
        n.settings.order.addAll(a.skip(1).map((s) => n.names[s]!));
        break;
      case 'ENUMERATION_LIMIT':
        n.settings.enumeration = int.parse(a[1]);
        break;
      case 'SEED':
        n.settings.seed = int.parse(a[1]);
        break;
      case 'SOURCE':
        n.variables[n.names[a[1]]!].source = a[2];
        break;
    }
  }
  final sampleLines = File('input/samples.csv').readAsLinesSync(),
      header = sampleLines.first.split(',');
  for (final line in sampleLines.skip(1)) {
    final values = line.split(','), a = List.filled(n.variables.length, 0);
    for (var col = 0; col < header.length; col++) {
      final v = n.names[header[col]]!;
      a[v] = n.variables[v].states.indexOf(values[col]);
    }
    n.samples.add(a);
  }
  n.queries.addAll(File('input/queries.txt').readAsLinesSync());
  return n;
}
