part of 'main.dart';

int sign(double v) => v > 0 ? 1 : -1;
String fixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return s.startsWith('-') && !s.substring(1).contains(RegExp('[1-9]'))
      ? s.substring(1)
      : s;
}

String ratio(int a, int b) => b == 0 ? '-' : fixed(a / b, 4);
String yes(bool b) => b ? 'yes' : 'no';
(List<int>, List<int>) folds(int n, int k, int fold) => (
  [
    for (var i = 0; i < n; i++)
      if (i % k != fold) i,
  ],
  [
    for (var i = 0; i < n; i++)
      if (i % k == fold) i,
  ],
);

class TestMetrics {
  int tp = 0, fp = 0, tn = 0, fn = 0, inside = 0;
  double auc = 0, positiveMean = 0, negativeMean = 0;
  int get correct => tp + tn;
}

TestMetrics evaluate(List<Example> data, List<double> values) {
  final out = TestMetrics();
  var positive = 0, negative = 0;
  for (var j = 0; j < data.length; j++) {
    final e = data[j], v = values[j];
    if (e.label == 1) {
      positive++;
      out.positiveMean += v;
      if (sign(v) == 1) {
        out.tp++;
      } else {
        out.fn++;
      }
    } else {
      negative++;
      out.negativeMean += v;
      if (sign(v) == 1) {
        out.fp++;
      } else {
        out.tn++;
      }
    }
    if (v > -1 && v < 1) out.inside++;
  }
  out.positiveMean /= positive;
  out.negativeMean /= negative;
  var sum = 0.0;
  for (var i = 0; i < data.length; i++) {
    if (data[i].label != 1) continue;
    for (var j = 0; j < data.length; j++) {
      if (data[j].label != -1) continue;
      if (values[i] > values[j]) {
        sum++;
      } else if (values[i] == values[j]) {
        sum += .5;
      }
    }
  }
  out.auc = sum / (positive * negative);
  return out;
}

int correct(List<Example> data, List<double> values) {
  var n = 0;
  for (var i = 0; i < data.length; i++) {
    if (sign(values[i]) == data[i].label) n++;
  }
  return n;
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

List<List<int>> confusion(List<Example> data, List<int> predictions) {
  final out = List.generate(3, (_) => List.filled(3, 0));
  for (var i = 0; i < data.length; i++) {
    out[data[i].label - 1][predictions[i] - 1]++;
  }
  return out;
}
