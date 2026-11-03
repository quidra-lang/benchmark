List<int> firstOccurrences(List<int> sequence) {
  final seen = <int>{};
  return sequence.where(seen.add).toList();
}

double chiSquare(int withTerm, int frequency, int classSize, int total) {
  final b = frequency - withTerm;
  final c = classSize - withTerm;
  final e = total - classSize - b;
  final difference = withTerm * e - b * c;
  final numerator = total * difference * difference;
  final denominator = frequency * (total - frequency) * classSize * (total - classSize);
  return denominator == 0 ? 0 : numerator / denominator;
}

class RankedTerm {
  final String term;
  final int frequency;
  final double score;
  final int bestClass;
  RankedTerm(this.term, this.frequency, this.score, this.bestClass);
}

class Vocabulary {
  late int termCount;
  late int candidateCount;
  late List<RankedTerm> ranking;
  late List<String> terms;
  late Map<String, int> index;
  late List<int> frequencies;
  Vocabulary(List<List<String>> sequences, List<int> labels,
      int classCount, int minDF, int size) {
    final counts = <String, List<int>>{};
    final classSizes = List.filled(classCount, 0);
    for (var i = 0; i < sequences.length; i++) {
      final label = labels[i];
      classSizes[label]++;
      for (final term in sequences[i].toSet()) {
        counts.putIfAbsent(term, () => List.filled(classCount, 0))[label]++;
      }
    }
    termCount = counts.length;
    ranking = [];
    final allTerms = counts.keys.toList()..sort();
    for (final term in allTerms) {
      final row = counts[term]!;
      final frequency = row.fold<int>(0, (sum, value) => sum + value);
      if (frequency < minDF) continue;
      var bestClass = 0;
      var bestScore = chiSquare(row[0], frequency, classSizes[0], sequences.length);
      for (var label = 1; label < classCount; label++) {
        final score = chiSquare(row[label], frequency, classSizes[label], sequences.length);
        if (score > bestScore) {
          bestClass = label;
          bestScore = score;
        }
      }
      ranking.add(RankedTerm(term, frequency, bestScore, bestClass));
    }
    candidateCount = ranking.length;
    ranking.sort((a, b) {
      final compared = b.score.compareTo(a.score);
      return compared != 0 ? compared : a.term.compareTo(b.term);
    });
    if (size > 0 && ranking.length > size) ranking = ranking.sublist(0, size);
    terms = ranking.map((entry) => entry.term).toList()..sort();
    index = {for (var i = 0; i < terms.length; i++) terms[i]: i};
    final df = {for (final entry in ranking) entry.term: entry.frequency};
    frequencies = terms.map((term) => df[term]!).toList();
  }
  List<int> encode(List<String> sequence) => [
    for (final term in sequence) if (index.containsKey(term)) index[term]!
  ];
}
