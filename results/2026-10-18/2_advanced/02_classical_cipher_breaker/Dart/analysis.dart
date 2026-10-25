import 'scoring.dart';

class Trigram {
  final String text;
  final List<int> positions;
  final List<int> gaps;
  final int divisor;
  Trigram(this.text, this.positions, this.gaps, this.divisor);
}

class KasiskiData {
  final List<Trigram> repeats;
  final List<int> gaps;
  KasiskiData(this.repeats, this.gaps);
  int count(int period) => gaps.where((gap) => gap % period == 0).length;
}

List<int> frequencies(String text) {
  final counts = List.filled(26, 0);
  for (final char in text.codeUnits) counts[char - 65]++;
  return counts;
}

int ioc(String text) {
  if (text.length < 2) return 0;
  var sum = 0;
  for (final count in frequencies(text)) sum += count * (count - 1);
  return (100000 * sum) ~/ (text.length * (text.length - 1));
}

String column(String text, int period, int position) {
  final result = StringBuffer();
  for (var i = position; i < text.length; i += period) result.write(text[i]);
  return result.toString();
}

List<int> columnIocs(String text, int period) =>
    List.generate(period, (index) => ioc(column(text, period, index)));

int averageIoc(String text, int period) =>
    columnIocs(text, period).reduce((a, b) => a + b) ~/ period;

int gcd(int a, int b) {
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

KasiskiData kasiski(String text) {
  final positions = <String, List<int>>{};
  for (var i = 0; i + 2 < text.length; i++) {
    final trigram = text.substring(i, i + 3);
    positions.putIfAbsent(trigram, () => []).add(i + 1);
  }
  final keys = positions.keys.toList()..sort();
  final repeats = <Trigram>[];
  final allGaps = <int>[];
  for (final key in keys) {
    final location = positions[key]!;
    if (location.length < 2) continue;
    final gaps = <int>[];
    for (var i = 1; i < location.length; i++) {
      gaps.add(location[i] - location[i - 1]);
    }
    var divisor = 0;
    for (final gap in gaps) divisor = gcd(divisor, gap);
    repeats.add(Trigram(key, location, gaps, divisor));
    allGaps.addAll(gaps);
  }
  return KasiskiData(repeats, allGaps);
}

List<String> periodTable(String text, int maxlen, KasiskiData data) {
  final result = <String>[];
  for (var period = 1; period <= maxlen; period++) {
    final columns = columnIocs(text, period);
    final average = columns.reduce((a, b) => a + b) ~/ period;
    result.add('L=$period ioc=$average kasiski=${data.count(period)} cols=${columns.join(",")}');
  }
  return result;
}

List<String> kasiskiTable(KasiskiData data) {
  final result = <String>[
    'kasiski repeats=${data.repeats.length} spacings=${data.gaps.length}',
  ];
  for (final item in data.repeats) {
    result.add('${item.text} at=${item.positions.join(",")} gaps=${item.gaps.join(",")} gcd=${item.divisor}');
  }
  return result;
}

String topPairs(String text, bool digraphs) {
  final counts = <String, int>{};
  final step = digraphs ? 2 : 1;
  for (var i = 0; i + 1 < text.length; i += step) {
    final pair = text.substring(i, i + 2);
    counts[pair] = (counts[pair] ?? 0) + 1;
  }
  final sorted = counts.keys.toList()
    ..sort((a, b) {
      final compare = counts[b]!.compareTo(counts[a]!);
      return compare != 0 ? compare : a.compareTo(b);
    });
  return sorted.take(10).map((key) => '$key:${counts[key]}').join(' ');
}

String percentage(int count, int total) {
  final tenths = (2000 * count + total) ~/ (2 * total);
  return '${tenths ~/ 10}.${tenths % 10}';
}

List<String> analyze(int job, String source, String text,
    List<int> mono, List<List<int>> bi, int maxlen) {
  final data = kasiski(text);
  final counts = frequencies(text);
  var doubles = 0;
  var pairDoubles = 0;
  for (var i = 0; i + 1 < text.length; i++) {
    if (text[i] == text[i + 1]) {
      doubles++;
      if (i.isEven) pairDoubles++;
    }
  }
  final result = <String>[
    'JOB $job ANALYZE source=$source',
    'letters=${text.length}',
    'ioc=${ioc(text)} mono=${monogram(text, mono)} bigram=${bigram(text, bi)}',
    'doubles=$doubles pair_doubles=$pairDoubles distinct=${counts.where((n) => n > 0).length}',
  ];
  for (var index = 0; index < 26; index++) {
    result.add('${upperLetter(index)} ${counts[index]} ${percentage(counts[index], text.length)}');
  }
  result.add('bigrams ${topPairs(text, false)}');
  result.addAll(periodTable(text, maxlen, data));
  result.addAll(kasiskiTable(data));
  return result;
}
