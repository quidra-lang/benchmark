part of 'main.dart';

String numberDigits(double value, int decimals) {
  final text = value.toStringAsFixed(decimals);
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

String number(double value) => numberDigits(value, 4);
String ratio(int a, int b) => b == 0 ? '-' : number(a / b);
String ratioReal(double a, double b) => b == 0 ? '-' : number(a / b);
int prediction(double score) => score > 0 ? 1 : -1;
(int, int) auc(List<Row> rows, List<double> scores) {
  final positive = <double>[], negative = <double>[];
  for (var i = 0; i < rows.length; i++) {
    (rows[i].label == 1 ? positive : negative).add(scores[i]);
  }
  var wins = 0, ties = 0;
  for (final p in positive) {
    for (final n in negative) {
      if (p > n) {
        wins++;
      } else if (p == n) {
        ties++;
      }
    }
  }
  return (2 * wins + ties, 2 * positive.length * negative.length);
}

List<List<int>> confusion(List<Row> rows, List<int> predictions, int classes) {
  final result = List.generate(classes, (_) => List.filled(classes, 0));
  for (var i = 0; i < rows.length; i++) {
    result[rows[i].label - 1][predictions[i] - 1]++;
  }
  return result;
}

int countAtMost(List<double> margins, double threshold) =>
    margins.where((v) => v <= threshold).length;
String ints(List<int> values) => values.join(' ');
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
