part of 'main.dart';

double activation(String kind, double z) => switch (kind) {
  'TANH' => 1 - 2 / (exp(2 * z) + 1),
  'SIGMOID' => 1 / (1 + exp(-z)),
  _ => z > 0 ? z : 0,
};
double derivative(String kind, double z, double a) => switch (kind) {
  'TANH' => 1 - a * a,
  'SIGMOID' => a * (1 - a),
  _ => z > 0 ? 1 : 0,
};
List<double> preactivations(
  Layer layer,
  List<double> theta,
  List<double> input,
) => List.generate(layer.units, (j) {
  var s = 0.0;
  for (var i = 0; i < input.length; i++) {
    s += theta[layer.weights + j * layer.inputs + i] * input[i];
  }
  return s + theta[layer.biases + j];
});
(List<double>, double, List<double>) output(
  String kind,
  List<double> z,
  int label,
) {
  final k = z.length, scores = List.filled(k, 0.0), delta = List.filled(k, 0.0);
  var loss = 0.0;
  if (kind == 'SOFTMAX') {
    final maximum = z[prediction(z)];
    var sum = 0.0;
    for (var j = 0; j < k; j++) {
      scores[j] = exp(z[j] - maximum);
      sum += scores[j];
    }
    for (var j = 0; j < k; j++) {
      scores[j] /= sum;
      delta[j] = scores[j] - (j == label ? 1 : 0);
    }
    loss = log(sum) - (z[label] - maximum);
  } else {
    for (var j = 0; j < k; j++) {
      scores[j] = 1 / (1 + exp(-z[j]));
      final difference = scores[j] - (j == label ? 1 : 0);
      loss += difference * difference;
      delta[j] = 2 * difference * scores[j] * (1 - scores[j]) / k;
    }
    loss /= k;
  }
  return (scores, loss, delta);
}

double propagate(
  Layer next,
  List<double> theta,
  List<double> nextDelta,
  int unit,
) {
  var s = 0.0;
  for (var k = 0; k < nextDelta.length; k++) {
    s += theta[next.weights + k * next.inputs + unit] * nextDelta[k];
  }
  return s;
}
