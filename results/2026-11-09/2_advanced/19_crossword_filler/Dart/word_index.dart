bool validWord(String text) => text.length >= 3 && text.length <= 15 && text.codeUnits.every((letter) => letter >= 65 && letter <= 90);
bool validInteger(String text, int low, int high) {
  if (text.isEmpty || text.startsWith('0') || text.length > high.toString().length || !text.codeUnits.every((digit) => digit >= 48 && digit <= 57)) {
    return false;
  }
  final value = int.parse(text);
  return value >= low && value <= high;
}

String wordLineError(String line) {
  final parts = line.split(' ');
  if (parts.length != 2) {
    return 'bad format';
  }
  if (!validWord(parts.first)) {
    return 'bad word';
  }
  return validInteger(parts[1], 1, 100) ? '' : 'bad score';
}

String clueLineError(String line) {
  final parts = line.split('|');
  if (parts.length != 2) {
    return 'bad format';
  }
  if (!validWord(parts.first)) {
    return 'bad word';
  }
  final clue = parts[1];
  return clue.isNotEmpty && clue.length <= 60 && !clue.startsWith(' ') && !clue.endsWith(' ') ? '' : 'bad clue';
}

bool matches(List<int> word, List<int> pattern) {
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] != 46 && pattern[i] != word[i]) {
      return false;
    }
  }
  return true;
}

class Word {
  final String text;
  final List<int> letters;
  final int score;
  Word(this.text, this.score) : letters = text.codeUnits;
}

class WordIndex {
  final words = <Word>[];
  final lookup = <String, int>{};
  final byLength = <int, List<int>>{};
  final byLetter = <(int, int, int), List<int>>{};
  WordIndex(Map<String, int> scores) {
    final ranked = scores.keys.toList()..sort((a, b) => scores[a] == scores[b] ? a.compareTo(b) : scores[b]!.compareTo(scores[a]!));
    for (final text in ranked) {
      final id = words.length;
      final word = Word(text, scores[text]!);
      words.add(word);
      lookup[text] = id;
      byLength.putIfAbsent(text.length, () => []).add(id);
      for (var position = 0; position < text.length; position++) {
        byLetter.putIfAbsent((text.length, position, word.letters[position]), () => []).add(id);
      }
    }
  }

  List<int> candidates(List<int> pattern, int minimum, List<bool> used) {
    var pool = byLength[pattern.length] ?? <int>[];
    for (var position = 0; position < pattern.length; position++) {
      if (pattern[position] == 46) {
        continue;
      }
      final bucket = byLetter[(pattern.length, position, pattern[position])] ?? <int>[];
      if (bucket.length < pool.length) {
        pool = bucket;
      }
    }
    return pool.takeWhile((id) => words[id].score >= minimum).where((id) => !used[id] && matches(words[id].letters, pattern)).toList();
  }
}
