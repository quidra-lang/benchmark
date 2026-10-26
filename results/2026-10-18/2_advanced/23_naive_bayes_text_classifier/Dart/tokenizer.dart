class Tokens {
  final List<String> words = [];
  late List<String> bigrams;
  late List<String> bigramTerms;
  var raw = 0;
  var stopwords = 0;
  var short = 0;
  Tokens(String text, Set<String> stops) {
    for (final match in RegExp(r'[a-z0-9]+').allMatches(text.toLowerCase())) {
      final word = match.group(0)!;
      raw++;
      if (stops.contains(word)) {
        stopwords++;
      } else if (word.length == 1) {
        short++;
      } else {
        words.add(word);
      }
    }
    bigrams = [for (var i = 0; i + 1 < words.length; i++) '${words[i]}_${words[i + 1]}'];
    bigramTerms = [...words, ...bigrams];
  }
  List<String> terms(bool useBigrams) => useBigrams ? bigramTerms : words;
}
bool isBigram(String term) => term.contains('_');
