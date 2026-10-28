part of 'main.dart';

String fixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return s.startsWith('-') && !s.substring(1).contains(RegExp('[1-9]'))
      ? s.substring(1)
      : s;
}

String ratio(int a, int b) {
  if (b == 0) return '-';
  final q = (20000 * a + b) ~/ (2 * b);
  return '${q ~/ 10000}.${(q % 10000).toString().padLeft(4, '0')}';
}

int prediction(List<double> scores) {
  var best = 0;
  for (var k = 1; k < scores.length; k++) {
    if (scores[k] > scores[best]) best = k;
  }
  return best;
}

int second(List<double> scores, int first) {
  var best = -1;
  for (var k = 0; k < scores.length; k++) {
    if (k != first && (best < 0 || scores[k] > scores[best])) best = k;
  }
  return best;
}

List<List<int>> confusion(List<Image> data, List<Forward> results, int k) {
  final out = List.generate(k, (_) => List.filled(k, 0));
  for (var i = 0; i < data.length; i++) {
    out[data[i].label][results[i].predicted]++;
  }
  return out;
}

(int, int, String, String, String) classMetrics(List<List<int>> matrix, int k) {
  var support = 0, predicted = 0;
  for (var j = 0; j < matrix.length; j++) {
    support += matrix[k][j];
    predicted += matrix[j][k];
  }
  final correct = matrix[k][k];
  return (
    support,
    predicted,
    ratio(correct, predicted),
    ratio(correct, support),
    ratio(2 * correct, support + predicted),
  );
}

List<String> levelLines(List<List<int>> levels, int w, int h) => [
  for (var r = 0; r < h; r++)
    [
      for (final values in levels) values.sublist(r * w, (r + 1) * w).join(),
    ].join(' '),
];
List<String> imageLines(Image image, int w, int h) => [
  for (var r = 0; r < h; r++)
    image.pixels
        .substring(r * w, (r + 1) * w)
        .replaceAll('1', '#')
        .replaceAll('0', '.'),
];
