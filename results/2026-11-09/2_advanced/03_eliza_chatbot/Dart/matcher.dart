import 'script_loader.dart';

bool wildcard(String element) => element == '*' || element == '#' || element.startsWith('@');
bool wordFits(String element, String word, Map<String, Group> groups) => element == '#' || (element.startsWith('@') ? (groups[element.substring(1)]?.members.contains(word) ?? false) : element == word);

List<List<String>>? matchPattern(List<String> pattern, List<String> words, Map<String, Group> groups) {
  List<List<String>>? search(int position, int start, List<List<String>> bindings) {
    if (position == pattern.length) return start == words.length ? bindings : null;
    final element = pattern[position];
    final ends = element == '*' ? [for (var end = start; end <= words.length; end++) end]
        : start < words.length && wordFits(element, words[start], groups) ? [start + 1] : <int>[];
    for (final end in ends) {
      final result = search(position + 1, end, wildcard(element) ? [...bindings, words.sublist(start, end)] : bindings);
      if (result != null) return result;
    }
    return null;
  }
  return search(0, 0, []);
}

bool patternCovers(List<String> earlier, List<String> later, Map<String, Group> groups) {
  bool covers(String element, String other) {
    if (element == '#') return other != '*';
    if (!element.startsWith('@')) return element == other;
    final members = groups[element.substring(1)]!.members;
    return other.startsWith('@') ? members.containsAll(groups[other.substring(1)]!.members) : members.contains(other);
  }
  bool search(int position, int start) {
    if (position == earlier.length) return start == later.length;
    if (earlier[position] == '*') {
      for (var end = start; end <= later.length; end++) if (search(position + 1, end)) return true;
      return false;
    }
    return start < later.length && covers(earlier[position], later[start]) && search(position + 1, start + 1);
  }
  return search(0, 0);
}
