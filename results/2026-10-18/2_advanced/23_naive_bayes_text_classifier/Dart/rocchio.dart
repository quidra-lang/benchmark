import 'dart:math' as math;
import 'naive_bayes.dart';

class SparseValue {
  final int term;
  final double value;
  SparseValue(this.term, this.value);
}
double vectorLength(List<SparseValue> values) {
  var total = 0.0;
  for (final value in values) {
    total += value.value * value.value;
  }
  return math.sqrt(total);
}

class Rocchio {
  final List<double> idf;
  final List<List<double>> centroids;
  final List<double> lengths;
  Rocchio(List<List<int>> sequences, List<int> labels, int classCount, List<int> frequencies)
      : idf = [for (final frequency in frequencies) math.log(sequences.length / frequency)],
        centroids = List.generate(classCount, (_) => List.filled(frequencies.length, 0.0)),
        lengths = List.filled(classCount, 0.0) {
    final documents = List.filled(classCount, 0);
    for (var i = 0; i < sequences.length; i++) {
      final label = labels[i];
      documents[label]++;
      final values = vector(sequences[i]);
      final length = vectorLength(values);
      if (length > 0) {
        for (final value in values) {
          centroids[label][value.term] += value.value / length;
        }
      }
    }
    for (var label = 0; label < classCount; label++) {
      var total = 0.0;
      for (var term = 0; term < frequencies.length; term++) {
        centroids[label][term] /= documents[label];
        total += centroids[label][term] * centroids[label][term];
      }
      lengths[label] = math.sqrt(total);
    }
  }

  List<SparseValue> vector(List<int> sequence) {
    final frequencies = <int, int>{};
    for (final term in sequence) {
      frequencies[term] = (frequencies[term] ?? 0) + 1;
    }
    final terms = frequencies.keys.toList()..sort();
    return [for (final term in terms) SparseValue(term, frequencies[term]! * idf[term])];
  }
  Prediction predict(List<int> sequence) {
    final values = vector(sequence);
    final length = vectorLength(values);
    final similarities = List.filled(centroids.length, 0.0);
    for (var label = 0; label < centroids.length; label++) {
      if (length <= 0 || lengths[label] <= 0) continue;
      var product = 0.0;
      for (final value in values) {
        product += value.value * centroids[label][value.term];
      }
      similarities[label] = product / (length * lengths[label]);
    }
    final ranking = classRanking(similarities);
    return Prediction(ranking[0], similarities[ranking[0]], ranking: ranking);
  }
}
