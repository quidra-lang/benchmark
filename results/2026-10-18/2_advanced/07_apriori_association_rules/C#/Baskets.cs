readonly record struct Itemset(string Key) : IComparable<Itemset>
{
    public static Itemset Empty => new("");
    public string[] Items => Key.Length == 0 ? [] : Key.Split('+');
    public int Size => Key.Length == 0 ? 0 : 1 + Key.Count(c => c == '+');
    public static Itemset Of(IEnumerable<string> items) => new(string.Join("+", items.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)));
    public int CompareTo(Itemset other) => StringComparer.Ordinal.Compare(Key, other.Key);
    public bool Contains(Itemset subset)
    {
        HashSet<string> items = new(Items, StringComparer.Ordinal);
        return subset.Items.All(items.Contains);
    }
    public Itemset Union(Itemset other) => Of(Items.Concat(other.Items));
}
record Product(string Name, string Category, long Price);
sealed class Transaction(string tid, string customer, int day)
{
    public string Tid = tid, Customer = customer;
    public int Day = day;
    public Dictionary<string, long> Counts = new(StringComparer.Ordinal);
    public bool Add(string item)
    {
        bool duplicate = Counts.TryGetValue(item, out long count); Counts[item] = count + 1; return duplicate;
    }
    public Itemset Products => Itemset.Of(Counts.Keys);
    public long Units => Counts.Values.Sum();
}
static class Baskets
{
    public static List<string[]> ReadRecords(string name) => File.ReadLines(Path.Combine("input", name)).Skip(1).Select(line => line.Split(',')).ToList();
    public static Itemset Extended(Itemset basket, Dictionary<string, string> taxonomy) => Itemset.Of(basket.Items.Concat(basket.Items.Select(item => taxonomy[item])));
}
