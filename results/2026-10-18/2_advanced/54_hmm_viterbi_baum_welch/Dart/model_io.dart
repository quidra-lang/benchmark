part of 'main.dart';

class Model {
  final String name;
  final List<String> states, symbols;
  final String missing;
  final List<double> initial;
  final List<List<double>> transition, emission;
  Model(
    this.name,
    this.states,
    this.symbols,
    this.missing,
    List<double> initial,
    List<List<double>> transition,
    List<List<double>> emission,
  ) : initial = normalize(initial),
      transition = transition.map(normalize).toList(),
      emission = emission.map(normalize).toList();
}

class RawRecord {
  final String name, role, observation, labels;
  final int line;
  RawRecord(
    this.name,
    this.observation,
    this.line, {
    this.role = '',
    this.labels = '',
  });
}

class RawInputs {
  final Model initial;
  final List<RawRecord> sequences, labeled;
  final Map<String, List<String>> params;
  RawInputs(this.initial, this.sequences, this.labeled, this.params);
}

double sum(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total;
}

List<double> normalize(List<double> values) {
  final total = sum(values);
  return [for (final value in values) value / total];
}

List<List<double>> matrix(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, 0.0));
Model newModel(
  String name,
  Model template,
  List<double> initial,
  List<List<double>> transition,
  List<List<double>> emission,
) => Model(
  name,
  template.states,
  template.symbols,
  template.missing,
  initial,
  transition,
  emission,
);
List<String> readLines(String path) => File(path).readAsLinesSync();
RawInputs readInputs() {
  var lines = readLines('input/model.txt');
  final states = lines[0].split(' ').sublist(1),
      symbols = lines[1].split(' ').sublist(1),
      missing = lines[2].split(' ')[1],
      initial = lines[3].split(' ').skip(1).map(double.parse).toList(),
      transition = <List<double>>[],
      emission = <List<double>>[];
  for (var i = 0; i < states.length; i++) {
    transition.add(lines[4 + i].split(' ').skip(2).map(double.parse).toList());
    emission.add(
      lines[4 + states.length + i]
          .split(' ')
          .skip(2)
          .map(double.parse)
          .toList(),
    );
  }
  final model = Model(
        'INITIAL',
        states,
        symbols,
        missing,
        initial,
        transition,
        emission,
      ),
      sequences = <RawRecord>[],
      labeled = <RawRecord>[],
      params = <String, List<String>>{};
  lines = readLines('input/sequences.txt');
  for (var i = 0; i < lines.length; i++) {
    final f = lines[i].split(' ');
    sequences.add(RawRecord(f[0], f[1], i + 1));
  }
  lines = readLines('input/labeled.txt');
  for (var i = 0; i < lines.length; i += 2) {
    final f = lines[i].split(' ');
    labeled.add(RawRecord(f[0], f[2], i + 1, role: f[1], labels: lines[i + 1]));
  }
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    params[f.first] = f.sublist(1);
  }
  return RawInputs(model, sequences, labeled, params);
}

String numberDigits(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

String number(double value) => numberDigits(value, 4);
String numberList(List<double> values) => values.map(number).join(' ');
List<String> modelLines(Model model) => [
  'MODEL ${model.name}',
  'STATES ${model.states.join(' ')}',
  'SYMBOLS ${model.symbols.join(' ')}',
  'MISSING ${model.missing}',
  'INITIAL ${numberList(model.initial)}',
  for (var i = 0; i < model.states.length; i++)
    'TRANSITION ${model.states[i]} ${numberList(model.transition[i])}',
  for (var i = 0; i < model.states.length; i++)
    'EMISSION ${model.states[i]} ${numberList(model.emission[i])}',
];
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
