import 'baskets.dart';

typedef CandidateLevel = ({int joined, int excluded, int pruned, List<Itemset> itemsets});

List<Itemset> oneSmallerSubsets(Itemset items) => [for (var i = 0; i < items.length; i++) [...items.take(i), ...items.skip(i + 1)]];

CandidateLevel generateCandidates(List<Itemset> previous, int size, Map<String, String>? taxonomy) {
  final ordered = [...previous]..sort(compareSets), joined = <Itemset>[];
  for (final (i, first) in ordered.indexed) {
    for (var j = i + 1; j < ordered.length; j++) {
      final second = ordered[j]; if (compareSets(first.sublist(0, first.length - 1), second.sublist(0, second.length - 1)) != 0) break;
      joined.add([...first, second.last]);
    }
  }
  final known = previous.map(setKey).toSet(), survivors = <Itemset>[];
  var excluded = 0, pruned = 0;
  for (final candidate in joined) {
    if (taxonomy != null && size == 2 && (taxonomy[candidate[0]] == candidate[1] || taxonomy[candidate[1]] == candidate[0])) { excluded++; continue; }
    if (oneSmallerSubsets(candidate).any((subset) => !known.contains(setKey(subset)))) { pruned++; } else { survivors.add(candidate); }
  }
  return (joined: joined.length, excluded: excluded, pruned: pruned, itemsets: survivors);
}

Map<String, int> countSupports(List<Set<String>> baskets, List<Itemset> candidates) {
  final counts = <String, int>{}, byFirst = <String, List<Itemset>>{};
  for (final items in candidates) { counts[setKey(items)] = 0; (byFirst[items.first] ??= []).add(items); }
  for (final basket in baskets) {
    for (final item in basket) {
      for (final items in byFirst[item] ?? <Itemset>[]) { if (containsSet(basket, items)) { final key = setKey(items); counts[key] = counts[key]! + 1; } }
    }
  }
  return counts;
}
