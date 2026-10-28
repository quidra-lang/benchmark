part of 'main.dart';

class Series {
  final String name;
  final periods = <String>[], raw = <double?>[], events = <String, String>{};
  late Policy policy;
  Series(this.name);
}

class Policy {
  final int onHand, lead, review;
  final double service;
  Policy(this.onHand, this.lead, this.review, this.service);
}

class Settings {
  final Map<String, List<String>> fields;
  Settings(this.fields);
  int integer(String key) => int.parse(fields[key]!.first);
  double number(String key) => double.parse(fields[key]!.first);
  List<double> reals(String key) => fields[key]!.map(double.parse).toList();
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(List<Series>, Settings) readInputs() {
  final series = <Series>[], named = <String, Series>{};
  for (final text in readLines('input/series.csv').skip(1)) {
    final fields = text.split(',');
    final record = named.putIfAbsent(fields[0], () {
      final record = Series(fields[0]);
      series.add(record);
      return record;
    });
    record.periods.add(fields[1]);
    record.raw.add(fields[2] == 'NA' ? null : double.parse(fields[2]));
  }
  for (final text in readLines('input/events.csv').skip(1)) {
    final fields = text.split(',');
    named[fields[0]]!.events[fields[1]] = fields[2];
  }
  for (final text in readLines('input/inventory.csv').skip(1)) {
    final fields = text.split(',');
    named[fields[0]]!.policy = Policy(
      int.parse(fields[1]),
      int.parse(fields[2]),
      int.parse(fields[3]),
      double.parse(fields[4]),
    );
  }
  final settings = Settings({
    for (final text in readLines('input/params.txt'))
      text.split(' ').first: text.split(' ').skip(1).toList(),
  });
  return (series, settings);
}

String nextMonth(String period) {
  var year = int.parse(period.substring(0, 4)),
      month = int.parse(period.substring(5));
  year += month ~/ 12;
  month = month % 12 + 1;
  return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

String real(double? value) {
  if (value == null) return 'NA';
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
