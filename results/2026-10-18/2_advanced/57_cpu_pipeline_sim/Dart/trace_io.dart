part of 'main.dart';

class PredictorConfig {
  final String name, scheme;
  final List<int> parameters;
  PredictorConfig(this.name, this.scheme, this.parameters);
}

class Variant {
  final String name, stage;
  final bool forward;
  final int latency;
  Variant(this.name, this.forward, this.stage, this.latency);
  Variant copy({bool? forward, String? stage, int? latency}) => Variant(
    name,
    forward ?? this.forward,
    stage ?? this.stage,
    latency ?? this.latency,
  );
}

class Config {
  int btb = 0, ras = 0, start = 0, end = 0, top = 0, interval = 0;
  String primaryVariant = '', primaryPredictor = '';
  final predictors = <PredictorConfig>[], variants = <Variant>[];
}

List<String> readLines(String path) => File(path).readAsLinesSync();
int? hexValue(String s) {
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(s)) return null;
  return int.parse(s, radix: 16);
}

int? register(String s) {
  if (s == '-') return -1;
  if (!RegExp(r'^r(0|[1-9][0-9]?)$').hasMatch(s)) return null;
  final n = int.parse(s.substring(1));
  return n <= 31 ? n : null;
}

Config readConfig() {
  final c = Config();
  for (final line in readLines('input/config.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'BTB':
        c.btb = int.parse(a[1]);
      case 'RAS':
        c.ras = int.parse(a[1]);
      case 'PREDICTOR':
        c.predictors.add(
          PredictorConfig(a[1], a[2], a.sublist(3).map(int.parse).toList()),
        );
      case 'VARIANT':
        c.variants.add(Variant(a[1], a[2] == 'ON', a[3], int.parse(a[4])));
      case 'PRIMARY':
        c.primaryVariant = a[1];
        c.primaryPredictor = a[2];
      case 'WINDOW':
        c.start = int.parse(a[1]);
        c.end = int.parse(a[2]);
      case 'TOP':
        c.top = int.parse(a[1]);
      case 'INTERVAL':
        c.interval = int.parse(a[1]);
    }
  }
  return c;
}
