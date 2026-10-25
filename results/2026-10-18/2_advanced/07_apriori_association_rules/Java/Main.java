import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.IntStream;

public final class Main {
    static String row(Object... parts) { return String.join(" ", Arrays.stream(parts).map(Object::toString).toList()); }
    static String fraction(Fraction value) { return Report.fractionText(value); }
    static String money(long cents) { return Report.money(cents); }
    static String percent(long part, long whole) { return Report.percent(part, whole); }
    static String text(Itemset itemset) { return Report.itemsetText(itemset); }
    static String arrow(Rule rule) { return Report.arrow(rule); }
    static List<Itemset> sizeOrder(Iterable<Itemset> itemsets) {
        List<Itemset> result = new ArrayList<>(); itemsets.forEach(result::add);
        result.sort(Comparator.comparingInt(Itemset::size).thenComparing(Comparator.naturalOrder())); return result;
    }
    static Fraction median(List<Long> values) {
        List<Long> ordered = values.stream().sorted().toList(); int middle = ordered.size() / 2;
        return ordered.size() % 2 == 1 ? new Fraction(ordered.get(middle)) : new Fraction(ordered.get(middle - 1) + ordered.get(middle), 2);
    }
    record Split(Itemset chosen, Itemset rest) {}
    static Split split(Itemset itemset, int mask) {
        List<String> chosen = new ArrayList<>(), rest = new ArrayList<>();
        for (int j = 0; j < itemset.size(); j++) ((mask >> j & 1) != 0 ? chosen : rest).add(itemset.items().get(j));
        return new Split(new Itemset(chosen), new Itemset(rest));
    }
    static final class Params {
        final long support, categorySupport, sequenceSupport, trainSupport, testSupport, negativeExpected;
        final int maximum, splitDay, top, matrix;
        final Fraction confidence, lift, groupLift, negativeLift, trend;
        Params() throws IOException {
            Map<String, String> fields = new HashMap<>();
            for (String line : Files.readAllLines(Path.of("input/params.txt"))) { String[] parts = line.split(" "); fields.put(parts[0], parts[1]); }
            support = integer(fields, "min_support"); categorySupport = integer(fields, "category_min_support"); sequenceSupport = integer(fields, "sequence_min_support");
            trainSupport = integer(fields, "train_min_support"); testSupport = integer(fields, "test_min_support"); negativeExpected = integer(fields, "negative_min_expected");
            maximum = integer(fields, "max_size"); splitDay = integer(fields, "split_day"); top = integer(fields, "recommend_top"); matrix = integer(fields, "matrix_size");
            confidence = parse(fields, "min_confidence"); lift = parse(fields, "min_lift"); groupLift = parse(fields, "group_min_lift"); negativeLift = parse(fields, "negative_max_lift"); trend = parse(fields, "trend_threshold");
        }
        private static int integer(Map<String, String> fields, String key) { return Integer.parseInt(fields.get(key)); }
        private static Fraction parse(Map<String, String> fields, String key) { String[] parts = fields.get(key).split("/"); return new Fraction(Long.parseLong(parts[0]), Long.parseLong(parts[1])); }
    }
    static final class Dataset {
        final List<String> errors = new ArrayList<>();
        final Map<String, Product> products = new TreeMap<>();
        final List<Transaction> transactions = new ArrayList<>();
        int itemRows, transactionLines, adopted, rejected, duplicates;
        void error(String file, int line, String message) { errors.add(file + " line " + line + ": " + message); }
        Dataset() throws IOException {
            List<String[]> records = Baskets.readRecords("items.csv"); itemRows = records.size();
            for (int j = 0; j < records.size(); j++) {
                String[] p = records.get(j); long price = Long.parseLong(p[2]);
                if (products.containsKey(p[0])) error("items.csv", j + 2, "duplicate item " + p[0]);
                else if (price == 0) error("items.csv", j + 2, "bad price 0");
                else products.put(p[0], new Product(p[0], p[1], price));
            }
            records = Baskets.readRecords("transactions.csv"); transactionLines = records.size(); Set<String> known = new HashSet<>();
            for (int j = 0; j < records.size(); j++) {
                String[] p = records.get(j); int day = Integer.parseInt(p[2]); String problem = null;
                if (known.contains(p[0]) && !p[0].equals(transactions.getLast().tid)) problem = row("tid", p[0], "not contiguous");
                else {
                    if (known.add(p[0])) transactions.add(new Transaction(p[0], p[1], day));
                    Transaction current = transactions.getLast();
                    if (!p[1].equals(current.customer)) problem = row("tid", p[0], "customer", p[1], "differs from", current.customer);
                    else if (day != current.day) problem = row("tid", p[0], "day", day, "differs from", current.day);
                    else if (!products.containsKey(p[3])) problem = row("unknown item", p[3]);
                }
                if (problem != null) { error("transactions.csv", j + 2, problem); rejected++; }
                else { adopted++; if (transactions.getLast().add(p[3])) duplicates++; }
            }
        }
    }
    record Level(int number, int candidates, int excluded, int pruned, int counted, List<Itemset> frequent) {}
    static final class AprioriResult {
        final List<Level> levels = new ArrayList<>();
        final Map<Itemset, Long> supports = new TreeMap<>();
        final Map<String, Long> singles = new TreeMap<>();
    }
    static AprioriResult runApriori(List<Itemset> baskets, List<String> universe, long minimum, int maximum, Map<String, String> taxonomy) {
        AprioriResult result = new AprioriResult();
        List<Itemset> candidates = universe.stream().sorted().map(Itemset::of).toList(), previous = List.of();
        for (int size = 1; size <= maximum; size++) {
            CandidateLevel generated = size == 1 ? new CandidateLevel(candidates.size(), 0, 0, candidates) : Apriori.generate(previous, size, taxonomy);
            Map<Itemset, Long> counts = Apriori.countSupports(baskets, generated.itemsets()); List<Itemset> frequent = new ArrayList<>();
            for (var entry : counts.entrySet()) {
                if (size == 1) result.singles.put(entry.getKey().items().getFirst(), entry.getValue());
                if (entry.getValue() >= minimum) { frequent.add(entry.getKey()); result.supports.put(entry.getKey(), entry.getValue()); }
            }
            result.levels.add(new Level(size, generated.joined(), generated.excluded(), generated.pruned(), generated.itemsets().size(), frequent));
            if (frequent.isEmpty()) break; previous = frequent;
        }
        return result;
    }
    static final class Tally {
        long cases, covered, top, hits, baseline;
        void add(String held, List<String> suggestion, List<String> popular) {
            cases++; if (!suggestion.isEmpty()) { covered++; if (suggestion.getFirst().equals(held)) top++; }
            if (suggestion.contains(held)) hits++; if (popular.contains(held)) baseline++;
        }
        String text() { return row("cases", cases, "covered", covered, "hit1", top, "hit", hits, "rate", fraction(new Fraction(hits, cases)), "baseline", baseline, "rate", fraction(new Fraction(baseline, cases))); }
    }
    record Sequence(String first, String second, long customers, long base, Fraction confidence, Fraction lift, Fraction gap) {}
    record Repeat(String item, int customers, int count, long minimum, long maximum, Fraction mean, Fraction median) {}
    record RuleKey(Itemset antecedent, Itemset consequent) {}
    record RuleCheck(Rule rule, long together, long antecedent, Fraction confidence, Fraction lift, String verdict) {}
    record Category(String name, int products, long units, long revenue, long baskets) {}
    record Group(List<String> members, int edges, String core, long revenue) {}
    record Substitute(String first, String second, long together, Fraction expected, Fraction lift) {}
    record Trend(String name, long units, Fraction slope, Fraction relative, String verdict) {}
    record Customer(String id, int baskets, int days, int first, int last, int products, long units, long revenue, String favorite, String segment, List<String> offer) {}
    static final class Analysis {
        final Params p;
        final Dataset data;
        final List<String> names, categories, customers;
        final Map<String, String> taxonomy = new TreeMap<>();
        final List<Transaction> baskets;
        final List<Itemset> sets, extended, train, test;
        final Map<String, List<Transaction>> customerBaskets = new TreeMap<>();
        final Map<String, Map<String, TreeSet<Integer>>> histories = new TreeMap<>();
        final int total, firstDay, lastDay;
        int sequencePairs, weeks;
        long totalRevenue;
        AprioriResult main, categoryRun, trainRun;
        GrowthResult growth;
        RuleSet mainRules, categoryRules;
        List<Rule> trainRules, emerging;
        List<Itemset> closed, maximal, generators = new ArrayList<>(), pairs;
        final Map<String, Long> buyers = new TreeMap<>(), units = new TreeMap<>(), revenue = new TreeMap<>(), heldOut = new TreeMap<>(), heldHits = new TreeMap<>();
        final List<Sequence> sequences = new ArrayList<>();
        final List<Repeat> repeats = new ArrayList<>();
        final List<RuleCheck> checks = new ArrayList<>();
        final Map<Integer, Tally> tallies = new TreeMap<>();
        final Tally overall = new Tally();
        final List<Category> categorySummaries = new ArrayList<>();
        final List<Group> groups = new ArrayList<>();
        final List<Substitute> substitutes = new ArrayList<>();
        final List<Trend> trends = new ArrayList<>();
        final List<Customer> customerSummaries = new ArrayList<>();
        long[] weekBaskets, weekUnits, weekCustomers;
        final Map<String, long[]> series = new TreeMap<>();
        Analysis() throws IOException {
            p = new Params(); data = new Dataset(); names = new ArrayList<>(data.products.keySet());
            data.products.forEach((name, product) -> taxonomy.put(name, product.category())); categories = taxonomy.values().stream().distinct().sorted().toList();
            baskets = data.transactions.stream().filter(transaction -> !transaction.counts.isEmpty()).toList(); total = baskets.size();
            sets = baskets.stream().map(Transaction::products).toList(); extended = sets.stream().map(basket -> Baskets.extended(basket, taxonomy)).toList();
            train = baskets.stream().filter(basket -> basket.day <= p.splitDay).map(Transaction::products).toList(); test = baskets.stream().filter(basket -> basket.day > p.splitDay).map(Transaction::products).toList();
            firstDay = baskets.stream().mapToInt(basket -> basket.day).min().orElseThrow(); lastDay = baskets.stream().mapToInt(basket -> basket.day).max().orElseThrow();
            for (Transaction basket : baskets) {
                customerBaskets.computeIfAbsent(basket.customer, _ -> new ArrayList<>()).add(basket);
                Map<String, TreeSet<Integer>> history = histories.computeIfAbsent(basket.customer, _ -> new TreeMap<>());
                for (String item : basket.counts.keySet()) history.computeIfAbsent(item, _ -> new TreeSet<>()).add(basket.day);
            }
            customers = new ArrayList<>(customerBaskets.keySet());
        }
        RuleSet makeRules(Map<Itemset, Long> supports, int count, Set<String> required) {
            RuleSet result = new RuleSet();
            for (var entry : supports.entrySet()) {
                Itemset z = entry.getKey();
                if (z.size() < 2 || required != null && z.items().stream().noneMatch(required::contains)) continue;
                for (int mask = 1; mask < (1 << z.size()) - 1; mask++) {
                    Split parts = split(z, mask); result.generated++;
                    Rule rule = new Rule(z, parts.chosen, parts.rest, entry.getValue(), count, supports.get(parts.chosen), supports.get(parts.rest));
                    if (!Rules.meets(rule.confidence, rule.lift, p.confidence, p.lift)) continue;
                    Fraction reference = new Fraction();
                    for (int subset = 0; subset < (1 << parts.chosen.size()) - 1; subset++) {
                        Itemset w = split(parts.chosen, subset).chosen;
                        Fraction confidence = new Fraction(supports.get(w.union(parts.rest)), w.size() == 0 ? count : supports.get(w));
                        if (confidence.compareTo(reference) > 0) reference = confidence;
                    }
                    rule.improvement = rule.confidence.subtract(reference); if (rule.improvement.numerator() > 0) result.productive++;
                    result.rules.add(rule);
                }
            }
            result.rules.sort(Rules::compare); for (int j = 0; j < result.rules.size(); j++) result.rules.get(j).rank = j + 1; return result;
        }
        static List<String> recommend(Itemset held, List<String> candidates, int limit) {
            List<String> selected = new ArrayList<>();
            for (String item : candidates) { if (selected.size() == limit) break; if (!held.items().contains(item) && !selected.contains(item)) selected.add(item); }
            return selected;
        }
        static List<String> ruleCandidates(List<Rule> rules, Itemset held) { return rules.stream().filter(rule -> rule.consequent.size() == 1 && held.contains(rule.antecedent)).map(rule -> rule.consequent.items().getFirst()).toList(); }
        void frequent() {
            main = runApriori(sets, names, p.support, p.maximum, null); growth = FpGrowth.run(sets, p.support, p.maximum);
            Set<Itemset> closedSet = new HashSet<>(main.supports.keySet()), maximalSet = new HashSet<>(main.supports.keySet());
            pairs = main.supports.keySet().stream().filter(itemset -> itemset.size() == 2).toList();
            for (var entry : main.supports.entrySet()) {
                boolean generator = true;
                for (Itemset subset : Apriori.smallerSubsets(entry.getKey())) {
                    long count = subset.size() == 0 ? total : main.supports.get(subset);
                    if (count <= entry.getValue()) generator = false;
                    if (subset.size() > 0) { maximalSet.remove(subset); if (count == entry.getValue()) closedSet.remove(subset); }
                }
                if (generator) generators.add(entry.getKey());
            }
            closed = sizeOrder(closedSet); maximal = sizeOrder(maximalSet); generators = sizeOrder(generators); mainRules = makeRules(main.supports, total, null);
            List<String> universe = new ArrayList<>(names); universe.addAll(categories);
            categoryRun = runApriori(extended, universe, p.categorySupport, p.maximum, taxonomy); categoryRules = makeRules(categoryRun.supports, total, new HashSet<>(categories));
        }
        void sequential() {
            Map<List<String>, List<Long>> gaps = new HashMap<>(); Map<String, List<Long>> intervals = new TreeMap<>(); Map<String, Integer> repeaters = new TreeMap<>();
            names.forEach(name -> buyers.put(name, 0L));
            for (var history : histories.values()) for (var first : history.entrySet()) {
                buyers.merge(first.getKey(), 1L, Long::sum);
                if (first.getValue().size() >= 2) {
                    repeaters.merge(first.getKey(), 1, Integer::sum); List<Long> found = intervals.computeIfAbsent(first.getKey(), _ -> new ArrayList<>());
                    int previous = first.getValue().first(); for (int day : first.getValue().tailSet(previous, false)) { found.add((long)day - previous); previous = day; }
                }
                for (var second : history.entrySet()) if (first.getValue().first() < second.getValue().last()) {
                    int shortest = 113;
                    for (int a : first.getValue()) for (int b : second.getValue()) if (a < b) shortest = Math.min(shortest, b - a);
                    gaps.computeIfAbsent(List.of(first.getKey(), second.getKey()), _ -> new ArrayList<>()).add((long)shortest);
                }
            }
            sequencePairs = gaps.size();
            for (var entry : gaps.entrySet()) if (entry.getValue().size() >= p.sequenceSupport) {
                String a = entry.getKey().getFirst(), b = entry.getKey().getLast(); int count = entry.getValue().size();
                sequences.add(new Sequence(a, b, count, buyers.get(a), new Fraction(count, buyers.get(a)), Rules.liftOf(customers.size(), count, buyers.get(a), buyers.get(b)), median(entry.getValue())));
            }
            sequences.sort(Comparator.comparingLong(Sequence::customers).reversed().thenComparing(Sequence::confidence, Comparator.reverseOrder()).thenComparing(Sequence::first).thenComparing(Sequence::second));
            for (var entry : intervals.entrySet()) {
                List<Long> values = entry.getValue(); long sum = values.stream().mapToLong(Long::longValue).sum();
                repeats.add(new Repeat(entry.getKey(), repeaters.get(entry.getKey()), values.size(), values.stream().mapToLong(Long::longValue).min().orElseThrow(), values.stream().mapToLong(Long::longValue).max().orElseThrow(), new Fraction(sum, values.size()), median(values)));
            }
            repeats.sort(Comparator.comparing(Repeat::mean).thenComparing(Repeat::item));
        }
        void validate() {
            trainRun = runApriori(train, names, p.trainSupport, p.maximum, null); trainRules = makeRules(trainRun.supports, train.size(), null).rules;
            Set<RuleKey> known = new HashSet<>();
            for (Rule rule : trainRules) {
                known.add(new RuleKey(rule.antecedent, rule.consequent));
                long a = Apriori.countSupport(test, rule.antecedent), b = Apriori.countSupport(test, rule.consequent), c = Apriori.countSupport(test, rule.itemset);
                Fraction confidence = null, lift = null; String verdict = "UNSEEN";
                if (a != 0 && b != 0) { confidence = new Fraction(c, a); lift = Rules.liftOf(test.size(), c, a, b); verdict = Rules.meets(confidence, lift, p.confidence, p.lift) ? "HOLD" : "FAIL"; }
                checks.add(new RuleCheck(rule, c, a, confidence, lift, verdict));
            }
            AprioriResult testRun = runApriori(test, names, p.testSupport, p.maximum, null);
            emerging = makeRules(testRun.supports, test.size(), null).rules.stream().filter(rule -> !known.contains(new RuleKey(rule.antecedent, rule.consequent))).toList();
            List<String> popularity = names.stream().sorted(Comparator.<String>comparingLong(trainRun.singles::get).reversed().thenComparing(Comparator.naturalOrder())).toList();
            names.forEach(name -> { heldOut.put(name, 0L); heldHits.put(name, 0L); });
            for (Itemset basket : test) if (basket.size() >= 2) for (String item : basket.items()) {
                Itemset held = Itemset.of(basket.items().stream().filter(name -> !name.equals(item)).toList());
                List<String> suggestion = recommend(held, ruleCandidates(trainRules, held), p.top), baseline = recommend(held, popularity, p.top);
                tallies.computeIfAbsent(basket.size(), _ -> new Tally()).add(item, suggestion, baseline); overall.add(item, suggestion, baseline);
                heldOut.merge(item, 1L, Long::sum); if (suggestion.contains(item)) heldHits.merge(item, 1L, Long::sum);
            }
        }
        Fraction pairLift(Itemset pair) { return Rules.liftOf(total, main.supports.get(pair), main.singles.get(pair.items().getFirst()), main.singles.get(pair.items().getLast())); }
        void summarizeProducts() {
            names.forEach(name -> units.put(name, 0L));
            for (Transaction basket : baskets) basket.counts.forEach((name, count) -> units.merge(name, count, Long::sum));
            for (String name : names) { revenue.put(name, units.get(name) * data.products.get(name).price()); totalRevenue += revenue.get(name); }
            for (String category : categories) {
                List<String> members = names.stream().filter(name -> taxonomy.get(name).equals(category)).toList();
                categorySummaries.add(new Category(category, members.size(), members.stream().mapToLong(units::get).sum(), members.stream().mapToLong(revenue::get).sum(), categoryRun.singles.get(category)));
            }
            categorySummaries.sort(Comparator.comparingLong(Category::revenue).reversed().thenComparing(Category::name));
            Map<String, List<String>> neighbors = new TreeMap<>(); names.forEach(name -> neighbors.put(name, new ArrayList<>()));
            for (Itemset pair : pairs) if (pairLift(pair).compareTo(p.groupLift) >= 0) { String a = pair.items().getFirst(), b = pair.items().getLast(); neighbors.get(a).add(b); neighbors.get(b).add(a); }
            Set<String> visited = new HashSet<>();
            for (String name : names) if (!visited.contains(name) && !neighbors.get(name).isEmpty()) {
                List<String> members = new ArrayList<>(); Deque<String> stack = new ArrayDeque<>(); stack.push(name); visited.add(name); long sum = 0; int degree = 0;
                while (!stack.isEmpty()) { String item = stack.pop(); members.add(item); sum += revenue.get(item); degree += neighbors.get(item).size(); for (String next : neighbors.get(item)) if (visited.add(next)) stack.push(next); }
                members.sort(Comparator.naturalOrder());
                String core = members.stream().min(Comparator.<String>comparingInt(item -> neighbors.get(item).size()).reversed().thenComparing(Comparator.<String>comparingLong(main.singles::get).reversed()).thenComparing(Comparator.naturalOrder())).orElseThrow();
                groups.add(new Group(members, degree / 2, core, sum));
            }
            groups.sort(Comparator.<Group>comparingInt(group -> group.members.size()).reversed().thenComparing(group -> group.members.getFirst()));
            List<Itemset> singles = main.levels.getFirst().frequent;
            for (int i = 0; i < singles.size(); i++) for (int j = i + 1; j < singles.size(); j++) {
                String a = singles.get(i).items().getFirst(), b = singles.get(j).items().getFirst(); long expected = main.singles.get(a) * main.singles.get(b);
                if (expected < p.negativeExpected * total) continue;
                long together = Apriori.countSupport(sets, Itemset.of(a, b)); Fraction lift = Rules.liftOf(total, together, main.singles.get(a), main.singles.get(b));
                if (lift.compareTo(p.negativeLift) <= 0) substitutes.add(new Substitute(a, b, together, new Fraction(expected, total), lift));
            }
            substitutes.sort(Comparator.comparing(Substitute::lift).thenComparing(Substitute::expected, Comparator.reverseOrder()).thenComparing(Substitute::first).thenComparing(Substitute::second));
        }
        void summarizeTrends() {
            weeks = (lastDay - 1) / 7 + 1; weekBaskets = new long[weeks]; weekUnits = new long[weeks]; weekCustomers = new long[weeks];
            List<Set<String>> weeklyCustomers = new ArrayList<>(); for (int j = 0; j < weeks; j++) weeklyCustomers.add(new HashSet<>());
            categories.forEach(name -> series.put(name, new long[weeks])); names.forEach(name -> series.put(name, new long[weeks]));
            for (Transaction basket : baskets) {
                int week = (basket.day - 1) / 7; weekBaskets[week]++; weekUnits[week] += basket.units(); weeklyCustomers.get(week).add(basket.customer);
                basket.counts.forEach((name, count) -> { series.get(name)[week] += count; series.get(taxonomy.get(name))[week] += count; });
            }
            for (int j = 0; j < weeks; j++) weekCustomers[j] = weeklyCustomers.get(j).size();
            long sumWeeks = 0, sumSquares = 0;
            for (int week = 1; week <= weeks; week++) { sumWeeks += week; sumSquares += week * week; }
            for (var entry : series.entrySet()) {
                long weighted = 0, sum = 0;
                for (int j = 0; j < weeks; j++) { sum += entry.getValue()[j]; weighted += (j + 1) * entry.getValue()[j]; }
                Fraction slope = new Fraction(weeks * weighted - sumWeeks * sum, weeks * sumSquares - sumWeeks * sumWeeks), relative = null;
                String verdict = "NONE";
                if (sum > 0) {
                    relative = slope.multiply(new Fraction(weeks, sum));
                    verdict = relative.compareTo(p.trend) >= 0 ? "RISING" : relative.compareTo(new Fraction(-p.trend.numerator(), p.trend.denominator())) <= 0 ? "FALLING" : "FLAT";
                }
                trends.add(new Trend(entry.getKey(), sum, slope, relative, verdict));
            }
            trends.sort((a, b) -> {
                if ((a.relative == null) != (b.relative == null)) return a.relative == null ? 1 : -1;
                int comparison = a.relative == null ? 0 : b.relative.compareTo(a.relative);
                return comparison == 0 ? a.name.compareTo(b.name) : comparison;
            });
        }
        void summarizeCustomers() {
            for (String id : customers) {
                List<Transaction> found = customerBaskets.get(id); Map<String, TreeSet<Integer>> history = histories.get(id);
                int days = (int)found.stream().mapToInt(basket -> basket.day).distinct().count(), first = found.stream().mapToInt(basket -> basket.day).min().orElseThrow(), last = found.stream().mapToInt(basket -> basket.day).max().orElseThrow();
                long customerUnits = 0, customerRevenue = 0; Map<String, Long> categoryUnits = new TreeMap<>();
                for (Transaction basket : found) for (var entry : basket.counts.entrySet()) {
                    customerUnits += entry.getValue(); customerRevenue += entry.getValue() * data.products.get(entry.getKey()).price();
                    categoryUnits.merge(taxonomy.get(entry.getKey()), entry.getValue(), Long::sum);
                }
                String favorite = categoryUnits.keySet().stream().min(Comparator.<String>comparingLong(categoryUnits::get).reversed().thenComparing(Comparator.naturalOrder())).orElseThrow();
                String segment = first > lastDay - 28 ? "NEW" : found.size() >= 4 && lastDay - last <= 14 ? "LOYAL" : lastDay - last > 28 ? "AT_RISK" : "REGULAR";
                Itemset held = Itemset.of(history.keySet()); List<String> offer = recommend(held, ruleCandidates(mainRules.rules, held), p.top);
                customerSummaries.add(new Customer(id, found.size(), days, first, last, history.size(), customerUnits, customerRevenue, favorite, segment, offer));
            }
        }
        List<String> summaryLines() {
            List<String> lines = new ArrayList<>(data.errors.stream().map(error -> "ERROR " + error).toList());
            lines.add(row("ITEMS rows", data.itemRows, "adopted", names.size(), "categories", categories.size()));
            lines.add(row("TRANSACTIONS lines", data.transactionLines, "adopted", data.adopted, "rejected", data.rejected, "duplicates", data.duplicates, "transactions", data.transactions.size(), "empty", data.transactions.size() - total));
            int largest = sets.stream().mapToInt(Itemset::size).max().orElseThrow(); long sizes = sets.stream().mapToLong(Itemset::size).sum();
            lines.add(row("BASKETS count", total, "customers", customers.size(), "first_day", firstDay, "last_day", lastDay, "average_size", fraction(new Fraction(sizes, total)), "largest", largest));
            for (int size = 1; size <= largest; size++) { long count = 0; for (Itemset basket : sets) if (basket.size() == size) count++; lines.add(row("SIZE", size, "baskets", count, "share", percent(count, total))); }
            lines.add(row("FREQUENT itemsets", main.supports.size(), "closed", closed.size(), "maximal", maximal.size(), "generators", generators.size(), "levels", main.levels.size()));
            boolean match = main.supports.equals(growth.itemsets);
            lines.add(row("FPGROWTH header", growth.header, "nodes", growth.nodes, "conditional_trees", growth.conditionalTrees, "conditional_nodes", growth.conditionalNodes, "itemsets", growth.itemsets.size(), match ? "MATCH" : "MISMATCH"));
            if (!match) for (int source = 0; source < 2; source++) {
                Map<Itemset, Long> from = source == 0 ? main.supports : growth.itemsets, to = source == 0 ? growth.itemsets : main.supports;
                for (Itemset itemset : sizeOrder(from.keySet().stream().filter(itemset -> !from.get(itemset).equals(to.get(itemset))).toList())) lines.add(row(source == 0 ? "ONLY_APRIORI" : "ONLY_FPGROWTH", text(itemset), from.get(itemset)));
            }
            lines.add(row("RULES generated", mainRules.generated, "passed", mainRules.rules.size(), "productive", mainRules.productive));
            for (Level level : categoryRun.levels) lines.add(row("CATEGORY_LEVEL", level.number, "candidates", level.candidates, "taxonomy", level.excluded, "pruned", level.pruned, "counted", level.counted, "frequent", level.frequent.size()));
            lines.add(row("CATEGORY_RULES itemsets", categoryRun.supports.size(), "generated", categoryRules.generated, "passed", categoryRules.rules.size(), "productive", categoryRules.productive));
            lines.add(row("SEQUENCES customers", customers.size(), "multi_day", customerSummaries.stream().filter(customer -> customer.days >= 2).count(), "pairs", sequencePairs, "frequent", sequences.size()));
            return lines;
        }
        List<String> itemsetLines() {
            List<String> lines = new ArrayList<>();
            for (Level level : main.levels) {
                lines.add(row("LEVEL", level.number, "candidates", level.candidates, "pruned", level.pruned, "counted", level.counted, "frequent", level.frequent.size()));
                for (Itemset itemset : level.frequent) lines.add(row(text(itemset), main.supports.get(itemset)));
            }
            return lines;
        }
        List<String> classificationLines() {
            List<String> lines = new ArrayList<>(); List<List<Itemset>> sections = List.of(closed, maximal, generators); String[] labels = {"CLOSED", "MAXIMAL", "GENERATOR"};
            for (int j = 0; j < 3; j++) for (Itemset itemset : sections.get(j)) lines.add(row(labels[j], text(itemset), main.supports.get(itemset)));
            return lines;
        }
        List<String> sequenceLines() {
            List<String> lines = new ArrayList<>();
            for (int j = 0; j < sequences.size(); j++) {
                Sequence s = sequences.get(j); lines.add(row("SEQ", j + 1, s.first, "->", s.second, "customers", s.customers, "base", s.base, "confidence", fraction(s.confidence), "lift", fraction(s.lift), "gap", fraction(s.gap)));
            }
            for (Repeat r : repeats) lines.add(row("REPEAT", r.item, "customers", r.customers, "intervals", r.count, "min", r.minimum, "max", r.maximum, "mean", fraction(r.mean), "median", fraction(r.median)));
            return lines;
        }
        List<String> validationLines() {
            List<String> lines = new ArrayList<>();
            for (RuleCheck check : checks) {
                Rule r = check.rule;
                lines.add(row("RULE", r.rank, arrow(r), "train", r.count, "confidence", fraction(r.confidence), "lift", fraction(r.lift), "test", check.together, "of", check.antecedent, "confidence", check.confidence == null ? "-" : fraction(check.confidence), "lift", check.lift == null ? "-" : fraction(check.lift), check.verdict));
            }
            for (Rule r : emerging) lines.add(row("EMERGING", r.rank, arrow(r), "test", r.count, "confidence", fraction(r.confidence), "lift", fraction(r.lift)));
            lines.add(row("VALIDATION train", train.size(), "test", test.size(), "itemsets", trainRun.supports.size(), "rules", trainRules.size(), "hold", checks.stream().filter(check -> check.verdict.equals("HOLD")).count(), "fail", checks.stream().filter(check -> check.verdict.equals("FAIL")).count(), "unseen", checks.stream().filter(check -> check.verdict.equals("UNSEEN")).count(), "emerging", emerging.size()));
            tallies.forEach((size, tally) -> lines.add(row("RECOMMEND size", size, tally.text()))); lines.add(row("RECOMMEND total", overall.text())); return lines;
        }
        String partner(String name) {
            Comparator<Itemset> order = (a, b) -> {
                int comparison = pairLift(b).compareTo(pairLift(a));
                if (comparison == 0) comparison = Long.compare(main.supports.get(b), main.supports.get(a));
                return comparison == 0 ? other(a, name).compareTo(other(b, name)) : comparison;
            };
            Itemset best = pairs.stream().filter(pair -> pair.items().contains(name)).min(order).orElse(null);
            return best == null ? "none" : row(other(best, name), fraction(pairLift(best)));
        }
        String other(Itemset pair, String name) { return pair.items().getFirst().equals(name) ? pair.items().getLast() : pair.items().getFirst(); }
        String strongest(String name) {
            Rule rule = mainRules.rules.stream().filter(candidate -> candidate.itemset.items().contains(name)).findFirst().orElse(null);
            return rule == null ? "none" : row(rule.rank, arrow(rule));
        }
        List<String> matrixLines(String label, List<String> items, Map<String, Long> counts, List<Itemset> baskets) {
            List<String> lines = new ArrayList<>();
            for (int j = 0; j < items.size(); j++) lines.add(row(label, j + 1, items.get(j), "baskets", counts.get(items.get(j))));
            StringBuilder heading = new StringBuilder("    "); for (int j = 1; j <= items.size(); j++) heading.append(pad(j, 7)); lines.add(heading.toString());
            for (int i = 0; i < items.size(); i++) {
                StringBuilder line = new StringBuilder(pad(i + 1, 4));
                for (int j = 0; j < items.size(); j++) {
                    String cell = "-";
                    if (i != j) cell = Long.toString(100L * baskets.size() * Apriori.countSupport(baskets, Itemset.of(items.get(i), items.get(j))) / (counts.get(items.get(i)) * counts.get(items.get(j))));
                    line.append(pad(cell, 7));
                }
                lines.add(line.toString());
            }
            return lines;
        }
        List<String> popularity(List<String> items, Map<String, Long> counts) { return items.stream().sorted(Comparator.<String>comparingLong(counts::get).reversed().thenComparing(Comparator.naturalOrder())).toList(); }
        List<String> itemLines() {
            List<String> lines = new ArrayList<>(), ranked = popularity(names, revenue);
            for (int j = 0; j < ranked.size(); j++) {
                String name = ranked.get(j); Product product = data.products.get(name); long count = main.singles.get(name);
                lines.add(row("ITEM", j + 1, name, product.category(), "price", money(product.price()), "units", units.get(name), "revenue", money(revenue.get(name)), "share", percent(revenue.get(name), totalRevenue), "baskets", count, "support", fraction(new Fraction(count, total)), "customers", buyers.get(name), "itemsets", main.supports.keySet().stream().filter(itemset -> itemset.items().contains(name)).count(), "heldout", heldOut.get(name), "hits", heldHits.get(name), "partner", partner(name), "best", strongest(name)));
            }
            for (Category c : categorySummaries) lines.add(row("CATEGORY", c.name, "items", c.products, "units", c.units, "revenue", money(c.revenue), "share", percent(c.revenue, totalRevenue), "baskets", c.baskets, "support", fraction(new Fraction(c.baskets, total))));
            lines.add(row("TOTAL items", names.size(), "units", units.values().stream().mapToLong(Long::longValue).sum(), "revenue", money(totalRevenue), "baskets", total, "customers", customers.size()));
            for (int j = 0; j < groups.size(); j++) {
                Group g = groups.get(j); lines.add(row("GROUP", j + 1, "items", g.members.size(), "edges", g.edges, "core", g.core, "revenue", money(g.revenue), "share", percent(g.revenue, totalRevenue), "members", String.join("+", g.members)));
            }
            for (Substitute s : substitutes) lines.add(row("SUBSTITUTE", s.first, s.second, "count", s.together, "expected", fraction(s.expected), "lift", fraction(s.lift)));
            lines.addAll(matrixLines("MATRIX", popularity(names, main.singles).subList(0, p.matrix), main.singles, sets));
            lines.addAll(matrixLines("CATEGORY_MATRIX", popularity(categories, categoryRun.singles), categoryRun.singles, extended)); return lines;
        }
        static String pad(Object value, int width) { String text = value.toString(); return " ".repeat(Math.max(0, width - text.length())) + text; }
        static String tableRow(String label, long[] values) {
            StringBuilder row = new StringBuilder(label).append(" ".repeat(Math.max(0, 17 - label.length())));
            for (long value : values) row.append(pad(value, 6)); return row.toString();
        }
        List<String> trendLines() {
            List<String> lines = new ArrayList<>(List.of(tableRow("WEEK", IntStream.rangeClosed(1, weeks).asLongStream().toArray()), tableRow("BASKETS", weekBaskets), tableRow("UNITS", weekUnits), tableRow("CUSTOMERS", weekCustomers)));
            for (String name : categories) lines.add(tableRow(name, series.get(name))); for (String name : names) lines.add(tableRow(name, series.get(name)));
            for (Trend t : trends) lines.add(row("TREND", t.name, "units", t.units, "slope", fraction(t.slope), "relative", t.relative == null ? "-" : fraction(t.relative), t.verdict)); return lines;
        }
        List<String> customerLines() {
            List<String> lines = new ArrayList<>();
            for (Customer c : customerSummaries) lines.add(row("CUSTOMER", c.id, "baskets", c.baskets, "days", c.days, "first", c.first, "last", c.last, "items", c.products, "units", c.units, "revenue", money(c.revenue), "average", money(c.revenue / c.baskets), "favorite", c.favorite, "segment", c.segment, "offer", c.offer.isEmpty() ? "none" : String.join("+", c.offer)));
            for (String segment : List.of("NEW", "LOYAL", "AT_RISK", "REGULAR")) {
                List<Customer> found = customerSummaries.stream().filter(customer -> customer.segment.equals(segment)).toList(); long sum = found.stream().mapToLong(Customer::revenue).sum();
                lines.add(row("SEGMENT", segment, "customers", found.size(), "revenue", money(sum), "share", percent(sum, totalRevenue)));
            }
            return lines;
        }
        void run() throws IOException {
            frequent(); sequential(); validate(); summarizeProducts(); summarizeTrends(); summarizeCustomers();
            Report.write("summary.txt", summaryLines()); Report.write("itemsets.txt", itemsetLines()); Report.write("closed_maximal.txt", classificationLines());
            Report.write("rules.csv", Report.rulesCsv(mainRules.rules)); Report.write("category_rules.csv", Report.rulesCsv(categoryRules.rules));
            Report.write("sequences.txt", sequenceLines()); Report.write("validation.txt", validationLines()); Report.write("items_report.txt", itemLines());
            Report.write("trends.txt", trendLines()); Report.write("customers.txt", customerLines());
        }
    }
    public static void main(String[] args) throws IOException { new Analysis().run(); }
}
