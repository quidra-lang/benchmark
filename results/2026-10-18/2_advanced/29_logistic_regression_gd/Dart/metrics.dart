class Fraction {
  final int a, b;
  Fraction(this.a, this.b);
  double get value => a / b;
  String text() {
    final d = a.gcd(b);
    return '${a ~/ d}/${b ~/ d} ${ratio(a, b)}';
  }
}

String fixed(double value, int places) {
  final text = value.toStringAsFixed(places);
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

String ratio(int a, int b) {
  if (b == 0) return '-';
  final q = (20000 * a + b) ~/ (2 * b);
  return '${q ~/ 10000}.${(q % 10000).toString().padLeft(4, '0')}';
}

class Confusion {
  int tp = 0, fp = 0, tn = 0, fn = 0;
  Confusion(List<int> prediction, List<int> targets) {
    for (var i = 0; i < prediction.length; i++) {
      if (prediction[i] == 1 && targets[i] == 1) {
        tp++;
      } else if (prediction[i] == 1) {
        fp++;
      } else if (targets[i] == 0) {
        tn++;
      } else {
        fn++;
      }
    }
  }
}

List<int> ordered(List<double> values, bool descending) =>
    List.generate(values.length, (i) => i)..sort((a, b) {
      var order = values[a].compareTo(values[b]);
      if (descending) order = -order;
      return order == 0 ? a.compareTo(b) : order;
    });
Fraction auc(List<double> scores, List<int> y) {
  final order = ordered(scores, false),
      positives = y.fold(0, (sum, value) => sum + value);
  var ranks = 0;
  for (var start = 0; start < order.length;) {
    var end = start;
    while (end + 1 < order.length &&
        scores[order[end + 1]] == scores[order[start]]) {
      end++;
    }
    for (var i = start; i <= end; i++) {
      if (y[order[i]] == 1) ranks += start + end + 2;
    }
    start = end + 1;
  }
  return Fraction(
    ranks - positives * (positives + 1),
    2 * positives * (y.length - positives),
  );
}

class RocPoint {
  final double threshold;
  final int tp, fp;
  RocPoint(this.threshold, this.tp, this.fp);
}

List<RocPoint> rocPoints(List<double> probabilities, List<int> targets) {
  final order = ordered(probabilities, true), points = <RocPoint>[];
  var tp = 0, fp = 0;
  for (var i = 0; i < order.length; i++) {
    final j = order[i];
    if (targets[j] == 1) {
      tp++;
    } else {
      fp++;
    }
    if (i + 1 == order.length ||
        probabilities[order[i + 1]] != probabilities[j])
      points.add(RocPoint(probabilities[j], tp, fp));
  }
  return points;
}
