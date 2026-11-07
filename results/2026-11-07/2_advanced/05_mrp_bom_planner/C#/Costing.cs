using System;
using System.Collections.Generic;
using System.Linq;

readonly record struct StandardCost(long Material, long Labor)
{
    public long Total => Material + Labor;
}
static class Costing
{
    public static Dictionary<string, StandardCost> Rollup(SortedDictionary<string, Item> items, Bom bom, List<string> planningOrder)
    {
        Dictionary<string, StandardCost> costs = new(StringComparer.Ordinal);
        foreach (string id in planningOrder.AsEnumerable().Reverse())
        {
            Item item = items[id]; long material = item.Material, labor = item.Labor;
            foreach (Edge edge in bom.Children[id]) { StandardCost child = costs[edge.Child]; material += (edge.Quantity * (100 + edge.Scrap) * child.Material + 50) / 100; labor += (edge.Quantity * (100 + edge.Scrap) * child.Labor + 50) / 100; }
            costs[id] = new(material, labor);
        }
        return costs;
    }
    public static Dictionary<string, string> Classes(Dictionary<string, long> values)
    {
        long total = values.Values.Sum(), before = 0; Dictionary<string, string> classes = new(StringComparer.Ordinal);
        foreach (var pair in values.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal)) { classes[pair.Key] = pair.Value == 0 ? "C" : 100 * before < 80 * total ? "A" : 100 * before < 95 * total ? "B" : "C"; before += pair.Value; }
        return classes;
    }
}
