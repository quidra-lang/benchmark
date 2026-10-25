import 'dart:io';

const controlConstants = <List<double>>[
  [1.880,2.659,0,3.267,0,3.267,1.128,0.7979], [1.023,1.954,0,2.568,0,2.574,1.693,0.8862],
  [0.729,1.628,0,2.266,0,2.282,2.059,0.9213], [0.577,1.427,0,2.089,0,2.114,2.326,0.9400],
  [0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515], [0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594],
  [0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650], [0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693],
  [0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727]
];

class Settings {
  final Map<String, String> fields;
  final Map<String, List<int>> rules;
  Settings(this.fields, this.rules);
  factory Settings.read() {
    final fields = <String, String>{}, rules = <String, List<int>>{};
    for (final line in File('input/spec.txt').readAsLinesSync()) {
      final words = line.split(' ');
      if (words[0] == 'rules') { rules[words[1]] = words.skip(2).map(int.parse).toList(); } else { fields[words[0]] = words[1]; }
    }
    return Settings(fields, rules);
  }
  String get characteristic => fields['characteristic']!;
  int get lsl => int.parse(fields['lsl']!);
  int get usl => int.parse(fields['usl']!);
  int get target => int.parse(fields['target']!);
  int get size => int.parse(fields['subgroup_size']!);
  int get phase1 => int.parse(fields['phase1_subgroups']!);
  int get passes => int.parse(fields['max_passes']!);
  double get cusumK => double.parse(fields['cusum_k']!);
  double get cusumH => double.parse(fields['cusum_h']!);
  double get lambda => double.parse(fields['ewma_lambda']!);
  double get ewmaL => double.parse(fields['ewma_l']!);
  int get span => int.parse(fields['ma_span']!);
  int get gap => int.parse(fields['event_gap']!);
  double get ciZ => double.parse(fields['ci_z']!);
  int get bin => int.parse(fields['histogram_bin']!);
  int get window => int.parse(fields['rolling_window']!);
  int get step => int.parse(fields['rolling_step']!);
}

class Lot {
  final int number, inspected, defectives, defects;
  Lot(List<int> fields) : number = fields[0], inspected = fields[1], defectives = fields[2], defects = fields[3];
}

List<List<int>> readRows(String name) => File('input/$name').readAsLinesSync().skip(1).map((line) => line.split(',').map(int.parse).toList()).toList();
List<int> readMeasurements() => readRows('measurements.csv').map((row) => row[2]).toList();
List<Lot> readAttributes() => readRows('attributes.csv').map(Lot.new).toList();
