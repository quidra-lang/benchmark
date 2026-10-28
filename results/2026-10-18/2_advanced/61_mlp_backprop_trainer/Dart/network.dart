part of 'main.dart';

class Layer {
  final int inputs, units, weights, biases;
  final String activation;
  Layer(this.inputs, this.units, this.activation, this.weights, this.biases);
}

class Forward {
  final activations = <List<double>>[], z = <List<double>>[];
  List<double> scores = [], outputDelta = [];
  double loss = 0, confidence = 0;
  int predicted = 0;
}

class Network {
  final String name;
  final layers = <Layer>[], initial = <double>[], weightIndices = <int>[];
  Network(this.name);
  Forward forward(List<double> theta, Image image) {
    final out = Forward();
    out.activations.add(image.input);
    for (var l = 0; l < layers.length; l++) {
      final layer = layers[l],
          z = preactivations(layer, theta, out.activations[l]);
      out.z.add(z);
      if (l + 1 == layers.length) {
        final (scores, loss, delta) = output(layer.activation, z, image.label);
        out.scores = scores;
        out.loss = loss;
        out.outputDelta = delta;
        out.activations.add(scores);
      } else {
        out.activations.add(
          z.map((v) => activation(layer.activation, v)).toList(),
        );
      }
    }
    out.predicted = prediction(out.scores);
    out.confidence = out.scores[out.predicted];
    return out;
  }

  (List<double>, List<double>, double) gradient(
    List<double> theta,
    Image image,
  ) {
    final f = forward(theta, image),
        deltas = List.generate(layers.length, (_) => <double>[]),
        last = layers.length - 1;
    deltas[last] = f.outputDelta;
    for (var l = last - 1; l >= 0; l--) {
      final layer = layers[l];
      deltas[l] = List.generate(
        layer.units,
        (j) =>
            propagate(layers[l + 1], theta, deltas[l + 1], j) *
            derivative(layer.activation, f.z[l][j], f.activations[l + 1][j]),
      );
    }
    final gradient = List.filled(theta.length, 0.0);
    for (var l = 0; l < layers.length; l++) {
      final layer = layers[l];
      for (var j = 0; j < layer.units; j++) {
        final d = deltas[l][j];
        for (var i = 0; i < layer.inputs; i++) {
          gradient[layer.weights + j * layer.inputs + i] =
              d * f.activations[l][i];
        }
        gradient[layer.biases + j] = d;
      }
    }
    final input = List.generate(
      layers[0].inputs,
      (i) => propagate(layers[0], theta, deltas[0], i),
    );
    return (gradient, input, f.loss);
  }

  (List<double>, double) meanGradient(
    List<double> theta,
    List<Image> data,
    List<int> indices,
  ) {
    final out = List.filled(theta.length, 0.0);
    var loss = 0.0;
    for (final index in indices) {
      final (g, _, v) = gradient(theta, data[index]);
      loss += v;
      for (var p = 0; p < g.length; p++) {
        out[p] += g[p];
      }
    }
    for (var p = 0; p < out.length; p++) {
      out[p] /= indices.length;
    }
    return (out, loss / indices.length);
  }
}
