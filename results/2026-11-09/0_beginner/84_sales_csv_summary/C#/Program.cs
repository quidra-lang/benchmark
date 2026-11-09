using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] lines = {
    "date,region,product,quantity,unit_price",
    "2026-04-01,north,notebook,10,200",
    "2026-04-01,east,marker,6,150",
    "2026-04-01,south,eraser,25,80",
    "2026-04-02,west,stapler,4,600",
    "2026-04-02,north,marker,8,150",
    "2026-04-02,east,notebook,9,200",
    "2026-04-03,south,stapler,3,600",
    "2026-04-03,west,eraser,15,80",
    "2026-04-03,north,eraser,20,80",
    "2026-04-04,east,stapler,5,600",
    "2026-04-04,south,notebook,6,200",
    "2026-04-04,west,marker,8,150" };
var regions = new Dictionary<string, int>();
var products = new SortedDictionary<string, int>(StringComparer.Ordinal);
var days = new SortedDictionary<string, int>(StringComparer.Ordinal);
foreach (string line in lines.Skip(1))
{
    string[] fields = line.Split(',');
    int quantity = int.Parse(fields[3], CultureInfo.InvariantCulture);
    int amount = quantity * int.Parse(fields[4], CultureInfo.InvariantCulture);
    regions[fields[1]] = regions.GetValueOrDefault(fields[1]) + amount;
    products[fields[2]] = products.GetValueOrDefault(fields[2]) + quantity;
    days[fields[0]] = days.GetValueOrDefault(fields[0]) + amount;
}
Console.WriteLine($"total: {days.Values.Sum()}");
foreach (var pair in regions.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal))
{
    Console.WriteLine($"{pair.Key}: {pair.Value}");
}
foreach (var pair in products) Console.WriteLine($"{pair.Key}: {pair.Value}");
var best = days.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).First();
Console.WriteLine($"best day: {best.Key} ({best.Value})");
