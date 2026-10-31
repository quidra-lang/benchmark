part of 'main.dart';

const classPairs = [(1, 2), (1, 3), (2, 3)];

class MultiPrediction {
  final rest = List.filled(3, 0.0),
      pair = List.filled(3, 0.0),
      votes = List.filled(3, 0);
  int ovr = 0, ovo = 0;
  bool tie = false;
}

class Multiclass {
  final rest = <Model>[], pair = <Model>[];
  MultiPrediction classify(Point point) {
    final out = MultiPrediction(), scores = List.filled(3, 0.0);
    var best = 0;
    for (var i = 0; i < 3; i++) {
      out.rest[i] = rest[i].decision(point);
      if (out.rest[i] > out.rest[best]) best = i;
    }
    out.ovr = best + 1;
    for (var i = 0; i < 3; i++) {
      final h = pair[i].decision(point),
          a = classPairs[i].$1 - 1,
          b = classPairs[i].$2 - 1;
      out.pair[i] = h;
      out.votes[h > 0 ? a : b]++;
      scores[a] += h;
      scores[b] -= h;
    }
    best = 0;
    final maximum = out.votes.reduce(max);
    var ties = 0;
    for (var i = 0; i < 3; i++) {
      if (out.votes[i] == maximum) {
        ties++;
        if (out.votes[best] != maximum || scores[i] > scores[best]) best = i;
      }
    }
    out.ovo = best + 1;
    out.tie = ties > 1;
    return out;
  }
}

Multiclass trainMulticlass(List<Example> data, Kernel k, double c, Params p) {
  final q = kernelMatrix(data, k), out = Multiclass();
  for (var cl = 1; cl <= 3; cl++) {
    final a = data.map((e) => e.withLabel(e.label == cl ? 1 : -1)).toList();
    out.rest.add(train(a, q, k, c, p));
  }
  for (final (a, b) in classPairs) {
    final indices = [
      for (var i = 0; i < data.length; i++)
        if (data[i].label == a || data[i].label == b) i,
    ];
    final (examples, matrix) = subset(data, q, indices);
    final binary = examples
        .map((e) => e.withLabel(e.label == a ? 1 : -1))
        .toList();
    out.pair.add(train(binary, matrix, k, c, p));
  }
  return out;
}
