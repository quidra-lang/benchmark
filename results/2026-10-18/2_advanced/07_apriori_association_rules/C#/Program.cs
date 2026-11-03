global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using static Report;

sealed class Params
{
    public long Support, CategorySupport, SequenceSupport, TrainSupport, TestSupport, NegativeExpected;
    public int Maximum, SplitDay, Top, Matrix;
    public Fraction Confidence, Lift, GroupLift, NegativeLift, Trend;
    public Params()
    {
        Dictionary<string, string> values = File.ReadLines("input/params.txt").Select(line => line.Split(' ')).ToDictionary(parts => parts[0], parts => parts[1], StringComparer.Ordinal);
        int I(string key) => int.Parse(values[key]);
        Fraction F(string key) { long[] parts = values[key].Split('/').Select(long.Parse).ToArray(); return new(parts[0], parts[1]); }
        Support = I("min_support"); CategorySupport = I("category_min_support"); SequenceSupport = I("sequence_min_support");
        TrainSupport = I("train_min_support"); TestSupport = I("test_min_support"); NegativeExpected = I("negative_min_expected");
        Maximum = I("max_size"); SplitDay = I("split_day"); Top = I("recommend_top"); Matrix = I("matrix_size");
        Confidence = F("min_confidence"); Lift = F("min_lift"); GroupLift = F("group_min_lift"); NegativeLift = F("negative_max_lift"); Trend = F("trend_threshold");
    }
}
sealed class Dataset
{
    public List<string> Errors = [];
    public Dictionary<string, Product> Products = new(StringComparer.Ordinal);
    public List<Transaction> Transactions = [];
    public int ItemRows, TransactionLines, Adopted, Rejected, Duplicates;
    void Error(string name, int line, string message) => Errors.Add($"{name} line {line}: {message}");
    public Dataset()
    {
        List<string[]> records = Baskets.ReadRecords("items.csv"); ItemRows = records.Count;
        for (int j = 0; j < records.Count; j++)
        {
            string[] row = records[j]; long price = long.Parse(row[2]);
            if (Products.ContainsKey(row[0])) Error("items.csv", j + 2, $"duplicate item {row[0]}");
            else if (price == 0) Error("items.csv", j + 2, "bad price 0");
            else Products[row[0]] = new(row[0], row[1], price);
        }
        records = Baskets.ReadRecords("transactions.csv"); TransactionLines = records.Count;
        HashSet<string> known = new(StringComparer.Ordinal);
        for (int j = 0; j < records.Count; j++)
        {
            string[] row = records[j]; int day = int.Parse(row[2]); string? problem = null;
            if (known.Contains(row[0]) && row[0] != Transactions[^1].Tid) problem = $"tid {row[0]} not contiguous";
            else
            {
                if (known.Add(row[0])) Transactions.Add(new(row[0], row[1], day));
                Transaction current = Transactions[^1];
                if (row[1] != current.Customer) problem = $"tid {row[0]} customer {row[1]} differs from {current.Customer}";
                else if (day != current.Day) problem = $"tid {row[0]} day {day} differs from {current.Day}";
                else if (!Products.ContainsKey(row[3])) problem = $"unknown item {row[3]}";
            }
            if (problem != null) { Error("transactions.csv", j + 2, problem); Rejected++; }
            else { Adopted++; if (Transactions[^1].Add(row[3])) Duplicates++; }
        }
    }
}
record Level(int Number, int Candidates, int Excluded, int Pruned, int Counted, List<Itemset> Frequent);
sealed class AprioriResult
{
    public List<Level> Levels = [];
    public Dictionary<Itemset, long> Supports = new();
    public Dictionary<string, long> Singles = new(StringComparer.Ordinal);
}
sealed class Tally
{
    public long Cases, Covered, Top, Hits, Baseline;
    public void Add(string held, List<string> suggestion, List<string> popular)
    {
        Cases++; if (suggestion.Count > 0) { Covered++; if (suggestion[0] == held) Top++; }
        if (suggestion.Contains(held)) Hits++; if (popular.Contains(held)) Baseline++;
    }
    public string Text => $"cases {Cases} covered {Covered} hit1 {Top} hit {Hits} rate {FractionText(new(Hits, Cases))} baseline {Baseline} rate {FractionText(new(Baseline, Cases))}";
}
record Sequence(string First, string Second, long Customers, long Base, Fraction Confidence, Fraction Lift, Fraction Gap);
record Repeat(string Item, int Customers, int Count, long Minimum, long Maximum, Fraction Mean, Fraction Median);
record RuleCheck(Rule Rule, long Together, long Antecedent, Fraction? Confidence, Fraction? Lift, string Verdict);
record Category(string Name, int Products, long Units, long Revenue, long Baskets);
record Group(List<string> Members, int Edges, string Core, long Revenue);
record Substitute(string First, string Second, long Together, Fraction Expected, Fraction Lift);
record Trend(string Name, long Units, Fraction Slope, Fraction? Relative, string Verdict);
record Customer(string Id, int Baskets, int Days, int First, int Last, int Products, long Units, long Revenue, string Favorite, string Segment, List<string> Offer);

sealed class Analysis
{
    readonly Params p = new();
    readonly Dataset data = new();
    readonly List<string> names, categories, customers;
    readonly Dictionary<string, string> taxonomy;
    readonly List<Transaction> baskets;
    readonly List<Itemset> sets, extended, train, test;
    readonly Dictionary<string, List<Transaction>> customerBaskets;
    readonly Dictionary<string, Dictionary<string, SortedSet<int>>> histories = new(StringComparer.Ordinal);
    readonly int total, firstDay, lastDay;
    int sequencePairs, weeks;
    long totalRevenue;
    AprioriResult main = new(), categoryRun = new(), trainRun = new();
    GrowthResult growth = new(0, 0);
    RuleSet mainRules = new(), categoryRules = new();
    List<Rule> trainRules = [], emerging = [];
    List<Itemset> closed = [], maximal = [], generators = [], pairs = [];
    readonly Dictionary<string, long> buyers = new(StringComparer.Ordinal), units = new(StringComparer.Ordinal), revenue = new(StringComparer.Ordinal), heldOut = new(StringComparer.Ordinal), heldHits = new(StringComparer.Ordinal);
    readonly List<Sequence> sequences = [];
    readonly List<Repeat> repeats = [];
    readonly List<RuleCheck> checks = [];
    readonly SortedDictionary<int, Tally> tallies = new();
    readonly Tally overall = new();
    readonly List<Category> categorySummaries = [];
    readonly List<Group> groups = [];
    readonly List<Substitute> substitutes = [];
    readonly List<Trend> trends = [];
    readonly List<Customer> customerSummaries = [];
    long[] weekBaskets = [], weekUnits = [], weekCustomers = [];
    readonly Dictionary<string, long[]> series = new(StringComparer.Ordinal);
    public Analysis()
    {
        names = data.Products.Keys.Order(StringComparer.Ordinal).ToList();
        taxonomy = data.Products.ToDictionary(pair => pair.Key, pair => pair.Value.Category, StringComparer.Ordinal);
        categories = taxonomy.Values.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToList();
        baskets = data.Transactions.Where(transaction => transaction.Counts.Count > 0).ToList(); total = baskets.Count;
        sets = baskets.Select(basket => basket.Products).ToList(); extended = sets.Select(items => Baskets.Extended(items, taxonomy)).ToList();
        train = baskets.Where(basket => basket.Day <= p.SplitDay).Select(basket => basket.Products).ToList();
        test = baskets.Where(basket => basket.Day > p.SplitDay).Select(basket => basket.Products).ToList();
        customerBaskets = baskets.GroupBy(basket => basket.Customer, StringComparer.Ordinal).ToDictionary(group => group.Key, group => group.ToList(), StringComparer.Ordinal);
        customers = customerBaskets.Keys.Order(StringComparer.Ordinal).ToList(); firstDay = baskets.Min(basket => basket.Day); lastDay = baskets.Max(basket => basket.Day);
        foreach (string customer in customers)
        {
            Dictionary<string, SortedSet<int>> history = new(StringComparer.Ordinal);
            foreach (Transaction basket in customerBaskets[customer]) foreach (string item in basket.Counts.Keys)
            {
                if (!history.TryGetValue(item, out SortedSet<int>? days)) history[item] = days = new();
                days.Add(basket.Day);
            }
            histories[customer] = history;
        }
    }
    static string Row(params object[] parts) => string.Join(" ", parts);
    static List<Itemset> SizeOrder(IEnumerable<Itemset> items) => items.OrderBy(itemset => itemset.Size).ThenBy(itemset => itemset).ToList();
    static Fraction Median(IEnumerable<long> values)
    {
        long[] ordered = values.Order().ToArray(); int middle = ordered.Length / 2;
        return ordered.Length % 2 == 1 ? new(ordered[middle]) : new(ordered[middle - 1] + ordered[middle], 2);
    }
    static (Itemset Chosen, Itemset Rest) Split(Itemset itemset, int mask)
    {
        string[] items = itemset.Items;
        return (Itemset.Of(items.Where((_, j) => (mask >> j & 1) != 0)), Itemset.Of(items.Where((_, j) => (mask >> j & 1) == 0)));
    }
    static AprioriResult RunApriori(List<Itemset> baskets, List<string> universe, long minimum, int maximum, Dictionary<string, string>? taxonomy = null)
    {
        AprioriResult result = new();
        List<Itemset> candidates = universe.Order(StringComparer.Ordinal).Select(item => Itemset.Of([item])).ToList(), previous = [];
        for (int size = 1; size <= maximum; size++)
        {
            CandidateLevel generated = size == 1 ? new(candidates.Count, 0, 0, candidates) : Apriori.Generate(previous, size, taxonomy);
            Dictionary<Itemset, long> counts = Apriori.CountSupports(baskets, generated.Itemsets);
            List<Itemset> frequent = counts.Keys.Where(itemset => counts[itemset] >= minimum).Order().ToList();
            foreach (var entry in counts)
            {
                if (size == 1) result.Singles[entry.Key.Items[0]] = entry.Value;
                if (entry.Value >= minimum) result.Supports[entry.Key] = entry.Value;
            }
            result.Levels.Add(new(size, generated.Joined, generated.Excluded, generated.Pruned, generated.Itemsets.Count, frequent));
            if (frequent.Count == 0) break; previous = frequent;
        }
        return result;
    }
    RuleSet MakeRules(Dictionary<Itemset, long> supports, int count, HashSet<string>? required = null)
    {
        RuleSet result = new();
        long Support(Itemset itemset) => itemset.Size == 0 ? count : supports[itemset];
        foreach (var entry in supports)
        {
            Itemset z = entry.Key;
            if (z.Size < 2 || required != null && !z.Items.Any(required.Contains)) continue;
            for (int mask = 1; mask < (1 << z.Size) - 1; mask++)
            {
                var parts = Split(z, mask); result.Generated++;
                Rule rule = new(z, parts.Chosen, parts.Rest, entry.Value, count, Support(parts.Chosen), Support(parts.Rest));
                if (!Rules.Meets(rule.Confidence, rule.Lift, p.Confidence, p.Lift)) continue;
                Fraction reference = new();
                for (int subset = 0; subset < (1 << parts.Chosen.Size) - 1; subset++)
                {
                    Itemset w = Split(parts.Chosen, subset).Chosen;
                    Fraction confidence = new(Support(w.Union(parts.Rest)), Support(w));
                    if (confidence > reference) reference = confidence;
                }
                rule.Improvement = rule.Confidence - reference; if (rule.Improvement > new Fraction()) result.Productive++;
                result.Rules.Add(rule);
            }
        }
        result.Rules.Sort(Rules.Compare); for (int j = 0; j < result.Rules.Count; j++) result.Rules[j].Rank = j + 1;
        return result;
    }
    static List<string> Recommend(Itemset held, IEnumerable<string> candidates, int limit)
    {
        HashSet<string> owned = new(held.Items, StringComparer.Ordinal); List<string> selected = [];
        foreach (string item in candidates) { if (selected.Count == limit) break; if (!owned.Contains(item) && !selected.Contains(item)) selected.Add(item); }
        return selected;
    }
    static IEnumerable<string> RuleCandidates(List<Rule> rules, Itemset held) => rules.Where(rule => rule.Consequent.Size == 1 && held.Contains(rule.Antecedent)).Select(rule => rule.Consequent.Items[0]);
    void Frequent()
    {
        main = RunApriori(sets, names, p.Support, p.Maximum); growth = FpGrowth.Run(sets, p.Support, p.Maximum);
        HashSet<Itemset> closedSet = new(main.Supports.Keys), maximalSet = new(main.Supports.Keys);
        pairs = main.Supports.Keys.Where(itemset => itemset.Size == 2).Order().ToList();
        foreach (var entry in main.Supports)
        {
            bool generator = true;
            foreach (Itemset subset in Apriori.SmallerSubsets(entry.Key))
            {
                long count = subset.Size == 0 ? total : main.Supports[subset];
                if (count <= entry.Value) generator = false;
                if (subset.Size > 0) { maximalSet.Remove(subset); if (count == entry.Value) closedSet.Remove(subset); }
            }
            if (generator) generators.Add(entry.Key);
        }
        closed = SizeOrder(closedSet); maximal = SizeOrder(maximalSet); generators = SizeOrder(generators);
        mainRules = MakeRules(main.Supports, total);
        categoryRun = RunApriori(extended, names.Concat(categories).ToList(), p.CategorySupport, p.Maximum, taxonomy);
        categoryRules = MakeRules(categoryRun.Supports, total, new(categories, StringComparer.Ordinal));
    }
    void Sequential()
    {
        Dictionary<(string First, string Second), List<long>> gaps = new();
        Dictionary<string, List<long>> intervals = new(StringComparer.Ordinal); Dictionary<string, int> repeaters = new(StringComparer.Ordinal);
        foreach (string name in names) buyers[name] = 0;
        foreach (var history in histories.Values) foreach (var first in history)
        {
            buyers[first.Key]++;
            if (first.Value.Count >= 2)
            {
                repeaters[first.Key] = repeaters.GetValueOrDefault(first.Key) + 1;
                if (!intervals.TryGetValue(first.Key, out List<long>? found)) intervals[first.Key] = found = [];
                int[] days = first.Value.ToArray(); for (int j = 1; j < days.Length; j++) found.Add(days[j] - days[j - 1]);
            }
            foreach (var second in history) if (first.Value.Min < second.Value.Max)
            {
                int shortest = 113;
                foreach (int a in first.Value) foreach (int b in second.Value) if (a < b) shortest = Math.Min(shortest, b - a);
                var key = (first.Key, second.Key);
                if (!gaps.TryGetValue(key, out List<long>? found)) gaps[key] = found = [];
                found.Add(shortest);
            }
        }
        sequencePairs = gaps.Count;
        foreach (var entry in gaps) if (entry.Value.Count >= p.SequenceSupport)
        {
            string a = entry.Key.First, b = entry.Key.Second; int count = entry.Value.Count;
            sequences.Add(new(a, b, count, buyers[a], new(count, buyers[a]), Rules.LiftOf(customers.Count, count, buyers[a], buyers[b]), Median(entry.Value)));
        }
        sequences.Sort((a, b) => { int c = b.Customers.CompareTo(a.Customers); if (c == 0) c = b.Confidence.CompareTo(a.Confidence); if (c == 0) c = StringComparer.Ordinal.Compare(a.First, b.First); return c == 0 ? StringComparer.Ordinal.Compare(a.Second, b.Second) : c; });
        foreach (var entry in intervals) repeats.Add(new(entry.Key, repeaters[entry.Key], entry.Value.Count, entry.Value.Min(), entry.Value.Max(), new(entry.Value.Sum(), entry.Value.Count), Median(entry.Value)));
        repeats.Sort((a, b) => { int c = a.Mean.CompareTo(b.Mean); return c == 0 ? StringComparer.Ordinal.Compare(a.Item, b.Item) : c; });
    }
    void Validate()
    {
        trainRun = RunApriori(train, names, p.TrainSupport, p.Maximum); trainRules = MakeRules(trainRun.Supports, train.Count).Rules;
        HashSet<(Itemset, Itemset)> known = new();
        foreach (Rule rule in trainRules)
        {
            known.Add((rule.Antecedent, rule.Consequent));
            long a = Apriori.CountSupport(test, rule.Antecedent), b = Apriori.CountSupport(test, rule.Consequent), c = Apriori.CountSupport(test, rule.Itemset);
            Fraction? confidence = null, lift = null; string verdict = "UNSEEN";
            if (a != 0 && b != 0) { confidence = new Fraction(c, a); lift = Rules.LiftOf(test.Count, c, a, b); verdict = Rules.Meets(confidence.Value, lift.Value, p.Confidence, p.Lift) ? "HOLD" : "FAIL"; }
            checks.Add(new(rule, c, a, confidence, lift, verdict));
        }
        AprioriResult testRun = RunApriori(test, names, p.TestSupport, p.Maximum);
        emerging = MakeRules(testRun.Supports, test.Count).Rules.Where(rule => !known.Contains((rule.Antecedent, rule.Consequent))).ToList();
        List<string> popularity = names.OrderByDescending(name => trainRun.Singles[name]).ThenBy(name => name, StringComparer.Ordinal).ToList();
        foreach (string name in names) { heldOut[name] = 0; heldHits[name] = 0; }
        foreach (Itemset basket in test) if (basket.Size >= 2) foreach (string item in basket.Items)
        {
            Itemset held = Itemset.Of(basket.Items.Where(name => name != item));
            List<string> suggestion = Recommend(held, RuleCandidates(trainRules, held), p.Top), baseline = Recommend(held, popularity, p.Top);
            if (!tallies.TryGetValue(basket.Size, out Tally? tally)) tallies[basket.Size] = tally = new();
            tally.Add(item, suggestion, baseline); overall.Add(item, suggestion, baseline); heldOut[item]++; if (suggestion.Contains(item)) heldHits[item]++;
        }
    }
    Fraction PairLift(Itemset pair)
    {
        string[] items = pair.Items; return Rules.LiftOf(total, main.Supports[pair], main.Singles[items[0]], main.Singles[items[1]]);
    }
    void SummarizeProducts()
    {
        foreach (string name in names) units[name] = 0;
        foreach (Transaction basket in baskets) foreach (var entry in basket.Counts) units[entry.Key] += entry.Value;
        foreach (string name in names) { revenue[name] = units[name] * data.Products[name].Price; totalRevenue += revenue[name]; }
        foreach (string category in categories)
        {
            List<string> members = names.Where(name => taxonomy[name] == category).ToList();
            categorySummaries.Add(new(category, members.Count, members.Sum(name => units[name]), members.Sum(name => revenue[name]), categoryRun.Singles[category]));
        }
        categorySummaries.Sort((a, b) => { int c = b.Revenue.CompareTo(a.Revenue); return c == 0 ? StringComparer.Ordinal.Compare(a.Name, b.Name) : c; });
        Dictionary<string, List<string>> neighbors = names.ToDictionary(name => name, _ => new List<string>(), StringComparer.Ordinal);
        foreach (Itemset pair in pairs) if (PairLift(pair) >= p.GroupLift) { string[] items = pair.Items; neighbors[items[0]].Add(items[1]); neighbors[items[1]].Add(items[0]); }
        HashSet<string> visited = new(StringComparer.Ordinal);
        foreach (string name in names) if (!visited.Contains(name) && neighbors[name].Count > 0)
        {
            List<string> members = []; Stack<string> stack = new(); stack.Push(name); visited.Add(name); long sum = 0; int degree = 0;
            while (stack.TryPop(out string? item))
            {
                members.Add(item); sum += revenue[item]; degree += neighbors[item].Count;
                foreach (string next in neighbors[item]) if (visited.Add(next)) stack.Push(next);
            }
            members.Sort(StringComparer.Ordinal);
            string core = members.OrderByDescending(item => neighbors[item].Count).ThenByDescending(item => main.Singles[item]).ThenBy(item => item, StringComparer.Ordinal).First();
            groups.Add(new(members, degree / 2, core, sum));
        }
        groups.Sort((a, b) => { int c = b.Members.Count.CompareTo(a.Members.Count); return c == 0 ? StringComparer.Ordinal.Compare(a.Members[0], b.Members[0]) : c; });
        List<Itemset> singles = main.Levels[0].Frequent;
        for (int i = 0; i < singles.Count; i++) for (int j = i + 1; j < singles.Count; j++)
        {
            string a = singles[i].Items[0], b = singles[j].Items[0]; long expected = main.Singles[a] * main.Singles[b];
            if (expected < p.NegativeExpected * total) continue;
            long together = Apriori.CountSupport(sets, Itemset.Of([a, b])); Fraction lift = Rules.LiftOf(total, together, main.Singles[a], main.Singles[b]);
            if (lift <= p.NegativeLift) substitutes.Add(new(a, b, together, new(expected, total), lift));
        }
        substitutes.Sort((a, b) => { int c = a.Lift.CompareTo(b.Lift); if (c == 0) c = b.Expected.CompareTo(a.Expected); if (c == 0) c = StringComparer.Ordinal.Compare(a.First, b.First); return c == 0 ? StringComparer.Ordinal.Compare(a.Second, b.Second) : c; });
    }
    void SummarizeTrends()
    {
        weeks = (lastDay - 1) / 7 + 1; weekBaskets = new long[weeks]; weekUnits = new long[weeks]; weekCustomers = new long[weeks];
        HashSet<string>[] weeklyCustomers = Enumerable.Range(0, weeks).Select(_ => new HashSet<string>(StringComparer.Ordinal)).ToArray();
        foreach (string name in categories.Concat(names)) series[name] = new long[weeks];
        foreach (Transaction basket in baskets)
        {
            int week = (basket.Day - 1) / 7; weekBaskets[week]++; weekUnits[week] += basket.Units; weeklyCustomers[week].Add(basket.Customer);
            foreach (var entry in basket.Counts) { series[entry.Key][week] += entry.Value; series[taxonomy[entry.Key]][week] += entry.Value; }
        }
        for (int j = 0; j < weeks; j++) weekCustomers[j] = weeklyCustomers[j].Count;
        long sumWeeks = 0, sumSquares = 0;
        for (int week = 1; week <= weeks; week++) { sumWeeks += week; sumSquares += week * week; }
        foreach (var entry in series)
        {
            long weighted = 0, sum = 0;
            for (int j = 0; j < weeks; j++) { sum += entry.Value[j]; weighted += (j + 1) * entry.Value[j]; }
            Fraction slope = new(weeks * weighted - sumWeeks * sum, weeks * sumSquares - sumWeeks * sumWeeks);
            Fraction? relative = null; string verdict = "NONE";
            if (sum > 0)
            {
                relative = slope * new Fraction(weeks, sum);
                verdict = relative.Value >= p.Trend ? "RISING" : relative.Value <= new Fraction(-p.Trend.Numerator, p.Trend.Denominator) ? "FALLING" : "FLAT";
            }
            trends.Add(new(entry.Key, sum, slope, relative, verdict));
        }
        trends.Sort((a, b) => {
            if (a.Relative.HasValue != b.Relative.HasValue) return a.Relative.HasValue ? -1 : 1;
            int c = a.Relative.HasValue ? b.Relative!.Value.CompareTo(a.Relative.Value) : 0;
            return c == 0 ? StringComparer.Ordinal.Compare(a.Name, b.Name) : c;
        });
    }
    void SummarizeCustomers()
    {
        foreach (string id in customers)
        {
            List<Transaction> found = customerBaskets[id]; var history = histories[id];
            int days = found.Select(basket => basket.Day).Distinct().Count(), first = found.Min(basket => basket.Day), last = found.Max(basket => basket.Day);
            long customerUnits = 0, customerRevenue = 0; Dictionary<string, long> categoryUnits = new(StringComparer.Ordinal);
            foreach (Transaction basket in found) foreach (var entry in basket.Counts)
            {
                customerUnits += entry.Value; customerRevenue += entry.Value * data.Products[entry.Key].Price;
                string category = taxonomy[entry.Key]; categoryUnits[category] = categoryUnits.GetValueOrDefault(category) + entry.Value;
            }
            string favorite = categoryUnits.Keys.OrderByDescending(category => categoryUnits[category]).ThenBy(category => category, StringComparer.Ordinal).First();
            string segment = first > lastDay - 28 ? "NEW" : found.Count >= 4 && lastDay - last <= 14 ? "LOYAL" : lastDay - last > 28 ? "AT_RISK" : "REGULAR";
            Itemset held = Itemset.Of(history.Keys); List<string> offer = Recommend(held, RuleCandidates(mainRules.Rules, held), p.Top);
            customerSummaries.Add(new(id, found.Count, days, first, last, history.Count, customerUnits, customerRevenue, favorite, segment, offer));
        }
    }
    List<string> SummaryLines()
    {
        List<string> lines = data.Errors.Select(error => "ERROR " + error).ToList();
        lines.Add(Row("ITEMS rows", data.ItemRows, "adopted", data.Products.Count, "categories", categories.Count));
        lines.Add(Row("TRANSACTIONS lines", data.TransactionLines, "adopted", data.Adopted, "rejected", data.Rejected, "duplicates", data.Duplicates, "transactions", data.Transactions.Count, "empty", data.Transactions.Count - total));
        int largest = sets.Max(basket => basket.Size);
        lines.Add(Row("BASKETS count", total, "customers", customers.Count, "first_day", firstDay, "last_day", lastDay, "average_size", FractionText(new(sets.Sum(basket => (long)basket.Size), total)), "largest", largest));
        for (int size = 1; size <= largest; size++) { int count = sets.Count(basket => basket.Size == size); lines.Add(Row("SIZE", size, "baskets", count, "share", Percent(count, total))); }
        lines.Add(Row("FREQUENT itemsets", main.Supports.Count, "closed", closed.Count, "maximal", maximal.Count, "generators", generators.Count, "levels", main.Levels.Count));
        bool match = main.Supports.Count == growth.Itemsets.Count && main.Supports.All(entry => growth.Itemsets.TryGetValue(entry.Key, out long count) && count == entry.Value);
        lines.Add(Row("FPGROWTH header", growth.Header, "nodes", growth.Nodes, "conditional_trees", growth.ConditionalTrees, "conditional_nodes", growth.ConditionalNodes, "itemsets", growth.Itemsets.Count, match ? "MATCH" : "MISMATCH"));
        if (!match) for (int source = 0; source < 2; source++)
        {
            var from = source == 0 ? main.Supports : growth.Itemsets; var to = source == 0 ? growth.Itemsets : main.Supports;
            foreach (Itemset itemset in SizeOrder(from.Keys.Where(itemset => !to.TryGetValue(itemset, out long count) || count != from[itemset]))) lines.Add(Row(source == 0 ? "ONLY_APRIORI" : "ONLY_FPGROWTH", ItemsetText(itemset), from[itemset]));
        }
        lines.Add(Row("RULES generated", mainRules.Generated, "passed", mainRules.Rules.Count, "productive", mainRules.Productive));
        foreach (Level level in categoryRun.Levels) lines.Add(Row("CATEGORY_LEVEL", level.Number, "candidates", level.Candidates, "taxonomy", level.Excluded, "pruned", level.Pruned, "counted", level.Counted, "frequent", level.Frequent.Count));
        lines.Add(Row("CATEGORY_RULES itemsets", categoryRun.Supports.Count, "generated", categoryRules.Generated, "passed", categoryRules.Rules.Count, "productive", categoryRules.Productive));
        lines.Add(Row("SEQUENCES customers", customers.Count, "multi_day", customerSummaries.Count(customer => customer.Days >= 2), "pairs", sequencePairs, "frequent", sequences.Count));
        return lines;
    }
    List<string> ItemsetLines()
    {
        List<string> lines = [];
        foreach (Level level in main.Levels)
        {
            lines.Add(Row("LEVEL", level.Number, "candidates", level.Candidates, "pruned", level.Pruned, "counted", level.Counted, "frequent", level.Frequent.Count));
            foreach (Itemset itemset in level.Frequent) lines.Add(Row(ItemsetText(itemset), main.Supports[itemset]));
        }
        return lines;
    }
    List<string> ClassificationLines()
    {
        List<string> lines = [];
        foreach (var section in new[] { ("CLOSED", closed), ("MAXIMAL", maximal), ("GENERATOR", generators) })
            foreach (Itemset itemset in section.Item2) lines.Add(Row(section.Item1, ItemsetText(itemset), main.Supports[itemset]));
        return lines;
    }
    List<string> SequenceLines()
    {
        List<string> lines = [];
        for (int j = 0; j < sequences.Count; j++)
        {
            Sequence s = sequences[j]; lines.Add(Row("SEQ", j + 1, s.First, "->", s.Second, "customers", s.Customers, "base", s.Base, "confidence", FractionText(s.Confidence), "lift", FractionText(s.Lift), "gap", FractionText(s.Gap)));
        }
        foreach (Repeat r in repeats) lines.Add(Row("REPEAT", r.Item, "customers", r.Customers, "intervals", r.Count, "min", r.Minimum, "max", r.Maximum, "mean", FractionText(r.Mean), "median", FractionText(r.Median)));
        return lines;
    }
    List<string> ValidationLines()
    {
        List<string> lines = [];
        foreach (RuleCheck check in checks)
        {
            Rule r = check.Rule;
            lines.Add(Row("RULE", r.Rank, Arrow(r), "train", r.Count, "confidence", FractionText(r.Confidence), "lift", FractionText(r.Lift), "test", check.Together, "of", check.Antecedent, "confidence", check.Confidence is Fraction confidence ? FractionText(confidence) : "-", "lift", check.Lift is Fraction lift ? FractionText(lift) : "-", check.Verdict));
        }
        foreach (Rule r in emerging) lines.Add(Row("EMERGING", r.Rank, Arrow(r), "test", r.Count, "confidence", FractionText(r.Confidence), "lift", FractionText(r.Lift)));
        lines.Add(Row("VALIDATION train", train.Count, "test", test.Count, "itemsets", trainRun.Supports.Count, "rules", trainRules.Count, "hold", checks.Count(check => check.Verdict == "HOLD"), "fail", checks.Count(check => check.Verdict == "FAIL"), "unseen", checks.Count(check => check.Verdict == "UNSEEN"), "emerging", emerging.Count));
        foreach (var entry in tallies) lines.Add(Row("RECOMMEND size", entry.Key, entry.Value.Text));
        lines.Add(Row("RECOMMEND total", overall.Text)); return lines;
    }
    string Partner(string name)
    {
        List<Itemset> candidates = pairs.Where(pair => pair.Items.Contains(name)).ToList();
        string Other(Itemset pair) => pair.Items.First(item => item != name);
        candidates.Sort((a, b) => { int c = PairLift(b).CompareTo(PairLift(a)); if (c == 0) c = main.Supports[b].CompareTo(main.Supports[a]); return c == 0 ? StringComparer.Ordinal.Compare(Other(a), Other(b)) : c; });
        return candidates.Count == 0 ? "none" : Row(Other(candidates[0]), FractionText(PairLift(candidates[0])));
    }
    string Strongest(string name)
    {
        Rule? rule = mainRules.Rules.FirstOrDefault(rule => rule.Itemset.Items.Contains(name)); return rule == null ? "none" : Row(rule.Rank, Arrow(rule));
    }
    List<string> MatrixLines(string label, List<string> items, Dictionary<string, long> counts, List<Itemset> baskets)
    {
        List<string> lines = items.Select((item, j) => Row(label, j + 1, item, "baskets", counts[item])).ToList();
        lines.Add("    " + string.Concat(Enumerable.Range(1, items.Count).Select(j => j.ToString().PadLeft(7))));
        for (int i = 0; i < items.Count; i++)
        {
            string text = (i + 1).ToString().PadLeft(4);
            for (int j = 0; j < items.Count; j++)
            {
                string cell = "-";
                if (i != j) cell = (100L * baskets.Count * Apriori.CountSupport(baskets, Itemset.Of([items[i], items[j]])) / (counts[items[i]] * counts[items[j]])).ToString();
                text += cell.PadLeft(7);
            }
            lines.Add(text);
        }
        return lines;
    }
    List<string> ItemLines()
    {
        List<string> lines = []; List<string> ranked = names.OrderByDescending(name => revenue[name]).ThenBy(name => name, StringComparer.Ordinal).ToList();
        for (int j = 0; j < ranked.Count; j++)
        {
            string name = ranked[j]; Product product = data.Products[name]; long count = main.Singles[name];
            lines.Add(Row("ITEM", j + 1, name, product.Category, "price", Money(product.Price), "units", units[name], "revenue", Money(revenue[name]), "share", Percent(revenue[name], totalRevenue), "baskets", count, "support", FractionText(new(count, total)), "customers", buyers[name], "itemsets", main.Supports.Keys.Count(itemset => itemset.Items.Contains(name)), "heldout", heldOut[name], "hits", heldHits[name], "partner", Partner(name), "best", Strongest(name)));
        }
        foreach (Category c in categorySummaries) lines.Add(Row("CATEGORY", c.Name, "items", c.Products, "units", c.Units, "revenue", Money(c.Revenue), "share", Percent(c.Revenue, totalRevenue), "baskets", c.Baskets, "support", FractionText(new(c.Baskets, total))));
        lines.Add(Row("TOTAL items", names.Count, "units", units.Values.Sum(), "revenue", Money(totalRevenue), "baskets", total, "customers", customers.Count));
        for (int j = 0; j < groups.Count; j++)
        {
            Group g = groups[j]; lines.Add(Row("GROUP", j + 1, "items", g.Members.Count, "edges", g.Edges, "core", g.Core, "revenue", Money(g.Revenue), "share", Percent(g.Revenue, totalRevenue), "members", string.Join("+", g.Members)));
        }
        foreach (Substitute s in substitutes) lines.Add(Row("SUBSTITUTE", s.First, s.Second, "count", s.Together, "expected", FractionText(s.Expected), "lift", FractionText(s.Lift)));
        List<string> Popular(List<string> items, Dictionary<string, long> counts) => items.OrderByDescending(item => counts[item]).ThenBy(item => item, StringComparer.Ordinal).ToList();
        lines.AddRange(MatrixLines("MATRIX", Popular(names, main.Singles).Take(p.Matrix).ToList(), main.Singles, sets));
        lines.AddRange(MatrixLines("CATEGORY_MATRIX", Popular(categories, categoryRun.Singles), categoryRun.Singles, extended)); return lines;
    }
    static string TableRow(string label, IEnumerable<long> values) => label.PadRight(17) + string.Concat(values.Select(value => value.ToString().PadLeft(6)));
    List<string> TrendLines()
    {
        List<string> lines = [TableRow("WEEK", Enumerable.Range(1, weeks).Select(week => (long)week)), TableRow("BASKETS", weekBaskets), TableRow("UNITS", weekUnits), TableRow("CUSTOMERS", weekCustomers)];
        foreach (string name in categories.Concat(names)) lines.Add(TableRow(name, series[name]));
        foreach (Trend t in trends) lines.Add(Row("TREND", t.Name, "units", t.Units, "slope", FractionText(t.Slope), "relative", t.Relative is Fraction relative ? FractionText(relative) : "-", t.Verdict));
        return lines;
    }
    List<string> CustomerLines()
    {
        List<string> lines = [];
        foreach (Customer c in customerSummaries) lines.Add(Row("CUSTOMER", c.Id, "baskets", c.Baskets, "days", c.Days, "first", c.First, "last", c.Last, "items", c.Products, "units", c.Units, "revenue", Money(c.Revenue), "average", Money(c.Revenue / c.Baskets), "favorite", c.Favorite, "segment", c.Segment, "offer", c.Offer.Count == 0 ? "none" : string.Join("+", c.Offer)));
        foreach (string segment in new[] { "NEW", "LOYAL", "AT_RISK", "REGULAR" })
        {
            List<Customer> found = customerSummaries.Where(customer => customer.Segment == segment).ToList(); long sum = found.Sum(customer => customer.Revenue);
            lines.Add(Row("SEGMENT", segment, "customers", found.Count, "revenue", Money(sum), "share", Percent(sum, totalRevenue)));
        }
        return lines;
    }
    public void Run()
    {
        Frequent(); Sequential(); Validate(); SummarizeProducts(); SummarizeTrends(); SummarizeCustomers();
        Write("summary.txt", SummaryLines()); Write("itemsets.txt", ItemsetLines()); Write("closed_maximal.txt", ClassificationLines());
        Write("rules.csv", RulesCsv(mainRules.Rules)); Write("category_rules.csv", RulesCsv(categoryRules.Rules));
        Write("sequences.txt", SequenceLines()); Write("validation.txt", ValidationLines()); Write("items_report.txt", ItemLines());
        Write("trends.txt", TrendLines()); Write("customers.txt", CustomerLines());
    }
}
static class Program
{
    static void Main() { CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; new Analysis().Run(); }
}
