String realText(double value) {
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}
String proportionText(int numerator, int denominator) =>
    '$numerator/$denominator ${realText(numerator / denominator)}';
String fractionText(int numerator, int denominator) {
  if (denominator == 0) return '- -';
  final divisor = numerator.gcd(denominator);
  return proportionText(numerator ~/ divisor, denominator ~/ divisor);
}

class Evaluation {
  final List<List<int>> matrix;
  final int total;
  var correct = 0;
  late double micro;
  late double macro;
  Evaluation(int classCount, List<int> truths, List<int> predictions)
      : matrix = List.generate(classCount, (_) => List.filled(classCount, 0)),
        total = truths.length {
    for (var i = 0; i < truths.length; i++) {
      matrix[truths[i]][predictions[i]]++;
    }
    var sum = 0.0;
    var scored = 0;
    for (var label = 0; label < classCount; label++) {
      correct += matrix[label][label];
      final denominator = predictedCount(label) + support(label);
      if (denominator > 0) {
        sum += (2 * matrix[label][label]) / denominator;
        scored++;
      }
    }
    micro = correct / total;
    macro = sum / scored;
  }
  int support(int label) => matrix[label].fold<int>(0, (sum, count) => sum + count);
  int predictedCount(int label) => matrix.fold<int>(0, (sum, row) => sum + row[label]);
  List<String> lines(List<String> names) {
    final lines = ['true\\predicted ${names.join(' ')}'];
    for (var label = 0; label < names.length; label++) {
      lines.add('${names[label]} ${matrix[label].join(' ')}');
    }
    for (var label = 0; label < names.length; label++) {
      final hits = matrix[label][label];
      final predicted = predictedCount(label);
      final actual = support(label);
      lines.add('class ${names[label]} precision ${fractionText(hits, predicted)} '
          'recall ${fractionText(hits, actual)} f1 ${fractionText(2 * hits, predicted + actual)} support $actual');
    }
    lines.add('micro_f1 ${realText(micro)} macro_f1 ${realText(macro)}');
    return lines;
  }
}
