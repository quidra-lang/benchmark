import 'dart:math' as math;
import 'vocabulary.dart';

class TrainingCounts {
  final int classCount;
  final int size;
  final int documentTotal;
  final List<int> documents;
  final List<List<int>> occurrences;
  final List<List<int>> containing;
  final List<int> totals;
  final List<int> termTotals;
  var total = 0;
  TrainingCounts(List<List<int>> sequences, List<int> labels, this.classCount, this.size)
      : documentTotal = sequences.length,
        documents = List.filled(classCount, 0), totals = List.filled(classCount, 0),
        termTotals = List.filled(size, 0),
        occurrences = List.generate(classCount, (_) => List.filled(size, 0)),
        containing = List.generate(classCount, (_) => List.filled(size, 0)) {
    for (var i = 0; i < sequences.length; i++) {
      final label = labels[i];
      documents[label]++;
      for (final term in sequences[i]) {
        occurrences[label][term]++;
      }
      for (final term in firstOccurrences(sequences[i])) {
        containing[label][term]++;
      }
    }
    for (var label = 0; label < classCount; label++) {
      for (var term = 0; term < size; term++) {
        totals[label] += occurrences[label][term];
        termTotals[term] += occurrences[label][term];
      }
      total += totals[label];
    }
  }
}

double smoothedLog(num count, num total, int alpha, int outcomes) =>
    math.log((100 * count + alpha) / (100 * total + alpha * outcomes));
List<int> classRanking(List<double> scores) =>
    List.generate(scores.length, (i) => i)..sort((a, b) {
      final compared = scores[b].compareTo(scores[a]);
      return compared != 0 ? compared : a.compareTo(b);
    });

class Prediction {
  final int label;
  final double score;
  final List<int> ranking;
  final List<double> scores;
  final List<double> probabilities;
  final double normalizer;
  final double margin;
  final int runnerUp;
  Prediction(this.label, this.score, {this.ranking = const [], this.scores = const [],
    this.probabilities = const [], this.normalizer = 0, this.margin = 0, this.runnerUp = 0});
}

Prediction posterior(List<double> scores) {
  final ranking = classRanking(scores);
  final label = ranking[0];
  final best = scores[label];
  final exponentials = [for (final score in scores) math.exp(score - best)];
  var normalizer = 0.0;
  for (final value in exponentials) {
    normalizer += value;
  }
  final probabilities = [for (final value in exponentials) value / normalizer];
  return Prediction(label, probabilities[label], ranking: ranking, scores: scores,
    probabilities: probabilities, normalizer: normalizer,
    margin: best - scores[ranking[1]], runnerUp: ranking[1]);
}

class NaiveBayes {
  final int kind;
  final List<double> priors;
  final List<double> base;
  final List<List<double>> weights;
  NaiveBayes(this.kind, this.priors, this.base, this.weights);
  Prediction predict(List<int> sequence) {
    final terms = kind == 1 ? firstOccurrences(sequence) : sequence;
    final scores = <double>[];
    for (var label = 0; label < weights.length; label++) {
      var score = base[label];
      for (final term in terms) {
        score += weights[label][term];
      }
      scores.add(score + priors[label]);
    }
    return posterior(scores);
  }
}

NaiveBayes trainModel(int kind, TrainingCounts counts, int alpha) {
  final priors = [for (final count in counts.documents) math.log(count / counts.documentTotal)];
  final base = List.filled(counts.classCount, 0.0);
  final weights = List.generate(counts.classCount, (_) => List.filled(counts.size, 0.0));
  for (var label = 0; label < counts.classCount; label++) {
    for (var term = 0; term < counts.size; term++) {
      if (kind == 0) {
        weights[label][term] = smoothedLog(counts.occurrences[label][term], counts.totals[label], alpha, counts.size);
      } else if (kind == 1) {
        final present = smoothedLog(counts.containing[label][term], counts.documents[label], alpha, 2);
        final absent = smoothedLog(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2);
        base[label] += absent;
        weights[label][term] = present - absent;
      } else {
        weights[label][term] = -smoothedLog(counts.termTotals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.size);
      }
    }
  }
  return NaiveBayes(kind, priors, base, weights);
}
