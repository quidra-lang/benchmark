import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

record CandidateLevel(int joined, int excluded, int pruned, List<Itemset> itemsets) {}
final class Apriori {
    static List<Itemset> smallerSubsets(Itemset itemset) {
        List<Itemset> result = new ArrayList<>();
        for (int j = 0; j < itemset.size(); j++) {
            List<String> subset = new ArrayList<>(itemset.items()); subset.remove(j); result.add(new Itemset(subset));
        }
        return result;
    }
    static CandidateLevel generate(List<Itemset> previous, int size, Map<String, String> taxonomy) {
        List<Itemset> ordered = previous.stream().sorted().toList(), survivors = new ArrayList<>();
        Set<Itemset> known = new HashSet<>(previous);
        int joined = 0, excluded = 0, pruned = 0;
        for (int i = 0; i < ordered.size(); i++) for (int j = i + 1; j < ordered.size(); j++) {
            List<String> first = ordered.get(i).items(), second = ordered.get(j).items();
            if (!first.subList(0, size - 2).equals(second.subList(0, size - 2))) break;
            List<String> items = new ArrayList<>(first); items.add(second.getLast()); Itemset candidate = new Itemset(items); joined++;
            if (taxonomy != null && size == 2 && (second.getFirst().equals(taxonomy.get(first.getFirst())) || first.getFirst().equals(taxonomy.get(second.getFirst())))) { excluded++; continue; }
            if (smallerSubsets(candidate).stream().anyMatch(subset -> !known.contains(subset))) pruned++;
            else survivors.add(candidate);
        }
        return new CandidateLevel(joined, excluded, pruned, survivors);
    }
    static long countSupport(List<Itemset> baskets, Itemset itemset) { return baskets.stream().filter(basket -> basket.contains(itemset)).count(); }
    static Map<Itemset, Long> countSupports(List<Itemset> baskets, List<Itemset> candidates) {
        Map<Itemset, Long> counts = new TreeMap<>(); Map<String, List<Itemset>> byFirst = new TreeMap<>();
        for (Itemset candidate : candidates) if (counts.putIfAbsent(candidate, 0L) == null) byFirst.computeIfAbsent(candidate.items().getFirst(), _ -> new ArrayList<>()).add(candidate);
        for (Itemset basket : baskets) for (String item : basket.items()) for (Itemset candidate : byFirst.getOrDefault(item, List.of())) if (basket.contains(candidate)) counts.merge(candidate, 1L, Long::sum);
        return counts;
    }
}
