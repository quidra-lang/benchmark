part of 'main.dart';

class Image {
  final String id, pixels;
  final int label;
  final List<double> input;
  Image(this.id, this.label, this.pixels, [List<double>? input])
    : input =
          input ?? pixels.split('').map((c) => c == '1' ? 1.0 : 0.0).toList();
}

class RunConfig {
  final String name, network, optimizer;
  final double eta, lambda, mu, beta1, beta2, epsilon;
  RunConfig(
    this.name,
    this.network,
    this.optimizer,
    this.eta,
    this.lambda, [
    this.mu = 0,
    this.beta1 = 0,
    this.beta2 = 0,
    this.epsilon = 0,
  ]);
}

class Params {
  int seed = 0,
      batch = 0,
      epochs = 0,
      patience = 0,
      step = 0,
      stride = 0,
      bins = 0;
  double gamma = 0;
  final prune = <int>[], noise = <int>[], runs = <RunConfig>[];
}

List<String> lines(String path) => File(path).readAsLinesSync();
List<Image> readImages(String path) => lines(path).skip(1).map((s) {
  final a = s.split(',');
  return Image(a[0], int.parse(a[1]), a[2]);
}).toList();
(List<Network>, int, int) readNetworks() {
  final a = lines('input/network.txt'),
      header = a.first.split(' '),
      w = int.parse(header[1]),
      h = int.parse(header[2]),
      out = <Network>[];
  for (final line in a.skip(1)) {
    if (line.isEmpty) continue;
    final f = line.split(' ');
    if (f[0] == 'NETWORK') {
      out.add(Network(f[1]));
    } else {
      final n = out.last,
          inputs = n.layers.isEmpty ? w * h : n.layers.last.units,
          units = int.parse(f[1]);
      n.layers.add(
        Layer(
          inputs,
          units,
          f[2],
          n.initial.length,
          n.initial.length + units * inputs,
        ),
      );
      n.initial.addAll(List.filled(units * (inputs + 1), 0));
    }
  }
  final index = {for (final n in out) n.name: n};
  for (final n in out) {
    for (final layer in n.layers) {
      n.weightIndices.addAll([
        for (var p = layer.weights; p < layer.biases; p++) p,
      ]);
    }
  }
  Network? current;
  var offset = 0;
  for (final line in lines('input/weights.txt')) {
    if (line.isEmpty) continue;
    final f = line.split(' ');
    if (f[0] == 'NETWORK') {
      current = index[f[1]]!;
      offset = 0;
    } else if (f[0] == 'W' || f[0] == 'B') {
      for (final s in f.skip(1)) {
        current!.initial[offset++] = double.parse(s);
      }
    }
  }
  return (out, w, h);
}

Params readParams() {
  final p = Params();
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'SEED':
        p.seed = int.parse(a[1]);
      case 'BATCH_SIZE':
        p.batch = int.parse(a[1]);
      case 'MAX_EPOCHS':
        p.epochs = int.parse(a[1]);
      case 'PATIENCE':
        p.patience = int.parse(a[1]);
      case 'LR_STEP':
        p.step = int.parse(a[1]);
        p.gamma = double.parse(a[2]);
      case 'GRADIENT_CHECK_STRIDE':
        p.stride = int.parse(a[1]);
      case 'CALIBRATION_BINS':
        p.bins = int.parse(a[1]);
      case 'PRUNE':
        p.prune.addAll(a.sublist(1).map(int.parse));
      case 'NOISE':
        p.noise.addAll(a.sublist(1).map(int.parse));
      case 'RUN':
        p.runs.add(
          RunConfig(
            a[1],
            a[2],
            a[3],
            double.parse(a[4]),
            double.parse(a[5]),
            a[3] == 'MOMENTUM' ? double.parse(a[6]) : 0,
            a[3] == 'ADAM' ? double.parse(a[6]) : 0,
            a[3] == 'ADAM' ? double.parse(a[7]) : 0,
            a[3] == 'ADAM' ? double.parse(a[8]) : 0,
          ),
        );
    }
  }
  return p;
}

class RNG {
  int state;
  RNG(this.state);
  int next() {
    state = 48271 * state % 2147483647;
    return state;
  }

  void shuffle(List<int> a) {
    for (var i = a.length - 1; i >= 1; i--) {
      final j = next() % (i + 1), temp = a[i];
      a[i] = a[j];
      a[j] = temp;
    }
  }
}
