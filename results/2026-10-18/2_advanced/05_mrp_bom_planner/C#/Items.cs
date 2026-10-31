using System;
using System.Collections.Generic;
using System.Linq;

sealed record Item(string Id, int Lead, string Rule, long First, long Second, long Safety, long OnHand, long Material, long Labor, string Description)
{
    public string LotLabel => Rule == "LFL" ? Rule : Rule == "MIN" ? $"MIN {First}/{Second}" : $"{Rule} {First}";
}
static class Items
{
    public static SortedDictionary<string, Item> Read(List<string> errors)
    {
        SortedDictionary<string, Item> items = new(StringComparer.Ordinal); HashSet<string> rules = ["LFL", "FOQ", "POQ", "MIN"];
        foreach (Row row in Io.Rows("items.csv"))
        {
            string[] f = row.Fields; long[] lot = f[3].Split('/').Select(long.Parse).ToArray(); string error = "";
            bool fits = f[2] == "LFL" ? lot.Length == 1 && lot[0] == 0 : f[2] == "MIN" ? lot.Length == 2 && lot[0] >= 1 && lot[1] >= 1 : lot.Length == 1 && lot[0] >= 1;
            if (items.ContainsKey(f[0])) error = "duplicate item " + f[0];
            else if (!rules.Contains(f[2])) error = "unknown lot rule " + f[2];
            else if (!fits) error = $"bad lot parameter {f[3]} for {f[2]}";
            if (error.Length > 0) Io.Error(errors, "items.csv", row.Line, error);
            else items[f[0]] = new(f[0], int.Parse(f[1]), f[2], lot[0], lot.Length == 2 ? lot[1] : 0, long.Parse(f[4]), long.Parse(f[5]), long.Parse(f[6]), long.Parse(f[7]), f[8]);
        }
        return items;
    }
}
